require "./board.cr"
require "./ai.cr"

class Chess
  VERSION = "0.1.0"
  property board : Board
  property white : Bool

  def initialize
    @white = true
    @board = Board.new
    @ai = AI.new
  end

  def next_turn
    puts "#{white ? "white" : "black"}'s turn: "
    move = ""
    error = ""
    if white
      move = gets
    else
      move = @ai.next_move(@board.moves, error)
      puts move
    end
    if move
      if board.turn(move, white)
        @white = !white
      else
        error = "invalid move: #{move}. try again!"
        puts error
      end
    end
  end

  def run
    while true
      board.draw
      next_turn
    end
  rescue ex
    board.draw
    puts ex.message
  end
end

game = Chess.new
game.run
