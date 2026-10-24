-- Hokm rules engine regression tests (Lua 5.4)
-- Run: lua5.4 test_game.lua

local Deck = require("deck")
local Game = require("game")

-- Test runner
local testCount = 0

local function test(name, fn)
    local ok, err = pcall(fn)

    if not ok then
        error(("FAIL: %s\n%s"):format(name, tostring(err)), 0)
    end

    testCount = testCount + 1
    print("PASS: " .. name)
end

-- Test helpers

local function card(suit, rank)
    return { suit = suit, rank = rank }
end

local function cards(...)
    return { ... }
end

local function playingGame(hands, tricks, matchPoints, hokm, hakem)
    local game = Game.new()

    game.phase = "PLAYING"
    game.hakem = hakem or 1
    game.hokm = hokm or "spades"
    game.currentSeat = 1
    game.trickScores = tricks or { 0, 0 }
    game.matchScores = matchPoints or { 0, 0 }
    game.handNumber = 1

    for seat = 1, 4 do
        game.players[seat].hand = hands[seat]
    end

    return game
end

local function oneCardGame(suitsAndRanks, tricks, matchPoints, hokm, hakem)
    local hands = {}

    for seat = 1, 4 do
        local spec = suitsAndRanks[seat]
        hands[seat] = { card(spec[1], spec[2]) }
    end

    return playingGame(hands, tricks, matchPoints, hokm, hakem)
end

local function playTrick(game)
    local result

    for _ = 1, 4 do
        local seat = game.currentSeat
        local moves = assert(game:getLegalMoves(seat))
        result = assert(game:playCard(seat, moves[1]))
    end

    assert(result.trickCompleted)
    return result
end

local function dealNewHand(game, hokm)
    local hand = assert(game:dealFirstFive())
    assert(game:chooseHokm(game.hakem, hokm or hand[1].suit))
    assert(game:dealRemainingCards())
end

local function assertUniqueHands(game, expectedCount)
    local seen = {}
    local count = 0

    for seat = 1, 4 do
        for _, c in ipairs(game.players[seat].hand) do
            assert(c.rank >= 2 and c.rank <= 14, "Bad card rank")

            assert(
                c.suit == "hearts"
                or c.suit == "diamonds"
                or c.suit == "clubs"
                or c.suit == "spades",
                "Bad suit"
            )

            local id = c.suit .. ":" .. c.rank

            assert(not seen[id], "Duplicate card: " .. id)

            seen[id] = true
            count = count + 1
        end
    end

    assert(
        count == expectedCount,
        "Expected " .. expectedCount .. " cards, got " .. count
    )

    return seen
end


-- ==================================================
-- DECK TESTS
-- ==================================================

test("Deck: 52 distinct cards, 13 cards per suit", function()
    local deck = Deck.new()

    assert(#deck.cards == 52)

    local seen = {}
    local suitCounts = {}

    for _, c in ipairs(deck.cards) do
        assert(c.rank >= 2 and c.rank <= 14 and c.rank % 1 == 0)

        assert(
            c.suit == "hearts"
            or c.suit == "diamonds"
            or c.suit == "clubs"
            or c.suit == "spades"
        )

        local key = c.suit .. ":" .. c.rank

        assert(not seen[key], "Duplicate: " .. key)

        seen[key] = true
        suitCounts[c.suit] = (suitCounts[c.suit] or 0) + 1
    end

    for _, suit in ipairs({
        "hearts", "diamonds", "clubs", "spades"
    }) do
        assert(suitCounts[suit] == 13)
    end
end)


test("Deck: shuffle preserves all 52 cards and their identity", function()
    local deck = Deck.new()
    deck:shuffle()

    local seen = {}

    for _, c in ipairs(deck.cards) do
        local key = c.suit .. ":" .. c.rank

        assert(not seen[key])
        seen[key] = true
    end

    assert(#deck.cards == 52)
    assert(#(Deck.new().cards) == 52)

    assert(deck:draw() ~= nil and #deck.cards == 51)

    -- Shuffling a partially drawn deck must not add cards.
    deck:shuffle()

    assert(#deck.cards == 51)
end)


test("Deck: draw each card exactly once; empty draw returns an error", function()
    local deck = Deck.new()
    deck:shuffle()

    local seen = {}

    for _ = 1, 52 do
        local c, err = deck:draw()

        assert(c and err == nil)

        local id = c.suit .. ":" .. c.rank

        assert(not seen[id])
        seen[id] = true
    end

    assert(#deck.cards == 0)

    local c, err = deck:draw()

    assert(c == nil and err == "deck_is_empty")
    assert(#deck.cards == 0)
end)


test("Deck: instances do not share cards or mutable card tables", function()
    local first = Deck.new()
    local second = Deck.new()

    first.cards[1].rank = 99
    first:draw()

    assert(#first.cards == 51)
    assert(#second.cards == 52)
    assert(second.cards[1].rank == 2)
end)


-- ==================================================
-- GAME PHASES AND DEALING
-- ==================================================

test("Game: reject methods called in the wrong phase", function()
    local game = Game.new()

    assert(game.phase == "CHOOSE_HAKEM")
    assert(not game:dealFirstFive())
    assert(not game:dealRemainingCards())
    assert(not game:chooseHokm(1, "hearts"))
    assert(not game:getLegalMoves(1))
    assert(not game:playCard(1, 1))
    assert(not game:startNextHand())

    assert(game.hakem == nil and game.deck == nil)

    local hakem = assert(game:chooseFirstHakem())

    assert(hakem >= 1 and hakem <= 4)
    assert(game.handNumber == 1)
    assert(game.phase == "DEAL_FIRST_FIVE")

    assert(not game:chooseFirstHakem())
    assert(not game:dealRemainingCards())
    assert(not game:chooseHokm(hakem, "hearts"))

    local hand = assert(game:dealFirstFive())

    assert(#hand == 5)
    assert(#game.deck.cards == 47)

    -- Cannot deal five cards twice.
    assert(not game:dealFirstFive())
    assert(not game:dealRemainingCards())

    assert(game.phase == "CHOOSE_HOKM")
end)


test("Game: Hakem alone chooses one valid trump suit", function()
    local game = Game.new()

    local hakem = assert(game:chooseFirstHakem())

    assert(game:dealFirstFive())

    local other = (hakem % 4) + 1

    assert(not game:chooseHokm(other, "clubs"))
    assert(not game:chooseHokm(hakem, "joker"))
    assert(not game:chooseHokm(hakem, "SPADES"))
    assert(not game:chooseHokm(hakem, nil))
    assert(not game:chooseHokm(hakem, 14))

    assert(game.hokm == nil)
    assert(game.phase == "CHOOSE_HOKM")

    assert(game:chooseHokm(hakem, "diamonds"))
    assert(game.hokm == "diamonds")

    -- Cannot choose Hokm again.
    assert(not game:chooseHokm(hakem, "spades"))
    assert(game.hokm == "diamonds")
end)


test("Game: Hakem may choose a suit missing from the first five cards", function()
    local game = Game.new()

    game.phase = "CHOOSE_HOKM"
    game.hakem = 1

    game.players[1].hand = {
        card("hearts", 2),
        card("hearts", 3),
        card("hearts", 4),
        card("hearts", 5),
        card("hearts", 6)
    }

    assert(game:chooseHokm(1, "clubs"))

    assert(game.hokm == "clubs")
    assert(game.phase == "DEAL_REMAINING")
end)


test("Game: deal 5-4-4 to each player, starting with Hakem", function()
    local game = Game.new()

    local hakem = assert(game:chooseFirstHakem())

    assert(game:dealFirstFive())

    for seat = 1, 4 do
        assert(
            #game.players[seat].hand ==
            (seat == hakem and 5 or 0)
        )
    end

    assert(#game.deck.cards == 47)

    assert(game:chooseHokm(hakem, "hearts"))
    assert(game:dealRemainingCards())

    -- Prevent double-dealing.
    assert(not game:dealRemainingCards())

    assert(game.phase == "PLAYING")
    assert(game.currentSeat == hakem)
    assert(#game.deck.cards == 0)

    for seat = 1, 4 do
        assert(#game.players[seat].hand == 13)
    end

    assertUniqueHands(game, 52)
end)


test("Game: separate game instances do not share match state", function()
    local first = Game.new()
    local second = Game.new()

    assert(first:chooseFirstHakem())
    assert(first:dealFirstFive())

    first.matchScores[1] = 5

    assert(second.phase == "CHOOSE_HAKEM")
    assert(second.matchScores[1] == 0)

    for seat = 1, 4 do
        assert(#second.players[seat].hand == 0)
    end
end)


-- ==================================================
-- TURNS AND LEGAL MOVES
-- ==================================================

test("Moves: leading player may play any card", function()
    local game = playingGame({
        cards(
            card("hearts", 2),
            card("spades", 14),
            card("clubs", 5)
        ),
        cards(card("hearts", 4)),
        cards(card("hearts", 5)),
        cards(card("hearts", 6))
    })

    local moves = assert(game:getLegalMoves(1))

    assert(#moves == 3)
    assert(moves[1] == 1)
    assert(moves[2] == 2)
    assert(moves[3] == 3)

    assert(not game:getLegalMoves(2))
    assert(not game:getLegalMoves(5))
    assert(not game:getLegalMoves(nil))
end)


test("Moves: follow suit even if player also has a trump card", function()
    local game = playingGame({
        cards(card("hearts", 2)),
        cards(
            card("hearts", 5),
            card("spades", 14)
        ),
        cards(card("hearts", 6)),
        cards(card("hearts", 7))
    })

    assert(game:playCard(1, 1))

    local moves = assert(game:getLegalMoves(2))

    assert(#moves == 1 and moves[1] == 1)

    assert(not game:playCard(2, 2))

    assert(#game.players[2].hand == 2)
    assert(#game.currentTrick == 1)
    assert(game.currentSeat == 2)

    assert(game:playCard(2, 1))
    assert(game:playCard(3, 1))

    local result = assert(game:playCard(4, 1))

    assert(result.trickWinner == 4)
    assert(result.winningTeam == 2)
end)


test("Moves: player without the led suit may discard OR play trump", function()
    local game = playingGame({
        cards(card("hearts", 14)),
        cards(
            card("clubs", 3),
            card("spades", 2)
        ),
        cards(card("hearts", 3)),
        cards(card("hearts", 4))
    })

    assert(game:playCard(1, 1))

    local moves = assert(game:getLegalMoves(2))

    assert(#moves == 2)
    assert(moves[1] == 1)
    assert(moves[2] == 2)

    -- Player 2 chooses to discard, not use trump.
    assert(game:playCard(2, 1))
    assert(game:playCard(3, 1))

    local result = assert(game:playCard(4, 1))

    -- Ace of hearts still wins.
    assert(result.trickWinner == 1)
end)


test("Moves: wrong turn and playing twice are rejected without mutation", function()
    local game = oneCardGame({
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 },
        { "hearts", 5 }
    })

    assert(not game:playCard(2, 1))

    assert(game:playCard(1, 1))

    -- Player 1 cannot play again immediately.
    assert(not game:playCard(1, 1))
    assert(not game:playCard(3, 1))

    assert(game.currentSeat == 2)
    assert(#game.currentTrick == 1)

    assert(game.trickScores[1] == 0)
    assert(game.trickScores[2] == 0)

    assert(#game.players[2].hand == 1)
end)


test("Moves: invalid card indices do not change game state", function()
    local game = oneCardGame({
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 },
        { "hearts", 5 }
    })

    local badValues = {
        0,
        -1,
        2,
        999,
        1.25,
        "1",
        false,
        {},
        math.huge,
        0 / 0
    }

    for _, index in ipairs(badValues) do
        local result, err = game:playCard(1, index)

        assert(result == nil)
        assert(type(err) == "string", "Invalid index accepted")

        assert(game.currentSeat == 1)
        assert(#game.currentTrick == 0)
        assert(#game.players[1].hand == 1)

        assert(game.trickScores[1] == 0)
        assert(game.trickScores[2] == 0)
    end

    assert(not game:playCard(1, nil))

    -- A valid action must still work.
    assert(game:playCard(1, 1))
end)


-- ==================================================
-- TRICK WINNER DETERMINATION
-- ==================================================

test("Tricks: without trump, highest card of LED suit wins", function()
    local game = oneCardGame({
        { "hearts",   4 },
        { "clubs",    14 },
        { "hearts",   13 },
        { "diamonds", 14 }
    })

    local result = playTrick(game)

    assert(result.trickWinner == 3)
    assert(result.winningTeam == 1)
    assert(result.trickScores[1] == 1)
end)


test("Tricks: lowest trump beats Ace of led suit", function()
    local game = oneCardGame({
        { "hearts", 14 },
        { "spades", 2 },
        { "hearts", 13 },
        { "clubs",  14 }
    })

    local result = playTrick(game)

    assert(result.trickWinner == 2)
    assert(result.winningTeam == 2)
end)


test("Tricks: among multiple trumps, highest trump wins", function()
    local game = oneCardGame({
        { "hearts", 14 },
        { "spades", 2 },
        { "spades", 13 },
        { "clubs",  14 }
    })

    local result = playTrick(game)

    assert(result.trickWinner == 3)
    assert(result.winningTeam == 1)
end)


test("Tricks: when trump is led, player holding trump must follow", function()
    local game = playingGame({
        cards(card("spades", 4)),
        cards(
            card("spades", 2),
            card("hearts", 14)
        ),
        cards(card("clubs", 14)),
        cards(card("spades", 13))
    })

    assert(game:playCard(1, 1))

    local moves = assert(game:getLegalMoves(2))

    assert(#moves == 1 and moves[1] == 1)

    assert(not game:playCard(2, 2))

    assert(game:playCard(2, 1))
    assert(game:playCard(3, 1))

    local result = assert(game:playCard(4, 1))

    assert(result.trickWinner == 4)
end)


test("Tricks: scores change only after fourth card; winner leads next", function()
    local game = playingGame({
        cards(
            card("hearts", 2),
            card("clubs", 10)
        ),
        cards(
            card("hearts", 14),
            card("clubs", 2)
        ),
        cards(
            card("hearts", 3),
            card("clubs", 3)
        ),
        cards(
            card("hearts", 4),
            card("clubs", 4)
        )
    })

    for i = 1, 3 do
        local result = assert(game:playCard(i, 1))

        assert(result.trickCompleted == false)
        assert(#game.currentTrick == i)
        assert(game.currentSeat == i + 1)

        assert(game.trickScores[1] == 0)
        assert(game.trickScores[2] == 0)
    end

    local result = assert(game:playCard(4, 1))

    assert(result.trickCompleted)
    assert(result.trickWinner == 2)

    assert(game.trickScores[2] == 1)
    assert(game.currentSeat == 2)
    assert(#game.currentTrick == 0)

    -- Player 2 must lead the next trick.
    assert(not game:playCard(1, 1))
    assert(game:playCard(2, 1))

    assert(game.currentSeat == 3)
    assert(#game.currentTrick == 1)
end)


test("Tricks: winner calculation matches independent rules across 1000 random tricks", function()
    math.randomseed(1031)

    local suits = {
        "hearts",
        "diamonds",
        "clubs",
        "spades"
    }

    for _ = 1, 1000 do
        local deck = Deck.new()
        deck:shuffle()

        local dealt = {}

        for seat = 1, 4 do
            dealt[seat] = deck:draw()
        end

        local hokm = suits[math.random(4)]

        local game = playingGame({
            { dealt[1] },
            { dealt[2] },
            { dealt[3] },
            { dealt[4] }
        }, nil, nil, hokm)

        -- Independent winner calculation.
        local candidateSuit = dealt[1].suit

        for _, c in ipairs(dealt) do
            if c.suit == hokm then
                candidateSuit = hokm
                break
            end
        end

        local winner = nil
        local bestRank = -1

        for seat, c in ipairs(dealt) do
            if c.suit == candidateSuit and c.rank > bestRank then
                winner = seat
                bestRank = c.rank
            end
        end

        assert(playTrick(game).trickWinner == winner)
    end
end)


-- ==================================================
-- SCORING AND HAND TRANSITIONS
-- ==================================================

test("Scores: normal Hakem-team win awards 1 point and retains Hakem", function()
    local game = oneCardGame({
        { "hearts", 14 },
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 6, 2 }, { 3, 1 })

    local result = playTrick(game)

    assert(result.handFinished)
    assert(not result.matchFinished)

    assert(result.handWinner == 1)
    assert(result.pointsEarned == 1)

    assert(game.matchScores[1] == 4)
    assert(game.phase == "HAND_FINISHED")

    assert(game:startNextHand() == 1)

    assert(game.phase == "DEAL_FIRST_FIVE")
    assert(game.hokm == nil)

    assert(game.matchScores[1] == 4)
    assert(game.trickScores[1] == 0)

    assert(game.currentSeat == nil)
    assert(#game.currentTrick == 0)

    assert(game.handNumber == 2)
    assert(game.deck == nil)

    for seat = 1, 4 do
        assert(#game.players[seat].hand == 0)
    end
end)


test("Scores: normal opposing-team win awards 1 point and rotates Hakem", function()
    local game = oneCardGame({
        { "hearts", 2 },
        { "hearts", 14 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 2, 6 }, { 0, 3 })

    local result = playTrick(game)

    assert(result.handWinner == 2)
    assert(result.pointsEarned == 1)

    assert(game.matchScores[2] == 4)

    assert(game:startNextHand() == 2)

    assert(game.matchScores[2] == 4)
    assert(game.trickScores[2] == 0)
end)


test("Scores: Hakem team 7-0 earns 2 points (Kot)", function()
    local game = oneCardGame({
        { "hearts", 14 },
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 6, 0 }, { 1, 2 })

    local result = playTrick(game)

    assert(result.pointsEarned == 2)
    assert(result.handWinner == 1)

    assert(game.matchScores[1] == 3)
    assert(game.matchScores[2] == 2)
end)


test("Scores: opposing team 7-0 earns 3 points (Hakem Koti)", function()
    local game = oneCardGame({
        { "hearts", 2 },
        { "hearts", 14 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 0, 6 }, { 2, 1 })

    local result = playTrick(game)

    assert(result.pointsEarned == 3)
    assert(result.handWinner == 2)

    assert(game.matchScores[1] == 2)
    assert(game.matchScores[2] == 4)
end)


test("Scores: match finishes at 7 or more (including Kot overrun)", function()
    local normal = oneCardGame({
        { "hearts", 14 },
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 6, 1 }, { 6, 0 })

    local r = playTrick(normal)

    assert(r.matchFinished)
    assert(r.matchWinner == 1)

    assert(normal.phase == "MATCH_FINISHED")
    assert(normal.matchScores[1] == 7)

    assert(not normal:startNextHand())

    local kot = oneCardGame({
        { "hearts", 14 },
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 6, 0 }, { 6, 0 })

    r = playTrick(kot)

    assert(r.matchFinished)
    assert(r.pointsEarned == 2)
    assert(kot.matchScores[1] == 8)

    local hakemKoti = oneCardGame({
        { "hearts", 2 },
        { "hearts", 14 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 0, 6 }, { 0, 5 })

    r = playTrick(hakemKoti)

    assert(r.matchFinished)
    assert(r.pointsEarned == 3)
    assert(hakemKoti.matchScores[2] == 8)
end)


test("Phases: no more moves or double scoring after a hand ends", function()
    local game = oneCardGame({
        { "hearts", 14 },
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 6, 2 }, { 3, 1 })

    local result = playTrick(game)

    assert(result.handFinished)
    assert(game.phase == "HAND_FINISHED")

    assert(not game:playCard(game.currentSeat, 1))
    assert(not game:getLegalMoves(game.currentSeat))
    assert(not game:dealRemainingCards())
    assert(not game:dealFirstFive())

    assert(game.matchScores[1] == 4)

    assert(game:startNextHand())

    -- Cannot reset the same hand twice.
    assert(not game:startNextHand())

    assert(game.matchScores[1] == 4)
end)


test("Phases: next Hakem wraps from seat 4 to seat 1", function()
    local game = oneCardGame({
        { "hearts", 14 },
        { "hearts", 2 },
        { "hearts", 3 },
        { "hearts", 4 }
    }, { 6, 2 }, { 0, 0 }, "spades", 4)

    local result = playTrick(game)

    assert(result.handWinner == 1)

    assert(game:startNextHand() == 1)
    assert(game.hakem == 1)

    dealNewHand(game)

    assert(game.currentSeat == 1)
    assert(game.phase == "PLAYING")

    assertUniqueHands(game, 52)
end)


-- ==================================================
-- FULL MATCH SIMULATIONS
-- ==================================================

test("Simulations: 100 complete matches maintain turn, count, and score invariants", function()
    for seed = 1, 100 do
        math.randomseed(seed)

        local game = Game.new()

        assert(game:chooseFirstHakem())

        local handsPlayed = 0

        while game.phase ~= "MATCH_FINISHED" do
            handsPlayed = handsPlayed + 1

            assert(handsPlayed <= 13, "Match did not terminate")
            assert(game.handNumber == handsPlayed)

            local hand = assert(game:dealFirstFive())

            assert(#hand == 5)

            assert(game:chooseHokm(
                game.hakem,
                hand[1].suit
            ))

            assert(game:dealRemainingCards())

            assertUniqueHands(game, 52)

            local tricksPlayed = 0
            local playedCards = 0

            local oldMatchScores = {
                game.matchScores[1],
                game.matchScores[2]
            }

            while game.phase == "PLAYING" do
                assert(playedCards < 52, "Too many cards played")

                local seat = game.currentSeat
                local currentLength = #game.currentTrick

                local oldTrickScores = {
                    game.trickScores[1],
                    game.trickScores[2]
                }

                local moves = assert(game:getLegalMoves(seat))

                assert(#moves > 0)

                local picked = moves[math.random(#moves)]

                local result = assert(game:playCard(seat, picked))

                assert(result.playedBy == seat)

                playedCards = playedCards + 1

                if result.trickCompleted then
                    assert(currentLength == 3)
                    assert(#game.currentTrick == 0)

                    assert(game.currentSeat == result.trickWinner)

                    tricksPlayed = tricksPlayed + 1

                    assert(
                        game.trickScores[1] + game.trickScores[2]
                        == tricksPlayed
                    )

                    assert(
                        game.trickScores[result.winningTeam]
                        == oldTrickScores[result.winningTeam] + 1
                    )

                    assert(
                        result.trickScores[1] == game.trickScores[1]
                        and result.trickScores[2] == game.trickScores[2]
                    )
                else
                    assert(currentLength < 3)
                    assert(#game.currentTrick == currentLength + 1)

                    assert(game.currentSeat == (seat % 4) + 1)

                    assert(
                        game.trickScores[1] == oldTrickScores[1]
                        and game.trickScores[2] == oldTrickScores[2]
                    )

                    assert(
                        game.matchScores[1] == oldMatchScores[1]
                        and game.matchScores[2] == oldMatchScores[2]
                    )
                end

                local remaining = 0

                for p = 1, 4 do
                    remaining = remaining + #game.players[p].hand
                end

                assert(
                    remaining + playedCards == 52,
                    "Card count changed"
                )
            end

            assert(tricksPlayed >= 7 and tricksPlayed <= 13)
            assert(playedCards == tricksPlayed * 4)

            assert(
                game.trickScores[1] == 7
                or game.trickScores[2] == 7
            )

            assert(
                game.matchScores[1] >= oldMatchScores[1]
                and game.matchScores[2] >= oldMatchScores[2]
            )

            assert(
                game.matchScores[1] == oldMatchScores[1]
                or game.matchScores[2] == oldMatchScores[2]
            )

            if game.phase == "HAND_FINISHED" then
                assert(game:startNextHand())
            end
        end

        assert(
            game.matchScores[1] >= 7
            or game.matchScores[2] >= 7
        )
    end
end)


print(
    ("All Hokm tests passed (%d test groups; 100 full matches; 1000 trick cases).")
    :format(testCount)
)
