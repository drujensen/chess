# Raised by Chess#report_game_status for an actual chess result (as opposed
# to an abort like too many invalid moves), carrying the PGN result code so
# Chess#finish_game can update the profile's rating and write the PGN file.
class GameOver < Exception
  property result : String

  def initialize(message : String, @result : String)
    super(message)
  end
end
