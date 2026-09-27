require "./spec_helper"
require "file_utils"

describe Profile do
  it "defaults to a starting rating with no games played" do
    profile = Profile.new
    profile.rating.should eq(1200.0)
    profile.games_played.should eq(0)
  end

  it "raises the rating after a win and lowers it after a loss" do
    profile = Profile.new
    profile.record_result(1750, 1.0)
    profile.rating.should be > 1200.0
    profile.games_played.should eq(1)
    profile.wins.should eq(1)

    profile = Profile.new
    profile.record_result(1750, 0.0)
    profile.rating.should be < 1200.0
    profile.losses.should eq(1)
  end

  it "barely moves the rating on a draw against a much weaker opponent" do
    profile = Profile.new
    profile.record_result(250, 0.5)
    profile.rating.should be < 1200.0
    profile.draws.should eq(1)
  end

  it "round-trips through JSON" do
    profile = Profile.new
    profile.record_result(1750, 1.0)

    reloaded = Profile.from_json(profile.to_json)
    reloaded.rating.should eq(profile.rating)
    reloaded.games_played.should eq(1)
    reloaded.wins.should eq(1)
  end

  it "saves to and loads from ~/.chess/profile.json" do
    fake_home = File.tempname("chess-profile-spec")
    Dir.mkdir_p(fake_home)
    original_home = ENV["HOME"]?
    begin
      ENV["HOME"] = fake_home

      profile = Profile.load
      profile.rating.should eq(1200.0)

      profile.record_result(1750, 1.0)
      profile.save

      reloaded = Profile.load
      reloaded.rating.should eq(profile.rating)
      reloaded.games_played.should eq(1)
    ensure
      ENV["HOME"] = original_home
      FileUtils.rm_rf(fake_home)
    end
  end
end
