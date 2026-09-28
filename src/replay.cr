require "./board.cr"
require "./profile.cr"
require "./analysis.cr"
require "./stockfish.cr"
require "./ai.cr"

# Browse saved PGN files under ~/.chess/games and step through one move by
# move. Resolves each file's SAN move list back to long-algebraic moves via
# Board#find_move_for_san, rather than needing a standalone SAN parser.
module Replay
  def self.browse
    games = saved_games
    if games.empty?
      puts "no saved games yet."
      return
    end

    games.each_with_index do |game, i|
      puts "#{i + 1}) #{game[:summary]}"
    end
    print "> (number, or blank to go back) "
    drain_stdin
    input = gets.try(&.strip)
    return if input.nil? || input.empty?

    index = input.to_i?
    unless index && index >= 1 && index <= games.size
      puts "invalid selection."
      return
    end

    play(games[index - 1][:path])
  end

  private def self.saved_games
    dir = Profile.directory / "games"
    return [] of NamedTuple(path: String, summary: String) unless Dir.exists?(dir.to_s)

    Dir.glob("#{dir}/*.pgn").sort.reverse.map do |path|
      headers = parse_headers(File.read(path))
      date = headers["Date"]? || "?"
      white = headers["White"]? || "?"
      black = headers["Black"]? || "?"
      result = headers["Result"]? || "*"
      {path: path, summary: "#{date} - #{white} vs #{black} (#{result})"}
    end
  end

  private def self.parse_headers(pgn : String) : Hash(String, String)
    headers = {} of String => String
    pgn.each_line do |line|
      if line =~ /^\[(\w+)\s+"(.*)"\]$/
        headers[$1] = $2
      end
    end
    headers
  end

  private def self.play(path : String)
    pgn = File.read(path)
    headers = parse_headers(pgn)
    notes = Analysis.parse(pgn)

    moves = [] of String
    board = Board.new
    board.setup
    white = true
    notes.each do |note|
      resolved = board.find_move_for_san(note[:san], white)
      if resolved.nil?
        puts "could not resolve move '#{note[:san]}' - stopping replay there."
        break
      end
      board.turn(resolved, white)
      moves << resolved
      white = !white
    end

    unless Analysis.annotated?(pgn) || moves.empty?
      notes = maybe_analyze(path, headers, moves, notes)
    end

    puts "replaying: #{headers["White"]?} vs #{headers["Black"]?} (#{headers["Result"]?})"
    step(moves, notes, path, headers)
  end

  # Offers to run Stockfish over a not-yet-annotated game and rewrite the
  # file with the results embedded, so it only ever runs once per game.
  private def self.maybe_analyze(path : String, headers : Hash(String, String), moves : Array(String), notes : Array(Analysis::Note)) : Array(Analysis::Note)
    unless Analysis.available?
      puts "stockfish isn't installed, so this game can't be analyzed for mistakes - install it (e.g. `sudo dnf install stockfish`) and reopen this game to enable it."
      return notes
    end

    print "analyze this game with Stockfish? this may take a bit. (y/N) "
    drain_stdin
    answer = gets.try(&.strip.downcase)
    return notes unless answer == "y" || answer == "yes"

    fresh = Analysis.analyze(moves) do |i, total|
      print "\ranalyzing move #{i}/#{total}..."
      STDOUT.flush
    end
    print "\r\e[2K"
    STDOUT.flush

    return notes if fresh.nil?

    result = headers["Result"]? || "*"
    File.write(path, Analysis.embed(headers, fresh, result))
    fresh
  end

  private def self.step(moves : Array(String), notes : Array(Analysis::Note), path : String, headers : Hash(String, String))
    index = 0
    loop do
      board = Board.new
      board.setup
      white = true
      moves[0...index].each do |move|
        board.turn(move, white)
        white = !white
      end

      flagged = index > 0 && !notes[index - 1][:comment].nil?
      if index > 0 && (eval = notes[index - 1][:eval])
        line = "eval: #{eval}"
        line += " - #{notes[index - 1][:comment]}" if notes[index - 1][:comment]
        puts line
      end
      board.draw
      played = index > 0 ? " (#{moves[index - 1]})" : ""
      puts "move #{index}/#{moves.size}#{played}"
      prompt = "[n]ext, [p]revious, [j]ump <n>, [q]uit"
      prompt += ", [e]xplain" if flagged
      print "#{prompt} > "
      drain_stdin

      input = gets.try(&.strip)
      case input
      when "n", ""
        index = Math.min(index + 1, moves.size)
      when "p"
        index = Math.max(index - 1, 0)
      when "q", nil
        break
      when "e"
        if flagged
          begin
            notes = explain(notes, moves, index, path, headers)
          rescue ex
            puts "couldn't get an explanation: #{ex.message}"
          end
        else
          puts "nothing to explain here - this move wasn't flagged."
        end
      else
        if input.starts_with?("j")
          n = input.split[1]?.try(&.to_i?)
          index = n.clamp(0, moves.size) if n
        end
      end
    end
  end

  # Gets (or, the first time, computes and caches) a plain-language
  # explanation for why a flagged move was worse than the engine's
  # suggestion. Stockfish supplies the concrete lines; the AI only narrates
  # them - see AI#explain_move for why that split matters.
  private def self.explain(notes : Array(Analysis::Note), moves : Array(String), index : Int32, path : String, headers : Hash(String, String)) : Array(Analysis::Note)
    note = notes[index - 1]
    if cached = note[:explanation]
      puts cached
      return notes
    end

    board = Board.new
    board.setup
    white = true
    moves[0...(index - 1)].each do |move|
      board.turn(move, white)
      white = !white
    end
    fen_before = board.to_fen(white)
    mover_white = white

    pv_before = nil
    pv_after = nil
    if Stockfish.available?
      engine = Stockfish.new(12)
      pv_before = engine.evaluate(fen_before)[:pv]
      board.turn(moves[index - 1], mover_white)
      pv_after = engine.evaluate(board.to_fen(!mover_white))[:pv]
      engine.close
    end

    explanation = AI.new.explain_move(fen_before, note[:san], Analysis.better_san(note), pv_after, pv_before)
    puts explanation

    updated = Analysis.with_explanation(notes, index - 1, explanation)
    File.write(path, Analysis.embed(headers, updated, headers["Result"]? || "*"))
    updated
  end
end
