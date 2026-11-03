-- Jokers for the card game (Balatro style). Each joker changes the score of
-- a played hand: chips x mult.
--   card(ctx, card)   called for every scoring card (card.rank 2..14, card.suit)
--   hand(ctx)         called once after the cards; ctx.hand = name of the poker hand,
--                     ctx.chips, ctx.mult can be changed, ctx.cards = scoring cards
--   icon              assets/sprites/icons/<icon>.png drawn on the joker card

return {
    joker = { name = "Шут", text = "+4 множ.", icon = "clover",
        hand = function(ctx) ctx.mult = ctx.mult + 4 end },
    greedy = { name = "Жадина", text = "+3 множ. за каждую ♦", icon = "coin",
        card = function(ctx, card) if card.suit == "diamonds" then ctx.mult = ctx.mult + 3 end end },
    lusty = { name = "Сердцеед", text = "+3 множ. за каждую ♥", icon = "potion",
        card = function(ctx, card) if card.suit == "hearts" then ctx.mult = ctx.mult + 3 end end },
    jolly = { name = "Весельчак", text = "+8 множ., если есть пара", icon = "mushroom",
        hand = function(ctx) if ctx.pairs >= 1 then ctx.mult = ctx.mult + 8 end end },
    banana = { name = "Морковка", text = "+30 фишек", icon = "carrot",
        hand = function(ctx) ctx.chips = ctx.chips + 30 end },
    stone = { name = "Каменщик", text = "x2 множ. за флеш", icon = "stone",
        hand = function(ctx) if ctx.flush then ctx.mult = ctx.mult * 2 end end },
    scholar = { name = "Учёный", text = "Тузы: +20 фишек, +4 множ.", icon = "key",
        card = function(ctx, card) if card.rank == 14 then ctx.chips = ctx.chips + 20; ctx.mult = ctx.mult + 4 end end },
}
