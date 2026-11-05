require "./spec_helper"
require "../src/ai"

describe AI do
  describe ".tool_reasoning_effort" do
    it "disables reasoning effort for GPT-6 Luna on OpenAI" do
      AI.tool_reasoning_effort("gpt-6-luna", "api.openai.com").should eq("none")
    end

    it "does not add the OpenAI-specific setting for other models or routes" do
      AI.tool_reasoning_effort("gpt-6-luna", "opencode.ai").should be_nil
      AI.tool_reasoning_effort("gpt-6", "api.openai.com").should be_nil
      AI.tool_reasoning_effort("claude-haiku-5-5", "api.anthropic.com").should be_nil
    end
  end
end
