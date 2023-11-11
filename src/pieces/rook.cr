require "./chessman.cr"

class Rook < ChessMan
  def initialize(@white = true)
    super
    @character = white ? '♜' : '♖'
    @value = 5
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    return false unless straight_move?(from_x, from_y, to_x, to_y)
    path_clear?(board, from_x, from_y, to_x, to_y)
  end

  private def straight_move?(from_x, from_y, to_x, to_y)
    from_x == to_x || from_y == to_y
  end

  private def path_clear?(board, from_x, from_y, to_x, to_y)
    if from_x == to_x
      range = from_y < to_y ? (from_y + 1...to_y) : (to_y + 1...from_y)
      range.none? { |y| !board.pieces[y][from_x].is_a?(Empty) }
    else
      range = from_x < to_x ? (from_x + 1...to_x) : (to_x + 1...from_x)
      range.none? { |x| !board.pieces[from_y][x].is_a?(Empty) }
    end
  end
end
