require "./spec_helper"

describe Board do
  describe "#legal_moves" do
    it "finds the 20 standard opening moves for white" do
      board = Board.new
      board.setup
      board.legal_moves(true).size.should eq(20)
    end

    it "finds the 20 standard opening moves for black" do
      board = Board.new
      board.setup
      board.legal_moves(false).size.should eq(20)
    end

    it "returns no moves for a color with no pieces on the board" do
      board = Board.new
      board.legal_moves(true).size.should eq(0)
    end
  end

  describe "#draw_by_fifty_move_rule?" do
    it "resets the clock on a pawn move or capture, and increments otherwise" do
      board = Board.new
      board.setup
      board.turn("g1f3", true)
      board.halfmove_clock.should eq(1)
      board.turn("g8f6", false)
      board.turn("e2e4", true)
      board.halfmove_clock.should eq(0)
    end

    it "is true once 100 plies pass without a pawn move or capture" do
      board = Board.new
      board.setup
      board.halfmove_clock = 99
      board.draw_by_fifty_move_rule?.should be_false
      board.halfmove_clock = 100
      board.draw_by_fifty_move_rule?.should be_true
    end
  end

  describe "#draw_by_repetition?" do
    it "is true once the same position occurs a third time" do
      board = Board.new
      board.setup

      2.times do
        board.turn("g1f3", true)
        board.turn("g8f6", false)
        board.turn("f3g1", true)
        board.turn("f6g8", false)
      end
      board.draw_by_repetition?.should be_true
    end

    it "is false when a position has only recurred twice" do
      board = Board.new
      board.setup

      board.turn("g1f3", true)
      board.turn("g8f6", false)
      board.turn("f3g1", true)
      board.turn("f6g8", false)
      board.draw_by_repetition?.should be_false
    end
  end

  describe "#sans / #to_pgn" do
    it "renders Fool's Mate in standard algebraic notation" do
      board = Board.new
      board.setup
      board.turn("f2f3", true)
      board.turn("e7e5", false)
      board.turn("g2g4", true)
      board.turn("d8h4", false)

      board.sans.should eq(["f3", "e5", "g4", "Qh4#"])
      board.to_pgn({"Result" => "0-1"}, "0-1").should eq(
        %([Result "0-1"]\n\n1. f3 e5 2. g4 Qh4# 0-1\n)
      )
    end

    it "notes captures and promotions" do
      board = Board.new
      board.setup
      board.turn("e2e4", true)
      board.turn("d7d5", false)
      board.turn("e4d5", true)
      board.sans.last.should eq("exd5")

      promo = Board.new
      promo.pieces[1][4] = King.new(true)
      promo.pieces[7][4] = King.new(false)
      promo.pieces[6][0] = Pawn.new(true)
      promo.turn("a7a8", true)
      promo.sans.last.should eq("a8=Q+")
    end

    it "disambiguates by file when two same-type pieces share a rank" do
      board = Board.new
      board.pieces[1][4] = King.new(true)
      board.pieces[7][4] = King.new(false)
      board.pieces[0][0] = Rook.new(true)
      board.pieces[0][7] = Rook.new(true)
      board.turn("a1d1", true)
      board.sans.last.should eq("Rad1")
    end

    it "disambiguates by rank when two same-type pieces share a file" do
      board = Board.new
      board.pieces[1][4] = King.new(true)
      board.pieces[7][4] = King.new(false)
      board.pieces[0][0] = Rook.new(true)
      board.pieces[3][0] = Rook.new(true)
      board.turn("a1a2", true)
      board.sans.last.should eq("R1a2")
    end
  end

  describe "#find_move_for_san" do
    it "resolves every SAN token of a game back to its original move" do
      board = Board.new
      board.setup
      board.turn("f2f3", true)
      board.turn("e7e5", false)
      board.turn("g2g4", true)
      board.turn("d8h4", false)

      replay = Board.new
      replay.setup
      white = true
      resolved = board.sans.map do |san|
        move = replay.find_move_for_san(san, white)
        replay.turn(move.not_nil!, white)
        white = !white
        move
      end

      resolved.should eq(["f2f3", "e7e5", "g2g4", "d8h4"])
      replay.checkmate?(true).should be_true
    end

    it "returns nil for a move that isn't currently legal" do
      board = Board.new
      board.setup
      board.find_move_for_san("Qh4#", true).should be_nil
    end
  end

  describe "#explain_invalid_move" do
    it "flags an unrecognizable move" do
      board = Board.new
      board.setup
      board.explain_invalid_move("zz9z", true).should contain("recognizable")
    end

    it "flags moving a piece you don't have on that square" do
      board = Board.new
      board.setup
      board.explain_invalid_move("e7e5", true).should contain("don't have a piece")
    end

    it "flags landing on your own piece" do
      board = Board.new
      board.setup
      board.explain_invalid_move("e1d1", true).should contain("own pieces")
    end

    it "flags a movement pattern the piece can't make" do
      board = Board.new
      board.setup
      board.explain_invalid_move("e2e5", true).should contain("can't move that way")
    end

    it "flags a move that leaves the mover's own king in check" do
      board = Board.new
      board.pieces[1][4] = King.new(true)
      board.pieces[7][4] = King.new(false)
      board.pieces[4][2] = Bishop.new(true) # c5, attacks e7 via d6
      board.explain_invalid_move("e8e7", false).should contain("leave your own king in check")
    end
  end

  describe "#turn (en passant)" do
    it "does not delete an unrelated piece when a pawn makes an ordinary diagonal capture" do
      board = Board.new
      board.pieces[4][1] = Pawn.new(true)    # b5
      board.pieces[5][2] = Knight.new(false) # c6, the actual capture target
      board.pieces[4][2] = Bishop.new(true)  # c5 - must survive untouched

      board.turn("b5c6", true).should be_true

      board.pieces[4][2].should be_a(Bishop)
      board.pieces[5][2].should be_a(Pawn)
      board.black_captured.map(&.class).should eq([Knight])
    end

    it "still correctly captures a pawn via genuine en passant" do
      board = Board.new
      board.setup
      board.turn("e2e4", true)
      board.turn("a7a6", false)
      board.turn("e4e5", true)
      board.turn("d7d5", false)

      board.turn("e5d6", true).should be_true

      board.pieces[4][3].should be_a(Empty) # captured black pawn is gone from d5
      board.pieces[5][3].should be_a(Pawn)  # white pawn landed on d6
      board.black_captured.map(&.class).should eq([Pawn])
    end
  end
end
