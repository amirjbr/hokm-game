# Hokm (Lua 5.4)

A terminal-only implementation of four-player partnership Hokm. It contains the game rules and a small console driver; it is not a FiveM resource.

## Run

```bash
lua5.4 main.lua
```

By default, `AUTO_PLAY = true` in `main.lua` simulates a complete match using very simple bots that always play the first legal card. Set it to `false` for local human input: the console prompts each of the four players in turn. The console is **not** a private multiplayer interface.

Test without manual input:

```bash
lua5.4 test_game.lua
```

## Rules implemented

- Four players with fixed teams 1+3 and 2+4. Seat order 1 -> 2 -> 3 -> 4 is anticlockwise.
- Choose the first Hakem by revealing cards until the first Ace appears.
- Start each hand with a fresh deck, deal 5 cards to Hakem, choose trump, then finish dealing (5 to each of the other players, followed by 4 to everyone twice).
- Hakem leads the first trick; the trick winner leads the next.
- Players must follow suit when possible. The highest trump wins; otherwise the highest card of the suit led wins.
- First partnership to win 7 tricks wins the hand. Ordinary win is 1 match point; 7-0 by Hakem's partnership gives 2 points, by their opponents gives 3 points.
- Hakem remains if their partnership won; otherwise the next player in turn order becomes Hakem.
- Match ends when a partnership reaches at least 7 match points.

## Known limitations

- Initial teams are fixed; the traditional second-Ace partner-selection procedure is not modeled.
- No GUI, FiveM integration, true multiplayer privacy, player identity/authentication, networking, persistence, or reconnect handling.
- Autobots make simple legal moves; no strategy.
- Uses `math.random()` for local simulation; a server deployment would require deliberate security and randomness design.
