# Chess

Play a game of chess against an AI.

Written in the Crystal language.

This is a terminal app that allows you to play chess against
an AI opponent. You get to play white; the AI plays black,
at a skill level you choose.

You may need to zoom in to see the board properly.

## Installation

By default the AI opponent is a local [Ollama](https://ollama.com) model
(`ornith:latest`, talking to `http://localhost:11434/v1`), so no API key
is required out of the box - just have Ollama running with that model
pulled.

The endpoint, model, and per-request timeout are all configurable via
environment variables, so you can point this at any OpenAI-compatible API
instead, including the real OpenAI API:
```
export OPENAI_BASE_URL=https://api.openai.com/v1
export OPENAI_MODEL=gpt-4o
export OPENAI_API_KEY=your-api-key
export OPENAI_TIMEOUT=300 # seconds per request before giving up (default 300)
```

Then clone the repository:
```
git clone https://github.com/drujensen/chess.git
```

Install crystal language:
MacOS:
```
brew install crystal
```

Linux:
```
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```

## Build

There are no dependencies to install. Just build the app:
```
shards build
```

## Usage

```
./bin/chess
```

You'll get a menu to start a new game or browse/replay your saved games.

To move, use long algebraic notation.
For example, to move the pawn: `e2e4`
To move the knight: `g1f3`

Type `quit` (or `exit`/`save`) on your turn to stop and pick the game back
up later - or just close the terminal or hit Ctrl+C, since progress is
saved after every move, not only on a clean exit. Use "Resume game" from
the main menu to continue where you left off; the board and move history
come back exactly as they were, though the AI's exact conversational memory
doesn't survive a restart, so it's briefed with the game-so-far instead.

Your player profile (name, Elo rating, win/loss/draw record) and every
finished game's PGN are saved under `~/.chess/` - `profile.json` and
`games/<timestamp>.pgn`. Your rating updates using the standard Elo formula
against the Elo midpoint of whatever skill level you played.

When browsing a saved game, if you have [Stockfish](https://stockfishchess.org/)
installed (e.g. `sudo dnf install stockfish` / `apt install stockfish` /
`brew install stockfish`), you'll be offered a one-time analysis pass that
flags mistakes and blunders with the engine's suggested move instead, shown
above the board as you step through. The analysis is written directly into
the game's PGN as standard comments/NAGs, so it's portable to any other
PGN-reading tool, and only ever computed once per game. Without Stockfish
installed, replay still works, just without the analysis.

On any flagged move, press `e` to have the AI explain *why* it was a
mistake in plain language - grounded in Stockfish's own line for both the
move played and its suggestion, so the AI is only narrating evidence it's
handed, not calculating anything itself. Also computed once and cached
back into the same PGN.

## Development

List of things to contribute:
- [x] Draw chess board using unicode characters
- [x] Handle validation of basic chess moves
- [x] Support long algebraic notation
- [x] Handle castling
- [x] Handle en passant
- [x] Handle pawn promotion - queen only
- [x] Handle check
- [x] Handle checkmate
- [x] Handle stalemate
- [x] Handle draw (threefold repetition / 50-move rule)
- [ ] Add time controls?
- [x] Give the AI a `board` tool (FEN) instead of just move-history text
- [x] Let the AI parse natural-language move requests for white (e.g. "move my king pawn up two squares")
- [ ] Recognize and display opening names (ECO) as a game progresses
- [x] Save finished games to disk (PGN) and let players browse/replay past games
- [x] Save an in-progress game after every move and let players resume it later
- [x] Post-game analysis mode (Stockfish reviews the finished game for blunders/mistakes, shown while browsing saved games - optional, needs `stockfish` installed)
- [ ] Hint mode - ask the AI for a suggested move without committing to it
- [ ] Undo/redo a move
- [x] Make the model/endpoint configurable via env vars instead of hardcoded constants
- [x] Track player rating/ELO across saved games
- [x] Selectable AI skill levels (Novice 0-500, Beginner 500-1000, Intermediate 1000-1500, Advanced 1500-2000, Master 2000-2500, Grandmaster 2500+) so players can progress

## Contributing

1. Fork it (<https://github.com/drujensen/chess/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Dru Jensen](https://github.com/drujensen) - creator and maintainer
