require "./chessman.cr"

class King < ChessMan
  def initialize(@white = true)
    @character = white ? '♚' : '♔'
    @value = 1000
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    to_spot = Spot.new(to_x, to_y)

    spots = [] of Spot
    spots << Spot.new(from_x - 1, from_y - 1)
    spots << Spot.new(from_x - 1, from_y)
    spots << Spot.new(from_x - 1, from_y + 1)
    spots << Spot.new(from_x, from_y + 1)
    spots << Spot.new(from_x, from_y - 1)
    spots << Spot.new(from_x + 1, from_y - 1)
    spots << Spot.new(from_x + 1, from_y)
    spots << Spot.new(from_x + 1, from_y + 1)

    if @white && !@moved
      # white king side
      if !board.pieces[0][7].moved &&
         board.pieces[0][6].is_a?(Empty) &&
         board.pieces[0][5].is_a?(Empty)
        spots << Spot.new(6, 0)
      end
      # white queen side
      if !board.pieces[0][0].moved &&
         board.pieces[0][1].is_a?(Empty) &&
         board.pieces[0][2].is_a?(Empty) &&
         board.pieces[0][3].is_a?(Empty)
        spots << Spot.new(2, 0)
      end
    end

    if !@white && !@moved
      # black king side
      if !board.pieces[7][7].moved &&
         board.pieces[7][6].is_a?(Empty) &&
         board.pieces[7][5].is_a?(Empty)
        spots << Spot.new(6, 7)
      end
      # black queen side
      if !board.pieces[7][0].moved &&
         board.pieces[7][1].is_a?(Empty) &&
         board.pieces[7][2].is_a?(Empty) &&
         board.pieces[7][3].is_a?(Empty)
        spots << Spot.new(2, 7)
      end
    end
    return spots.any? { |spot| spot == to_spot }
  end
end
