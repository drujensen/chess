require "./board.cr"
require "./ai.cr"

class Chess
  VERSION = "0.1.0"
  property board : Board
  property ai : AI
  property white : Bool
  property error_count : Int32
  property move : String?
  property last_move : NamedTuple(tool_call_id: String, move: String)? = nil

  def initialize
    @board = Board.new
    @ai = AI.new
    @white = true
    @move = ""
    @error_count = 0
  end

  def next_turn
    puts "#{@white ? "white" : "black"}'s turn: "
    error = ""
    if @white
      @move = gets
    else
      if last_move = @last_move
        if move = @move
          ai.prev_move(last_move["tool_call_id"], move)
        end
      end
      @last_move = ai.next_move(board.moves, error)
      if last_move = @last_move
        @move = last_move["move"]
      end
      puts @move
    end
    if move = @move
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
