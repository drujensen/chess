require "json"
require "./profile.cr"

# An in-progress game, saved after every move so Ctrl+C, closing the
# terminal, or stdin EOF never loses committed moves - only one game can be
# "in progress" at a time, at ~/.chess/in_progress.json.
class SavedGame
  include JSON::Serializable

  property moves : Array(String) = [] of String
  property skill_level : String = "Advanced"
  property saved_at : String = ""

  def initialize
  end

  def self.path : Path
    Profile.directory / "in_progress.json"
  end

  def self.exists? : Bool
    File.exists?(path)
  end

  def self.load : SavedGame?
    return nil unless exists?
    SavedGame.from_json(File.read(path))
  end

  def self.clear
    File.delete(path) if exists?
  end

  def save
    Dir.mkdir_p(Profile.directory)
    File.write(self.class.path, to_json)
  end
end
