require "../spec_helper"

describe Bishop do
  describe "#valid?" do
    it "returns true for valid diagonal moves" do
      board = Board.new
      bishop = Bishop.new(true) # White bishop
      from_x, from_y = 2, 0     # Starting position
      to_x, to_y = 4, 2         # Valid diagonal move

      # Assuming the board is empty or the path is clear
      board.pieces[to_y][to_x] = Empty.new

      bishop.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "returns false for invalid moves" do
      board = Board.new
      bishop = Bishop.new(true) # White bishop
      from_x, from_y = 2, 0     # Starting position
      to_x, to_y = 3, 0         # Invalid move (not diagonal)

      # Assuming the board is empty or the path is clear
      board.pieces[to_y][to_x] = Empty.new

      bishop.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end

    it "returns false for moves blocked by a piece of the same color" do
      board = Board.new
      bishop = Bishop.new(true) # White bishop
      from_x, from_y = 2, 0     # Starting position
      to_x, to_y = 4, 2         # Diagonal move blocked by another white piece

      # Placing a white piece in the path of the bishop
      board.pieces[from_y + 1][from_x + 1] = Bishop.new(true)

      bishop.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end

    it "returns true for moves that capture an opponent's piece" do
      board = Board.new
      bishop = Bishop.new(true) # White bishop
      from_x, from_y = 2, 0     # Starting position
      to_x, to_y = 4, 2         # Diagonal move that captures a black piece

      # Placing a black piece at the destination
      board.pieces[to_y][to_x] = Bishop.new(false)

      bishop.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end
  end
end
