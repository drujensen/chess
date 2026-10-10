require "time"
require "./profile.cr"

# Keeps tool-call chatter and background failures out of the player's
# terminal - they're appended to ~/.chess/chess.log instead, so the console
# only ever shows what the player actually cares about (moves, prompts,
# game results), while the detail needed to actually debug a weird session
# still exists somewhere on disk.
module GameLog
  def self.path : Path
    Profile.directory / "chess.log"
  end

  def self.info(message : String)
    write("INFO", message)
  end

  # For an exception that was already shown to the player as a short
  # message - this is where the full backtrace goes instead of the console.
  def self.error(message : String, ex : Exception? = nil)
    write("ERROR", ex ? "#{message}\n#{ex.class}: #{ex.message}\n#{ex.backtrace.join('\n')}" : message)
  end

  private def self.write(level : String, message : String)
    Dir.mkdir_p(Profile.directory)
    File.open(path, "a") do |file|
      file.puts "[#{Time.local.to_s("%Y-%m-%d %H:%M:%S")}] #{level} #{message}"
    end
  end
end
