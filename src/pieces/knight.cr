require "./chessman.cr"

class Knight < ChessMan
  def initialize(@white = true)
    super
    @character = white ? '♞' : '♘'
    @value = 3
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    # Calculate the difference in x and y coordinates
    delta_x = (from_x - to_x).abs
    delta_y = (from_y - to_y).abs

    # Check if the target spot is occupied by a piece of the same color
    target_piece = board.pieces[to_y][to_x]
    if target_piece && target_piece.white == @white
      return false
    end

    # A knight's move is valid if it moves 2 squares along one axis and 1 square along the other
    (delta_x == 2 && delta_y == 1) || (delta_x == 1 && delta_y == 2)
  end
end
