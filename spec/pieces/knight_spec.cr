require "../spec_helper"

describe Knight do
  describe "#valid?" do
    # Create a board instance for testing
    board = Board.new

    # Place a white knight at position (4, 4) for testing
    knight = Knight.new(true)
    from_x, from_y = 4, 4

    it "returns true for valid knight moves" do
      # List of valid moves for a knight from position (4, 4)
      valid_moves = [
        {to_x: 6, to_y: 5},
        {to_x: 6, to_y: 3},
        {to_x: 2, to_y: 5},
        {to_x: 2, to_y: 3},
        {to_x: 5, to_y: 6},
        {to_x: 5, to_y: 2},
        {to_x: 3, to_y: 6},
        {to_x: 3, to_y: 2},
      ]

      valid_moves.each do |move|
        knight.valid?(board, from_x, from_y, move[:to_x], move[:to_y]).should be_true
      end
    end

    it "returns false for invalid knight moves" do
      # List of invalid moves for a knight from position (4, 4)
      invalid_moves = [
        {to_x: 4, to_y: 4},
        {to_x: 5, to_y: 5},
        {to_x: 7, to_y: 7},
        {to_x: 0, to_y: 0},
      ]

      invalid_moves.each do |move|
        knight.valid?(board, from_x, from_y, move[:to_x], move[:to_y]).should be_false
      end
    end

    it "returns true if the destination is occupied by an opponent" do
      to_x, to_y = 6, 5

      board.pieces[to_y][to_x] = Pawn.new(false)

      knight.valid?(board, from_x, from_y, to_x, to_y).should be_true
    end

    it "returns false if the destination is occupied by self" do
      to_x, to_y = 6, 5

      board.pieces[to_y][to_x] = Pawn.new(true)

      knight.valid?(board, from_x, from_y, to_x, to_y).should be_false
    end
  end
end
