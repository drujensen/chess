require "./board.cr"
require "./profile.cr"

# Browse saved PGN files under ~/.chess/games and step through one move by
# move. Resolves each file's SAN move list back to long-algebraic moves via
# Board#find_move_for_san, rather than needing a standalone SAN parser.
module Replay
  RESULT_TOKENS = ["1-0", "0-1", "1/2-1/2", "*"]

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

  private def self.parse_sans(pgn : String) : Array(String)
    move_text = pgn.split("\n\n", 2).last
    move_text.split(/\s+/).reject do |token|
      token.empty? || token =~ /^\d+\.+$/ || RESULT_TOKENS.includes?(token)
    end
  end

  private def self.play(path : String)
    pgn = File.read(path)
    headers = parse_headers(pgn)

    moves = [] of String
    board = Board.new
    board.setup
    white = true
    parse_sans(pgn).each do |san|
      resolved = board.find_move_for_san(san, white)
      if resolved.nil?
        puts "could not resolve move '#{san}' - stopping replay there."
        break
      end
      board.turn(resolved, white)
      moves << resolved
      white = !white
    end

    puts "replaying: #{headers["White"]?} vs #{headers["Black"]?} (#{headers["Result"]?})"
    step(moves)
  end

  private def self.step(moves : Array(String))
    index = 0
    loop do
      board = Board.new
      board.setup
      white = true
      moves[0...index].each do |move|
        board.turn(move, white)
        white = !white
      end
      board.draw
      puts "move #{index}/#{moves.size}"
      print "[n]ext, [p]revious, [j]ump <n>, [q]uit > "

      input = gets.try(&.strip)
      case input
      when "n", ""
        index = Math.min(index + 1, moves.size)
      when "p"
        index = Math.max(index - 1, 0)
      when "q", nil
        break
      else
        if input.starts_with?("j")
          n = input.split[1]?.try(&.to_i?)
          index = n.clamp(0, moves.size) if n
        end
      end
    end
  end
end
