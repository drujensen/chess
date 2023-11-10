require "./chessman.cr"

class Pawn < ChessMan
  def initialize(@white = true)
    super
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

    # handle en passant here
    if white
      if from_y == 4 && to_y == 5 && to_w == nil
        if board.pieces[4][to_x].class == Pawn && board.pieces[4][to_x].en_passant
          spots << Spot.new(to_x, 5)
        end
      end
    else
      if from_y == 3 && to_y == 2 && to_w == nil
        if board.pieces[3][to_x].class == Pawn && board.pieces[3][to_x].en_passant
          spots << Spot.new(to_x, 2)
        end
      end
    end

    return spots.any? { |spot| spot == to_spot }
  end
end
