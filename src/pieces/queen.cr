require "./chessman.cr"

class Queen < ChessMan
  def initialize(@white = true)
    super
    @character = white ? '♛' : '♕'
    @value = 9
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    to_spot = Spot.new(to_x, to_y)
    spots = [] of Spot

    y = from_y
    (0..from_x - 1).reverse_each do |x|
      y += 1
      break if y > 7
      to_color = board.pieces[y][x].white
      if to_color == nil
        spots << Spot.new(x, y)
      elsif to_color == !white
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
      to_color = board.pieces[y][x].white
      if to_color == nil
        spots << Spot.new(x, y)
      elsif to_color == !white
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
      to_color = board.pieces[y][x].white
      if to_color == nil
        spots << Spot.new(x, y)
      elsif to_color == !white
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
      to_color = board.pieces[y][x].white
      if to_color == nil
        spots << Spot.new(x, y)
      elsif to_color == !white
        spots << Spot.new(x, y)
        break
      else
        break
      end
    end

    (0..from_x - 1).reverse_each do |x|
      to_color = board.pieces[from_y][x].white
      if to_color == nil
        spots << Spot.new(x, from_y)
      elsif to_color == !white
        spots << Spot.new(x, from_y)
        break
      else
        break
      end
    end

    (from_x + 1..7).each do |x|
      to_color = board.pieces[from_y][x].white
      if to_color == nil
        spots << Spot.new(x, from_y)
      elsif to_color == !white
        spots << Spot.new(x, from_y)
        break
      else
        break
      end
    end

    (0..from_y - 1).reverse_each do |y|
      to_color = board.pieces[y][from_x].white
      if to_color == nil
        spots << Spot.new(from_x, y)
      elsif to_color == !white
        spots << Spot.new(from_x, y)
        break
      else
        break
      end
    end

    (from_y + 1..7).each do |y|
      to_color = board.pieces[y][from_x].white
      if to_color == nil
        spots << Spot.new(from_x, y)
      elsif to_color == !white
        spots << Spot.new(from_x, y)
        break
      else
        break
      end
    end

    return spots.any? { |spot| spot == to_spot }
  end
end
