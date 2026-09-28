require "./spec_helper"

describe Analysis do
  describe "#parse" do
    it "parses plain PGN with no annotations" do
      pgn = %([Result "0-1"]\n\n1. f3 e5 2. g4 Qh4# 0-1\n\n)
      notes = Analysis.parse(pgn)
      notes.map(&.[:san]).should eq(["f3", "e5", "g4", "Qh4#"])
      notes.all? { |n| n[:nag].nil? && n[:eval].nil? && n[:comment].nil? }.should be_true
    end

    it "parses NAGs, eval, and comment back out separately" do
      pgn = %([Result "*"]\n\n1. e4 {[%eval 0.35]} e5 $6 {[%eval 0.1] Inaccuracy. Better: Nc6.} 2. Nf3 *\n\n)
      notes = Analysis.parse(pgn)

      notes[0][:san].should eq("e4")
      notes[0][:eval].should eq("0.35")
      notes[0][:nag].should be_nil
      notes[0][:comment].should be_nil

      notes[1][:san].should eq("e5")
      notes[1][:nag].should eq(6)
      notes[1][:eval].should eq("0.1")
      notes[1][:comment].should eq("Inaccuracy. Better: Nc6.")

      notes[2][:san].should eq("Nf3")
    end
  end

  describe "#annotated?" do
    it "detects the presence of an eval tag" do
      Analysis.annotated?("plain text with no tags").should be_false
      Analysis.annotated?("1. e4 {[%eval 0.3] fine} *").should be_true
    end
  end

  describe "#embed" do
    it "rebuilds a PGN from notes, round-tripping through #parse" do
      notes = [
        {san: "e4", nag: nil, eval: "+0.35", comment: nil, explanation: nil},
        {san: "e5", nag: 4, eval: "-3.0", comment: "Blunder. Better: c5.", explanation: nil},
      ] of Analysis::Note

      pgn = Analysis.embed({"Result" => "1-0"}, notes, "1-0")
      pgn.should contain(%([Result "1-0"]))
      pgn.should contain("1. e4 {[%eval +0.35]} e5 $4 {[%eval -3.0] Blunder. Better: c5.} 1-0")
      pgn.should end_with("\n\n")

      Analysis.parse(pgn).should eq(notes)
    end
  end

  describe "#better_san" do
    it "extracts the suggested move from a flagged note's comment" do
      note = {san: "Bd7", nag: 6, eval: "+11.48", comment: "Inaccuracy. Better: Kf8.", explanation: nil}.as(Analysis::Note)
      Analysis.better_san(note).should eq("Kf8")
    end

    it "returns nil when the move wasn't flagged" do
      note = {san: "e4", nag: nil, eval: "+0.35", comment: nil, explanation: nil}.as(Analysis::Note)
      Analysis.better_san(note).should be_nil
    end
  end

  describe "#with_explanation" do
    it "sets the explanation on only the targeted note, sanitized of bracket/brace characters" do
      notes = [
        {san: "e4", nag: nil, eval: "+0.35", comment: nil, explanation: nil},
        {san: "Nc6", nag: 4, eval: "-3.0", comment: "Blunder. Better: d5.", explanation: nil},
      ] of Analysis::Note

      updated = Analysis.with_explanation(notes, 1, "The knight [hangs] to {a fork}. ")
      updated[0][:explanation].should be_nil
      updated[1][:explanation].should eq("The knight hangs to a fork.")
    end

    it "round-trips through #embed and #parse" do
      notes = [
        {san: "e4", nag: nil, eval: "+0.35", comment: nil, explanation: nil},
        {san: "Nc6", nag: 4, eval: "-3.0", comment: "Blunder. Better: d5.", explanation: "The knight hangs to a fork."},
      ] of Analysis::Note

      pgn = Analysis.embed({"Result" => "*"}, notes, "*")
      pgn.should contain("[%explain The knight hangs to a fork.]")

      parsed = Analysis.parse(pgn)
      parsed[1][:comment].should eq("Blunder. Better: d5.")
      parsed[1][:explanation].should eq("The knight hangs to a fork.")
    end
  end

  describe "#analyze", tags: "stockfish" do
    it "runs a real Stockfish over Fool's Mate and flags the losing side's blunders" do
      pending! "stockfish not installed" unless Analysis.available?

      moves = ["f2f3", "e7e5", "g2g4", "d8h4"]
      notes = Analysis.analyze(moves) { |_, _| }
      notes.should_not be_nil
      notes = notes.not_nil!

      notes.size.should eq(4)
      notes.map(&.[:san]).should eq(["f3", "e5", "g4", "Qh4#"])
      # every move gets an eval, win or lose
      notes.all? { |n| !n[:eval].nil? }.should be_true
      # White's two moves are the actual blunders (f3, g4) - both should be
      # flagged, since either one alone hands black a forced mate shortly
      # after. Black's replies are winning moves, never flagged.
      notes[0][:nag].should_not be_nil
      notes[2][:nag].should_not be_nil
      notes[1][:nag].should be_nil
      notes[3][:nag].should be_nil
    end
  end
end
