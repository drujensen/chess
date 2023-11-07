require "./chessman.cr"

class Bishop < ChessMan
  def initialize(@white = true)
    @character = white ? '♝' : '♗'
    @value = 3
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    to_spot = Spot.new(to_x, to_y)
    spots = [] of Spot

    y = from_y
    (0..from_x - 1).reverse_each do |x|
      y += 1
      break if y > 7
      to_w = board.pieces[y][x].white
      if to_w == nil
        spots << Spot.new(x, y)
      elsif to_w == !white
        spots << Spot.new(x, y)
        break
      else
        break
      end
    end

    y = from_y
    (from_x + 1..7).each do |x|
      y += 1
      break if y > 7
      to_w = board.pieces[y][x].white
      if to_w == nil
        spots << Spot.new(x, y)
      elsif to_w == !white
        spots << Spot.new(x, y)
        break
      else
        break
      end
    end

    y = from_y
    (0..from_x - 1).reverse_each do |x|
      y -= 1
      break if y < 0
      to_w = board.pieces[y][x].white
      if to_w == nil
        spots << Spot.new(x, y)
      elsif to_w == !white
        spots << Spot.new(x, y)
        break
      else
        break
      end
    end

    y = from_y
    (from_x + 1..7).each do |x|
      y -= 1
      break if y < 0
      to_w = board.pieces[y][x].white
      if to_w == nil
        spots << Spot.new(x, y)
      elsif to_w == !white
        spots << Spot.new(x, y)
        break
      else
        break
      end
    end

    return spots.any? { |spot| spot == to_spot }
  end
end
