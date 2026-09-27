require "./spec_helper"
require "file_utils"

describe SavedGame do
  it "reports no save when none exists" do
    fake_home = File.tempname("chess-saved-game-spec")
    Dir.mkdir_p(fake_home)
    original_home = ENV["HOME"]?
    begin
      ENV["HOME"] = fake_home
      SavedGame.exists?.should be_false
      SavedGame.load.should be_nil
    ensure
      ENV["HOME"] = original_home
      FileUtils.rm_rf(fake_home)
    end
  end

  it "saves, loads, and clears an in-progress game" do
    fake_home = File.tempname("chess-saved-game-spec")
    Dir.mkdir_p(fake_home)
    original_home = ENV["HOME"]?
    begin
      ENV["HOME"] = fake_home

      saved = SavedGame.new
      saved.moves = ["e2e4", "e7e5"]
      saved.skill_level = "Advanced"
      saved.save

      SavedGame.exists?.should be_true
      reloaded = SavedGame.load.not_nil!
      reloaded.moves.should eq(["e2e4", "e7e5"])
      reloaded.skill_level.should eq("Advanced")

      SavedGame.clear
      SavedGame.exists?.should be_false
    ensure
      ENV["HOME"] = original_home
      FileUtils.rm_rf(fake_home)
    end
  end
end
