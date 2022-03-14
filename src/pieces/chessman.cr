require "../spot.cr"

abstract class ChessMan
  property character : Char
  property white : Bool?

  def initialize(@white = nil, @character = ' ')
  end

  def draw
    "#{character} "
  end

  abstract def valid?(board : Board, from_x, from_y, to_x, to_y)
end
