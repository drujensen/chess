require "json"
require "http/client"

class AI
  URL   = "https://api.openai.com/v1/chat/completions"
  MODEL = "gpt-4-1106-preview"

  def initialize
    @api_key = ENV["OPENAI_API_KEY"]
    @messages = [] of NamedTuple(role: String, content: String) | NamedTuple(tool_call_id: String, role: String, name: String, content: String)

    @messages.push(
      {
        role:    "user",
        content: "you are playing a game of chess. you are black. what is your next move?",
      }
    )
  end

  def next_move(moves : Array(String), error : String? = nil)
    @messages.push({role: "system", content: "error: #{error}"}) unless error.empty?
    body = {
      model:       MODEL,
      temperature: 2.0,
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
    puts body
    response = HTTP::Client.post(URL, headers: build_headers, body: body)

    result = handle_response(response)
    puts result

    message = result["choices"][0]["message"]

    if message["tool_calls"].size == 0
      raise "Error: no tool calls"
    end

    if message["tool_calls"][0]["function"]["name"] == "moves"
      puts "function moves called"
      tool_id = message["tool_calls"][0]["function"]["tool_call_id"].to_s
      @messages.push({
        tool_call_id: tool_id.to_s,
        role:         "tool",
        name:         "moves",
        content:      "#{moves.join(", ")}",
      })
      return next_move(moves, error)
    else
      puts "function move called"
      move = JSON.parse(message["tool_calls"][0]["function"]["arguments"].to_s)["nextMove"]
    end

    return move.to_s.strip
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
