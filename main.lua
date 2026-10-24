local Game = require("game")

math.randomseed(os.time())

-- true: simulate a complete match automatically.
-- false: enter each player's card number manually.
local AUTO_PLAY = false

local function ask(message)
    io.write(message)
    local response = io.read("*l")
    if not response then
        print("\nInput closed.")
        os.exit(0)
    end
    return response:match("^%s*(.-)%s*$"):lower()
end

local function showHand(hand, legalMoves)
    local legal = {}
    if legalMoves then
        for _, index in ipairs(legalMoves) do
            legal[index] = true
        end
    end
    for index, card in ipairs(hand) do
        local marker = (legalMoves and legal[index]) and "*" or " "
        print(('%2d. %-9s %2d %s'):format(index, card.suit, card.rank, marker))
    end
end

local function chooseTrump(game)
    local hand = game.players[game.hakem].hand
    if AUTO_PLAY then
        local counts = { hearts = 0, diamonds = 0, clubs = 0, spades = 0 }
        for _, card in ipairs(hand) do
            counts[card.suit] = counts[card.suit] + 1
        end
        local bestSuit = "hearts"
        for _, suit in ipairs({ "diamonds", "clubs", "spades" }) do
            if counts[suit] > counts[bestSuit] then
                bestSuit = suit
            end
        end
        return bestSuit
    end

    showHand(hand)
    while true do
        local suit = ask("Hakem, choose Hokm (hearts/diamonds/clubs/spades): ")
        if ({ hearts = true, diamonds = true, clubs = true, spades = true })[suit] then
            return suit
        end
        print("Invalid suit; try again.")
    end
end

local function chooseCard(game, seat)
    local moves = assert(game:getLegalMoves(seat))
    if AUTO_PLAY then
        return moves[1] -- Simplest bot: play first legal card.
    end

    if #game.currentTrick > 0 then
        print("\nCards already played in this trick:")
        for _, entry in ipairs(game.currentTrick) do
            print(("P%d: %d of %s"):format(entry.seat,
                entry.card.rank, entry.card.suit))
        end
    end

    print("\nPlayer " .. seat .. "'s hand (* = legal move):")
    showHand(game.players[seat].hand, moves)
    return tonumber(ask("Choose card number: "))
end

local game = Game.new()
assert(game:chooseFirstHakem())

while game.phase ~= "MATCH_FINISHED" do
    print(("\n=== Hand %d | Hakem: Player %d ===")
        :format(game.handNumber, game.hakem))

    assert(game:dealFirstFive())
    local suit = chooseTrump(game)
    assert(game:chooseHokm(game.hakem, suit))
    assert(game:dealRemainingCards())
    print("Hokm: " .. game.hokm)

    while game.phase == "PLAYING" do
        local seat = game.currentSeat
        local cardIndex = chooseCard(game, seat)
        local result, err = game:playCard(seat, cardIndex)

        if not result then
            print("Invalid move: " .. err)
        else
            print(("P%d played %d of %s")
                :format(seat, result.playedCard.rank, result.playedCard.suit))

            if result.trickCompleted then
                print(("Trick winner: P%d (Team %d) | Tricks: %d-%d")
                    :format(result.trickWinner, result.winningTeam,
                        result.trickScores[1], result.trickScores[2]))
            end

            if result.handFinished then
                print(("Hand winner: Team %d | +%d match points | Match: %d-%d")
                    :format(result.handWinner, result.pointsEarned,
                        result.matchScores[1], result.matchScores[2]))
            end
        end
    end

    if game.phase == "HAND_FINISHED" then
        assert(game:startNextHand())
    end
end

print(("\nMatch finished! Final score: Team 1 = %d, Team 2 = %d")
    :format(game.matchScores[1], game.matchScores[2]))
