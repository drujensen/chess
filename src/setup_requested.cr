# Raised from within AI#chat when the AI's own `setup_position` tool has a
# validated move sequence ready to apply - caught by Chess#next_turn, which
# performs the actual rebuild the same way UndoRequested does, so there's
# only one place that knows how to rebuild the board and the AI's context.
class SetupRequested < Exception
  property moves : Array(String)

  def initialize(@moves : Array(String))
    super("setup requested")
  end
end
