require "../spec_helper"

describe King do
  describe "#valid?" do
    it "allows the King to move one square in any direction" do
      board = Board.new
      king = King.new(true)
      from_x, from_y = 4, 4 # Place the king in the center of the board

      # Test movement by one square in all directions
      [[3, 3], [3, 4], [3, 5], [4, 5], [4, 3], [5, 3], [5, 4], [5, 5]].each do |pos|
        to_x, to_y = pos
        king.valid?(board, from_x, from_y, to_x, to_y).should be_true
      end
    end

    it "does not allow the King to move more than one square away" do
      board = Board.new
      king = King.new(true)
      from_x, from_y = 4, 4 # Place the king in the center of the board

      # Test invalid movement more than one square away
      [[2, 2], [2, 4], [2, 6], [4, 6], [4, 2], [6, 2], [6, 4], [6, 6]].each do |pos|
        to_x, to_y = pos
        king.valid?(board, from_x, from_y, to_x, to_y).should be_false
      end
    end

    it "allows castling when conditions are met" do
      board = Board.new
      king = King.new
      rook = Rook.new
      from_x, from_y = 4, 0
      to_x, to_y = 6, 0

      # Set up the board for castling
      board.pieces[from_y][from_x] = king
      board.pieces[from_y][7] = rook

      king.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "disallows castling if the king has moved" do
      board = Board.new
      king = King.new
      king.moved = true # Simulate that the king has moved
      rook = Rook.new
      from_x, from_y = 4, 0
      to_x, to_y = 6, 0

      # Set up the board for castling
      board.pieces[from_y][from_x] = king
      board.pieces[from_y][7] = rook

      king.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end

    it "disallows castling if the rook has moved" do
      board = Board.new
      king = King.new
      rook = Rook.new
      rook.moved = true # Simulate that the king has moved
      from_x, from_y = 4, 0
      to_x, to_y = 6, 0

      # Set up the board for castling
      board.pieces[from_y][from_x] = king
      board.pieces[from_y][7] = rook

      king.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end
  end
end
