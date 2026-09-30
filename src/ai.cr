require "json"
require "http/client"
require "time"
require "./skill_level.cr"
require "./game_over.cr"

class AI
  property prev_tool_id : String?
  property skill_level : SkillLevel
  BASE_URL      = ENV.fetch("OPENAI_BASE_URL", "http://localhost:11434/v1")
  BASE_URI      = URI.parse(BASE_URL)
  ENDPOINT_PATH = "#{BASE_URI.path}/chat/completions"
  MODEL         = ENV.fetch("OPENAI_MODEL", "qwen3.8:latest")

  # How long a single request may run before giving up - a slow or stuck
  # local model would otherwise hang forever with no way to notice, since
  # nothing else in this app puts any bound on how long "thinking" can take.
  CONNECT_TIMEOUT = 10.seconds
  TIMEOUT         = ENV.fetch("OPENAI_TIMEOUT", "300").to_i.seconds

  # resume_moves: long-algebraic moves already played (alternating white/
  # black, starting with white), when picking a previously-saved game back
  # up. The exact prior conversation can't be restored, so instead the model
  # is briefed with the game-so-far as its first message.
  def initialize(@skill_level : SkillLevel = SkillLevel::Advanced, resume_moves : Array(String)? = nil)
    @api_key = ENV["OPENAI_API_KEY"]?
    @client = HTTP::Client.new(BASE_URI)
    @client.connect_timeout = CONNECT_TIMEOUT
    @client.read_timeout = TIMEOUT
    @messages = [] of NamedTuple(role: String, content: String) | NamedTuple(tool_call_id: String, role: String, name: String, content: String) | JSON::Any

    @messages.push(
      {
        role:    "system",
        content: "You are a #{skill_level.to_s.downcase} chess player, rated approximately #{skill_level.elo_range} Elo. You are playing a game of chess against a human. the human is white and you are black. There are 4 functions available to you. moves: list of moves played so far. board: the current board position as FEN, call this whenever you need to see where the pieces actually are before choosing a move. move: play the next move. resign: give up the game if your position is truly lost (e.g. you're getting checkmated soon with no way out, or you've lost overwhelming material with no compensation) - only resign when it's genuinely hopeless, not just because you're slightly worse. You have about #{TIMEOUT.total_seconds.to_i} seconds to reply each time you're asked something - don't overthink it, decide promptly and call the relevant function.",
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
  def chat(board : Board, text : String) : String
    @messages.push({role: "user", content: text})
    chat_loop(board)
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
    body = {model: MODEL, temperature: 0.3, messages: messages}.to_json

    result = post_to_openai(body)
    choices = result["choices"]
    choices[choices.size - 1]["message"]["content"].to_s
  end

  private def chat_loop(board : Board) : String
    body = {
      model:       MODEL,
      temperature: 0.3,
      messages:    @messages,
      tools:       [moves_tool, board_tool],
      tool_choice: "auto",
    }.to_json

    result = post_to_openai(body)
    choices = result["choices"]
    message = choices[choices.size - 1]["message"]
    tool_calls = message["tool_calls"]?

    return message["content"].to_s if tool_calls.nil?

    @messages.push(message)
    tool = tool_calls[tool_calls.size - 1]
    tool_id = tool["id"].to_s

    case tool["function"]["name"]
    when "moves"
      puts "moves called: #{board.moves.join(", ")}"
      @messages.push({tool_call_id: tool_id, role: "tool", name: "moves", content: board.moves.join(", ")})
    else
      fen = board.to_fen(true)
      puts "board called: #{fen}"
      @messages.push({tool_call_id: tool_id, role: "tool", name: "board", content: fen})
    end

    chat_loop(board)
  end

  def next_move(board : Board, error : String? = nil) : String
    @messages.push({role: "user", content: "I played #{board.moves.last}.  your turn."})

    legal = board.legal_moves(false)

    if board.in_check?(false)
      @messages.push({
        role:    "system",
        content: "You are in check! You must play a move that gets your king out of check - capture the checking piece, block it, or move the king.",
      })
    end

    if legal.size == 1
      @messages.push({
        role:    "system",
        content: "You have exactly one legal move available right now: #{legal.first}. There is no other option - you must play this exact move.",
      })
    end

    unless error.nil? || error.empty?
      @messages.push({
        role:    "system",
        content: "error: #{error} Your legal moves right now are: #{legal.join(", ")}. Pick one of these exactly.",
      })
    end

    if rand < skill_level.weak_move_chance
      @messages.push({
        role:    "system",
        content: "For this move only: play like a genuine #{skill_level.to_s.downcase}. Don't calculate deeply - play a simple, natural-looking move rather than searching for your objectively strongest option, and it's fine to miss a tactic or overlook a threat. Legal moves right now: #{board.legal_moves(false).join(", ")}.",
      })
    end

    next_move_loop(board)
  end

  private def next_move_loop(board : Board) : String
    body = {
      model:       MODEL,
      temperature: 0.3,
      messages:    @messages,
      tools:       [moves_tool, board_tool, move_tool, resign_tool],
      tool_choice: "auto",
    }.to_json

    result = post_to_openai(body)

    choices = result["choices"]
    message = choices[choices.size - 1]["message"]

    tool_calls = message["tool_calls"]?

    if tool_calls.nil?
      puts message["content"]
      return next_move_loop(board)
    end

    @messages.push(message)

    tool = tool_calls[tool_calls.size - 1]
    tool_id = tool["id"].to_s

    case tool["function"]["name"]
    when "moves"
      puts "moves called: #{board.moves.join(", ")}"
      @messages.push({
        tool_call_id: tool_id,
        role:         "tool",
        name:         "moves",
        content:      "#{board.moves.join(", ")}",
      })

      next_move_loop(board)
    when "board"
      fen = board.to_fen(false)
      puts "board called: #{fen}"
      @messages.push({
        tool_call_id: tool_id,
        role:         "tool",
        name:         "board",
        content:      fen,
      })

      next_move_loop(board)
    when "resign"
      puts "black resigns!"
      raise GameOver.new("black resigns - white wins!", "1-0")
    else
      requested_move = JSON.parse(tool["function"]["arguments"].to_s)["nextMove"].to_s.strip
      @messages.push({
        tool_call_id: tool_id,
        role:         "tool",
        name:         "move",
        content:      "success",
      })

      puts "move called: #{requested_move}"
      requested_move
    end
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
        description: "resign the game - only when your position is genuinely hopeless, not just worse",
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
  def resolve_move(board : Board, text : String) : String?
    legal = board.legal_moves(true)
    return nil if legal.empty?

    messages = [
      {
        role:    "system",
        content: "You translate a chess player's instruction into one legal move for the white side. You are given the position as FEN and the full list of white's legal moves in long algebraic notation. If the instruction clearly identifies exactly one of those legal moves, call propose_move with it verbatim. If it's ambiguous, illegal, or isn't describing a move at all (e.g. a question or comment), call not_a_move instead.",
      },
      {
        role:    "user",
        content: "FEN: #{board.to_fen(true)}\nLegal moves: #{legal.join(", ")}\nInstruction: #{text}",
      },
    ]
    body = {
      model:       MODEL,
      temperature: 0.2,
      messages:    messages,
      tools:       [
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
      ],
      tool_choice: "auto",
    }.to_json

    result = post_to_openai(body)
    choices = result["choices"]
    message = choices[choices.size - 1]["message"]
    tool_calls = message["tool_calls"]?
    return nil if tool_calls.nil?

    tool = tool_calls[tool_calls.size - 1]
    return nil unless tool["function"]["name"] == "propose_move"

    move = JSON.parse(tool["function"]["arguments"].to_s)["move"].to_s.strip
    legal.includes?(move) ? move : nil
  end

  private def post_to_openai(body)
    retry_count = 0

    while retry_count < 3
      response = with_spinner { @client.post(ENDPOINT_PATH, headers: build_headers, body: body) }
      if response.success?
        return JSON.parse(response.body)
      else
        retry_count += 1
      end
    end
    raise "Failed to get response from OpenAI API"
  rescue e : IO::TimeoutError
    # not retried - the model was already given the full timeout once, and
    # trying again with the same budget just multiplies the wait
    raise "#{MODEL} didn't respond within #{TIMEOUT.total_seconds.to_i}s (set OPENAI_TIMEOUT to change this) - it may be stuck or overloaded."
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
