require "./chessman.cr"

class Knight < ChessMan
  def initialize(@white = true)
    @character = white ? '♞' : '♘'
    @value = 3
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    to_spot = Spot.new(to_x, to_y)
    to_w = board.pieces[to_y][to_x].white

    spots = [] of Spot
    spots << Spot.new(from_x + 2, from_y + 1)
    spots << Spot.new(from_x + 2, from_y - 1)
    spots << Spot.new(from_x - 2, from_y + 1)
    spots << Spot.new(from_x - 2, from_y - 1)
    spots << Spot.new(from_x + 1, from_y + 2)
    spots << Spot.new(from_x + 1, from_y - 2)
    spots << Spot.new(from_x - 1, from_y + 2)
    spots << Spot.new(from_x - 1, from_y - 2)

    return spots.any? { |spot| spot == to_spot }
  end
end
