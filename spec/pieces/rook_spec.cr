require "../spec_helper"

describe Rook do
  describe "#valid?" do
    board = Board.new
    rook = Rook.new(true)

    board.pieces[4][4] = rook

    it "allows moving vertically and horizontally on an empty board" do
      # Horizontal moves
      (0..7).each do |x|
        next if x == 4 # Skip the rook's current position
        rook.valid?(board, 4, 4, x, 4).should be_true
      end

      # Vertical moves
      (0..7).each do |y|
        next if y == 4 # Skip the rook's current position
        rook.valid?(board, 4, 4, 4, y).should be_true
      end
    end

    it "does not allow moving diagonally" do
      # Diagonal moves
      (-1..1).step(2) do |dx|
        (-1..1).step(2) do |dy|
          (1..3).each do |i|
            rook.valid?(board, 4, 4, 4 + i * dx, 4 + i * dy).should be_false
          end
        end
      end
    end

    it "does not allow moving over other pieces" do
      board.pieces[4][2] = Rook.new        # Friendly piece at (2, 4)
      board.pieces[4][6] = Rook.new(false) # Enemy piece at (6, 4)

      # Blocked by friendly piece
      rook.valid?(board, 4, 4, 1, 4).should be_false
      # Can capture enemy piece
      rook.valid?(board, 4, 4, 6, 4).should be_true
      # Blocked by enemy piece
      rook.valid?(board, 4, 4, 7, 4).should be_false
    end
  end
end
