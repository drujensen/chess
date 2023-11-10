# Chess

Play a game of chess against ChatGPT 4 Turbo.

Written in the Crystal language.

This is a terminal app that allows you to play chess against
the best player in the world. Lucky for you, you get to play
white. ChatGPT will play black.

You may need to zoom in to see the board properly.

## Installation

You will need an API Key from OpenAI to use this app.
```
export OPENAI_API_KEY=your-api-key
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

To move, use long algebraic notation. 
For example, to move the pawn: `e2e4`
To move the knight: `g1f3`

## Development

List of things to contribute:
- [x] Draw chess board using unicode characters
- [x] Handle validation of basic chess moves
- [x] Support long algebraic notation
- [x] Handle castling
- [x] Handle en passant
- [x] Handle pawn promotion - queen only
- [ ] Handle check
- [ ] Handle checkmate
- [ ] Handle stalemate
- [ ] Handle draw
- [ ] Add time controls?

## Contributing

1. Fork it (<https://github.com/drujensen/chess/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Dru Jensen](https://github.com/drujensen) - creator and maintainer
