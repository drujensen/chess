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

  DEFAULTS = [
    Opponent.new("Ollama - Qwen3 8B (local)", "qwen3.8:latest", provider: "ollama"),
    Opponent.new("OpenAI - GPT-5.1", "gpt-5.1", provider: "openai"),
    Opponent.new("xAI - Grok 4", "grok-4", provider: "xai"),
    Opponent.new("DeepSeek - DeepSeek Chat", "deepseek-chat", provider: "deepseek"),
    Opponent.new("Groq - Llama 3.3 70B", "llama-3.3-70b-versatile", provider: "groq"),
    Opponent.new("Mistral - Mistral Large", "mistral-large-latest", provider: "mistral"),
    Opponent.new("Gemini - Gemini 2.5 Pro", "gemini-2.5-pro", provider: "gemini"),
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
