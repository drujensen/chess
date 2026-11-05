require "./spec_helper"
# Required via ai.cr rather than opponent.cr: Opponent#resolve_base_url reads
# AI::PROVIDERS but opponent.cr can't require it back without a cycle, so it
# only resolves once ai.cr has been loaded - which is how the app itself always
# does it.
require "../src/ai"
require "file_utils"

describe Opponent do
  list = [
    Opponent.new("First", "m1", provider: "ollama"),
    Opponent.new("Second", "m2", provider: "ollama"),
  ]

  describe ".from_selection" do
    it "maps a valid 1-based number to that opponent" do
      Opponent.from_selection("1", list).try(&.name).should eq("First")
      Opponent.from_selection("2", list).try(&.name).should eq("Second")
    end

    it "accepts surrounding whitespace" do
      Opponent.from_selection("  2  ", list).try(&.name).should eq("Second")
    end

    # The point of the whole exercise: mid-game, an unusable answer has to mean
    # "leave the opponent alone". Returning list.first here would silently swap
    # a player's opponent out from under them on a stray Enter.
    it "returns nil (cancel) for blank input rather than the first entry" do
      Opponent.from_selection("", list).should be_nil
    end

    it "returns nil for 0, which the switch menu offers as cancel" do
      Opponent.from_selection("0", list).should be_nil
    end

    it "returns nil for out-of-range and non-numeric input" do
      Opponent.from_selection("3", list).should be_nil
      Opponent.from_selection("99", list).should be_nil
      Opponent.from_selection("-1", list).should be_nil
      Opponent.from_selection("switch", list).should be_nil
      Opponent.from_selection("2.5", list).should be_nil
    end

    it "returns nil for an empty list rather than raising" do
      Opponent.from_selection("1", [] of Opponent).should be_nil
    end
  end

  describe "#resolve_base_url" do
    it "resolves a known provider shortcut" do
      Opponent.new("x", "m", provider: "anthropic").resolve_base_url
        .should eq("https://api.anthropic.com/v1")
    end

    it "prefers an explicit base_url over the provider shortcut" do
      Opponent.new("x", "m", provider: "openai", base_url: "http://localhost:9/v1")
        .resolve_base_url.should eq("http://localhost:9/v1")
    end

    it "names the offending provider when it is neither known nor explicit" do
      expect_raises(Exception, /no base_url set/) do
        Opponent.new("Ghost", "m", provider: "not-a-provider").resolve_base_url
      end
    end
  end

  describe ".load" do
    # Every case here redirects HOME to a temp dir first: Opponent.path resolves
    # against Profile.directory (~/.chess), so anything else would read - and in
    # the malformed case overwrite - the player's real opponent list.
    it "writes defaults on first read, then loads them back unchanged" do
      fake_home = File.tempname("opponent-spec")
      original = ENV["HOME"]?
      begin
        ENV["HOME"] = fake_home
        loaded = Opponent.load
        loaded.should_not be_empty
        File.exists?(Opponent.path).should be_true
        Opponent.load.map(&.name).should eq(loaded.map(&.name))
      ensure
        ENV["HOME"] = original
        FileUtils.rm_rf(fake_home)
      end
    end

    it "falls back to defaults on a malformed file instead of crashing the menu" do
      fake_home = File.tempname("opponent-spec")
      original = ENV["HOME"]?
      begin
        ENV["HOME"] = fake_home
        Dir.mkdir_p(Opponent.path.parent)
        File.write(Opponent.path, "{not json")
        Opponent.load.should_not be_empty
      ensure
        ENV["HOME"] = original
        FileUtils.rm_rf(fake_home)
      end
    end

    it "falls back to defaults when the file exists but is empty" do
      fake_home = File.tempname("opponent-spec")
      original = ENV["HOME"]?
      begin
        ENV["HOME"] = fake_home
        Dir.mkdir_p(Opponent.path.parent)
        File.write(Opponent.path, "[]")
        Opponent.load.should_not be_empty
      ensure
        ENV["HOME"] = original
        FileUtils.rm_rf(fake_home)
      end
    end

    it "preserves a hand-edited list rather than overwriting it with defaults" do
      fake_home = File.tempname("opponent-spec")
      original = ENV["HOME"]?
      begin
        ENV["HOME"] = fake_home
        Dir.mkdir_p(Opponent.path.parent)
        custom = [Opponent.new("My Endpoint", "my-model", base_url: "http://localhost:1234/v1")]
        File.write(Opponent.path, custom.to_json)
        loaded = Opponent.load
        loaded.size.should eq(1)
        loaded.first.name.should eq("My Endpoint")
        loaded.first.resolve_base_url.should eq("http://localhost:1234/v1")
      ensure
        ENV["HOME"] = original
        FileUtils.rm_rf(fake_home)
      end
    end

    it "finds an entry by its exact name and returns nil for anything else" do
      fake_home = File.tempname("opponent-spec")
      original = ENV["HOME"]?
      begin
        ENV["HOME"] = fake_home
        Opponent.load # writes defaults
        Opponent.find_by_name("Anthropic - Claude Haiku 5.5").try(&.model)
          .should eq("claude-haiku-5-5")
        Opponent.find_by_name("Does Not Exist").should be_nil
      ensure
        ENV["HOME"] = original
        FileUtils.rm_rf(fake_home)
      end
    end
  end
end
