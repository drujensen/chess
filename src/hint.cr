require "./board.cr"
require "./stockfish.cr"
require "./game_log.cr"

# Asks a local Stockfish for a ranked shortlist of candidate moves for
# whichever side is to move, and renders them either for the human (who typed
# `hint`, optionally `hint N`, on their own turn - see Chess#show_hint) or for
# the model (via its own `hint` tool, see AI). The engine only ever *suggests*
# - nothing here plays a move, changes the board, or consumes a turn, so a hint
# is free to take and always reversible by simply ignoring it.
#
# Why this exists at all: the model's own chess calculation has repeatedly been
# unreliable (see SkillLevel's weak-move nudge and the resign gate), so
# handing it a real engine's ranked shortlist - with scores and continuations -
# grounds its choice in something stronger than pattern-matching, without
# taking the decision away from it.
module Hint
  # The default hint count, and the count the AI's own hint/ranking requests
  # use. Five is wide enough to show that a hint is a *choice* rather than one
  # dictated move, and narrow enough that ranking them all stays fast.
  MOVES = 5
  # Upper bound for a human-requested count (`hint N`). A MultiPV much larger
  # than this makes Stockfish's search noticeably slower without adding much
  # signal - ten ranked moves is already more than a player can weigh at once.
  # Depth is the other tunable knob if a hint ever feels slow (see DEPTH).
  MAX_MOVES = 10
  DEPTH = ENV.fetch("CHESS_HINT_DEPTH", "16").to_i

  # move is long algebraic, exactly as board.legal_moves spells it, so it can
  # be handed straight to Board#turn or to the model's own `move` tool; san is
  # for reading (e.g. "Nf3", "exd5", "a8=Q").
  alias Suggestion = NamedTuple(
    move: String,
    san: String,
    score: String,
    cp: Int32?,
    mate: Int32?,
    pv: Array(String),
  )

  def self.available? : Bool
    Stockfish.available?
  end

  # The engine's top `count` moves for `white`, best-first, or nil if there's
  # no usable answer - Stockfish isn't installed, the search died, or the
  # engine's output couldn't be matched to legal moves. Never raises: a hint is
  # a convenience, and losing a game to one that failed is not acceptable. An
  # empty array means "this side has no legal moves at all" (checkmate or
  # stalemate), which is a real answer, not a failure.
  def self.suggestions(board : Board, white : Bool, count : Int32 = MOVES) : Array(Suggestion)?
    legal = board.legal_moves(white)
    return [] of Suggestion if legal.empty?
    return nil unless available?

    engine = begin
      Stockfish.new(DEPTH, count.clamp(1, MAX_MOVES))
    rescue ex
      GameLog.error("hint: failed to start stockfish", ex)
      nil
    end
    return nil if engine.nil?

    begin
      lines = engine.top_moves(board.to_fen(white))
    rescue ex
      GameLog.error("hint: stockfish search failed", ex)
      return nil
    ensure
      engine.close
    end

    build(lines, legal, board, white)
  end

  # Turns the engine's ranked lanes into suggestions, keeping only those whose
  # first move is actually legal for this side. The engine is searching the
  # position we derived from this board, so its moves should already match -
  # but a mismatch (or a crash that left it with nothing to say) is far better
  # reported as "no hint" than as a suggestion the human can't play.
  private def self.build(lines : Array(Stockfish::Line), legal : Array(String), board : Board, white : Bool) : Array(Suggestion)?
    suggestions = [] of Suggestion

    lines.each do |line|
      move = normalize_move(line[:move])
      next if move.nil? || !legal.includes?(move)
      # Guard against an engine that reports the same move in two lanes.
      # Distinct promotion pieces (e.g. a7b8q vs a7b8n) now stay distinct,
      # since both are real, different legal moves.
      next if suggestions.any? { |s| s[:move] == move }

      suggestions << {
        move:  move,
        san:   board.move_to_san(move, white),
        score: score_text(line[:cp], line[:mate]),
        cp:    line[:cp],
        mate:  line[:mate],
        pv:    line[:pv],
      }
    end

    suggestions.empty? ? nil : suggestions
  end

  # A UCI promotion comes back as e.g. "e7e8q" (or "e7e8b"), and the rest of
  # the app spells it the same way now that underpromotion is supported - the
  # engine's piece letter is meaningful ("e7e8q" and "e7e8n" are different
  # legal moves), so the full move is kept rather than clipped to the 4-char
  # non-promotion form. Dropping the suffix was exactly what made every
  # promotion the engine suggested vanish as "not a legal move".
  private def self.normalize_move(uci_move : String) : String?
    return nil if uci_move.empty? || uci_move.in?({"(none)", "0000"})
    uci_move[0, 5]
  end

  # Centipawns are the engine's own units, from the side to move's perspective
  # (whoever that is varies by position, so it's left unqualified rather than
  # guessed at as "white", which would be wrong half the time).
  private def self.score_text(cp : Int32?, mate : Int32?) : String
    if m = mate
      # Mate scores are the mover's, so a positive one is "I mate you", not a
      # number of pawns - shown as moves rather than a sign, which reads.
      m > 0 ? "mate in #{m}" : "get mated in #{m.abs}"
    elsif c = cp
      pawns = c / 100.0
      pawns >= 0 ? "+#{pawns.round(2)}" : pawns.round(2).to_s
    else
      "?"
    end
  end

  # A short engine line, in the app's long algebraic form, for "what happens
  # after this" - six plies (three white/black pairs) so the follow-up is
  # concrete without turning each hint into a full line of its own.
  private def self.line_text(pv : Array(String)) : String
    pv.map { |m| normalize_move(m) }.compact[0, 6].join(" ")
  end

  # Numbered list for the terminal, e.g.
  #   1) Nf3   (+0.34)  then: Nf3 g8f6 c2c3 e7e5 g2g3 f8g7
  #   2) e4    (-0.12)  then: ...
  def self.render_for_human(suggestions : Array(Suggestion)) : String
    return "" if suggestions.empty?
    width = suggestions.map { |s| s[:san].size }.max
    suggestions.map_with_index do |s, i|
      "#{i + 1}) #{s[:san].ljust(width)} (#{s[:score]})  then: #{line_text(s[:pv])}"
    end.join("\n")
  end

  # The same information for the model, but keyed on long algebraic notation,
  # since that's the exact form its `move` tool needs - SAN would make it
  # translate back, and a model that has to translate can get it wrong. The
  # closing note is the part that keeps this a *hint*: without it a model
  # reading a ranked list tends to treat #1 as an instruction.
  def self.render_for_ai(suggestions : Array(Suggestion), white : Bool) : String
    header = "Stockfish's top #{suggestions.size} move#{suggestions.size == 1 ? "" : "s"} for #{white ? "white" : "black"}, best first (score from that side's perspective, in pawns; negative means worse for them):"
    body = suggestions.map_with_index do |s, i|
      "#{i + 1}) #{s[:move]} (#{s[:san]}) #{s[:score]}  line: #{line_text(s[:pv])}"
    end.join("\n")

    "#{header}\n#{body}\n\nThese are suggestions only - you may play any legal move you like, including one not on this list, if you can justify it."
  end
end
