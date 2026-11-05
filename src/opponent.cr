require "json"
require "./profile.cr"
require "./game_log.cr"

# One entry from the opponent menu shown at the start of a new game - a named
# provider+model pairing (e.g. "DeepSeek - DeepSeek Chat") the human can pick
# from instead of only ever playing whatever CHESS_PROVIDER/CHESS_MODEL
# happen to be exported. Lives at ~/.chess/opponents.json, alongside the
# profile and saved game, so it's user-editable without touching source -
# `provider` is a shortcut key into AI::PROVIDERS (same ones CHESS_PROVIDER
# accepts), resolved to a base_url/api_key_env the same way; `base_url`/
# `api_key_env` can instead be set directly on an entry for an endpoint
# that isn't one of AI::PROVIDERS' shortcuts, or to override just one half of
# a known provider's pair. CHESS_API_KEY still wins over everything, same as
# it does for the env-var path.
class Opponent
  include JSON::Serializable

  property name : String
  property provider : String? = nil
  property model : String
  property base_url : String? = nil
  property api_key_env : String? = nil

  def initialize(@name : String, @model : String, @provider : String? = nil, @base_url : String? = nil, @api_key_env : String? = nil)
  end

  # A cheap roster, ordered free-first: the two zero-cost options (local Ollama,
  # Google's free Gemma tier) lead, then the paid models by price, with the
  # opencode gateway entries grouped together at the end. Prices are blended
  # per million tokens across roughly 10:1 input:output, which is this app's
  # shape - it re-sends the running conversation on every turn, so input cost
  # dominates and a model's headline output price undersells what it actually
  # costs to play a game with.
  #
  # Everything except Grok Build 0.1 sits at or under ~$0.20 blended. Grok is
  # xAI's cheapest tool-calling model (~$1.09) and is here because it was asked
  # for, not because it competes on price - and note it could NOT be verified:
  # this account's xAI credits are exhausted, so unlike every other entry below
  # nobody has seen it complete a turn here.
  #
  # The rest were verified to complete a real turn, tool calls included; Claude
  # Haiku 5.5, GPT-6 Luna, Gemma 4, DeepSeek Flash and Mistral Small
  # additionally find a mate-in-one when handed Stockfish's ranking. gpt-6-luna
  # was tested through the opencode route, since this account's OpenAI credits
  # are exhausted - same model and same price either way, so it is listed under
  # both providers.
  #
  # Deliberately excluded: Mistral Large ($0.59) and Gemini 2.5 Flash ($0.50) -
  # ~3x the cost of Claude Haiku 5.5 for no measurable gain in play, since the
  # engine ranking attached to every turn does the heavy lifting either way.
  # Also gone: entries retired upstream (gemini-2.5-pro now 404s, grok-4 isn't
  # in xAI's catalog), and gemini-2.5-flash-lite, which is cheaper than
  # anything here but answered a black turn with white's move.
  #
  # The free local Ollama stays first because #prompt falls back to list.first
  # on blank/unrecognized input, and a local model is the safest thing to
  # default a player into.
  DEFAULTS = [
    Opponent.new("Ollama - Qwen3 8B (local)", "qwen3.8:latest", provider: "ollama"),
    Opponent.new("Google - Gemma 4 31B (free, slow)", "gemma-4-31b-it", provider: "gemini"),
    Opponent.new("Anthropic - Claude Haiku 5.5", "claude-haiku-5-5", provider: "anthropic"),
    Opponent.new("OpenAI - GPT-6 Luna", "gpt-6-luna", provider: "openai"),
    # Both "deepseek-chat" (the original entry) and "deepseek-v4-flash" turned
    # out to be aliases - the first isn't listed in DeepSeek's /models anymore,
    # the second is marked deprecated in models.dev - and all three names
    # resolve to the same weights. deepseek-flash is the id DeepSeek actually
    # lists today, so the label now matches what plays.
    Opponent.new("DeepSeek - DeepSeek Flash", "deepseek-flash", provider: "deepseek"),
    Opponent.new("Mistral - Mistral Small", "mistral-small-latest", provider: "mistral"),
    # xAI's cheapest tool-calling model, and its coding-tuned one.
    Opponent.new("xAI - Grok Build 0.1", "grok-build-0.1", provider: "xai"),
    # The opencode gateway: a pass-through to upstream providers, not its own
    # hosting. For the two models listed below that are also available direct
    # (gpt-6-luna, claude-haiku-5-5) its per-token price is identical to going
    # direct, and it is the route that works when a provider key has no credits
    # left. Do not assume that holds generally - opencode does not carry
    # Mistral Small at all, and its deepseek-v4-flash is priced below
    # DeepSeek's own, though that appears to be a different weights snapshot
    # behind the same label rather than a genuine discount.
    Opponent.new("OpenCode - GPT-6 Luna", "gpt-6-luna", provider: "opencode"),
    Opponent.new("OpenCode - Claude Haiku 5.5", "claude-haiku-5-5", provider: "opencode"),
    Opponent.new("OpenCode - Qwen3.8 Flash", "qwen3.8-flash", provider: "opencode"),
  ]

  def self.path : Path
    Profile.directory / "opponents.json"
  end

  # Reads the config file, writing it out with DEFAULTS first if it doesn't
  # exist yet - so there's always something to pick from, and the file is
  # discoverable (and editable) the first time anyone looks for it. A
  # malformed file falls back to DEFAULTS rather than crashing the whole menu
  # loop over a typo in hand-edited JSON.
  def self.load : Array(Opponent)
    unless File.exists?(path)
      Dir.mkdir_p(Profile.directory)
      File.write(path, DEFAULTS.to_json)
    end
    list = Array(Opponent).from_json(File.read(path))
    list.empty? ? DEFAULTS : list
  rescue ex
    GameLog.error("failed to read #{path}, falling back to built-in defaults", ex)
    DEFAULTS
  end

  def self.find_by_name(name : String) : Opponent?
    load.find { |o| o.name == name }
  end

  # Shown right after SkillLevel.prompt when starting a new game - same
  # "numbered list, blank/invalid defaults to the first entry" shape as
  # SkillLevel.prompt, so the two prompts feel like one flow.
  def self.prompt : Opponent
    list = load
    puts "Select opponent:"
    list.each_with_index do |o, i|
      puts "#{i + 1}) #{o.name} (#{o.model})"
    end
    print "> "
    drain_stdin
    index = gets.try(&.strip.to_i?)
    (index && index >= 1 && index <= list.size) ? list[index - 1] : list.first
  end

  # AI::PROVIDERS is the same provider shortcut map CHESS_PROVIDER resolves
  # against - reused here so an opponents.json entry only needs a provider
  # name, not a hand-typed base_url, for anything already in that list.
  def resolve_base_url : String
    base_url || provider.try { |p| AI::PROVIDERS[p.downcase]?.try(&.[:base_url]) } ||
      raise "opponent #{name.inspect}: no base_url set and provider #{provider.inspect} isn't one of #{AI::PROVIDERS.keys.join(", ")} - fix #{self.class.path}"
  end

  def resolve_api_key : String?
    ENV["CHESS_API_KEY"]? || effective_key_env.try { |key_env| ENV[key_env]? }
  end

  private def effective_key_env : String?
    api_key_env || provider.try { |p| AI::PROVIDERS[p.downcase]?.try(&.[:key_env]) }
  end
end
