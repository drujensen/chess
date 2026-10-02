require "time"
require "./board.cr"
require "./ai.cr"
require "./profile.cr"
require "./game_over.cr"
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
      @white = true
      saved.moves.each do |move|
        @board.turn(move, @white)
        @white = !@white
      end
      @ai = AI.new(skill_level, resume_moves: saved.moves)
      puts "resumed game (#{skill_level}) - #{saved.moves.size} moves replayed. #{@white ? "white" : "black"}'s turn."
    else
      @ai = AI.new(select_skill_level)
      @white = true
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

  def next_turn
    puts "#{@white ? "white" : "black"}'s turn: "
    if @white
      drain_stdin
      input = gets
      raise "goodbye!" if input.nil?
      move = input.strip
      move = nil if move.empty?
      raise "game saved - see you next time!" if move && ["quit", "exit", "save"].includes?(move.downcase)
      raise GameOver.new("you resign - black wins!", "0-1") if move && move.downcase == "resign"
    else
      move = ai.next_move(board, last_error)
      puts move
    end

    if move
      if @white && !(move =~ /^\D\d(x)?\D\d$/)
        resolved = ai.resolve_move(board, move)
        if resolved.nil?
          puts ai.chat(board, move)
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
    saved.saved_at = Time.local.to_s("%Y-%m-%d %H:%M:%S")
    saved.save
  end

  private def finish_game(result : String)
    SavedGame.clear

    score = case result
            when "1-0" then 1.0
            when "0-1" then 0.0
            else            0.5
            end

    old_rating = profile.rating
    profile.record_result(ai.skill_level.elo_midpoint, score)
    profile.save

    headers = {
      "Event"  => "Casual Game vs AI",
      "Site"   => "Local",
      "Date"   => Time.local.to_s("%Y.%m.%d"),
      "Round"  => "-",
      "White"  => profile.name,
      "Black"  => "AI (#{ai.skill_level}, ~#{ai.skill_level.elo_midpoint} Elo)",
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
      @board.draw
      next_turn
    end
  rescue ex : GameOver
    @board.draw
    puts ex.message
    finish_game(ex.result)
  rescue ex
    @board.draw
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
