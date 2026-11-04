require "json"

# Trims the message list sent to the model on each request. `AI` keeps an
# append-only log of the whole game, but nothing in chess needs the whole
# transcript to choose a move: the current position plus the move list already
# carries every fact an earlier turn's FEN or engine ranking did. Left to grow,
# those older messages are both a cost that scales with game length and a
# source of real confusion - by move 20 the log holds twenty different FENs and
# twenty different "top 5 moves" lists describing positions that no longer
# exist, each of which was phrased as though it were current.
#
# This lives apart from `AI` because its one hard rule - never split a tool
# call from the response that answers it - is exactly the kind of thing that
# should be tested directly rather than inferred from a live API call.
module Context
  # How many exchanges of genuine conversational history to keep verbatim, on
  # top of the system prompt. An "exchange" is one unit from #units, so this is
  # roughly the last couple of turns - enough for the model to remember what it
  # just did and what the human said, not enough to keep re-reading stale
  # assessments of positions from ten moves ago.
  RECENT_EXCHANGES = 6

  # A plain chat message, or one message with the tool calls still attached as
  # the model returned them (JSON::Any), since those are pushed back verbatim.
  alias Text = NamedTuple(role: String, content: String)

  # A tool response, which must always stay glued to the assistant message
  # that asked for it - see #units.
  alias Tool = NamedTuple(tool_call_id: String, role: String, name: String, content: String)

  # The same thing as sent on the wire: `name` is optional in the OpenAI
  # tool-message schema, and Anthropic's endpoint rejects it outright, so
  # AI#wire_safe drops it just before the request goes out (see AI).
  alias WireTool = NamedTuple(tool_call_id: String, role: String, content: String)

  alias Message = Text | Tool | WireTool | JSON::Any

  # Groups the log into indivisible exchanges: an assistant message that asked
  # for tools, plus every response answering it, is one unit and can never be
  # trimmed apart. Providers reject a request that carries an assistant tool
  # call with no matching response, or a response whose assistant call was
  # dropped, so trimming at any other boundary risks a 400 that kills the turn.
  def self.units(log : Array(Message)) : Array(Array(Message))
    grouped = [] of Array(Message)

    log.each do |message|
      if tool_response?(message) && !grouped.empty?
        grouped.last << message
      else
        grouped << [message]
      end
    end

    grouped
  end

  def self.tool_response?(message : Message) : Bool
    message.as?(Tool) ? true : false
  end

  # True once this log has grown past what #trim would send untouched - i.e.
  # something would actually be elided. Callers use it to decide whether to
  # bother building a summary at all, so a short game pays nothing for it.
  def self.eliding?(log : Array(Message), recent : Int32 = RECENT_EXCHANGES) : Bool
    units(log).size > recent + 1
  end

  # The messages to actually send: the system prompt (always - it's the only
  # thing stating who the model is and which color it plays), a compact
  # restatement of anything elided, and the most recent exchanges whole.
  #
  # A log that fits is returned as-is, so a short game keeps its exact wording
  # and no summary is invented for history that was never dropped.
  def self.trim(log : Array(Message), recent : Int32 = RECENT_EXCHANGES, summary : Message? = nil) : Array(Message)
    return log.dup unless eliding?(log, recent)

    grouped = units(log)

    # The first unit is kept unconditionally even if it isn't the system prompt,
    # since dropping it would be a far bigger change to the conversation than
    # trimming the middle.
    kept = [] of Message
    grouped.first.each { |message| kept << message }
    if summary
      kept << summary
    end
    grouped[-recent..].each { |unit| unit.each { |message| kept << message } }

    kept
  end
end
