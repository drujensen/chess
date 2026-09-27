require "json"

# The human player's persistent record, stored at ~/.chess/profile.json so it
# survives across games regardless of which directory the app is run from.
class Profile
  include JSON::Serializable

  property name : String = ENV.fetch("USER", "player")
  property rating : Float64 = 1200.0
  property games_played : Int32 = 0
  property wins : Int32 = 0
  property losses : Int32 = 0
  property draws : Int32 = 0

  K_FACTOR = 32.0

  def initialize
  end

  def self.directory : Path
    Path.home / ".chess"
  end

  def self.path : Path
    directory / "profile.json"
  end

  def self.load : Profile
    File.exists?(path) ? Profile.from_json(File.read(path)) : Profile.new
  end

  def save
    Dir.mkdir_p(self.class.directory)
    File.write(self.class.path, to_json)
  end

  # score: 1.0 win, 0.5 draw, 0.0 loss, from the human's perspective.
  def record_result(opponent_rating : Int32, score : Float64)
    expected = 1.0 / (1.0 + 10.0 ** ((opponent_rating - rating) / 400.0))
    @rating += K_FACTOR * (score - expected)
    @games_played += 1

    if score == 1.0
      @wins += 1
    elsif score == 0.0
      @losses += 1
    else
      @draws += 1
    end
  end
end
