-- Memory (pairs): flip two cards, keep them if the pictures match.
-- Cards: "Asset Pack Pixel Poker" by Chasersgaming (CC0), pictures: item icons ("496 pixel art icons", CC0).
--
--   game.stage "tavern_pairs" { kind = "memory", pairs = 8, mistakes = 6 }
--   local r = s:play("memory", { pairs = 6, time = 60 })       -- r.win, r.score, r.mistakes
--
--   pairs      how many pairs (2..12, default 4 + 2 x level)
--   mistakes   wrong tries allowed (default pairs + 2; false = no limit)
--   icons      your own pictures: { "carrot", "coin", ... } (names from assets/sprites/icons)
--   peek       seconds to see all the cards at the start (default 1.5, 0 = none)

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Memory = class(Arcade)
Memory.keymap = "puzzle"
Memory.info = {
    title = "Парочки",
    rules = "Открывай по две карты. Одинаковые картинки остаются открытыми. Найди все пары и не ошибайся слишком часто.",
    keys = { { "up", "выбор", "[←↑→↓]" }, { "select", "открыть" } },
    background = "forest",
    dim = 0.55,
}
Memory.defaultLives = 0

local ICONS = { "carrot", "coin", "sword", "potion", "mushroom", "clover", "key", "fish", "ring", "book", "hat",
    "boots", "axe", "bread", "torch", "map", "helmet", "letter" }
local CW, CH = 34, 50       -- the pixel card inside its 64x64 picture

function Memory:setup()
    self.back = assets.image("assets/sprites/cards/back.png")
    self.face = assets.image("assets/sprites/cards/empty.png")
    local pairsCount = math.max(2, math.min(12, self.def.pairs or (4 + 2 * self.level)))
    local icons = {}
    for i, name in ipairs(self.def.icons or ICONS) do icons[i] = name end
    for i = #icons, 2, -1 do
        local j = love.math.random(i)
        icons[i], icons[j] = icons[j], icons[i]
    end
    local deck = {}
    for i = 1, pairsCount do
        local icon = icons[(i - 1) % #icons + 1]
        deck[#deck + 1] = icon
        deck[#deck + 1] = icon
    end
    for i = #deck, 2, -1 do
        local j = love.math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    local n = #deck
    -- the biggest cards that fit, full rows if possible
    local best
    for _, scale in ipairs({ 3, 2, 1.5, 1 }) do      -- whole pixels first
        for cols = math.min(n, 10), 2, -1 do
            local rows = math.ceil(n / cols)
            local w, h = cols * (CW * scale + 14), rows * (CH * scale + 12)
            if w <= 900 and h <= 450 then
                local score = scale * 10 - (n % cols == 0 and 0 or 3) - math.abs(cols - rows * 1.8) * 0.3
                if not best or score > best.score then best = { score = score, cols = cols, rows = rows, scale = scale } end
            end
        end
    end
    self.cols, self.rows, self.scale = best.cols, best.rows, best.scale
    local gw, gh = CW * self.scale + 14, CH * self.scale + 12
    self.ox = math.floor((screen.width - self.cols * gw) / 2) + gw / 2
    self.oy = math.floor(64 + (screen.height - 80 - self.rows * gh) / 2) + gh / 2
    self.cards = {}
    for i, icon in ipairs(deck) do
        local c, r = (i - 1) % self.cols, math.floor((i - 1) / self.cols)
        self.cards[i] = { icon = icon, x = self.ox + c * gw, y = self.oy + r * gh, open = false, flip = 0,
            found = false, deal = -i * 0.04 }
    end
    self.pairsCount = pairsCount
    self.found = 0
    self.mistakes = 0
    local m = self.def.mistakes
    if m == nil then m = pairsCount + 2 end
    self.maxMistakes = m
    self.peek = self.def.peek or 1.5
    self.cursor = 1
    self.streak = 0
    self.picked = {}
end

function Memory:goalText()
    local t = "Найди " .. self.pairsCount .. " пар"
    if self.maxMistakes then t = t .. ", ошибок можно: " .. self.maxMistakes end
    return t
end

function Memory:progress()
    local t = "Пары " .. self.found .. "/" .. self.pairsCount
    if self.maxMistakes then t = t .. "    Ошибки " .. self.mistakes .. "/" .. self.maxMistakes end
    return t
end

function Memory:results()
    self.extraResult = { mistakes = self.mistakes }
    return { "Пар найдено: " .. self.found .. " из " .. self.pairsCount, "Ошибок: " .. self.mistakes }
end

function Memory:onStart()
    if self.peek > 0 then
        for _, c in ipairs(self.cards) do c.open = true end
        self.peekT = self.peek + 0.6
    end
end

function Memory:cardAt(x, y)
    for i, c in ipairs(self.cards) do
        if math.abs(x - c.x) < CW * self.scale / 2 and math.abs(y - c.y) < CH * self.scale / 2 then return i end
    end
end

function Memory:pick(i)
    local c = self.cards[i]
    if not c or c.open or c.found or #self.picked >= 2 then return end
    c.open = true
    audio.play("card_flip")
    table.insert(self.picked, i)
    if #self.picked == 2 then
        local a, b = self.cards[self.picked[1]], self.cards[self.picked[2]]
        if a.icon == b.icon then
            self.timer:after(0.35, function()
                a.found, b.found = true, true
                a.glow, b.glow = 1, 1
                self.found = self.found + 1
                self.streak = self.streak + 1
                local pts = 100 * self.streak
                self:addScore(pts, (a.x + b.x) / 2, (a.y + b.y) / 2 - 40)
                self:burst(a.x, a.y, { 1, 0.9, 0.4 }, 10, 120)
                self:burst(b.x, b.y, { 1, 0.9, 0.4 }, 10, 120)
                audio.play("coin", { pitch = 1 + self.streak * 0.08 })
                if self.streak >= 3 then self:banner(self.streak .. " ПОДРЯД!") end
                self.picked = {}
                if self.found >= self.pairsCount then
                    self.timer:after(0.5, function() self:win() end)
                end
            end)
        else
            self.timer:after(0.8, function()
                a.open, b.open = false, false
                a.shake, b.shake = 0.3, 0.3
                self.picked = {}
                self.streak = 0
                self.mistakes = self.mistakes + 1
                audio.play("ui_error")
                if self.maxMistakes and self.mistakes >= self.maxMistakes then
                    self:shake(6, 0.3)
                    self:lose()
                end
            end)
        end
    end
end

function Memory:step(dt)
    for _, c in ipairs(self.cards) do
        local target = c.open and 1 or 0
        c.flip = c.flip + (target - c.flip) * math.min(1, dt * 12)
        c.deal = c.deal + dt
        if c.glow then c.glow = math.max(0, c.glow - dt) end
        if c.shake then c.shake = c.shake - dt; if c.shake <= 0 then c.shake = nil end end
    end
    if self.peekT then
        self.peekT = self.peekT - dt
        if self.peekT <= 0 then
            self.peekT = nil
            for _, c in ipairs(self.cards) do c.open = false end
            audio.play("card_slide")
        end
        return
    end
    local n = #self.cards
    if input.pressed("left", true) then self.cursor = (self.cursor - 2) % n + 1; audio.play("ui_move") end
    if input.pressed("right", true) then self.cursor = self.cursor % n + 1; audio.play("ui_move") end
    if input.pressed("up", true) then self.cursor = (self.cursor - 1 - self.cols) % n + 1; audio.play("ui_move") end
    if input.pressed("down", true) then self.cursor = (self.cursor - 1 + self.cols) % n + 1; audio.play("ui_move") end
    if input.pressed("select") then self:pick(self.cursor) end
    local m = input.mouse
    local over = self:cardAt(m.x, m.y)
    if over and m.moved then self.cursor = over end
    if over and m.pressed[1] then self:pick(over) end
end

function Memory:drawGame()
    local lg = love.graphics
    local SCALE = self.scale
    for i, c in ipairs(self.cards) do
        if c.deal > 0 then
            local k = math.min(1, c.deal * 4)
            local x = c.x + (1 - k) * (screen.width / 2 - c.x)
            local y = c.y + (1 - k) * (screen.height + 80 - c.y)
            if c.shake then x = x + math.sin(c.shake * 60) * 4 end
            local f = c.flip
            local sx = math.abs(math.cos(f * math.pi)) * SCALE
            local showFace = f > 0.5
            local lift = (i == self.cursor and self.phase == "play") and -6 or 0
            lg.setColor(0, 0, 0, 0.3)
            lg.rectangle("fill", x - CW * sx / 2 + 4, y - CH * SCALE / 2 + 6, CW * sx, CH * SCALE, 4)
            lg.setColor(1, 1, 1, c.found and 0.85 or 1)
            lg.draw(showFace and self.face or self.back, x, y + lift, 0, sx, SCALE, 32, 32)
            if showFace then
                lg.setColor(1, 1, 1, 1)
                local img = assets.image("assets/sprites/icons/" .. c.icon .. ".png")
                local k = SCALE >= 3 and 2 or (SCALE >= 2 and 1.5 or 1)
                lg.draw(img, x, y + lift, 0, sx / SCALE * k, k, 17, 17)
            end
            if c.glow and c.glow > 0 then
                lg.setBlendMode("add")
                lg.setColor(1, 0.9, 0.5, c.glow * 0.6)
                lg.draw(self.face, x, y + lift, 0, sx, SCALE, 32, 32)
                lg.setBlendMode("alpha")
            end
            if i == self.cursor and self.phase == "play" and not self.peekT then
                lg.setColor(1, 0.9, 0.4, 0.7 + 0.3 * math.sin(self.time * 8))
                lg.setLineWidth(3)
                lg.rectangle("line", x - CW * SCALE / 2 - 4, y - CH * SCALE / 2 - 4 + lift, CW * SCALE + 8, CH * SCALE + 8, 6)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

return Memory
