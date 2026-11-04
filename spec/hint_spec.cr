require "./spec_helper"
require "../src/hint"

# Replays a move list onto a fresh board, for the positions these specs need.
def hint_fixture(moves : Array(String)) : Board
  board = Board.new
  board.setup
  white = true
  moves.each do |move|
    raise "spec setup: #{move} is illegal" unless board.turn(move, white)
    white = !white
  end
  board
end

describe Hint do
  describe "#suggestions" do
    it "returns an empty list (not a failure) when that side has no legal moves" do
      # Fool's mate: white is mated, so there is nothing to hint - and this
      # must be distinguishable from "Stockfish isn't installed", which is nil.
      board = hint_fixture(["f2f3", "e7e5", "g2g4", "d8h4"])
      board.legal_moves(true).should be_empty
      Hint.suggestions(board, true).should eq([] of Hint::Suggestion)
    end

    describe "with a real engine", tags: "stockfish" do
      it "returns the top 5 legal moves, ranked, with scores and lines" do
        pending! "stockfish not installed" unless Hint.available?

        suggestions = Hint.suggestions(hint_fixture([] of String), true).not_nil!
        suggestions.size.should eq(Hint::MOVES)
        suggestions.all? { |s| !s[:score].empty? && !s[:pv].empty? }.should be_true
        # Every suggestion has to be one this board can actually play.
        legal = hint_fixture([] of String).legal_moves(true)
        suggestions.all? { |s| legal.includes?(s[:move]) }.should be_true
        # all distinct - no duplicated rows from two lanes normalizing together
        suggestions.map { |s| s[:move] }.uniq.size.should eq(suggestions.size)
        # the opening has no forced mate in it, so every lane is a pawn score
        suggestions.all? { |s| !s[:cp].nil? }.should be_true
      end

      it "finds the mate-in-one in Fool's Mate position for black" do
        pending! "stockfish not installed" unless Hint.available?

        board = hint_fixture(["f2f3", "e7e5", "g2g4"])
        suggestions = Hint.suggestions(board, false).not_nil!
        best = suggestions.first
        best[:move].should eq("d8h4")
        best[:mate].should eq(1)
        best[:score].should eq("mate in 1")
        best[:san].should eq("Qh4")
      end

      it "keeps a promotion the engine suggests instead of dropping it on the =Q suffix" do
        pending! "stockfish not installed" unless Hint.available?

        # 1.a4 b5 2.axb5 a6 3.bxa6 h5 4.a7 h6 - white's a-pawn can promote by
        # capturing the rook on b8. UCI spells that a7b8q; Board#legal_moves
        # spells it a7b8, so an exact match alone would silently discard it.
        board = hint_fixture(["a2a4", "b7b5", "a4b5", "a7a6", "b5a6", "h7h5", "a6a7", "h5h4"])
        board.legal_moves(true).should contain("a7b8")

        suggestions = Hint.suggestions(board, true).not_nil!
        promotion = suggestions.find { |s| s[:move] == "a7b8" }
        promotion.should_not be_nil
        promotion.not_nil![:san].should eq("axb8=Q")
        # the engine ranks a7b8q and a7b8n in separate lanes - both normalize
        # to the same move here (this app always promotes to queen), and that
        # must not show up as two identical rows.
        suggestions.count { |s| s[:move] == "a7b8" }.should eq(1)
      end

      it "never repeats the same move across suggestions" do
        pending! "stockfish not installed" unless Hint.available?

        board = hint_fixture(["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5"])
        suggestions = Hint.suggestions(board, white: true).not_nil!
        suggestions.map { |s| s[:move] }.uniq.should eq(suggestions.map { |s| s[:move] })
      end
    end
  end

  describe "#render_for_human" do
    it "returns empty text rather than raising on an empty list" do
      # Array#max raises EmptyError on nothing to measure, and this module's
      # whole contract is that a hint can't blow up a live game.
      Hint.render_for_human([] of Hint::Suggestion).should eq("")
    end

    it "renders a numbered, aligned list of san, score, and the engine's line" do
      suggestions = [
        {move: "d2d4", san: "d4", score: "+0.33", cp: 33, mate: nil, pv: ["d2d4", "g8f6", "c2c4"]},
        {move: "d8h4", san: "Qh4", score: "mate in 1", cp: nil, mate: 1, pv: ["d8h4"]},
      ] of Hint::Suggestion

      Hint.render_for_human(suggestions).should eq(
        "1) d4  (+0.33)  then: d2d4 g8f6 c2c4\n" +
          "2) Qh4 (mate in 1)  then: d8h4"
      )
    end
  end

  describe "#render_for_ai" do
    it "leads with long algebraic notation, since that is what the move tool needs" do
      suggestions = [
        {move: "e2e4", san: "e4", score: "+0.44", cp: 44, mate: nil, pv: ["e2e4", "e7e5"]},
      ] of Hint::Suggestion

      rendered = Hint.render_for_ai(suggestions, true)
      rendered.should contain("for white")
      rendered.should contain("1) e2e4 (e4) +0.44  line: e2e4 e7e5")
      # Without this the model reads a ranked list as an instruction.
      rendered.should contain("you may play any legal move you like")
    end

    it "names black when the suggestions are black's" do
      suggestions = [
        {move: "d8h4", san: "Qh4", score: "mate in 1", cp: nil, mate: 1, pv: ["d8h4"]},
      ] of Hint::Suggestion

      Hint.render_for_ai(suggestions, false).should contain("for black")
    end
  end
end
