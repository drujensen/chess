require "../spot.cr"

abstract class ChessMan
  property character : Char
  property white : Bool?
  property moved : Bool = false
  property value : Int32
  property en_passant : Bool

  def initialize(@white = nil, @character = ' ', @value = 0, @en_passant = false)
  end

  def draw
    "#{character} "
  end

  abstract def valid?(board : Board, from_x, from_y, to_x, to_y)
end
