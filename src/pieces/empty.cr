require "./chessman.cr"

class Empty < ChessMan
  def initialize
    super
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    return false
  end
end
