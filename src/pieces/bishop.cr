require "./chessman.cr"

class Bishop < ChessMan
  def initialize(@white = true)
    super
    @character = white ? '♝' : '♗'
    @value = 3
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    to_spot = Spot.new(to_x, to_y)
    paths = generate_diagonal_paths(board, from_x, from_y)
    paths.any? { |path| path.includes?(to_spot) }
  end

  private def generate_diagonal_paths(board : Board, from_x, from_y)
    paths = [] of Array(Spot)
    directions = [[-1, 1], [1, 1], [-1, -1], [1, -1]]

    directions.each do |dir|
      dx, dy = dir
      path = [] of Spot
      x, y = from_x, from_y

      while (0..7).includes?(x + dx) && (0..7).includes?(y + dy)
        x += dx
        y += dy
        to_color = board.pieces[y][x].white

        if to_color == nil
          path << Spot.new(x, y)
        elsif to_color == !white
          path << Spot.new(x, y)
          break
        else
          break
        end
      end

      paths << path
    end

    paths
  end
end
