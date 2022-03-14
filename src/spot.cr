class Spot
  include Comparable(Spot)

  property x : Int32
  property y : Int32

  def initialize(@x : Int32, @y : Int32)
  end

  def <=>(other : Spot)
    n = x <=> other.x
    return n if n != 0
    y <=> other.y
  end
end
