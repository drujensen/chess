require "./spec_helper"
require "../src/ai"

class StubResponseAI < AI
  def initialize(@responses : Array(JSON::Any))
    super()
  end

  private def post_chat_completion(body) : JSON::Any
    @responses.shift
  end
end

describe AI do
  describe "responses with null tool_calls" do
    it "treats null tool_calls as a plain-text chat response" do
      response = JSON.parse(%({"choices":[{"message":{"content":"Hello!","tool_calls":null}}]}))
      ai = StubResponseAI.new([response])
      board = Board.new
      board.setup

      ai.chat(board, "hello").should eq("Hello!")
    end

    it "retries a move response when tool_calls is null" do
      plain_text = JSON.parse(%({"choices":[{"message":{"content":"Let me think.","tool_calls":null}}]}))
      move = JSON.parse(%({"choices":[{"message":{"tool_calls":[{"id":"move-1","type":"function","function":{"name":"move","arguments":"{\\"nextMove\\":\\"e7e5\\"}"}}]}}]}))
      ai = StubResponseAI.new([plain_text, move])
      board = Board.new
      board.setup

      ai.next_move(board).should eq("e7e5")
    end

    it "treats null tool_calls as an unresolved natural-language move" do
      response = JSON.parse(%({"choices":[{"message":{"content":"That is not a move.","tool_calls":null}}]}))
      ai = StubResponseAI.new([response])
      board = Board.new
      board.setup

      ai.resolve_move(board, "hello", true).should be_nil
    end
  end

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
