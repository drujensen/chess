# Raised from within AI#chat when the human asks the AI (via chat) to play
# their own move for them, and the AI's `play_for_human` tool call names one
# of the human's actual current legal moves - caught by Chess#next_turn,
# which applies it exactly like a normal human move (board.turn + the usual
# status/save bookkeeping), rather than AI having any way to touch board
# state itself.
class MoveRequested < Exception
  property move : String

  def initialize(@move : String)
    super("move requested")
  end
end
