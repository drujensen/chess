# A thin UCI (Universal Chess Interface) client for a local Stockfish
# process. Used for post-game analysis (see Analysis) and for live hints
# (see Hint) - so its absence should degrade gracefully, not break anything.
class Stockfish
  def self.available? : Bool
    !Process.find_executable("stockfish").nil?
  rescue
    false
  end

  def initialize(@depth : Int32 = 16, @multipv : Int32 = 1)
    @process = Process.new("stockfish", input: Process::Redirect::Pipe, output: Process::Redirect::Pipe)
    send("uci")
    wait_for("uciok")
    # Ask for N ranked lines per depth rather than only the best, which is what
    # makes Hint's "top 5" possible at all. Left at the default of 1 when not
    # asked for, so existing single-best-move callers (Analysis) are unaffected.
    if @multipv > 1
      send("setoption name MultiPV value #{@multipv}")
    end
    send("isready")
    wait_for("readyok")
  end

  # Evaluates the given position, returning the engine's score (from the
  # perspective of the side to move in that FEN - exactly one of cp/mate
  # is set), its suggested best move in long algebraic notation (e.g.
  # "e2e4", or "e7e8q" for a promotion), and its principal variation - the
  # forced-ish line it expects to follow, in the same notation.
  def evaluate(fen : String) : NamedTuple(cp: Int32?, mate: Int32?, best: String?, pv: Array(String)?)
    cp = nil
    mate = nil
    best = nil
    pv = nil

    search(fen) do |line|
      if line.starts_with?("info")
        if m = line.match(/score cp (-?\d+)/)
          cp = m[1].to_i
          mate = nil
        elsif m = line.match(/score mate (-?\d+)/)
          mate = m[1].to_i
          cp = nil
        end
        if m = line.match(/ pv (.+)$/)
          pv = m[1].split
        end
        false
      elsif line.starts_with?("bestmove")
        best = line.split[1]?
        true
      else
        false
      end
    end

    {cp: cp, mate: mate, best: best, pv: pv}
  end

  alias Line = NamedTuple(cp: Int32?, mate: Int32?, move: String, pv: Array(String))

  # Evaluates the given position and returns the engine's ranked candidate
  # moves - up to the `multipv` count it was constructed with - best-first,
  # each with its own score (again from the side to move's perspective, so no
  # sign flipping is needed by the caller) and principal variation. UCI
  # reports one `info depth X multipv K ...` line per candidate per depth, so
  # each K lane is kept separately, last write per lane winning (the deepest
  # value reported for it). `move` is the first move of that lane's pv, in the
  # engine's own UCI notation - so a promotion comes back as e.g. "e7e8q",
  # longer than the 4-character form the rest of this app uses (see
  # Hint.normalize_move).
  #
  # Returns an empty array if the search produced nothing usable - a died
  # process (this build of Stockfish aborts outright on an *illegal* position,
  # seen while prototyping) or a `bestmove (none)` both land here rather than
  # raising, leaving it to the caller to decide what a failed search means.
  def top_moves(fen : String) : Array(Line)
    lanes = {} of Int32 => Line

    search(fen) do |line|
      if line.starts_with?("info depth")
        # A lowerbound/upperbound line is just one lane's provisional score
        # while a deeper search is still proving it out - not a final ranking.
        unless line.includes?("lowerbound") || line.includes?("upperbound")
          if (entry = parse_info_line(line))
            lanes[entry[:lane]] = entry[:line]
          end
        end
        false
      elsif line.starts_with?("bestmove")
        true
      else
        false
      end
    end

    lanes.to_a.sort_by(&.first).map(&.last)
  end

  # Sends `position`/`go` and yields each output line until the block returns
  # true (done reading) or the process ends - the two readers above want
  # different things out of the same search.
  private def search(fen : String, &block : String -> Bool)
    send("position fen #{fen}")
    send("go depth #{@depth}")

    loop do
      line = @process.output.gets
      break if line.nil?
      break if block.call(line)
    end
  end

  # Splits one `info depth 16 seldepth 25 multipv 2 score cp 34 nodes ... pv
  # g1f3 g8f6 ...` line into its lane number plus the score/move/pv worth
  # keeping. A lane without both a score and a pv isn't a usable candidate
  # yet, so it's skipped rather than recorded half-filled.
  private def parse_info_line(line : String) : NamedTuple(lane: Int32, line: Line)?
    cp = nil
    mate = nil
    if m = line.match(/score cp (-?\d+)/)
      cp = m[1].to_i
    elsif m = line.match(/score mate (-?\d+)/)
      mate = m[1].to_i
    else
      return nil
    end

    m = line.match(/ pv (.+)$/)
    return nil if m.nil?
    pv_moves = m[1].split.reject(&.empty?)
    return nil if pv_moves.empty?

    # Single-PV searches omit the token entirely - they're all lane 1.
    lane = 1
    if lm = line.match(/multipv (\d+)/)
      lane = lm[1].to_i
    end

    {lane: lane, line: {cp: cp, mate: mate, move: pv_moves[0], pv: pv_moves}}
  end

  def close
    send("quit")
    @process.wait
  rescue
  end

  private def send(command : String)
    @process.input.puts(command)
    @process.input.flush
  end

  private def wait_for(token : String)
    loop do
      line = @process.output.gets
      break if line.nil? || line.includes?(token)
    end
  end
end
