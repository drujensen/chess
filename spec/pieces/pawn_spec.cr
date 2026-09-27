require "../spec_helper"

describe Pawn do
  describe "#valid?" do
    # Create a board and a pawn for the tests
    board = Board.new
    white_pawn = Pawn.new(true)
    black_pawn = Pawn.new(false)

    it "allows white pawn to move forward one square" do
      from_x, from_y = 4, 1
      to_x, to_y = 4, 2
      board.pieces[from_y][from_x] = white_pawn
      white_pawn.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "allows white pawn to move forward two squares from starting position" do
      from_x, from_y = 4, 1
      to_x, to_y = 4, 3
      board.pieces[from_y][from_x] = white_pawn
      white_pawn.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "allows black pawn to move forward one square" do
      from_x, from_y = 4, 6
      to_x, to_y = 4, 5
      board.pieces[from_y][from_x] = black_pawn
      black_pawn.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "allows black pawn to move forward two squares from starting position" do
      from_x, from_y = 4, 6
      to_x, to_y = 4, 4
      board.pieces[from_y][from_x] = black_pawn
      black_pawn.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "does not allow white pawn to move forward if blocked" do
      from_x, from_y = 4, 1
      to_x, to_y = 4, 2
      blocking_piece = Pawn.new(false) # Black pawn as a blocker
      board.pieces[from_y][from_x] = white_pawn
      board.pieces[to_y][to_x] = blocking_piece
      white_pawn.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end

    it "does not allow white pawn to jump over a piece on a two-square advance" do
      fresh_board = Board.new
      jumping_pawn = Pawn.new(true)
      fresh_board.pieces[1][4] = jumping_pawn
      fresh_board.pieces[2][4] = Knight.new(true)
      jumping_pawn.valid?(fresh_board, 4, 1, 4, 3).should be_false
    end

    it "does not allow black pawn to jump over a piece on a two-square advance" do
      fresh_board = Board.new
      jumping_pawn = Pawn.new(false)
      fresh_board.pieces[6][4] = jumping_pawn
      fresh_board.pieces[5][4] = Knight.new(false)
      jumping_pawn.valid?(fresh_board, 4, 6, 4, 4).should be_false
    end

    it "allows white pawn to capture black pawn en passant" do
      from_x, from_y = 4, 4
      to_x, to_y = 5, 5
      board.pieces[from_y][from_x] = white_pawn
      board.pieces[to_y - 1][to_x] = black_pawn
      black_pawn.en_passant = true

      white_pawn.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "allows black pawn to capture white pawn en passant" do
      from_x, from_y = 4, 3
      to_x, to_y = 5, 2
      board.pieces[from_y][from_x] = black_pawn
      board.pieces[to_y + 1][to_x] = white_pawn
      white_pawn.en_passant = true

      black_pawn.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end
  end
end
