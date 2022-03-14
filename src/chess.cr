require "./board.cr"

class Chess
  VERSION = "0.1.0"
  property board : Board
  property white : Bool

  def initialize
    @white = true
    @board = Board.new
  end

  def next_turn
    puts "#{white ? "white" : "black"}'s turn: "
    if move = gets
      if board.turn(move, white)
        @white = !white
      else
        puts "invalid move!"
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
