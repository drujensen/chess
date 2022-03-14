require "./chessman.cr"

class Rook < ChessMan
  def initialize(@white = true)
    @character = white ? '♜' : '♖'
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    to_spot = Spot.new(to_x, to_y)
    spots = [] of Spot

    (0..from_x - 1).reverse_each do |x|
      to_w = board.pieces[from_y][x].white
      if to_w == nil
        spots << Spot.new(x, from_y)
      elsif to_w == !white
        spots << Spot.new(x, from_y)
        break
      else
        break
      end
    end

    (from_x + 1..7).each do |x|
      to_w = board.pieces[from_y][x].white
      if to_w == nil
        spots << Spot.new(x, from_y)
      elsif to_w == !white
        spots << Spot.new(x, from_y)
        break
      else
        break
      end
    end

    (0..from_y - 1).reverse_each do |y|
      to_w = board.pieces[y][from_x].white
      if to_w == nil
        spots << Spot.new(from_x, y)
      elsif to_w == !white
        spots << Spot.new(from_x, y)
        break
      else
        break
      end
    end

    (from_y + 1..7).each do |y|
      to_w = board.pieces[y][from_x].white
      if to_w == nil
        spots << Spot.new(from_x, y)
      elsif to_w == !white
        spots << Spot.new(from_x, y)
        break
      else
        break
      end
    end

    return spots.any? { |spot| spot == to_spot }
  end
end
