require "./spec_helper"

describe SkillLevel do
  describe "#elo_range" do
    it "returns the expected range for each level" do
      SkillLevel::Novice.elo_range.should eq("0-500")
      SkillLevel::Grandmaster.elo_range.should eq("2500+")
    end
  end

  describe "#weak_move_chance" do
    it "decreases as skill level increases" do
      SkillLevel::Novice.weak_move_chance.should be > SkillLevel::Beginner.weak_move_chance
      SkillLevel::Beginner.weak_move_chance.should be > SkillLevel::Intermediate.weak_move_chance
      SkillLevel::Intermediate.weak_move_chance.should be > SkillLevel::Advanced.weak_move_chance
    end

    it "never nudges Master or Grandmaster" do
      SkillLevel::Master.weak_move_chance.should eq(0.0)
      SkillLevel::Grandmaster.weak_move_chance.should eq(0.0)
    end
  end

  describe ".from_input" do
    it "accepts a numeric choice" do
      SkillLevel.from_input("3").should eq(SkillLevel::Intermediate)
    end

    it "accepts a name, case-insensitively" do
      SkillLevel.from_input("Grandmaster").should eq(SkillLevel::Grandmaster)
    end

    it "returns nil for anything unrecognized" do
      SkillLevel.from_input("nonsense").should be_nil
    end
  end
end
