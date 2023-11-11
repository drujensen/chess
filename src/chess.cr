require "./board.cr"
require "./ai.cr"

class Chess
  VERSION = "0.1.0"
  property board : Board
  property ai : AI
  property white : Bool
  property error_count : Int32
  property last_move : NamedTuple(tool_call_id: String, move: String)? = nil

  def initialize
    @board = Board.new
    @ai = AI.new
    @white = true
    @error_count = 0
  end

  def next_turn
    puts "#{@white ? "white" : "black"}'s turn: "
    error = ""
    if @white
      move = gets
    else
      move = ai.next_move(board.moves, error)
      puts move
    end
    if move
      if @white && !(move =~ /^\D\d(x)?\D\d$/)
        puts ai.chat(board.moves, move)
        return
      end

      if board.turn(move, @white)
        @white = !@white
        @error_count = 0
      else
        error = "invalid move: #{move}. try again!"
        @error_count += 1
        puts error
      end
    end
    if @error_count > 3
      raise "too many errors."
    end
  end

  def run
    while true
      @board.draw
      next_turn
    end
  rescue ex
    @board.draw
    puts ex.message
  end
end

game = Chess.new
game.run
