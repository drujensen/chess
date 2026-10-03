# Raised from within AI#chat when the human asks the AI (via chat) to undo
# the last move(s) - caught by Chess#next_turn, which performs the actual
# rollback the same way the human-typed `undo` command does, so there's only
# one place that knows how to rebuild the board and the AI's context.
class UndoRequested < Exception
  property count : Int32

  def initialize(@count : Int32 = 1)
    super("undo requested")
  end
end
