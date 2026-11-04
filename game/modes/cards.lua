-- Card game in the style of Balatro: play poker hands, every hand scores chips x mult,
-- jokers change the score (cards: "Asset Pack Pixel Poker" by Chasersgaming, CC0; jokers: game/data/jokers.lua).
--
--   game.stage "tavern_cards" { kind = "cards", goal = 300, hands = 4, discards = 3 }
--   local r = s:play("cards", { goal = 500, jokers = { "joker", "greedy" } })   -- r.win, r.score
--
--   goal       points to reach (default 300 + 150 x level)
--   hands      hands you can play (default 4)
--   discards   times you can throw cards away and take new ones (default 3)
--   jokers     list of joker ids (default: two random ones); jokers = false - none
--   handSize   cards in the hand (default 8)
-- Keys: [←][→] choose, [Space]/[↑] take a card, [Enter] play, [X] discard, [C] sort.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local function G()
    return require("game")
end

local Cards = class(Arcade)
Cards.keymap = "cards"
Cards.info = {
    title = "Покер Кашки",
    rules = "Выбери до пяти карт и сыграй покерную комбинацию: очки = фишки x множитель. Шуты меняют счёт. "
        .. "Набери цель, пока не кончились ходы.",
    keys = { { "left", "выбор", "[←][→]" }, { "select", "взять" }, { "play", "сыграть" }, { "discard", "сбросить" },
        { "sort", "сортировка" } },
    background = "night",
    dim = 0,
    music = "calm",
}
Cards.defaultLives = 0

local SUITS = { "hearts", "diamonds", "clubs", "spades" }
local SUIT_MARK = { hearts = "♥", diamonds = "♦", clubs = "♣", spades = "♠" }
local RANK_FILE = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
local HANDS = {
    { id = "straight_flush", name = "Стрит-флеш", chips = 100, mult = 8 },
    { id = "four", name = "Каре", chips = 60, mult = 7 },
    { id = "full_house", name = "Фулл-хаус", chips = 40, mult = 4 },
    { id = "flush", name = "Флеш", chips = 35, mult = 4 },
    { id = "straight", name = "Стрит", chips = 30, mult = 4 },
    { id = "three", name = "Тройка", chips = 30, mult = 3 },
    { id = "two_pair", name = "Две пары", chips = 20, mult = 2 },
    { id = "pair", name = "Пара", chips = 10, mult = 2 },
    { id = "high", name = "Старшая карта", chips = 5, mult = 1 },
}
local CW, CH = 68, 100     -- a 34x50 pixel card drawn 2x
local HAND_Y = 400

local function cardChips(rank)
    if rank == 14 then return 11 end
    return math.min(10, rank)
end

-- the best poker hand in the played cards; returns the hand and the cards that score
local function evaluate(cards)
    local byRank, bySuit = {}, {}
    for _, c in ipairs(cards) do
        byRank[c.rank] = byRank[c.rank] or {}
        table.insert(byRank[c.rank], c)
        bySuit[c.suit] = (bySuit[c.suit] or 0) + 1
    end
    local groups = {}
    for rank, list in pairs(byRank) do table.insert(groups, { rank = rank, cards = list }) end
    table.sort(groups, function(a, b)
        if #a.cards ~= #b.cards then return #a.cards > #b.cards end
        return a.rank > b.rank
    end)
    local flush = #cards == 5 and next(bySuit) and bySuit[cards[1].suit] == 5
    local straight = false
    if #cards == 5 and #groups == 5 then
        local ranks = {}
        for _, c in ipairs(cards) do table.insert(ranks, c.rank) end
        table.sort(ranks)
        straight = ranks[5] - ranks[1] == 4 or (ranks[5] == 14 and ranks[1] == 2 and ranks[4] == 5)
    end
    local function hand(id) for _, h in ipairs(HANDS) do if h.id == id then return h end end end
    local function concat(...)
        local out = {}
        for _, g in ipairs({ ... }) do for _, c in ipairs(g.cards) do table.insert(out, c) end end
        return out
    end
    local pairsCount = 0
    for _, g in ipairs(groups) do if #g.cards >= 2 then pairsCount = pairsCount + 1 end end
    local ctx = { pairs = pairsCount, flush = flush, straight = straight }
    if straight and flush then return hand("straight_flush"), cards, ctx end
    if #groups[1].cards == 4 then return hand("four"), groups[1].cards, ctx end
    if #groups[1].cards == 3 and groups[2] and #groups[2].cards >= 2 then return hand("full_house"), cards, ctx end
    if flush then return hand("flush"), cards, ctx end
    if straight then return hand("straight"), cards, ctx end
    if #groups[1].cards == 3 then return hand("three"), groups[1].cards, ctx end
    if #groups[1].cards == 2 and groups[2] and #groups[2].cards == 2 then return hand("two_pair"), concat(groups[1], groups[2]), ctx end
    if #groups[1].cards == 2 then return hand("pair"), groups[1].cards, ctx end
    return hand("high"), { groups[1].cards[1] }, ctx
end

function Cards:setup()
    self.images = {}
    self.back = assets.image("assets/sprites/cards/back.png")
    self.blank = assets.image("assets/sprites/cards/empty.png")
    self.goal = self.def.goal or (300 + 150 * self.level)
    self.handsLeft = self.def.hands or 4
    self.discardsLeft = self.def.discards or 3
    self.handSize = self.def.handSize or 8
    self.deck = {}
    for _, suit in ipairs(SUITS) do
        for rank = 2, 14 do
            table.insert(self.deck, { suit = suit, rank = rank })
        end
    end
    for i = #self.deck, 2, -1 do
        local j = love.math.random(i)
        self.deck[i], self.deck[j] = self.deck[j], self.deck[i]
    end
    local all = G().jokers or {}
    local ids = self.def.jokers
    if ids == nil then
        local keys = {}
        for id in pairs(all) do table.insert(keys, id) end
        table.sort(keys)
        ids = {}
        for _ = 1, math.min(2, #keys) do
            table.insert(ids, table.remove(keys, love.math.random(#keys)))
        end
    end
    self.jokers = {}
    for _, id in ipairs(ids or {}) do
        if all[id] then table.insert(self.jokers, { id = id, def = all[id], wiggle = 0 }) end
    end
    self.hand = {}
    self.cursor = 1
    self.sortBy = "rank"
    self.state = "deal"
    self:dealCards()
end

function Cards:goalText()
    return "Набери " .. self.goal .. " очков за " .. self.handsLeft .. " хода"
end

function Cards:progress()
    return "Цель " .. self.goal .. "   Ходы " .. self.handsLeft .. "   Сбросы " .. self.discardsLeft
end

function Cards:results()
    return { self.bestHand and ("Лучшая комбинация: " .. self.bestHand) or "Ни одной комбинации" }
end

function Cards:imageOf(card)
    local key = card.suit .. "_" .. (RANK_FILE[card.rank] or string.format("%02d", card.rank))
    if not self.images[key] then
        self.images[key] = assets.image("assets/sprites/cards/" .. key .. ".png")
    end
    return self.images[key]
end

-- take cards from the deck until the hand is full
function Cards:dealCards()
    local delay = 0
    while #self.hand < self.handSize and #self.deck > 0 do
        local c = table.remove(self.deck)
        c.x, c.y, c.lift, c.t = screen.width + 60, HAND_Y, 0, -delay
        table.insert(self.hand, c)
        delay = delay + 0.06
    end
    self:sortHand()
    self.timer:after(delay + 0.2, function() if self.state == "deal" then self.state = "pick" end end)
    for i = 1, math.floor(delay / 0.06) do
        self.timer:after(i * 0.06, function() audio.play("card_deal") end)
    end
end

function Cards:sortHand()
    local order = { hearts = 1, diamonds = 2, clubs = 3, spades = 4 }
    table.sort(self.hand, function(a, b)
        if self.sortBy == "suit" and a.suit ~= b.suit then return order[a.suit] < order[b.suit] end
        if a.rank ~= b.rank then return a.rank > b.rank end
        return order[a.suit] < order[b.suit]
    end)
end

function Cards:selected()
    local list = {}
    for _, c in ipairs(self.hand) do if c.picked then table.insert(list, c) end end
    return list
end

function Cards:slotX(i, n)
    local gap = math.min(CW + 8, (screen.width - 160) / math.max(1, n))
    return screen.width / 2 + (i - (n + 1) / 2) * gap
end

function Cards:step(dt)
    for i, c in ipairs(self.hand) do
        c.t = (c.t or 0) + dt
        if c.t > 0 then
            local tx = self:slotX(i, #self.hand)
            local ty = HAND_Y - (c.picked and 30 or 0) - ((i == self.cursor and self.state == "pick") and 8 or 0)
            c.x = c.x + (tx - c.x) * math.min(1, dt * 14)
            c.y = c.y + (ty - c.y) * math.min(1, dt * 14)
        end
    end
    for _, j in ipairs(self.jokers) do j.wiggle = math.max(0, j.wiggle - dt * 3) end
    if self.state == "score" then
        return self:stepScore(dt)
    elseif self.state ~= "pick" then
        return
    end
    local n = #self.hand
    if n == 0 then return end
    if input.pressed("left", true) then self.cursor = (self.cursor - 2) % n + 1; audio.play("ui_move") end
    if input.pressed("right", true) then self.cursor = self.cursor % n + 1; audio.play("ui_move") end
    local m = input.mouse
    local over
    for i = n, 1, -1 do
        local c = self.hand[i]
        if math.abs(m.x - c.x) < CW / 2 and math.abs(m.y - c.y) < CH / 2 then over = i; break end
    end
    if over and m.moved then self.cursor = over end
    if input.pressed("select") or (over and m.pressed[1]) then
        local c = self.hand[self.cursor]
        if c.picked then
            c.picked = false
            audio.play("card_slide")
        elseif #self:selected() < 5 then
            c.picked = true
            audio.play("card_place")
        else
            audio.play("ui_error")
        end
    end
    if input.pressed("sort") then
        self.sortBy = self.sortBy == "rank" and "suit" or "rank"
        self:sortHand()
        audio.play("card_slide")
    end
    local picked = self:selected()
    if input.pressed("play") and #picked > 0 then
        self:playHand(picked)
    elseif input.pressed("discard") and #picked > 0 then
        if self.discardsLeft <= 0 then
            audio.play("ui_error")
            self:popup(screen.width / 2, HAND_Y - 110, "Сбросов не осталось", { 1, 0.5, 0.4 })
        else
            self.discardsLeft = self.discardsLeft - 1
            for i = #self.hand, 1, -1 do
                if self.hand[i].picked then table.remove(self.hand, i) end
            end
            self.cursor = 1
            audio.play("card_slide")
            self.state = "deal"
            self:dealCards()
        end
    end
end

function Cards:playHand(picked)
    local hand, scoring, info = evaluate(picked)
    self.handsLeft = self.handsLeft - 1
    for i = #self.hand, 1, -1 do
        if self.hand[i].picked then table.remove(self.hand, i) end
    end
    local ctx = { hand = hand.id, chips = hand.chips, mult = hand.mult, cards = scoring, pairs = info.pairs,
        flush = info.flush, straight = info.straight }
    -- the scoring is shown step by step: every card, then every joker
    local steps = {}
    for _, c in ipairs(scoring) do
        table.insert(steps, { card = c, chips = cardChips(c.rank) })
    end
    for _, j in ipairs(self.jokers) do
        if j.def.card then
            for _, c in ipairs(scoring) do
                table.insert(steps, { joker = j, card = c, fn = function() j.def.card(ctx, c) end })
            end
        end
        if j.def.hand then
            table.insert(steps, { joker = j, fn = function() j.def.hand(ctx) end })
        end
    end
    for i, c in ipairs(picked) do
        c.playX = screen.width / 2 + (i - (#picked + 1) / 2) * (CW + 12)
        c.scoring = false
        for _, s in ipairs(scoring) do if s == c then c.scoring = true end end
    end
    self.play = { hand = hand, cards = picked, ctx = ctx, steps = steps, i = 0, t = -0.5 }
    self.state = "score"
    if not self.bestHandRank or self:handRank(hand) < self.bestHandRank then
        self.bestHandRank, self.bestHand = self:handRank(hand), hand.name
    end
    audio.play("card_place")
end

function Cards:handRank(hand)
    for i, h in ipairs(HANDS) do if h == hand then return i end end
    return #HANDS
end

function Cards:stepScore(dt)
    local p = self.play
    p.t = p.t + dt
    for _, c in ipairs(p.cards) do
        c.x = c.x + (c.playX - c.x) * math.min(1, dt * 10)
        c.y = c.y + (230 - c.y) * math.min(1, dt * 10)
    end
    if p.t < 0.32 then return end
    p.t = 0
    p.i = p.i + 1
    local s = p.steps[p.i]
    if s then
        local ctx = p.ctx
        local chips, mult = ctx.chips, ctx.mult
        if s.chips then
            ctx.chips = ctx.chips + s.chips
            s.card.bump = 1
        end
        if s.fn then s.fn() end
        local dc, dm = ctx.chips - chips, ctx.mult - mult
        local x, y = s.card and s.card.x or screen.width / 2, s.card and (s.card.y - 80) or 110
        if s.joker then
            if dc == 0 and math.abs(dm) < 1e-9 then return self:stepScore(0.4) end -- nothing happened: next
            s.joker.wiggle = 1
            x, y = s.joker.x or x, 150
        end
        if dc ~= 0 then self:popup(x, y, "+" .. dc, { 0.4, 0.7, 1 }) end
        if math.abs(dm) > 1e-9 then
            local text = (ctx.mult / math.max(mult, 1e-9) >= 1.99 and dm > 0 and mult > 1) and ("x" .. math.floor(ctx.mult / mult + 0.5))
                or ((dm > 0 and "+" or "") .. dm)
            self:popup(x, y - 20, text .. " множ.", { 1, 0.4, 0.35 })
        end
        audio.play("chips", { pitch = 1 + p.i * 0.05 })
        return
    end
    -- the total
    if not p.total then
        p.total = math.floor(p.ctx.chips * p.ctx.mult)
        self:addScore(p.total, screen.width / 2, 170, { 1, 0.85, 0.3 })
        audio.play(p.total >= 100 and "fanfare" or "coin")
        if p.total >= self.goal * 0.5 then self:shake(5, 0.3) end
        p.t = -0.5
        return
    end
    -- done: next hand or the end
    self.play = nil
    if self.score >= self.goal then return self:win() end
    if self.handsLeft <= 0 then return self:lose() end
    self.cursor = 1
    self.state = "deal"
    self:dealCards()
end

function Cards:drawPlayingCard(c, alpha)
    local lg = love.graphics
    local bump = c.bump or 0
    if bump > 0 then c.bump = math.max(0, bump - love.timer.getDelta() * 3) end
    local s = 2 * (1 + bump * 0.15)
    lg.setColor(0, 0, 0, 0.35)
    lg.rectangle("fill", c.x - CW / 2 + 5, c.y - CH / 2 + 7, CW, CH, 4)
    lg.setColor(1, 1, 1, alpha or 1)
    lg.draw(self:imageOf(c), c.x, c.y, math.sin((c.t or 0) * 2 + c.rank) * 0.015, s, s, 32, 32)
end

function Cards:drawGame()
    local lg = love.graphics
    -- the table: green felt with a wooden edge
    lg.setColor(0.13, 0.32, 0.2, 1)
    lg.rectangle("fill", 20, 40, screen.width - 40, screen.height - 60, 30)
    lg.setColor(0.35, 0.2, 0.1, 1)
    lg.setLineWidth(10)
    lg.rectangle("line", 20, 40, screen.width - 40, screen.height - 60, 30)
    lg.setColor(1, 1, 1, 0.05)
    lg.circle("fill", screen.width / 2, 260, 200)
    -- jokers on top
    local jn = #self.jokers
    for i, j in ipairs(self.jokers) do
        j.x = screen.width / 2 + (i - (jn + 1) / 2) * 200
        local y = 112
        local rot = math.sin(j.wiggle * 20) * 0.12 * j.wiggle
        lg.setColor(1, 1, 1, 1)
        -- a joker: a blank pixel card with its picture, the name and the rule next to it
        lg.draw(self.blank, j.x - 60, y, rot, 2, 2, 32, 32)
        local icon = assets.image("assets/sprites/icons/" .. (j.def.icon or "clover") .. ".png")
        lg.draw(icon, j.x - 60, y, rot, 1, 1, 17, 17)
        ui.print(j.def.name, j.x - 20, y - 30, { font = "small", color = "accent" })
        local font = ui.font("small")
        local _, lines = font:getWrap(j.def.text, 116)
        for li, line in ipairs(lines) do
            ui.print(line, j.x - 20, y - 6 + (li - 1) * (font:getHeight() + 2), { font = "small", color = "light" })
        end
    end
    -- the deck
    for k = 0, math.min(4, #self.deck - 1) do
        lg.setColor(1, 1, 1, 1)
        lg.draw(self.back, 850 - k * 2, 250 - k * 2, 0, 2, 2, 32, 32)
    end
    ui.print(#self.deck, 850, 300, { font = "small", align = "center", color = "light" })
    -- the hand being scored
    local p = self.play
    if p then
        ui.print(p.hand.name, screen.width / 2, 300, { font = "body", align = "center", color = "accent" })
        local ctx = p.ctx
        local text = math.floor(ctx.chips) .. "  x  " .. (math.floor(ctx.mult * 10 + 0.5) / 10)
        ui.print(text, screen.width / 2, 336, { font = "pixel", align = "center", color = "light" })
        for _, c in ipairs(p.cards) do self:drawPlayingCard(c, c.scoring and 1 or 0.45) end
    elseif self.state == "pick" then
        local picked = self:selected()
        if #picked > 0 then
            local hand = evaluate(picked)
            ui.print(hand.name .. ":  " .. hand.chips .. " x " .. hand.mult, screen.width / 2, 300,
                { font = "small", align = "center", color = "accent" })
        end
    end
    for _, c in ipairs(self.hand) do
        if (c.t or 0) > 0 then self:drawPlayingCard(c) end
    end
    -- the cursor
    local c = self.hand[self.cursor]
    if c and self.state == "pick" then
        lg.setColor(1, 0.9, 0.4, 0.6 + 0.4 * math.sin(self.time * 8))
        lg.setLineWidth(3)
        lg.rectangle("line", c.x - CW / 2 - 4, c.y - CH / 2 - 4, CW + 8, CH + 8, 8)
    end
    -- the score so far against the goal
    ui.bar(screen.width / 2 - 150, 498, 300, 10, self.score, self.goal, "gold")
    lg.setColor(1, 1, 1, 1)
end

return Cards
