require "../spec_helper"

describe Queen do
  describe "#valid?" do
    # Create a board with no pieces for simplicity
    board = Board.new

    # Place a white queen at position (3, 3)
    queen = Queen.new(true)
    from_x, from_y = 3, 3

    before_each do
      board.pieces[from_y][from_x] = queen
    end

    it "returns true for a valid diagonal move" do
      to_x = 5
      to_y = 5
      queen.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "returns true for a valid straight move" do
      to_x = 3
      to_y = 6
      queen.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "returns false for an invalid move" do
      to_x = 4
      to_y = 5
      queen.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end

    it "returns false for a move blocked by another piece" do
      # Place a blocking piece at (3, 4)
      blocker = Pawn.new(true)
      board.pieces[4][3] = blocker

      to_x = 3
      to_y = 5
      queen.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end

    it "returns true for a move capturing an opponent's piece" do
      # Place an opponent's piece at (5, 5)
      opponent_piece = Pawn.new(false)
      board.pieces[5][5] = opponent_piece

      to_x = 5
      to_y = 5
      queen.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end
  end
end
