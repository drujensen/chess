# A thin UCI (Universal Chess Interface) client for a local Stockfish
# process. Used only for post-game analysis (see Analysis) - never during
# live play - so its absence should degrade gracefully, not break anything.
class Stockfish
  def self.available? : Bool
    !Process.find_executable("stockfish").nil?
  rescue
    false
  end

  def initialize(@depth : Int32 = 16)
    @process = Process.new("stockfish", input: Process::Redirect::Pipe, output: Process::Redirect::Pipe)
    send("uci")
    wait_for("uciok")
    send("isready")
    wait_for("readyok")
  end

  # Evaluates the given position, returning the engine's score (from the
  # perspective of the side to move in that FEN - exactly one of cp/mate
  # is set), its suggested best move in long algebraic notation (e.g.
  # "e2e4", or "e7e8q" for a promotion), and its principal variation - the
  # forced-ish line it expects to follow, in the same notation.
  def evaluate(fen : String) : NamedTuple(cp: Int32?, mate: Int32?, best: String?, pv: Array(String)?)
    send("position fen #{fen}")
    send("go depth #{@depth}")

    cp = nil
    mate = nil
    best = nil
    pv = nil

    loop do
      line = @process.output.gets
      break if line.nil?

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
      elsif line.starts_with?("bestmove")
        best = line.split[1]?
        break
      end
    end

    {cp: cp, mate: mate, best: best, pv: pv}
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
