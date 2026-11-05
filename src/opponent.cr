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

  # A cheap roster: every entry is at or under roughly $0.20 per million tokens
  # blended across this app's heavily input-weighted traffic (it re-sends
  # history on every turn). Each was verified to complete a real turn here, tool
  # calls included; Claude Haiku 5.5, GPT-6 Luna, Gemma 4, DeepSeek V4 Flash and
  # Mistral Small additionally find a mate-in-one when handed Stockfish's
  # ranking. gpt-6-luna was tested through the opencode route, since this
  # account's OpenAI credits are exhausted - same model and same price either
  # way, so it is listed under both providers.
  #
  # Deliberately excluded: anything above that band. Mistral Large ($0.59) and
  # Gemini 2.5 Flash ($0.50) were dropped not just for costing ~3x but because
  # they were dominated - Claude Haiku 5.5 is cheaper, faster, and plays just as
  # well once the engine ranking is attached. Also gone are entries retired
  # upstream (gemini-2.5-pro now 404s, grok-4 isn't in xAI's catalog) and the
  # xAI models, whose cheapest (Grok Build 0.1, ~$1.09) sits above the band.
  #
  # The free local Ollama stays first because #prompt falls back to list.first
  # on blank/unrecognized input, and a local model is the safest thing to
  # default a player into.
  DEFAULTS = [
    Opponent.new("Ollama - Qwen3 8B (local)", "qwen3.8:latest", provider: "ollama"),
    Opponent.new("Google - Gemma 4 31B (free, slow)", "gemma-4-31b-it", provider: "gemini"),
    Opponent.new("Anthropic - Claude Haiku 5.5", "claude-haiku-5-5", provider: "anthropic"),
    Opponent.new("OpenAI - GPT-6 Luna", "gpt-6-luna", provider: "openai"),
    # Was "deepseek-chat", a legacy alias that DeepSeek's API still answers but
    # no longer lists in /models - it silently serves the same deepseek-flash
    # either way, so this rename makes the label honest rather than upgrading
    # the model.
    Opponent.new("DeepSeek - DeepSeek V4 Flash", "deepseek-v4-flash", provider: "deepseek"),
    # The same gpt-6-luna as above, through the opencode gateway: identical
    # per-token price, and the route that works when an OpenAI key has no
    # credits left.
    Opponent.new("OpenCode - GPT-6 Luna", "gpt-6-luna", provider: "opencode"),
    Opponent.new("OpenCode - Claude Haiku 5.5", "claude-haiku-5-5", provider: "opencode"),
    Opponent.new("Mistral - Mistral Small", "mistral-small-latest", provider: "mistral"),
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
