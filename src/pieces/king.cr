require "./chessman.cr"

class King < ChessMan
  def initialize(@white = true)
    super
    @character = white ? '♚' : '♔'
    @value = 4
  end

  def valid?(board : Board, from_x, from_y, to_x, to_y)
    dx = (to_x - from_x).abs
    dy = (to_y - from_y).abs

    # Check for standard king move (one square in any direction)
    return true if dx <= 1 && dy <= 1

    # Check for castling
    return can_castle?(board, from_x, from_y, to_x, to_y) if !@moved && (dx == 2 && dy == 0)

    false
  end

  private def can_castle?(board : Board, from_x, from_y, to_x, to_y)
    return false unless [0, 7].includes?(from_y) # Castling only happens on the king's row

    direction = to_x > from_x ? 1 : -1 # 1 for king side, -1 for queen side
    rook_x = direction == 1 ? 7 : 0
    rook = board.pieces[from_y][rook_x]

    # Check if the rook has moved or the spaces between the king and rook are not empty
    return false if !rook.is_a?(Rook) || rook.moved

    # Check if the squares between the king and the rook are empty
    (from_x + direction).step(to: rook_x - direction, by: direction).each do |x|
      return false unless board.pieces[from_y][x].is_a?(Empty)
    end

    true
  end
end
