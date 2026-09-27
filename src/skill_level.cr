enum SkillLevel
  Novice
  Beginner
  Intermediate
  Advanced
  Master
  Grandmaster

  def elo_range : String
    case self
    in .novice?       then "0-500"
    in .beginner?     then "500-1000"
    in .intermediate? then "1000-1500"
    in .advanced?     then "1500-2000"
    in .master?       then "2000-2500"
    in .grandmaster?  then "2500+"
    end
  end

  # Chance that, on a given move, the model is explicitly told to play like
  # this tier instead of its objectively strongest move - a visible
  # instruction the model consciously acts on, never a move swapped in after
  # the fact (that would leave the model's own account of the game wrong).
  # Master/Grandmaster never get the nudge: no amount of prompting reliably
  # makes a small local model play at that level, so their strength is
  # whatever the underlying model can actually do.
  def weak_move_chance : Float64
    case self
    in .novice?       then 0.6
    in .beginner?     then 0.35
    in .intermediate? then 0.15
    in .advanced?     then 0.05
    in .master?       then 0.0
    in .grandmaster?  then 0.0
    end
  end

  # Representative Elo used as the "opponent rating" when updating the
  # human's rating after a game. Grandmaster has no real upper bound, so
  # 2750 stands in as a typical top-GM figure.
  def elo_midpoint : Int32
    case self
    in .novice?       then 250
    in .beginner?     then 750
    in .intermediate? then 1250
    in .advanced?     then 1750
    in .master?       then 2250
    in .grandmaster?  then 2750
    end
  end

  def self.from_input(input : String) : SkillLevel?
    case input.strip.downcase
    when "1", "novice"       then Novice
    when "2", "beginner"     then Beginner
    when "3", "intermediate" then Intermediate
    when "4", "advanced"     then Advanced
    when "5", "master"       then Master
    when "6", "grandmaster"  then Grandmaster
    else
      nil
    end
  end
end
