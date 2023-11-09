require "json"
require "http/client"

class AI
  property prev_tool_id : String?
  URL   = "https://api.openai.com/v1/chat/completions"
  MODEL = "gpt-4-1106-preview"

  def initialize
    @api_key = ENV["OPENAI_API_KEY"]
    @messages = [] of NamedTuple(role: String, content: String) | NamedTuple(tool_call_id: String, role: String, name: String, content: String) | JSON::Any
    @prev_tool_id = nil

    @messages.push(
      {
        role:    "user",
        content: "you are playing a game of chess against Magnus Carlson. you are black. do not ask questions. what is your next move?",
      }
    )
  end

  def next_move(moves : Array(String), error : String? = nil)
    if tool_id = @prev_tool_id
      @messages.push({
        tool_call_id: tool_id,
        role:         "tool",
        name:         "move",
        content:      moves.last,
      })
    end
    @messages.push({role: "system", content: "error: #{error}"}) unless error.empty?
    body = {
      model:       MODEL,
      temperature: 1.0,
      messages:    @messages,
      tools:       [
        {
          type:     "function",
          function: {
            name:        "moves",
            description: "list of moves played so far",
            parameters:  {
              type:       "object",
              properties: {} of String => String,
            },
          },
        },
        {
          type:     "function",
          function: {
            name:        "move",
            description: "play the next move",
            parameters:  {
              type:       "object",
              properties: {
                nextMove: {
                  type:        "string",
                  description: "long algebraic notation i.e. e2e4",
                },
              },
            },
          },
        },
      ],
      tool_choice: "auto",
    }.to_json

    response = HTTP::Client.post(URL, headers: build_headers, body: body)
    result = handle_response(response)
    puts result

    choices = result["choices"]
    message = choices[choices.size - 1]["message"]
    @messages.push(message)

    tool_calls = message["tool_calls"]

    if tool_calls.nil?
      puts message["content"]
      return next_move(moves, error)
    end

    tool = tool_calls[tool_calls.size - 1]
    if tool["function"]["name"] == "moves"
      @messages.push({
        tool_call_id: tool["id"].to_s,
        role:         "tool",
        name:         "moves",
        content:      "#{moves.join(", ")}",
      })
      return next_move(moves, error)
    else
      @prev_tool_id = tool["id"].to_s
      return JSON.parse(tool["function"]["arguments"].to_s)["nextMove"].to_s.strip
    end
  end

  private def build_headers(extra_headers : HTTP::Headers? = nil)
    headers = HTTP::Headers{
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type"  => "application/json",
    }
    extra_headers.try &.each do |key, value|
      headers.add(key, value)
    end
    headers
  end

  private def handle_response(response : HTTP::Client::Response)
    if response.success?
      JSON.parse(response.body)
    else
      raise "Error: #{response.status_code} - #{response.body}"
    end
  end
end
