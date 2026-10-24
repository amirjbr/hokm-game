local Deck = require("deck")

local Game = {}
Game.__index = Game

local validSuits = {
    hearts = true,
    diamonds = true,
    clubs = true,
    spades = true
}

local function nextSeat(seat)
    return (seat % 4) + 1
end

local function teamOf(seat)
    return (seat % 2 == 1) and 1 or 2
end

local function giveCards(game, seat, count)
    for _ = 1, count do
        local card = assert(game.deck:draw())
        table.insert(game.players[seat].hand, card)
    end
end

local function cardStrength(card, ledSuit, trumpSuit)
    if card.suit == trumpSuit then
        return 200 + card.rank
    elseif card.suit == ledSuit then
        return 100 + card.rank
    end
    return card.rank
end

local function trickWinner(trick, trumpSuit)
    local ledSuit = trick[1].card.suit
    local best = trick[1]
    local bestStrength = cardStrength(best.card, ledSuit, trumpSuit)

    for i = 2, #trick do
        local entry = trick[i]
        local strength = cardStrength(entry.card, ledSuit, trumpSuit)
        if strength > bestStrength then
            best = entry
            bestStrength = strength
        end
    end

    return best.seat
end

function Game.new()
    local players = {}
    for seat = 1, 4 do
        players[seat] = { seat = seat, hand = {} }
    end

    return setmetatable({
        players = players,
        deck = nil,
        hakem = nil,
        hokm = nil,
        phase = "CHOOSE_HAKEM",
        handNumber = 0,
        currentSeat = nil,
        currentTrick = {},
        trickScores = {0, 0},
        matchScores = {0, 0},
        lastHandWinner = nil
    }, Game)
end

function Game:chooseFirstHakem()
    if self.phase ~= "CHOOSE_HAKEM" then
        return nil, "Invalid game phase"
    end

    local selectionDeck = Deck.new()
    selectionDeck:shuffle()
    local seat = 1

    while true do
        local card = assert(selectionDeck:draw())
        if card.rank == 14 then
            self.hakem = seat
            self.handNumber = 1
            self.phase = "DEAL_FIRST_FIVE"
            return seat
        end
        seat = nextSeat(seat)
    end
end

function Game:dealFirstFive()
    if self.phase ~= "DEAL_FIRST_FIVE" then
        return nil, "Invalid game phase"
    end

    self.deck = Deck.new()
    self.deck:shuffle()
    giveCards(self, self.hakem, 5)

    self.phase = "CHOOSE_HOKM"
    return self.players[self.hakem].hand
end

function Game:chooseHokm(playerSeat, suit)
    if self.phase ~= "CHOOSE_HOKM" then
        return false, "Not time to choose Hokm"
    end
    if playerSeat ~= self.hakem then
        return false, "Only Hakem can choose Hokm"
    end
    if not validSuits[suit] then
        return false, "Invalid suit"
    end

    self.hokm = suit
    self.phase = "DEAL_REMAINING"
    return true
end

function Game:dealRemainingCards()
    if self.phase ~= "DEAL_REMAINING" then
        return false, "Hokm must be chosen first"
    end

    -- Complete the first packet (5 cards) for the other 3 players.
    local seat = nextSeat(self.hakem)
    for _ = 1, 3 do
        giveCards(self, seat, 5)
        seat = nextSeat(seat)
    end

    -- Two further packets of 4 cards for every player.
    for _ = 1, 2 do
        seat = self.hakem
        for _ = 1, 4 do
            giveCards(self, seat, 4)
            seat = nextSeat(seat)
        end
    end

    self.currentSeat = self.hakem
    self.phase = "PLAYING"
    return true
end

function Game:getLegalMoves(seat)
    if self.phase ~= "PLAYING" then
        return nil, "Not in playing phase"
    end
    if seat ~= self.currentSeat then
        return nil, "Not your turn"
    end

    local hand = self.players[seat].hand
    local ledSuit = self.currentTrick[1]
        and self.currentTrick[1].card.suit

    local hasLedSuit = false
    if ledSuit then
        for _, card in ipairs(hand) do
            if card.suit == ledSuit then
                hasLedSuit = true
                break
            end
        end
    end

    local moves = {}
    for index, card in ipairs(hand) do
        if not hasLedSuit or card.suit == ledSuit then
            table.insert(moves, index)
        end
    end

    return moves
end

function Game:playCard(seat, cardIndex)
    local moves, err = self:getLegalMoves(seat)
    if not moves then
        return nil, err
    end

    if type(cardIndex) ~= "number" or cardIndex % 1 ~= 0 then
        return nil, "Invalid card index"
    end

    local allowed = false
    for _, index in ipairs(moves) do
        if index == cardIndex then
            allowed = true
            break
        end
    end
    if not allowed then
        return nil, "Card not found or you must follow suit"
    end

    local card = table.remove(self.players[seat].hand, cardIndex)
    table.insert(self.currentTrick, { seat = seat, card = card })

    local result = {
        playedCard = card,
        playedBy = seat,
        trickCompleted = false,
        handFinished = false,
        matchFinished = false
    }

    if #self.currentTrick < 4 then
        self.currentSeat = nextSeat(seat)
        return result
    end

    local winnerSeat = trickWinner(self.currentTrick, self.hokm)
    local winnerTeam = teamOf(winnerSeat)
    self.trickScores[winnerTeam] = self.trickScores[winnerTeam] + 1

    result.trickCompleted = true
    result.trickWinner = winnerSeat
    result.winningTeam = winnerTeam
    result.trickScores = {self.trickScores[1], self.trickScores[2]}

    self.currentTrick = {}
    self.currentSeat = winnerSeat

    if self.trickScores[winnerTeam] >= 7 then
        local losingTeam = 3 - winnerTeam
        local points = 1
        if self.trickScores[losingTeam] == 0 then
            points = (winnerTeam == teamOf(self.hakem)) and 2 or 3
        end

        self.matchScores[winnerTeam] = self.matchScores[winnerTeam] + points
        self.lastHandWinner = winnerTeam

        result.handFinished = true
        result.handWinner = winnerTeam
        result.pointsEarned = points
        result.matchScores = {self.matchScores[1], self.matchScores[2]}

        if self.matchScores[winnerTeam] >= 7 then
            self.phase = "MATCH_FINISHED"
            result.matchFinished = true
            result.matchWinner = winnerTeam
        else
            self.phase = "HAND_FINISHED"
        end
    end

    return result
end

function Game:startNextHand()
    if self.phase ~= "HAND_FINISHED" then
        return nil, "Previous hand has not finished, or match is over"
    end

    if self.lastHandWinner ~= teamOf(self.hakem) then
        self.hakem = nextSeat(self.hakem)
    end

    for seat = 1, 4 do
        self.players[seat].hand = {}
    end
    self.deck = nil
    self.hokm = nil
    self.currentSeat = nil
    self.currentTrick = {}
    self.trickScores = {0, 0}
    self.lastHandWinner = nil
    self.handNumber = self.handNumber + 1
    self.phase = "DEAL_FIRST_FIVE"

    return self.hakem
end

return Game
