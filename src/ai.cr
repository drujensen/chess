require "json"
require "http/client"

class AI
  BASE_URL = "https://api.openai.com/v1"
  MODEL    = "gpt-4-1106-preview"

  def initialize
    @api_key = ENV["OPENAI_API_KEY"]
  end

  def next_move(moves : Array(String), error : String? = nil)
    url = "#{BASE_URL}/chat/completions"

    content = "let's play a game of chess! I'm white and you are black. I always play first.\n"
    content += "oh no! it looks like your last move was invalid: #{error}\n" unless error.empty?
    content += "here is a list of all the moves played so far:\n"
    content += "#{moves.join(", ")}.\n"
    content += "what is your next move?"

    body = {
      model:    MODEL,
      messages: [
        {
          role:    "user",
          content: content,
        },
      ],
      tools: [
        {
          type:     "function",
          function: {
            name:        "move",
            description: "A function that plays the next move in a chess game.",
            parameters:  {
              type:       "object",
              properties: {
                nextMove: {
                  type:        "string",
                  description: "The next move to play in standard chess notation i.e. e2e4",
                },
              },
            },
          },
        },
      ],
      tool_choice: "auto",
    }.to_json

    response = HTTP::Client.post(url, headers: build_headers, body: body)

    result = handle_response(response)

    move = JSON.parse(result["choices"][0]["message"]["tool_calls"][0]["function"]["arguments"].to_s)["nextMove"]

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
