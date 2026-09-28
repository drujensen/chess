require "./pieces/*"

class Board
  property pieces : Array(Array(ChessMan))
  property white_captured : Array(ChessMan)
  property black_captured : Array(ChessMan)
  property moves : Array(String)
  property sans : Array(String)
  property halfmove_clock : Int32
  property position_counts : Hash(String, Int32)

  def initialize
    @pieces = Array(Array(ChessMan)).new(8) do
      Array(ChessMan).new(8) do
        Empty.new
      end
    end
    @black_captured = Array(ChessMan).new
    @white_captured = Array(ChessMan).new
    @moves = Array(String).new
    @sans = Array(String).new
    @halfmove_clock = 0
    @position_counts = Hash(String, Int32).new(0)
  end

  def setup
    init_black
    init_white
    record_position(true)
  end

  def init_black
    @pieces[7][0] = Rook.new(false)
    @pieces[7][1] = Knight.new(false)
    @pieces[7][2] = Bishop.new(false)
    @pieces[7][3] = Queen.new(false)
    @pieces[7][4] = King.new(false)
    @pieces[7][5] = Bishop.new(false)
    @pieces[7][6] = Knight.new(false)
    @pieces[7][7] = Rook.new(false)

    @pieces[6][0] = Pawn.new(false)
    @pieces[6][1] = Pawn.new(false)
    @pieces[6][2] = Pawn.new(false)
    @pieces[6][3] = Pawn.new(false)
    @pieces[6][4] = Pawn.new(false)
    @pieces[6][5] = Pawn.new(false)
    @pieces[6][6] = Pawn.new(false)
    @pieces[6][7] = Pawn.new(false)
  end

  def init_white
    @pieces[0][0] = Rook.new(true)
    @pieces[0][1] = Knight.new(true)
    @pieces[0][2] = Bishop.new(true)
    @pieces[0][3] = Queen.new(true)
    @pieces[0][4] = King.new(true)
    @pieces[0][5] = Bishop.new(true)
    @pieces[0][6] = Knight.new(true)
    @pieces[0][7] = Rook.new(true)

    @pieces[1][0] = Pawn.new(true)
    @pieces[1][1] = Pawn.new(true)
    @pieces[1][2] = Pawn.new(true)
    @pieces[1][3] = Pawn.new(true)
    @pieces[1][4] = Pawn.new(true)
    @pieces[1][5] = Pawn.new(true)
    @pieces[1][6] = Pawn.new(true)
    @pieces[1][7] = Pawn.new(true)
  end

  def turn(move : String, white : Bool) : Bool
    # move needs to be either 4 or 5 characters long (with 'x' for captures)
    return false unless move =~ /^\D\d(x)?\D\d$/

    # Remove 'x' if present
    move = move.delete('x')

    # convert a-h to 0-7
    from_x = move.chars[0].ord - 'a'.ord
    return false if from_x < 0 || from_x > 7

    # convert 1-8 to 0-7
    from_y = move.chars[1].to_i - 1
    return false if from_y < 0 || from_y > 7

    # convert a-h to 0-7
    to_x = move.chars[2].ord - 'a'.ord
    return false if to_x < 0 || to_x > 7

    # convert 1-8 to 0-7
    to_y = move.chars[3].to_i - 1
    return false if to_y < 0 || to_y > 7

    # check if piece is yours
    return false if @pieces[from_y][from_x].white != white

    # check if new location is empty or opponents
    return false if @pieces[to_y][to_x].white == white

    # check piece if a valid move
    return false unless @pieces[from_y][from_x].valid?(self, from_x, from_y, to_x, to_y)

    # a move that leaves your own king in check is not legal
    return false if move_leaves_king_in_check?(from_x, from_y, to_x, to_y, white)

    # an en passant capture is only available for the single move right
    # after the opponent's double pawn step - expire any older flags
    @pieces.each { |row| row.each { |p| p.en_passant = false if p.is_a?(Pawn) && p.white == !white } }

    # a pawn move or a capture resets the fifty-move-rule clock
    was_pawn_move = @pieces[from_y][from_x].is_a?(Pawn)

    # everything needed for SAN must be read before the board is mutated
    san_prefix = san_prefix_for(from_x, from_y, to_x, to_y, white)

    # save the lost piece
    lost = @pieces[to_y][to_x]

    # save move
    @moves << "#{white ? "w" : "b"}: #{move}"

    # move to new location
    @pieces[to_y][to_x] = @pieces[from_y][from_x]
    @pieces[to_y][to_x].moved = true

    # if king side castle then move rook
    if @pieces[to_y][to_x].is_a?(King) && (from_x - to_x).abs == 2
      if to_x == 6
        @pieces[to_y][5] = @pieces[to_y][7]
        @pieces[to_y][5].moved = true
        @pieces[to_y][7] = Empty.new
      elsif to_x == 2
        @pieces[to_y][3] = @pieces[to_y][0]
        @pieces[to_y][3].moved = true
        @pieces[to_y][0] = Empty.new
      end
    end

    # if pawn promotion then promote to queen
    if @pieces[to_y][to_x].is_a?(Pawn) && (to_y == 0 || to_y == 7)
      @pieces[to_y][to_x] = Queen.new(white)
    end

    # if pawn double move then set en passant
    if @pieces[to_y][to_x].is_a?(Pawn) && (from_y - to_y).abs == 2
      @pieces[to_y][to_x].en_passant = true
    end

    # if capturing en passant - only when the mover was a pawn moving
    # diagonally onto a square that was actually empty; a normal diagonal
    # capture onto an occupied square must never fall into this branch, or
    # it wrongly deletes whatever piece happens to sit on the "captured
    # pawn" square instead
    if was_pawn_move && lost.is_a?(Empty)
      if white
        if from_y == 4 && to_y == 5 && (from_x - to_x).abs == 1
          lost = @pieces[4][to_x]
          @pieces[4][to_x] = Empty.new
        end
      else
        if from_y == 3 && to_y == 2 && (from_x - to_x).abs == 1
          lost = @pieces[3][to_x]
          @pieces[3][to_x] = Empty.new
        end
      end
    end

    if lost.is_a?(Empty)
      lost = nil
    else
      lost.white ? @white_captured << lost : @black_captured << lost
    end

    # empty old location
    @pieces[from_y][from_x] = Empty.new

    # did you win?
    if lost.is_a?(King)
      raise Exception.new("#{white ? "white" : "black"} wins! game over.")
    end

    if was_pawn_move || lost
      @halfmove_clock = 0
    else
      @halfmove_clock += 1
    end
    record_position(!white)

    if checkmate?(!white)
      san_prefix += "#"
    elsif in_check?(!white)
      san_prefix += "+"
    end
    @sans << san_prefix

    return true
  end

  # All squares a piece of the given color could legally move to right now,
  # in long algebraic notation (e.g. "e2e4"). Used for blunder-injection when
  # simulating a weaker skill level.
  def legal_moves(white : Bool) : Array(String)
    moves = [] of String
    (0..7).each do |from_y|
      (0..7).each do |from_x|
        piece = @pieces[from_y][from_x]
        next if piece.white != white

        (0..7).each do |to_y|
          (0..7).each do |to_x|
            next if from_x == to_x && from_y == to_y
            next if @pieces[to_y][to_x].white == white
            next unless piece.valid?(self, from_x, from_y, to_x, to_y)
            next if move_leaves_king_in_check?(from_x, from_y, to_x, to_y, white)

            from_file = ('a'.ord + from_x).chr
            to_file = ('a'.ord + to_x).chr
            moves << "#{from_file}#{from_y + 1}#{to_file}#{to_y + 1}"
          end
        end
      end
    end
    moves
  end

  def king_position(white : Bool) : Spot?
    (0..7).each do |y|
      (0..7).each do |x|
        piece = @pieces[y][x]
        return Spot.new(x, y) if piece.is_a?(King) && piece.white == white
      end
    end
    nil
  end

  def in_check?(white : Bool) : Bool
    king = king_position(white)
    return false if king.nil?

    (0..7).each do |y|
      (0..7).each do |x|
        piece = @pieces[y][x]
        next if piece.white != !white
        return true if piece.valid?(self, x, y, king.x, king.y)
      end
    end
    false
  end

  def checkmate?(white : Bool) : Bool
    in_check?(white) && legal_moves(white).empty?
  end

  def stalemate?(white : Bool) : Bool
    !in_check?(white) && legal_moves(white).empty?
  end

  # Retraces #turn's own legality checks, in the same order, to explain why
  # a rejected move was rejected - so the human/AI gets a concrete reason
  # ("that leaves your king in check") instead of a bare "invalid move".
  # Only meaningful to call after #turn has already returned false.
  def explain_invalid_move(move : String, white : Bool) : String
    return "'#{move}' isn't a recognizable move - use long algebraic notation like e2e4" unless move =~ /^\D\d(x)?\D\d$/

    clean = move.delete('x')
    from_x = clean.chars[0].ord - 'a'.ord
    from_y = clean.chars[1].to_i - 1
    to_x = clean.chars[2].ord - 'a'.ord
    to_y = clean.chars[3].to_i - 1

    return "that square is off the board" if [from_x, from_y, to_x, to_y].any? { |n| n < 0 || n > 7 }
    return "you don't have a piece on that starting square" if @pieces[from_y][from_x].white != white
    return "that destination square already has one of your own pieces on it" if @pieces[to_y][to_x].white == white
    return "that piece can't move that way" unless @pieces[from_y][from_x].valid?(self, from_x, from_y, to_x, to_y)
    return "that would leave your own king in check" if move_leaves_king_in_check?(from_x, from_y, to_x, to_y, white)

    "that move looks legal, so something else went wrong"
  end

  # Finds which of the color's current legal moves (in long algebraic
  # notation) produces the given SAN token, for replaying a saved PGN move
  # by move without needing a separate SAN parser.
  def find_move_for_san(san : String, white : Bool) : String?
    target = san.gsub(/[+#]$/, "")
    legal_moves(white).find do |candidate|
      from_x = candidate[0].ord - 'a'.ord
      from_y = candidate[1].to_i - 1
      to_x = candidate[2].ord - 'a'.ord
      to_y = candidate[3].to_i - 1
      san_prefix_for(from_x, from_y, to_x, to_y, white) == target
    end
  end

  # SAN for a candidate move that hasn't been played yet, e.g. an engine's
  # suggested "better move" - no check/mate suffix, since that needs the
  # position after playing it, which a move under consideration never gets.
  def move_to_san(move : String, white : Bool) : String
    from_x = move[0].ord - 'a'.ord
    from_y = move[1].to_i - 1
    to_x = move[2].ord - 'a'.ord
    to_y = move[3].to_i - 1
    san_prefix_for(from_x, from_y, to_x, to_y, white)
  end

  # Forsyth-Edwards Notation for the current position, for use as a compact
  # "here's the board" tool response for the AI - cheaper and less ambiguous
  # than reconstructing state from a move-history string.
  def to_fen(white_to_move : Bool) : String
    "#{position_key(white_to_move)} #{halfmove_clock} #{(@moves.size // 2) + 1}"
  end

  # A draw may be claimed once no pawn has moved and no piece has been
  # captured in the last 50 moves by each side (100 plies).
  def draw_by_fifty_move_rule? : Bool
    @halfmove_clock >= 100
  end

  # A draw may be claimed once the same position (piece placement, side to
  # move, castling rights, en passant target) has occurred three times.
  def draw_by_repetition? : Bool
    @position_counts.each_value do |count|
      return true if count >= 3
    end
    false
  end

  private def record_position(white_to_move : Bool)
    key = position_key(white_to_move)
    @position_counts[key] += 1
  end

  # Piece placement, side to move, castling rights, and en passant target -
  # everything that identifies a position for threefold-repetition purposes,
  # without the halfmove/fullmove counters that make every FEN unique.
  private def position_key(white_to_move : Bool) : String
    placement = (0..7).to_a.reverse.map { |y| fen_rank(y) }.join("/")
    active = white_to_move ? "w" : "b"
    "#{placement} #{active} #{fen_castling_rights} #{fen_en_passant_target}"
  end

  private def fen_rank(y : Int32) : String
    String.build do |str|
      empty_count = 0
      (0..7).each do |x|
        char = fen_char(@pieces[y][x])
        if char.nil?
          empty_count += 1
        else
          str << empty_count if empty_count > 0
          empty_count = 0
          str << char
        end
      end
      str << empty_count if empty_count > 0
    end
  end

  private def fen_char(piece : ChessMan) : Char?
    letter = case piece
             when Pawn   then 'p'
             when Knight then 'n'
             when Bishop then 'b'
             when Rook   then 'r'
             when Queen  then 'q'
             when King   then 'k'
             else
               return nil
             end
    piece.white ? letter.upcase : letter
  end

  private def fen_castling_rights : String
    rights = String.build do |str|
      str << "K" if can_castle_rights?(true, king_side: true)
      str << "Q" if can_castle_rights?(true, king_side: false)
      str << "k" if can_castle_rights?(false, king_side: true)
      str << "q" if can_castle_rights?(false, king_side: false)
    end
    rights.empty? ? "-" : rights
  end

  private def can_castle_rights?(white : Bool, king_side : Bool) : Bool
    rank = white ? 0 : 7
    king = @pieces[rank][4]
    return false unless king.is_a?(King) && !king.moved

    rook = @pieces[rank][king_side ? 7 : 0]
    rook.is_a?(Rook) && !rook.moved
  end

  private def fen_en_passant_target : String
    (0..7).each do |y|
      (0..7).each do |x|
        piece = @pieces[y][x]
        next unless piece.is_a?(Pawn) && piece.en_passant

        target_y = piece.white ? y - 1 : y + 1
        file = ('a'.ord + x).chr
        return "#{file}#{target_y + 1}"
      end
    end
    "-"
  end

  # Standard Algebraic Notation for the game's moves, PGN-ready (e.g. "e4",
  # "Nf3", "O-O", "Qxh4#"). Built incrementally by #turn since it needs both
  # pre-move state (piece identity, disambiguation) and post-move state
  # (check/checkmate suffix).
  def to_pgn(headers : Hash(String, String), result : String) : String
    header_lines = headers.map { |key, value| %([#{key} "#{value}"]) }.join("\n")

    move_text = String.build do |str|
      @sans.each_with_index do |san, i|
        str << "#{(i // 2) + 1}. " if i.even?
        str << san << " "
      end
      str << result
    end

    # A trailing blank line is required, not just a newline - the PGN spec
    # separates consecutive games in a multi-game file with one, and without
    # it a parser that builds a game list from [Event] tags (as PyChess
    # does) can still list this game but fail to find where its movetext
    # ends, showing a blank board when you open it.
    "#{header_lines}\n\n#{move_text}\n\n"
  end

  private def san_prefix_for(from_x, from_y, to_x, to_y, white) : String
    piece = @pieces[from_y][from_x]
    is_pawn = piece.is_a?(Pawn)
    is_castle = piece.is_a?(King) && (from_x - to_x).abs == 2
    return to_x == 6 ? "O-O" : "O-O-O" if is_castle

    is_en_passant = is_pawn && from_x != to_x && @pieces[to_y][to_x].is_a?(Empty)
    is_capture = !@pieces[to_y][to_x].is_a?(Empty) || is_en_passant
    promotes = is_pawn && (to_y == 0 || to_y == 7)

    from_file = ('a'.ord + from_x).chr
    to_square = "#{('a'.ord + to_x).chr}#{to_y + 1}"

    prefix = if is_pawn
               is_capture ? "#{from_file}x#{to_square}" : to_square
             else
               "#{san_piece_letter(piece)}#{san_disambiguation(piece, from_x, from_y, to_x, to_y, white)}#{is_capture ? "x" : ""}#{to_square}"
             end
    promotes ? "#{prefix}=Q" : prefix
  end

  private def san_piece_letter(piece : ChessMan) : String
    case piece
    when Knight then "N"
    when Bishop then "B"
    when Rook   then "R"
    when Queen  then "Q"
    when King   then "K"
    else
      ""
    end
  end

  # Which of file, rank, or both are needed to tell this piece's move apart
  # from another piece of the same type and color that could reach the same
  # square - the standard SAN disambiguation rule.
  private def san_disambiguation(piece : ChessMan, from_x, from_y, to_x, to_y, white) : String
    others = [] of Spot
    (0..7).each do |y|
      (0..7).each do |x|
        next if x == from_x && y == from_y

        candidate = @pieces[y][x]
        next unless candidate.class == piece.class && candidate.white == white
        next unless candidate.valid?(self, x, y, to_x, to_y)
        next if move_leaves_king_in_check?(x, y, to_x, to_y, white)

        others << Spot.new(x, y)
      end
    end
    return "" if others.empty?

    same_file = others.any? { |spot| spot.x == from_x }
    same_rank = others.any? { |spot| spot.y == from_y }
    from_file = ('a'.ord + from_x).chr
    if !same_file
      from_file.to_s
    elsif !same_rank
      (from_y + 1).to_s
    else
      "#{from_file}#{from_y + 1}"
    end
  end

  # Simulates the move on the piece grid, checks whether it leaves the
  # mover's own king in check, then reverts. Doesn't replay castling/en
  # passant side effects since those never remove check on their own king.
  private def move_leaves_king_in_check?(from_x, from_y, to_x, to_y, white) : Bool
    moving_piece = @pieces[from_y][from_x]
    captured_piece = @pieces[to_y][to_x]

    @pieces[to_y][to_x] = moving_piece
    @pieces[from_y][from_x] = Empty.new
    result = in_check?(white)
    @pieces[from_y][from_x] = moving_piece
    @pieces[to_y][to_x] = captured_piece

    result
  end

  def draw
    puts "black: #{white_captured.sum(&.value)} white: #{black_captured.sum(&.value)}"
    puts "\e[0m  a b c d e f g h \e[0m"
    puts "\e[0m8 \e[48;5;240m#{pieces[7][0].draw}\e[48;5;243m#{pieces[7][1].draw}\e[48;5;240m#{pieces[7][2].draw}\e[48;5;243m#{pieces[7][3].draw}\e[48;5;240m#{pieces[7][4].draw}\e[48;5;243m#{pieces[7][5].draw}\e[48;5;240m#{pieces[7][6].draw}\e[48;5;243m#{pieces[7][7].draw}\e[0m 8"
    puts "\e[0m7 \e[48;5;243m#{pieces[6][0].draw}\e[48;5;240m#{pieces[6][1].draw}\e[48;5;243m#{pieces[6][2].draw}\e[48;5;240m#{pieces[6][3].draw}\e[48;5;243m#{pieces[6][4].draw}\e[48;5;240m#{pieces[6][5].draw}\e[48;5;243m#{pieces[6][6].draw}\e[48;5;240m#{pieces[6][7].draw}\e[0m 7"
    puts "\e[0m6 \e[48;5;240m#{pieces[5][0].draw}\e[48;5;243m#{pieces[5][1].draw}\e[48;5;240m#{pieces[5][2].draw}\e[48;5;243m#{pieces[5][3].draw}\e[48;5;240m#{pieces[5][4].draw}\e[48;5;243m#{pieces[5][5].draw}\e[48;5;240m#{pieces[5][6].draw}\e[48;5;243m#{pieces[5][7].draw}\e[0m 6"
    puts "\e[0m5 \e[48;5;243m#{pieces[4][0].draw}\e[48;5;240m#{pieces[4][1].draw}\e[48;5;243m#{pieces[4][2].draw}\e[48;5;240m#{pieces[4][3].draw}\e[48;5;243m#{pieces[4][4].draw}\e[48;5;240m#{pieces[4][5].draw}\e[48;5;243m#{pieces[4][6].draw}\e[48;5;240m#{pieces[4][7].draw}\e[0m 5"
    puts "\e[0m4 \e[48;5;240m#{pieces[3][0].draw}\e[48;5;243m#{pieces[3][1].draw}\e[48;5;240m#{pieces[3][2].draw}\e[48;5;243m#{pieces[3][3].draw}\e[48;5;240m#{pieces[3][4].draw}\e[48;5;243m#{pieces[3][5].draw}\e[48;5;240m#{pieces[3][6].draw}\e[48;5;243m#{pieces[3][7].draw}\e[0m 4"
    puts "\e[0m3 \e[48;5;243m#{pieces[2][0].draw}\e[48;5;240m#{pieces[2][1].draw}\e[48;5;243m#{pieces[2][2].draw}\e[48;5;240m#{pieces[2][3].draw}\e[48;5;243m#{pieces[2][4].draw}\e[48;5;240m#{pieces[2][5].draw}\e[48;5;243m#{pieces[2][6].draw}\e[48;5;240m#{pieces[2][7].draw}\e[0m 3"
    puts "\e[0m2 \e[48;5;240m#{pieces[1][0].draw}\e[48;5;243m#{pieces[1][1].draw}\e[48;5;240m#{pieces[1][2].draw}\e[48;5;243m#{pieces[1][3].draw}\e[48;5;240m#{pieces[1][4].draw}\e[48;5;243m#{pieces[1][5].draw}\e[48;5;240m#{pieces[1][6].draw}\e[48;5;243m#{pieces[1][7].draw}\e[0m 2"
    puts "\e[0m1 \e[48;5;243m#{pieces[0][0].draw}\e[48;5;240m#{pieces[0][1].draw}\e[48;5;243m#{pieces[0][2].draw}\e[48;5;240m#{pieces[0][3].draw}\e[48;5;243m#{pieces[0][4].draw}\e[48;5;240m#{pieces[0][5].draw}\e[48;5;243m#{pieces[0][6].draw}\e[48;5;240m#{pieces[0][7].draw}\e[0m 1"
    puts "\e[0m  a b c d e f g h \e[0m"
  end
end
