require "./pieces/*"

class Board
  property pieces : Array(Array(ChessMan))

  def initialize
    @pieces = Array(Array(ChessMan)).new(8) do
      Array(ChessMan).new(8) do
        Empty.new
      end
    end
    init_black
    init_white
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
    # move needs to be 4 characters long
    return false if move.size != 4
    # convert a-h to 0-7
    from_x = move.chars[0].ord - 97
    return false if from_x < 0 || from_x > 7

    # convert 1-8 to 0-7
    from_y = move.chars[1].to_i - 1
    return false if from_y < 0 || from_y > 7

    # convert a-h to 0-7
    to_x = move.chars[2].ord - 97
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

    # save the lost piece
    lost = @pieces[to_y][to_x]

    # move to new location
    @pieces[to_y][to_x] = @pieces[from_y][from_x]

    # empty old location
    @pieces[from_y][from_x] = Empty.new

    # did you win?
    if lost.is_a?(King)
      raise Exception.new("#{white ? "white" : "black"} wins! game over.")
    end

    return true
  end

  def draw
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
