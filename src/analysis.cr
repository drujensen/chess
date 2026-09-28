require "./board.cr"
require "./stockfish.cr"

# Runs a saved game through Stockfish and annotates it with standard PGN
# comments ({[%eval X] ...}) and NAGs ($2/$4/$6) for moves that swing the
# evaluation sharply against the player who made them. Storage is the PGN
# file itself - no separate database - so the annotations round-trip with
# any other PGN-compatible tool, and re-opening an already-analyzed game
# never needs to run the engine again.
module Analysis
  DEPTH                = 16
  BLUNDER_THRESHOLD    =  300
  MISTAKE_THRESHOLD    =  100
  INACCURACY_THRESHOLD =   50

  RESULT_TOKENS = ["1-0", "0-1", "1/2-1/2", "*"]
  TOKEN_RE      = /(?:\d+\.+\s*)?(\S+?)(?:\s+\$(\d+))?(?:\s+(\{[^}]*\}))?(?=\s|$)/
  EVAL_TAG_RE   = /^\{\[%eval\s+([^\]]+)\]\s*(.*)\}$/
  EXPLAIN_RE    = /\[%explain\s+([^\]]*)\]\s*$/
  BETTER_RE     = /Better:\s+(\S+)\./

  alias Eval = NamedTuple(cp: Int32?, mate: Int32?, best: String?, pv: Array(String)?)

  # eval is set for every move once a game has been analyzed (the position's
  # score, from White's perspective, after that move) - comment is only set
  # for a move that actually got flagged (label + suggested alternative).
  # explanation is only ever added later, on demand (see Replay) - analysis
  # itself never calls the AI, only Stockfish.
  alias Note = NamedTuple(san: String, nag: Int32?, eval: String?, comment: String?, explanation: String?)

  def self.available? : Bool
    Stockfish.available?
  end

  def self.annotated?(pgn : String) : Bool
    pgn.includes?("[%eval")
  end

  # Parses the movetext of a PGN (annotated or not) into one Note per move.
  # Works on plain PGN too - eval/nag/comment just come back nil for every
  # move.
  def self.parse(pgn : String) : Array(Note)
    move_text = pgn.split("\n\n", 2).last
    notes = [] of Note

    move_text.scan(TOKEN_RE) do |m|
      san = m[1]?
      next if san.nil? || san.empty?
      next if RESULT_TOKENS.includes?(san)

      nag = m[2]?.try(&.to_i)
      eval = nil
      comment = nil
      explanation = nil
      if (raw = m[3]?) && (tag = raw.match(EVAL_TAG_RE))
        eval = tag[1]
        rest = tag[2]
        if ex = rest.match(EXPLAIN_RE)
          explanation = ex[1].empty? ? nil : ex[1]
          rest = rest[0, ex.begin(0)].strip
        end
        comment = rest.empty? ? nil : rest
      end

      notes << {san: san, nag: nag, eval: eval, comment: comment, explanation: explanation}
    end

    notes
  end

  # Runs the engine over every position of the game, yielding (index, total)
  # after each move so the caller can show progress. Returns nil if
  # Stockfish isn't installed.
  def self.analyze(moves : Array(String), depth : Int32 = DEPTH, &progress : Int32, Int32 ->) : Array(Note)?
    return nil unless available?

    engine = Stockfish.new(depth)
    board = Board.new
    board.setup

    evals = [engine.evaluate(board.to_fen(true))]
    notes = [] of Note

    moves.each_with_index do |move, i|
      mover_white = i.even?
      san = board.move_to_san(move, mover_white)

      before = evals[i]
      better_move = before[:best]?.try(&.[0, 4])
      better_san = (better_move && better_move != move) ? board.move_to_san(better_move, mover_white) : nil

      board.turn(move, mover_white)
      san += "#" if board.checkmate?(!mover_white)
      san += "+" if !san.ends_with?("#") && board.in_check?(!mover_white)
      evals << engine.evaluate(board.to_fen(!mover_white))
      progress.call(i + 1, moves.size)

      after = evals[i + 1]
      swing = mover_swing(before, mover_white, after, !mover_white)
      eval_text = format_eval(after, !mover_white)

      if classification = classify(swing)
        detail = better_san ? "#{classification[:label]}. Better: #{better_san}." : "#{classification[:label]}."
        notes << {san: san, nag: classification[:nag], eval: eval_text, comment: detail, explanation: nil}
      else
        notes << {san: san, nag: nil, eval: eval_text, comment: nil, explanation: nil}
      end
    end

    engine.close
    notes
  end

  # Rebuilds a full PGN file from headers, annotated notes, and the result.
  def self.embed(headers : Hash(String, String), notes : Array(Note), result : String) : String
    header_lines = headers.map { |key, value| %([#{key} "#{value}"]) }.join("\n")

    move_text = String.build do |str|
      notes.each_with_index do |note, i|
        str << "#{(i // 2) + 1}. " if i.even?
        str << note[:san]
        str << " $#{note[:nag]}" if note[:nag]
        if eval = note[:eval]
          comment_text = "[%eval #{eval}]"
          comment_text += " #{note[:comment]}" if note[:comment]
          comment_text += " [%explain #{note[:explanation]}]" if note[:explanation]
          str << " {#{comment_text}}"
        end
        str << " "
      end
      str << result
    end

    "#{header_lines}\n\n#{move_text}\n\n"
  end

  # The SAN of the suggested alternative move, pulled back out of a flagged
  # note's own rendered comment ("Blunder. Better: Nc3.") rather than kept
  # as a separate field - one less thing for #embed/#parse to round-trip.
  def self.better_san(note : Note) : String?
    note[:comment].try { |c| c.match(BETTER_RE) }.try(&.[1])
  end

  # A fresh copy of notes with the note at index carrying the given
  # explanation - NamedTuples are immutable, so this rebuilds the one entry
  # that changed rather than mutating in place.
  def self.with_explanation(notes : Array(Note), index : Int32, explanation : String) : Array(Note)
    notes.map_with_index do |note, i|
      i == index ? note.merge({explanation: sanitize(explanation)}) : note
    end
  end

  # Strips characters that would break the PGN comment's own bracket/brace
  # syntax out of AI-generated prose before it gets embedded.
  private def self.sanitize(text : String) : String
    text.strip.gsub(/[\[\]{}]/, "")
  end

  private def self.classify(swing : Int32) : NamedTuple(nag: Int32, label: String)?
    return {nag: 4, label: "Blunder"} if swing <= -BLUNDER_THRESHOLD
    return {nag: 2, label: "Mistake"} if swing <= -MISTAKE_THRESHOLD
    return {nag: 6, label: "Inaccuracy"} if swing <= -INACCURACY_THRESHOLD
    nil
  end

  # A mate score doesn't compare numerically to a centipawn score, so it's
  # mapped onto the same scale as a very large centipawn value - sooner
  # mates are more extreme than later ones, in either direction.
  private def self.pseudo_cp(eval : Eval) : Int32
    if mate = eval[:mate]
      mate > 0 ? 100_000 - mate : -100_000 - mate
    elsif cp = eval[:cp]
      cp
    else
      0
    end
  end

  private def self.white_cp(eval : Eval, white_to_move : Bool) : Int32
    raw = pseudo_cp(eval)
    white_to_move ? raw : -raw
  end

  private def self.mover_swing(
    before : Eval, mover_white : Bool,
    after : Eval, next_to_move_white : Bool,
  ) : Int32
    before_white = white_cp(before, mover_white)
    after_white = white_cp(after, next_to_move_white)
    mover_before = mover_white ? before_white : -before_white
    mover_after = mover_white ? after_white : -after_white
    mover_after - mover_before
  end

  # Bare eval value from White's perspective, no wrapping tag - "+0.72",
  # "-3.49", "#4" (White mates in 4), "#-3" (White gets mated in 3).
  private def self.format_eval(eval : Eval, white_to_move : Bool) : String
    if mate = eval[:mate]
      white_mate = white_to_move ? mate : -mate
      "##{white_mate}"
    elsif cp = eval[:cp]
      white_cp_val = white_to_move ? cp : -cp
      pawns = white_cp_val / 100.0
      pawns >= 0 ? "+#{pawns.round(2)}" : pawns.round(2).to_s
    else
      "?"
    end
  end
end
