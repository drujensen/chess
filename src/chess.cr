require "time"
require "./board.cr"
require "./ai.cr"
require "./profile.cr"
require "./game_over.cr"
require "./undo_requested.cr"
require "./replay.cr"
require "./saved_game.cr"

# Discards any input that arrived before this point, so a stray keystroke
# typed while waiting on something slow (the AI thinking, etc.) doesn't get
# misread as the answer to a prompt shown well after it was typed - e.g.
# quitting at the main menu turning into "start a new game" because an
# earlier keypress was still queued up when the prompt appeared.
def drain_stdin
  STDIN.read_timeout = 0.05.seconds
  loop do
    break if STDIN.gets.nil?
  end
rescue IO::TimeoutError
  # no more pending input - done draining
ensure
  STDIN.read_timeout = nil
end

class Chess
  VERSION = "0.1.0"
  property board : Board
  property ai : AI
  property profile : Profile
  property white : Bool
  property human_white : Bool
  property error_count : Int32
  property last_error : String
  property last_move : NamedTuple(tool_call_id: String, move: String)? = nil

  def initialize(saved : SavedGame? = nil)
    @board = Board.new
    @board.setup
    @profile = Profile.load
    puts "#{profile.name}'s rating: #{profile.rating.round(1)} (#{profile.games_played} games played)"
    puts "opponent: #{AI::MODEL} @ #{AI::BASE_URL}"
    @error_count = 0
    @last_error = ""

    if saved
      skill_level = SkillLevel.from_input(saved.skill_level) || SkillLevel::Advanced
      @human_white = saved.human_white
      @white = true
      saved.moves.each do |move|
        @board.turn(move, @white)
        @white = !@white
      end
      @ai = AI.new(skill_level, ai_white: !@human_white, resume_moves: saved.moves)
      puts "resumed game (#{skill_level}, you are #{@human_white ? "white" : "black"}) - #{saved.moves.size} moves replayed. #{@white ? "white" : "black"}'s turn."
    else
      skill_level = select_skill_level
      @human_white = select_side
      @ai = AI.new(skill_level, ai_white: !@human_white)
      @white = true
      puts "you are playing #{@human_white ? "white" : "black"}."
    end
  end

  def select_skill_level : SkillLevel
    puts "Select opponent skill level:"
    SkillLevel.values.each_with_index do |level, i|
      puts "#{i + 1}) #{level} (#{level.elo_range} Elo)"
    end
    print "> "
    drain_stdin
    SkillLevel.from_input(gets || "") || SkillLevel::Advanced
  end

  def select_side : Bool
    puts "Choose your side:"
    puts "1) White"
    puts "2) Black"
    puts "3) Random"
    print "> "
    drain_stdin
    case gets.try(&.strip)
    when "2" then false
    when "3" then rand < 0.5
    else          true
    end
  end

  def next_turn
    puts "#{@white ? "white" : "black"}'s turn: "
    humans_turn = @white == @human_white

    if humans_turn
      drain_stdin
      input = gets
      raise "goodbye!" if input.nil?
      move = input.strip
      move = nil if move.empty?
      raise "game saved - see you next time!" if move && ["quit", "exit", "save"].includes?(move.downcase)
      raise GameOver.new("you resign - #{@human_white ? "black" : "white"} wins!", @human_white ? "0-1" : "1-0") if move && move.downcase == "resign"

      if move && (undo_match = move.downcase.match(/^undo(?:\s+(\d+))?$/))
        undo((undo_match[1]? || "1").to_i)
        return
      end
    else
      move = ai.next_move(board, last_error)
      puts move
    end

    if move
      if humans_turn && !(move =~ /^\D\d(x)?\D\d$/)
        resolved = ai.resolve_move(board, move, @human_white)
        if resolved.nil?
          begin
            puts ai.chat(board, move)
          rescue ex : UndoRequested
            undo(ex.count)
          end
          return
        end
        puts "playing #{resolved} for you."
        ai.record_move_resolution(move, resolved)
        move = resolved
      end

      if board.turn(move, @white)
        report_game_status(!@white)
        @white = !@white
        @error_count = 0
        @last_error = ""
        save_progress
      else
        @last_error = "invalid move: #{move} - #{board.explain_invalid_move(move, @white)}. try again!"
        @error_count += 1
        puts @last_error
      end
    end
    if @error_count > 3
      raise "too many errors."
    end
  end

  # Takes back `rounds` of the human's own last moves - and the AI's reply to
  # each - so the human can try something different from an earlier position.
  # Triggered either by typing `undo` directly, or by the AI calling its own
  # `undo` tool mid-chat. Always removes an even number of plies (one full
  # round at a time) so the human lands back on their own turn to move, never
  # mid-AI-turn - an odd-ply undo would hand the very next turn straight back
  # to `ai.next_move` with no chance for the human to undo further or play
  # something else, defeating the point of "undo multiple times".
  #
  # There's no inverse of Board#turn to walk backwards (it has too much side
  # state - captures, castling rights, en passant, repetition counts - to
  # safely unwind by hand), so this rebuilds the board from scratch and
  # replays what's left, the same way resuming a saved game already does.
  # The AI gets a fresh instance briefed on the rolled-back position for the
  # same reason resuming does: its exact prior conversation can't be
  # surgically rewound (especially mid-tool-call, as from its own undo tool),
  # only approximated by re-briefing from the actual position.
  private def undo(rounds : Int32)
    all_moves = board.moves.map { |m| m.split(": ", 2).last }
    if all_moves.empty?
      puts "nothing to undo."
      return
    end

    remove = (rounds.clamp(1, Int32::MAX) * 2).clamp(1, all_moves.size)
    remaining = all_moves[0...(all_moves.size - remove)]

    @board = Board.new
    @board.setup
    white = true
    remaining.each do |move|
      @board.turn(move, white)
      white = !white
    end
    @white = white

    @ai = AI.new(ai.skill_level, ai_white: !@human_white, resume_moves: remaining)
    @error_count = 0
    @last_error = ""
    save_progress

    puts "undid #{remove} move#{remove == 1 ? "" : "s"} - #{remaining.size} move#{remaining.size == 1 ? "" : "s"} remain. #{@white ? "white" : "black"}'s turn."
  end

  private def report_game_status(white : Bool)
    if board.checkmate?(white)
      raise GameOver.new("checkmate! #{white ? "black" : "white"} wins!", white ? "0-1" : "1-0")
    elsif board.stalemate?(white)
      raise GameOver.new("stalemate! it's a draw.", "1/2-1/2")
    elsif board.draw_by_fifty_move_rule?
      raise GameOver.new("draw! 50 moves without a pawn move or capture.", "1/2-1/2")
    elsif board.draw_by_repetition?
      raise GameOver.new("draw! threefold repetition.", "1/2-1/2")
    elsif board.in_check?(white)
      puts "#{white ? "white" : "black"} is in check!"
    end
  end

  # Persists the in-progress game after every successful move, so Ctrl+C,
  # closing the terminal, or stdin EOF never loses committed moves.
  private def save_progress
    saved = SavedGame.new
    saved.moves = board.moves.map { |m| m.split(": ", 2).last }
    saved.skill_level = ai.skill_level.to_s
    saved.human_white = @human_white
    saved.saved_at = Time.local.to_s("%Y-%m-%d %H:%M:%S")
    saved.save
  end

  private def finish_game(result : String)
    SavedGame.clear

    # result is from white's perspective (PGN convention) - translate to a
    # score for the human specifically, since they may be playing either side.
    score = case result
            when "1/2-1/2" then 0.5
            else                @human_white == (result == "1-0") ? 1.0 : 0.0
            end

    old_rating = profile.rating
    profile.record_result(ai.skill_level.elo_midpoint, score)
    profile.save

    ai_name = "AI (#{ai.skill_level}, ~#{ai.skill_level.elo_midpoint} Elo)"
    headers = {
      "Event"  => "Casual Game vs AI",
      "Site"   => "Local",
      "Date"   => Time.local.to_s("%Y.%m.%d"),
      "Round"  => "-",
      "White"  => @human_white ? profile.name : ai_name,
      "Black"  => @human_white ? ai_name : profile.name,
      "Result" => result,
    }
    path = save_pgn(board.to_pgn(headers, result))

    puts "rating: #{old_rating.round(1)} -> #{profile.rating.round(1)} (#{profile.wins}W #{profile.losses}L #{profile.draws}D)"
    puts "game saved to #{path}"
  end

  private def save_pgn(pgn : String) : Path
    games_dir = Profile.directory / "games"
    Dir.mkdir_p(games_dir)
    path = games_dir / "#{Time.local.to_s("%Y%m%d-%H%M%S")}.pgn"
    File.write(path, pgn)
    path
  end

  def run
    while true
      @board.draw(!@human_white)
      next_turn
    end
  rescue ex : GameOver
    @board.draw(!@human_white)
    puts ex.message
    finish_game(ex.result)
  rescue ex
    @board.draw(!@human_white)
    puts ex.message
  end
end

loop do
  puts "\n1) New game"
  puts "2) Resume game"
  puts "3) Browse saved games"
  puts "4) Quit"
  print "> "
  drain_stdin

  case gets.try(&.strip)
  when "2"
    saved = SavedGame.load
    if saved
      Chess.new(saved).run
    else
      puts "no game in progress."
    end
  when "3"
    Replay.browse
  when "4", nil
    break
  else
    if SavedGame.exists?
      print "starting a new game will discard your in-progress game - continue? (y/N) "
      drain_stdin
      confirm = gets.try(&.strip.downcase)
      next unless confirm == "y" || confirm == "yes"
    end
    Chess.new.run
  end
end
