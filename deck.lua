local Deck = {}
Deck.__index = Deck

local suits = {"hearts", "diamonds", "clubs", "spades"}

function Deck.new()
    local self = setmetatable({ cards = {} }, Deck)
    for _, suit in ipairs(suits) do
        for rank = 2, 14 do
            table.insert(self.cards, { suit = suit, rank = rank })
        end
    end
    return self
end

function Deck:shuffle()
    for i = #self.cards, 2, -1 do
        local j = math.random(i)
        self.cards[i], self.cards[j] = self.cards[j], self.cards[i]
    end
end

function Deck:draw()
    if #self.cards == 0 then
        return nil, "deck_is_empty"
    end
    return table.remove(self.cards)
end

return Deck
