require "./spec_helper"
require "../src/context"

# A realistic slice of a game log: a system prompt, then one turn per count,
# each turn being a user message, an assistant message that asked for a tool
# (kept as JSON::Any, exactly as the API returns it), and the tool response
# that answers it.
def context_transcript(turns : Int32) : Array(Context::Message)
  log = [{role: "system", content: "you are black"}] of Context::Message
  turns.times do |i|
    log << {role: "user", content: "move #{i + 1}"}
    log << JSON.parse(%({"role":"assistant","content":"","tool_calls":[{"id":"c#{i}","function":{"name":"board"}}]}))
    log << {tool_call_id: "c#{i}", role: "tool", name: "board", content: "FEN-#{i}"}
  end
  log
end

# Which tool_call_ids are requested by, and answered in, a message list.
def context_calls(log : Array(Context::Message)) : Array(String)
  log.flat_map do |message|
    json = message.as?(JSON::Any)
    next [] of String if json.nil?
    json["tool_calls"]?.try { |calls| calls.as_a.map { |c| c["id"].to_s } } || ([] of String)
  end
end

def context_answers(log : Array(Context::Message)) : Array(String)
  log.compact_map { |message| message.as?(Context::Tool).try(&.[:tool_call_id]) }
end

describe Context do
  describe "#units" do
    it "keeps a tool response glued to the assistant message that asked for it" do
      units = Context.units(context_transcript(2))
      # system, then two units per turn (the user message, then assistant+its
      # tool response together)
      units.size.should eq(5)
      units[2].size.should eq(2)
      units[2][0].as?(JSON::Any).should_not be_nil
      units[2][1].as?(Context::Tool).should_not be_nil
    end

    it "treats a plain message as its own unit" do
      log = [{role: "user", content: "hi"}, {role: "assistant", content: "hello"}] of Context::Message
      Context.units(log).size.should eq(2)
    end
  end

  describe "#trim" do
    it "returns the log untouched while it still fits" do
      log = context_transcript(2)
      Context.eliding?(log, recent: 6).should be_false
      Context.trim(log, recent: 6).should eq(log)
    end

    it "keeps the system prompt and only the most recent exchanges" do
      trimmed = Context.trim(context_transcript(10), recent: 3)

      trimmed.first.should eq({role: "system", content: "you are black"})
      # system + the last three units, which is 5 messages
      trimmed.size.should eq(6)
      context_answers(trimmed).should eq(["c8", "c9"])
    end

    it "inserts the summary only when something was actually elided" do
      summary : Context::Message = {role: "system", content: "SUMMARY"}

      Context.trim(context_transcript(2), recent: 6).should_not contain(summary)
      Context.trim(context_transcript(10), recent: 3, summary: summary).should contain(summary)
    end

    it "never sends a tool response whose assistant call was dropped, or the reverse" do
      # The failure this exists to prevent: some providers reject the entire
      # request with a 400 when a tool_call_id has no matching response (or a
      # response outlives its call) - and that raises all the way past
      # Chess#run, losing the game's progress since the last save.
      log = context_transcript(12)
      (1..8).each do |recent|
        trimmed = Context.trim(log, recent: recent)
        context_answers(trimmed).should eq(context_calls(trimmed))
      end
    end

    it "is stable - trimming an already-trimmed log changes nothing further" do
      trimmed = Context.trim(context_transcript(12), recent: 4)
      Context.trim(trimmed, recent: 4).should eq(trimmed)
    end

    it "serializes to a request the way an OpenAI-compatible API expects" do
      # Roles and tool_call_id links have to survive JSON, since that's the
      # only form the provider ever sees.
      trimmed = Context.trim(context_transcript(12), recent: 4, summary: {role: "system", content: "SUMMARY"})

      parsed = JSON.parse(trimmed.to_json).as_a
      parsed.map { |m| m["role"].to_s }.uniq.should eq(["system", "user", "assistant", "tool"])
      parsed.map { |m| m["role"].to_s }.first(2).should eq(["system", "system"])

      calls = parsed.select { |m| m["tool_calls"]? }.flat_map { |m| m["tool_calls"].as_a.map { |c| c["id"].to_s } }
      answers = parsed.select { |m| m["tool_call_id"]? }.map { |m| m["tool_call_id"].to_s }
      answers.should eq(calls)
      answers.empty?.should be_false
    end
  end
end
