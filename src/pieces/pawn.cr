require "./chessman.cr"

class Pawn < ChessMan
  def initialize(@white = true)
    @character = white ? '♟' : '♙'
    @value = 1
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    to_spot = Spot.new(to_x, to_y)
    to_w = board.pieces[to_y][to_x].white

    spots = [] of Spot
    if white
      spots << Spot.new(from_x, from_y + 1) if to_w == nil
      spots << Spot.new(from_x, from_y + 2) if to_w == nil && from_y == 1
      spots << Spot.new(from_x + 1, from_y + 1) if to_w == !white
      spots << Spot.new(from_x - 1, from_y + 1) if to_w == !white
    else
      spots << Spot.new(from_x, from_y - 1) if to_w == nil
      spots << Spot.new(from_x, from_y - 2) if to_w == nil && from_y == 6
      spots << Spot.new(from_x + 1, from_y - 1) if to_w == !white
      spots << Spot.new(from_x - 1, from_y - 1) if to_w == !white
    end

    return spots.any? { |spot| spot == to_spot }
  end
end
