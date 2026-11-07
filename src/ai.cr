require "json"
require "http/client"
require "time"
require "./skill_level.cr"
require "./game_over.cr"
require "./undo_requested.cr"
require "./setup_requested.cr"
require "./move_requested.cr"
require "./board.cr"
require "./game_log.cr"
require "./hint.cr"
require "./context.cr"
require "./opponent.cr"

class AI
  property prev_tool_id : String?
  property skill_level : SkillLevel
  getter model : String
  getter base_url : String
  @api_key : String?
  @think : Bool
  @send_temperature : Bool

  # CHESS_PROVIDER picks one of these so switching providers is one env var
  # instead of re-exporting CHESS_BASE_URL/CHESS_API_KEY by hand each time -
  # the API key stays wherever it already lives (e.g. XAI_API_KEY alongside
  # everything else in a .profile), never duplicated under CHESS_API_KEY.
  # CHESS_BASE_URL/CHESS_API_KEY still work directly for anything not listed
  # here, and take precedence when both are set.
  PROVIDERS = {
    "openai"     => {base_url: "https://api.openai.com/v1", key_env: "OPENAI_API_KEY"},
    "xai"        => {base_url: "https://api.x.ai/v1", key_env: "XAI_API_KEY"},
    "deepseek"   => {base_url: "https://api.deepseek.com/v1", key_env: "DEEPSEEK_API_KEY"},
    # Note the /inference/openai prefix - https://opencode.ai/v1 serves the
    # website, not the API, so a bare /v1 here returns HTML instead of JSON.
    "opencode"   => {base_url: "https://opencode.ai/inference/openai/v1", key_env: "OPENCODE_API_KEY"},
    "mistral"    => {base_url: "https://api.mistral.ai/v1", key_env: "MISTRAL_API_KEY"},
    # OpenAI-compatible surface, not the native /v1/messages API - so the
    # existing tool-calling code works against it unchanged.
    "anthropic"  => {base_url: "https://api.anthropic.com/v1", key_env: "ANTHROPIC_API_KEY"},
    "fireworks"  => {base_url: "https://api.fireworks.ai/inference/v1", key_env: "FIREWORKS_API_KEY"},
    "openrouter" => {base_url: "https://openrouter.ai/api/v1", key_env: "OPENROUTER_API_KEY"},
    "gemini"     => {base_url: "https://generativelanguage.googleapis.com/v1beta/openai", key_env: "GEMINI_API_KEY"},
    "ollama"     => {base_url: "http://localhost:11434/v1", key_env: nil},
    "drujensen"  => {base_url: "https://ai.drujensen.com/v1", key_env: "DRUJENSEN_API_KEY"},
  }

  def self.provider_config
    name = ENV["CHESS_PROVIDER"]?
    return nil unless name
    PROVIDERS[name.downcase]? || raise "unknown CHESS_PROVIDER: #{name} - known providers: #{PROVIDERS.keys.join(", ")}"
  end

  BASE_URL      = ENV["CHESS_BASE_URL"]? || provider_config.try(&.[:base_url]) || "http://localhost:11434/v1"
  BASE_URI      = URI.parse(BASE_URL)
  ENDPOINT_PATH = "#{BASE_URI.path}/chat/completions"
  MODEL         = ENV.fetch("CHESS_MODEL", "qwen3.8:latest")

  # How long a single request may run before giving up - a slow or stuck
  # local model would otherwise hang forever with no way to notice, since
  # nothing else in this app puts any bound on how long "thinking" can take.
  CONNECT_TIMEOUT = 10.seconds
  TIMEOUT         = ENV.fetch("CHESS_TIMEOUT", "300").to_i.seconds

  # GPT-6 Luna on OpenAI's Chat Completions endpoint requires reasoning_effort
  # to be explicitly set to "none" when function tools are used. Other
  # providers/routes have their own defaults and should not receive this
  # OpenAI-specific parameter.
  def self.tool_reasoning_effort(model : String, host : String?) : String?
    "none" if host == "api.openai.com" && model == "gpt-6-luna"
  end

  # resume_moves: long-algebraic moves already played (alternating white/
  # black, starting with white), when picking a previously-saved game back
  # up. The exact prior conversation can't be restored, so instead the model
  # is briefed with the game-so-far as its first message.
  #
  # opponent: the provider/model picked from Opponent.prompt's menu (nil
  # falls back to the CHESS_PROVIDER/CHESS_BASE_URL/CHESS_MODEL env-var
  # constants below, same as before this existed - resolve_move/explain_move
  # callers that build a stateless one-off AI.new with no opponent, e.g.
  # Replay#explain, still get that env-based default).
  def initialize(@skill_level : SkillLevel = SkillLevel::Advanced, @ai_white : Bool = false, resume_moves : Array(String)? = nil, opponent : Opponent? = nil)
    @model = opponent.try(&.model) || MODEL
    @base_url = opponent.try(&.resolve_base_url) || BASE_URL
    @base_uri = URI.parse(@base_url)
    @endpoint_path = "#{@base_uri.path}/chat/completions"
    @api_key = if opponent
                 opponent.resolve_api_key
               else
                 ENV["CHESS_API_KEY"]? || AI.provider_config.try(&.[:key_env]).try { |key_env| ENV[key_env]? }
               end
    @client = HTTP::Client.new(@base_uri)
    @client.connect_timeout = CONNECT_TIMEOUT
    @client.read_timeout = TIMEOUT
    @messages = [] of Context::Message

    # Best-effort hint to a local Ollama server to turn on a reasoning model's
    # extended-thinking mode (e.g. qwen3's `think` request field) before
    # picking a move - detected by host rather than by provider name, so it
    # also covers the no-CHESS_PROVIDER-set default (localhost:11434, no api
    # key) the same way as an opponents.json entry with provider: "ollama".
    # Cloud providers never get this field, since several of them (e.g. the
    # real OpenAI API) reject unrecognized request parameters outright.
    @think = @api_key.nil? && @base_uri.host.in?({"localhost", "127.0.0.1"})

    # Anthropic rejects `temperature` outright on its current models ("`temperature`
    # is deprecated for this model", HTTP 400), so any Claude option would fail
    # every request while the app kept sending it. Detected by host rather than
    # provider name, so it also covers an opencode/gateway URL that happens to
    # serve a Claude model through an Anthropic-shaped endpoint, and is skipped
    # for OpenAI-compatible surfaces that accept the field. Omitting it lets the
    # model use its own default, which is the only option that works at all here.
    @send_temperature = @base_uri.host != "api.anthropic.com"

    human_color = @ai_white ? "black" : "white"
    ai_color = @ai_white ? "white" : "black"
    @messages.push(
      {
        role:    "system",
        content: "You are a #{skill_level.to_s.downcase} chess player, rated approximately #{skill_level.elo_range} Elo. You are playing a game of chess against a human. the human is #{human_color} and you are #{ai_color}. There are 5 functions available to you. moves: list of moves played so far. board: the current board position as FEN, call this whenever you need to see where the pieces actually are before choosing a move. hint: ask the local Stockfish engine for its top 5 moves in the current position, with scores and the lines it expects - call it whenever you want a second opinion before committing to a move. move: play the next move. resign: give up the game - but this is only even allowed once you have nothing left but pawns (and your king); it's rejected otherwise, no matter how far behind you are. Even once you're down to just pawns, only actually call it for a forced checkmate you can see coming with no defense, or a hopeless pawn ending with no realistic chance to draw or swindle something - a single piece (bishop, knight, rook, or queen) still on the board, of either color, is always a reason to keep playing it out. You have about #{TIMEOUT.total_seconds.to_i} seconds to reply each time you're asked something, which is enough time to actually calculate - before calling move, work out concretely whether your candidate hangs a piece, allows a tactic, or ignores a threat from the opponent's last move, and check your opponent's best reply to it. Play at the real strength of a #{skill_level.to_s.downcase}, #{skill_level.elo_range} Elo - that means genuinely calculating, not just pattern-matching the first reasonable-looking move. A hint is an aid, never an order: you don't have to play its top move, and you're responsible for whatever you do play.",
      }
    )

    if resume_moves && !resume_moves.empty?
      @messages.push({
        role:    "user",
        content: "This game is already in progress and you're picking it back up. Moves so far, in order, alternating white/black starting with white: #{resume_moves.join(", ")}.",
      })
    end
  end

  # Lets the human chat with the AI mid-game. Grounded with the same
  # `moves`/`board` tools next_move gets, minus `move` itself - chat can look
  # but not touch the game state. Pushes the human's message once, then loops
  # on tool calls without re-pushing it.
  #
  # Chess#next_turn only ever calls this after AI#resolve_move has already
  # failed to resolve `text` into one of the human's current legal moves -
  # the model isn't told that on its own, and its own message history is full
  # of "(played X)" confirmations from genuinely-resolved moves
  # (#record_move_resolution), so on a near-miss like a typo'd move it would
  # sometimes just free-text echo that same "(played X)" phrasing as its chat
  # reply without actually calling a tool - nothing on the board ever
  # changes, since next_turn only reacts to a real MoveRequested/
  # UndoRequested/SetupRequested exception, but the human reading that reply
  # reasonably believed their move had been played. The reminder below heads
  # that off by naming the actual situation explicitly.
  def chat(board : Board, text : String) : String
    @messages.push({role: "user", content: text})
    # Not pushed into @messages: this only makes sense about the one instruction
    # that failed to resolve right now, and persisting it left the model
    # believing later, genuine messages were also failed moves.
    reminder = [{
      role:    "system",
      content: "That didn't automatically resolve to one of the human's current legal moves, so it's reaching you as a chat message instead. If it looks like they meant to make a move, tell them it wasn't recognized (use the board/moves tools if you need to check the position) so they can try again with clearer notation - never say or imply that a move was played unless you actually call play_for_human. If it's a genuine question or comment instead, just answer it normally.",
    }] of Context::Message
    chat_loop(board, reminder)
  end

  # Records a natural-language instruction that got resolved into an actual
  # move (see #resolve_move), so the shared history reflects what was asked
  # and what happened - not just the bare notation the move list shows.
  def record_move_resolution(instruction : String, move : String)
    @messages.push({role: "user", content: instruction})
    @messages.push({role: "assistant", content: "(played #{move})"})
  end

  # Explains, in plain language, why a flagged move from Stockfish's game
  # analysis (see Analysis) was worse than the engine's suggestion - the
  # model isn't asked to find or judge anything itself, only to narrate a
  # concrete position + line the engine already worked out, which is a much
  # more reliable task for a small local model than actually playing chess.
  # Stateless like #resolve_move - its own throwaway message list, no tools.
  def explain_move(
    fen : String, played_san : String, better_san : String?,
    pv_after : Array(String)?, pv_before : Array(String)?,
  ) : String
    prompt = String.build do |str|
      str << "Position (FEN): #{fen}\n"
      str << "Move actually played: #{played_san}\n"
      str << "What follows after that move, per the engine's own analysis (long algebraic notation): #{pv_after.try(&.join(" ")) || "not available"}\n"
      if better_san
        str << "Suggested move instead: #{better_san}\n"
        str << "What would follow after that instead, per the engine's analysis: #{pv_before.try(&.join(" ")) || "not available"}\n"
      end
      str << "Explain concretely why #{played_san} was a mistake here"
      str << (better_san ? " compared to #{better_san}." : ".")
    end

    messages = [
      {
        role:    "system",
        content: "You are a chess coach explaining one move to a club player reviewing their own game. Be concrete and specific - name the actual piece, square, or tactic involved (a hanging piece, a fork, a pin, a discovered attack, a weak back rank, etc), using the given position and lines as your evidence. 2-4 sentences. Don't just restate an evaluation number.",
      },
      {role: "user", content: prompt},
    ]
    body = chat_body(messages)

    result = post_chat_completion(body)
    choices = result["choices"]
    choices[choices.size - 1]["message"]["content"].to_s
  end

  # One place that assembles a chat-completions request body, because its
  # optional fields depend on the endpoint/model rather than the caller:
  # `temperature` must be omitted entirely for Anthropic (see @send_temperature),
  # `think` is only ever meant for a local Ollama server (see @think), and
  # OpenAI's GPT-6 Luna needs `reasoning_effort: "none"` when function tools are
  # enabled. Left to per-call-site literals, these combinations would be
  # duplicated across the request paths, and a body that silently differs
  # between them is exactly the kind of thing that only shows up as a 400
  # mid-game.
  private def chat_body(messages, tools = nil, think = false, temperature = 0.3) : String
    JSON.build do |json|
      json.object do
        json.field "model", @model
        json.field("temperature", temperature) if @send_temperature
        json.field("think", true) if think
        if tools && (effort = self.class.tool_reasoning_effort(@model, @base_uri.host))
          json.field "reasoning_effort", effort
        end
        json.field "messages" do
          messages.to_json(json)
        end
        if (t = tools)
          json.field "tools" do
            t.to_json(json)
          end
          json.field "tool_choice", "auto"
        end
      end
    end
  end

  private def response_tool_calls(message : JSON::Any) : Array(JSON::Any)?
    # OpenAI-compatible providers commonly return `"tool_calls": null` when
    # the assistant responds with plain text. A missing key is nil, but an
    # explicit JSON null is a non-nil JSON::Any wrapping Nil, so use the
    # optional cast rather than calling `as_a` on it.
    message["tool_calls"]?.try(&.as_a?)
  end

  private def chat_loop(board : Board, notices : Array(Context::Message)) : String
    body = chat_body(
      request_messages(board, notices),
      [moves_tool, board_tool, undo_tool, setup_position_tool, play_for_human_tool, hint_tool("the human's side")],
    )

    result = post_chat_completion(body)
    choices = result["choices"]
    message = choices[choices.size - 1]["message"]
    tool_calls = response_tool_calls(message)

    return message["content"].to_s if tool_calls.nil?

    @messages.push(message)

    # Every tool_call in the message must get a matching tool response before
    # @messages is ever sent again, or the next request is rejected outright
    # (some providers, e.g. DeepSeek, enforce this strictly) - so all of them
    # are answered here, not just the last one. "undo" and a validated
    # "setup_position" are the exception - they raise straight out instead,
    # since Chess#next_turn discards this entire AI (and its @messages,
    # unanswered tool_call included) and builds a fresh one briefed on the
    # new position, same as a resumed game. An invalid "setup_position" does
    # get a normal tool response instead (the validation failure reason), so
    # the model can retry with a corrected sequence in the same chat turn.
    tool_calls.each do |tool|
      tool_id = tool["id"].to_s

      case tool["function"]["name"]
      when "moves"
        GameLog.info("chat: moves called: #{board.moves.join(", ")}")
        @messages.push({tool_call_id: tool_id, role: "tool", name: "moves", content: board.moves.join(", ")})
      when "undo"
        args = JSON.parse(tool["function"]["arguments"].to_s)
        count = args["count"]?.try(&.as_i?) || 1
        GameLog.info("chat: undo called: #{count}")
        raise UndoRequested.new(count)
      when "setup_position"
        moves = begin
          JSON.parse(tool["function"]["arguments"].to_s)["moves"].as_a.map(&.as_s)
        rescue
          nil
        end
        GameLog.info("chat: setup_position called: #{moves ? moves.join(", ") : "(unparseable)"}")

        if moves.nil?
          @messages.push({tool_call_id: tool_id, role: "tool", name: "setup_position", content: "rejected: couldn't parse the moves list - call again with a \"moves\" array of strings in long algebraic notation."})
        elsif (rejection = invalid_setup_reason(moves))
          @messages.push({tool_call_id: tool_id, role: "tool", name: "setup_position", content: "rejected: #{rejection} Earlier moves in the sequence were fine - try again with a corrected sequence."})
        else
          raise SetupRequested.new(moves)
        end
      when "hint"
        content = hint_response(board, !@ai_white)
        GameLog.info("chat: hint called for the human (#{!@ai_white ? "white" : "black"}):\n#{content}")
        @messages.push({tool_call_id: tool_id, role: "tool", name: "hint", content: content})
      when "board"
        fen = board.to_fen(!@ai_white)
        GameLog.info("chat: board called: #{fen}")
        @messages.push({tool_call_id: tool_id, role: "tool", name: "board", content: fen})
      when "play_for_human"
        candidate = JSON.parse(tool["function"]["arguments"].to_s)["nextMove"]?.try(&.as_s?).try(&.strip)
        legal = board.legal_moves(!@ai_white)

        if candidate.nil? || candidate.empty?
          @messages.push({tool_call_id: tool_id, role: "tool", name: "play_for_human", content: "error: missing or empty \"nextMove\" argument - call again with one of the human's legal moves in long algebraic notation."})
        elsif !legal.includes?(candidate)
          @messages.push({tool_call_id: tool_id, role: "tool", name: "play_for_human", content: "error: \"#{candidate}\" isn't one of the human's legal moves right now: #{legal.join(", ")}. call again with one of these exactly."})
        else
          GameLog.info("chat: play_for_human called: #{candidate}")
          raise MoveRequested.new(candidate)
        end
      else
        name = tool["function"]["name"].to_s
        GameLog.error("chat: unknown tool called: #{name}")
        @messages.push({tool_call_id: tool_id, role: "tool", name: name, content: "error: \"#{name}\" isn't available right now - choose one of moves, board, hint, undo, setup_position, or play_for_human."})
      end
    end

    chat_loop(board, notices)
  end

  # Replays `moves` on a throwaway Board (the live `board` passed to `chat`
  # is left untouched here - this only checks whether the sequence is even
  # legal before Chess#next_turn is asked to actually apply it) from the
  # starting position, returning nil if every move is legal in sequence, or
  # a description of the first illegal one otherwise - so a mistaken
  # sequence from the model can be reported back and retried in the same
  # chat turn instead of silently producing the wrong position.
  private def invalid_setup_reason(moves : Array(String)) : String?
    scratch = Board.new
    scratch.setup
    white = true

    moves.each_with_index do |move, i|
      unless scratch.turn(move, white)
        return "move #{i + 1} (#{move}) is illegal - #{scratch.explain_invalid_move(move, white)}."
      end
      white = !white
    end

    nil
  end

  # Everything the model needs to know about the *current* position that isn't
  # already implied by the move list. These are deliberately NOT pushed into
  # @messages: they describe one specific turn, and persisting them is exactly
  # how the log ends up holding a dozen contradictory "current" positions. They
  # ride along on the request that they're about, and are gone after it.
  private def turn_notices(board : Board, error : String?, weak_move : Bool) : Array(Context::Message)
    notices = [] of Context::Message
    legal = board.legal_moves(@ai_white)

    if board.in_check?(@ai_white)
      notices << {
        role:    "system",
        content: "You are in check! You must play a move that gets your king out of check - capture the checking piece, block it, or move the king.",
      }
    end

    if legal.size == 1
      notices << {
        role:    "system",
        content: "You have exactly one legal move available right now: #{legal.first}. There is no other option - you must play this exact move.",
      }
    end

    unless error.nil? || error.empty?
      notices << {
        role:    "system",
        content: "error: #{error} Your legal moves right now are: #{legal.join(", ")}. Pick one of these exactly.",
      }
    end

    if weak_move
      notices << {
        role:    "system",
        content: "For this move only: play like a genuine #{skill_level.to_s.downcase}. Don't calculate deeply and don't rely on any engine suggestion - play a simple, natural-looking move, and it's fine to miss a tactic or overlook a threat. Legal moves right now: #{legal.join(", ")}.",
      }
    elsif legal.size > 1
      # Attached rather than offered as a tool the model must think to call:
      # DeepSeek was given the `hint` tool on every move of a real game and used
      # it zero times, so an opt-in aid is no aid at all for a model that
      # doesn't reach for one. Still a suggestion, not an order - the
      # disclaimer in Hint.render_for_ai keeps it that way. Skipped when there's
      # only one legal move, since paying for a search to confirm the obvious
      # is pointless, and on a weak-move turn, where the tier is the point.
      if (suggestions = Hint.suggestions(board, @ai_white)) && !suggestions.empty?
        notices << {
          role:    "system",
          content: "Stockfish's assessment of the current position, ranked best-first. Unless you can see a concrete reason the top pick is wrong, prefer one of these over pattern-matching your first instinct - though you remain free to play any legal move.\n#{Hint.render_for_ai(suggestions, @ai_white)}\n(This is valid for this move only; it will not be repeated for your opponent's next turn.)",
        }
      end
    end

    notices
  end

  # Stands in for the turns #trim elided: the move list and the current
  # position, which together say everything a dropped FEN or engine ranking
  # would have - only truthfully, since this one is the position that's
  # actually on the board now.
  # The side to move is *derived* from the move list rather than assumed, so it
  # stays correct in every case - an AI's own turn (its color, whenever it's
  # actually its move), chat during the human's turn, and - the case a
  # hardcoded color silently gets wrong - setup_position/undo handing the next
  # move to whoever the position says it belongs to.
  private def context_summary(board : Board) : Context::Message
    white_to_move = board.moves.size.even?
    {
      role:    "system",
      content: "Earlier turns of this game have been compacted out of this conversation. Here is everything that carries forward:\nMoves so far: #{board.moves.join(", ")}\nCurrent position (FEN): #{board.to_fen(white_to_move)}\nTrust this position over any earlier one you remember seeing - the older ones are no longer accurate.",
    }
  end

  # The full message list for one request: trimmed history + the current turn's
  # notices, always appended at the very end so the model sees them last (most
  # recent = highest attention for most models) and so trimming can never
  # accidentally drop them.
  private def request_messages(board : Board, notices : Array(Context::Message)) : Array(Context::Message)
    eliding = Context.eliding?(@messages)
    trimmed = Context.trim(@messages, summary: eliding ? context_summary(board) : nil)
    trimmed.concat(notices)
    trimmed = wire_safe(trimmed)
    GameLog.info("context: #{eliding ? "trimmed #{@messages.size} -> #{trimmed.size}" : "untrimmed #{trimmed.size}"} messages + #{notices.size} notice(s)")
    trimmed
  end

  # Anthropic's OpenAI-compatible endpoint rejects tool messages that carry a
  # `name` ("cannot preserve named conversation participants", HTTP 400) - and
  # since every tool response in this app has one, any Claude model would work
  # for its first request and then fail the moment a tool is actually called.
  # The field is optional in the OpenAI tool-message schema and nothing here
  # ever reads it back, so it's simply dropped on the way out rather than
  # stripped from all thirteen push sites - which keeps the local log readable
  # while sending what every provider accepts.
  private def wire_safe(messages : Array(Context::Message)) : Array(Context::Message)
    messages.map do |message|
      if tool = message.as?(Context::Tool)
        {tool_call_id: tool[:tool_call_id], role: "tool", content: tool[:content]}
      else
        message
      end
    end
  end

  def next_move(board : Board, error : String? = nil) : String
    opening_prompt = board.moves.empty? ? "You are playing white and move first. Make your opening move." : "I played #{board.moves.last}.  your turn."
    @messages.push({role: "user", content: opening_prompt})

    next_move_loop(board, turn_notices(board, error, rand < skill_level.weak_move_chance))
  end

  private def next_move_loop(board : Board, notices : Array(Context::Message)) : String
    # The `hint` tool is deliberately not offered here: its answer is already
    # attached to every request as a notice (see #turn_notices), so a tool for
    # fetching the same thing again would only ever return what the model was
    # just handed.
    tools = [moves_tool, board_tool, move_tool, resign_tool]
    names = tools.map { |t| t[:function][:name] }.join(", ")
    GameLog.info("next_move: tools offered: #{names}")
    body = chat_body(request_messages(board, notices), tools, @think)

    result = post_chat_completion(body)

    choices = result["choices"]
    message = choices[choices.size - 1]["message"]

    # Ollama surfaces a thinking model's reasoning under one of a few field
    # names depending on endpoint/version - logged for visibility (not shown
    # in the terminal, same as other tool-call chatter) rather than relied on,
    # since whichever field is actually present is best-effort.
    reasoning = message["thinking"]? || message["reasoning_content"]? || message["reasoning"]?
    GameLog.info("next_move: reasoning: #{reasoning}") if reasoning

    tool_calls = response_tool_calls(message)

    if tool_calls.nil?
      GameLog.info("next_move: replied without a tool call: #{message["content"]}")
      return next_move_loop(board, notices)
    end

    @messages.push(message)

    # Every tool_call in the message must get a matching tool response before
    # @messages is ever sent again, or the next request is rejected outright
    # (some providers, e.g. DeepSeek, enforce this strictly) - so all of them
    # are answered here, not just the last one, even when (as with "move" or
    # "resign") only one of them actually ends the turn.
    requested_move = nil

    tool_calls.each do |tool|
      tool_id = tool["id"].to_s

      case tool["function"]["name"]
      when "moves"
        GameLog.info("next_move: moves called: #{board.moves.join(", ")}")
        @messages.push({
          tool_call_id: tool_id,
          role:         "tool",
          name:         "moves",
          content:      "#{board.moves.join(", ")}",
        })
      when "board"
        fen = board.to_fen(@ai_white)
        GameLog.info("next_move: board called: #{fen}")
        @messages.push({
          tool_call_id: tool_id,
          role:         "tool",
          name:         "board",
          content:      fen,
        })
      when "resign"
        if board.only_pawns_left?(@ai_white)
          GameLog.info("next_move: #{@ai_white ? "white" : "black"} resigns")
          raise GameOver.new("#{@ai_white ? "white" : "black"} resigns - #{@ai_white ? "black" : "white"} wins!", @ai_white ? "0-1" : "1-0")
        else
          GameLog.info("next_move: resign rejected - #{@ai_white ? "white" : "black"} still has a piece besides pawns")
          @messages.push({
            tool_call_id: tool_id,
            role:         "tool",
            name:         "resign",
            content:      "rejected: you still have at least one piece other than pawns on the board - you can't resign yet. Keep playing; call board if you need to re-check the position.",
          })
        end
      when "move"
        next_move_candidate = JSON.parse(tool["function"]["arguments"].to_s)["nextMove"]?.try(&.as_s?).try(&.strip)
        if next_move_candidate.nil? || next_move_candidate.empty?
          @messages.push({
            tool_call_id: tool_id,
            role:         "tool",
            name:         "move",
            content:      "error: missing or empty \"nextMove\" argument - call move again with a single move in long algebraic notation.",
          })
        else
          requested_move = next_move_candidate
          @messages.push({
            tool_call_id: tool_id,
            role:         "tool",
            name:         "move",
            content:      "success",
          })

          GameLog.info("next_move: move called: #{requested_move}")
        end
      else
        name = tool["function"]["name"].to_s
        GameLog.error("next_move: unknown tool called: #{name}")
        @messages.push({
          tool_call_id: tool_id,
          role:         "tool",
          name:         name,
          content:      "error: \"#{name}\" isn't available right now - choose one of moves, board, move, or resign.",
        })
      end
    end

    requested_move || next_move_loop(board, notices)
  end

  private def moves_tool
    {
      type:     "function",
      function: {
        name:        "moves",
        description: "list of moves played so far",
        parameters:  {
          type:       "object",
          properties: {} of String => String,
        },
      },
    }
  end

  private def board_tool
    {
      type:     "function",
      function: {
        name:        "board",
        description: "get the current board position as FEN (Forsyth-Edwards Notation)",
        parameters:  {
          type:       "object",
          properties: {} of String => String,
        },
      },
    }
  end

  private def undo_tool
    {
      type:     "function",
      function: {
        name:        "undo",
        description: "take back the human's last move and your reply to it, so they can try something different from an earlier position. Only call this when the human clearly asks to undo, take back, or go back - never on your own initiative.",
        parameters:  {
          type:       "object",
          properties: {
            count: {
              type:        "integer",
              description: "how many of the human's own previous moves to go back - each one also undoes your reply to it. Defaults to 1 if omitted.",
            },
          },
        },
      },
    }
  end

  private def setup_position_tool
    {
      type:     "function",
      function: {
        name:        "setup_position",
        description: "Set up the board to a specific sequence of moves from the starting position - e.g. to show a known opening or a teaching scenario the human asked about. This replaces the current game's position entirely, so only call it when the human clearly describes a position or opening they want to see or practice, never on your own initiative. If the human's description is informal (names a piece/opening loosely, e.g. \"Ruy Lopez\" or \"knight to f3\"), translate it into the exact, correct long algebraic sequence yourself - an illegal or wrong sequence is rejected and you'll be told which move failed and why, so you can retry.",
        parameters:  {
          type:       "object",
          properties: {
            moves: {
              type:        "array",
              items:       {type: "string"},
              description: "the full sequence of moves from the starting position, in long algebraic notation (e.g. e2e4), alternating white then black",
            },
          },
        },
      },
    }
  end

  private def hint_tool(about : String)
    {
      type:     "function",
      function: {
        name:        "hint",
        description: "Get the top 5 moves for #{about} in the current position, ranked by the local Stockfish engine, each with its score and the line the engine expects to follow. Optional - call it whenever you want a second opinion before deciding. The list is a suggestion, not an instruction: you stay free to play any legal move you like, including one not on it.",
        parameters:  {
          type:       "object",
          properties: {} of String => String,
        },
      },
    }
  end

  # The engine's ranked list for `white`, as a tool response - always an
  # answer, never an error, so the model's turn simply continues (same shape
  # as board/moves). A nil from Hint.suggestions means no usable engine, and an
  # empty list means the side to move genuinely has no legal move at all; those
  # are different facts and the model needs to be told which one it got.
  private def hint_response(board : Board, white : Bool) : String
    if (suggestions = Hint.suggestions(board, white))
      if suggestions.empty?
        "#{white ? "white" : "black"} has no legal moves in this position at all - it's checkmate or stalemate, so there's nothing left to hint."
      else
        Hint.render_for_ai(suggestions, white)
      end
    else
      "unavailable: the local Stockfish engine isn't installed or didn't answer. Pick your own move from the position instead - call board if you need to see it again."
    end
  end

  private def play_for_human_tool
    {
      type:     "function",
      function: {
        name:        "play_for_human",
        description: "Play a move on the human's behalf, when they clearly ask you to choose and make their move for them (e.g. \"move for me\", \"you choose\", \"just play something\"). Pick a reasonable legal move for their side - you don't need to find the objectively best move, just a sound one. Only call this when the human clearly asks you to play for them - never on your own initiative, and never when they're just asking about or discussing a move rather than asking you to play it.",
        parameters:  {
          type:       "object",
          properties: {
            nextMove: {
              type:        "string",
              description: "the move to play for the human, in long algebraic notation i.e. e2e4 - must be one of their actual current legal moves",
            },
          },
        },
      },
    }
  end

  private def move_tool
    {
      type:     "function",
      function: {
        name:        "move",
        description: "play the next move",
        parameters:  {
          type:       "object",
          properties: {
            nextMove: {
              type:        "string",
              description: "long algebraic notation i.e. e2e4",
            },
          },
        },
      },
    }
  end

  private def resign_tool
    {
      type:     "function",
      function: {
        name:        "resign",
        description: "resign the game - rejected unless you have nothing left but pawns and your king. Even then, only call it for a forced checkmate you can see coming, or a truly hopeless pawn ending.",
        parameters:  {
          type:       "object",
          properties: {} of String => String,
        },
      },
    }
  end

  # Resolves a natural-language instruction from the human ("move my queen
  # up 2 spots") into a single long-algebraic move, grounded in the current
  # position and its actual legal moves. Returns nil if the instruction
  # doesn't clearly describe exactly one legal move for white, so the caller
  # can fall back to treating it as ordinary chat.
  def resolve_move(board : Board, text : String, white : Bool) : String?
    legal = board.legal_moves(white)
    return nil if legal.empty?

    side = white ? "white" : "black"
    messages = [
      {
        role:    "system",
        content: "You translate a chess player's instruction into one legal move for the #{side} side. You are given the position as FEN and the full list of #{side}'s legal moves in long algebraic notation. If the instruction clearly identifies exactly one of those legal moves, call propose_move with it verbatim. If it's ambiguous, illegal, or isn't describing a move at all (e.g. a question or comment), call not_a_move instead.",
      },
      {
        role:    "user",
        content: "FEN: #{board.to_fen(white)}\nLegal moves: #{legal.join(", ")}\nInstruction: #{text}",
      },
    ]
    resolve_tools = [
      {
        type:     "function",
        function: {
          name:        "propose_move",
          description: "propose the resolved move",
          parameters:  {
            type:       "object",
            properties: {
              move: {
                type:        "string",
                description: "one of the given legal moves, in long algebraic notation i.e. e2e4",
              },
            },
          },
        },
      },
      {
        type:     "function",
        function: {
          name:        "not_a_move",
          description: "the instruction does not clearly identify a single legal move",
          parameters:  {
            type:       "object",
            properties: {} of String => String,
          },
        },
      },
    ]
    body = chat_body(messages, resolve_tools, temperature: 0.2)

    result = post_chat_completion(body)
    choices = result["choices"]
    message = choices[choices.size - 1]["message"]
    tool_calls = response_tool_calls(message)
    return nil if tool_calls.nil?

    tool = tool_calls[tool_calls.size - 1]
    return nil unless tool["function"]["name"] == "propose_move"

    move = JSON.parse(tool["function"]["arguments"].to_s)["move"].to_s.strip
    legal.includes?(move) ? move : nil
  end

  private def post_chat_completion(body)
    retry_count = 0
    last_error = "no attempts made"

    while retry_count < 3
      begin
        response = with_spinner { @client.post(@endpoint_path, headers: build_headers, body: body) }
        return JSON.parse(response.body) if response.success?
        last_error = "HTTP #{response.status_code}: #{response.body}"
        GameLog.error("request attempt #{retry_count + 1}/3 failed: #{last_error}")
      rescue e : IO::TimeoutError
        # re-raised, not retried here - caught below by the method-level
        # rescue, same as if it had propagated straight out of the loop
        raise e
      rescue e : IO::Error
        # some providers' proxies drop an idle kept-alive connection out from
        # under us (IO::EOFError "Unexpected end of http response") or reset it
        # outright (plain IO::Error "Connection reset by peer") - either way the
        # socket is dead, so retrying on it would just hit the same error again;
        # closing forces a fresh connection on the next attempt
        @client.close
        last_error = "connection dropped (#{e.message})"
        GameLog.error("request attempt #{retry_count + 1}/3 failed: #{last_error}", e)
      end
      retry_count += 1
    end
    raise "request to #{@base_url} failed after 3 attempts - #{last_error}"
  rescue e : IO::TimeoutError
    # not retried - the model was already given the full timeout once, and
    # trying again with the same budget just multiplies the wait
    raise "#{@model} didn't respond within #{TIMEOUT.total_seconds.to_i}s (set CHESS_TIMEOUT to change this) - it may be stuck or overloaded."
  end

  SPINNER_FRAMES = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

  # Runs a blocking HTTP call on a separate fiber while animating a spinner
  # with an elapsed-seconds counter on the main one, so a slow model and a
  # genuinely hung one don't look identical (nothing printed at all).
  private def with_spinner(&block : -> HTTP::Client::Response) : HTTP::Client::Response
    result = Channel(HTTP::Client::Response | Exception).new
    spawn do
      begin
        result.send(block.call)
      rescue e
        # An unhandled exception inside a spawned fiber is only printed and
        # silently drops the fiber - it never reaches the receiving fiber on
        # its own, which would otherwise leave the spinner looping forever
        # on a channel that's never going to receive anything.
        result.send(e)
      end
    end

    started_at = Time.instant
    frame = 0

    response = loop do
      select
      when r = result.receive
        break r
      when timeout(100.milliseconds)
        elapsed = (Time.instant - started_at).total_seconds.to_i
        print "\r\e[2K#{SPINNER_FRAMES[frame % SPINNER_FRAMES.size]} thinking... #{format_elapsed(elapsed)}"
        STDOUT.flush
        frame += 1
      end
    end

    print "\r\e[2K"
    STDOUT.flush
    raise response if response.is_a?(Exception)
    response
  end

  private def format_elapsed(seconds : Int32) : String
    return "#{seconds}s" if seconds < 60

    "#{seconds // 60}m #{seconds % 60}s"
  end

  private def build_headers(extra_headers : HTTP::Headers? = nil)
    headers = HTTP::Headers{
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type"  => "application/json",
    }
    extra_headers.try &.each do |key, value|
      headers.add(key, value)
    end
    headers
  end
end
