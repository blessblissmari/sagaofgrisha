-- Base of the arcade mini-games: a title card, the game, the pause, the result card
-- and the high score table. Every mini-game is a stage kind (game/modes/<kind>.lua):
--
--   game.stage "pier" { kind = "fishing", goal = 3, time = 90, prize = { coin = 5 } }
--   local r = s:play("snake", { goal = 15 })      -- r.win, r.score (+ fields of the game)
--
-- Fields of every mini-game stage (each game adds its own, see the top of its file):
--   goal        what to reach to win (points, bricks, fish... see the game)
--   time        time limit in seconds (nil = none)
--   lives       tries (hearts)
--   level       difficulty: 1 easy .. 5 hard (default 2)
--   record      name in the high score table (default: the stage name)
--   intro       false = no title card, the game starts at once
--   background  name from game/data/backgrounds.lua behind the game
--   music       default "arcade"; false = silence
--   prize       { coin = 5 } items given for a win (shown on the result card)
--   title, rules  change the text of the title card
--
-- A new mini-game: local MyGame = class(Arcade) with
--   MyGame.info = { title = "...", rules = "...", keys = { { "fire", "огонь" } } }
--   setup()  onStart()  step(dt)  drawGame()  and optionally progress() -> text for the HUD,
--   goalText() -> text for the title card, results() -> extra lines for the result card.
-- Inside: self:addScore(n, x, y), self:popup(x, y, text), self:banner(text),
--   self:shake(), self:flash(), self:loseLife() -> true when no lives left,
--   self:win(), self:lose().

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local Background = engine.Background or require("engine.background")
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Mode = require("game.modes.base")

local function G()
    return require("game")
end

local Arcade = class(Mode)
Arcade.keymap = "arcade"
Arcade.info = { title = "Мини-игра", rules = "", keys = {} }
Arcade.defaultLives = 3

function Arcade:init(def)
    Mode.init(self, def)
    self.level = def.level or 2
    self.goal = def.goal or self.info.goal
    self.maxLives = def.lives or self.defaultLives
    self.lives = self.maxLives
    self.timeLimit = def.time or self.info.time
    self.timeLeft = self.timeLimit
    self.score = 0
    self.recordName = def.record or def.name or def.kind
    self.phase = def.intro == false and "play" or "title"
    self.fx.font = ui.font("pixel")
    self.flashT, self.flashColor = 0, { 1, 1, 1 }
    self.banners = {}
    local bg = def.background or self.info.background
    if bg then
        local bdef = type(bg) == "table" and bg or G().backgrounds[bg]
        self.background = bdef and Background(bdef)
    end
    self:setup()
end

function Arcade:setup() end
function Arcade:onStart() end
function Arcade:step(dt) end
function Arcade:drawGame() end
function Arcade:progress() return nil end
function Arcade:results() return {} end

function Arcade:goalText()
    if self.goal then
        return "Цель: " .. self.goal .. " очков"
    end
    return "Набери как можно больше очков"
end

function Arcade:enter()
    local m = self.def.music
    if m == nil then
        m = self.info.music or "arcade"
    end
    if m then
        audio.music(m)
    else
        audio.stopMusic(0.5)
    end
    audio.play("lag")
end

-- helpers for the games -------------------------------------------------------------

function Arcade:addScore(n, x, y, color)
    self.score = math.max(0, self.score + n)
    if x then
        self:popup(x, y, (n >= 0 and "+" or "") .. n, color or { 1, 0.9, 0.4 })
    end
end

function Arcade:popup(x, y, text, color, opts)
    opts = opts or {}
    opts.color = color or opts.color or { 1, 1, 1 }
    self.fx:popup(x, y, text, opts)
end

function Arcade:banner(text, color, time)
    table.insert(self.banners, { text = text, color = color or "gold", t = 0, life = time or 1.3 })
end

function Arcade:shake(power, duration)
    self.shakeTime, self.shakePower = duration or 0.25, power or 5
end

function Arcade:flash(color, time)
    self.flashColor = color or { 1, 1, 1 }
    self.flashT, self.flashMax = time or 0.25, time or 0.25
end

function Arcade:burst(x, y, color, count, speed)
    self.fx:burst(x, y, { color = color, count = count or 12, speed = speed or 140, life = 0.6, size = 3, drag = 3 })
end

-- one life less; true when there are none left (the game is lost then)
function Arcade:loseLife()
    self.lives = self.lives - 1
    self:shake(7, 0.35)
    self:flash({ 1, 0.2, 0.2 }, 0.3)
    if self.lives <= 0 then
        self:lose()
        return true
    end
    audio.play("hurt")
    return false
end

function Arcade:win() self:gameOver(true) end
function Arcade:lose() self:gameOver(false) end

-- the time is over: a win if the goal is reached (or there is no goal)
function Arcade:timeUp()
    self:gameOver(self.goal == nil or self.score >= self.goal)
end

function Arcade:gameOver(win)
    if self.phase == "over" then
        return
    end
    self.phase = "over"
    self.won = win
    self.overTime = 0
    self.newRecord = G().record(self.recordName, self.score)
    if win then
        audio.play("fanfare")
        local prize = self.def.prize
        if prize then
            local inv = G().state and G().state.inventory
            for item, n in pairs(prize) do
                if inv then inv:add(item, n) end
            end
        end
    else
        audio.stopMusic(1)
        audio.play("longsad")
    end
    if self.newRecord and self.score > 0 then
        self.timer:after(1.2, function() audio.play("cool") end)
    end
end

-- 0 right on the beat of the music .. 1 just before the next one, and the beat number
function Arcade:beat()
    local info = audio.musicInfo()
    local bpm = info.bpm or 120
    local t = audio.musicTime() - (info.beatOffset or 0)
    local beats = t * bpm / 60
    return beats - math.floor(beats), math.floor(beats)
end

function Arcade:result()
    local r = { win = self.won, score = self.score }
    for k, v in pairs(self.extraResult or {}) do r[k] = v end
    return r
end

-- callbacks ---------------------------------------------------------------------------

function Arcade:update(dt)
    Mode.update(self, dt)
    if self.flashT > 0 then
        self.flashT = math.max(0, self.flashT - dt)
    end
    for i = #self.banners, 1, -1 do
        local b = self.banners[i]
        b.t = b.t + dt
        if b.t > b.life then table.remove(self.banners, i) end
    end
    if self.background then
        self.background:update(dt)
    end
    if self:pausePressed() and self.phase ~= "over" then
        input.consume("pause")
        self:openPause(self:pauseItems())
        return
    end
    if self.phase == "title" then
        if input.pressed("confirm") then
            input.consume("confirm")
            audio.play("ui_select")
            self.phase = "play"
            self.playTime = 0
        end
        return
    elseif self.phase == "over" then
        self.overTime = self.overTime + dt
        if self.overTime > 1.2 and input.pressed("confirm") then
            input.consume("confirm")
            self:finish(self:result())
        end
        self:idle(dt)
        return
    end
    if not self.begun then
        self.begun = true
        self:onStart()
    end
    self.playTime = (self.playTime or 0) + dt
    if self.timeLeft then
        self.timeLeft = self.timeLeft - dt
        if self.timeLeft <= 0 then
            self.timeLeft = 0
            self:timeUp()
            return
        end
    end
    self:step(dt)
end

-- animations that go on behind the result card
function Arcade:idle(dt) end

-- extra items of the pause menu
function Arcade:pauseItems()
    return { { label = "Сдаться", action = function()
        engine.scene.pop()
        self:lose()
    end } }
end

local function fmtTime(t)
    t = math.max(0, math.ceil(t))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

function Arcade:drawHud()
    if self.info.hud == false then return end
    local y = 10
    ui.print(self.score, 20, y, { font = "pixel", color = "gold", outline = { 0, 0, 0, 0.8 } })
    local p = self:progress()
    if p then
        ui.print(p, screen.width / 2, y, { font = "pixel", align = "center", color = "light", outline = { 0, 0, 0, 0.8 } })
    end
    local right = screen.width - 20
    if self.timeLeft then
        local low = self.timeLeft < 10
        ui.print(fmtTime(self.timeLeft), right, y, { font = "pixel", align = "right",
            color = low and (math.floor(self.time * 4) % 2 == 0 and "red" or "light") or "light", outline = { 0, 0, 0, 0.8 } })
        right = right - 110
    end
    if self.maxLives and self.maxLives > 0 and self.info.lives ~= false then
        ui.hearts(right - self.maxLives * 38 * 0.6, y - 4, self.lives * 2, self.maxLives * 2, 0.6)
    end
end

function Arcade:keysLine()
    local parts = {}
    for _, k in ipairs(self.info.keys or {}) do
        local name = k[3] or ("[" .. input.keyNames(k[1], 1) .. "]")
        table.insert(parts, name .. " " .. k[2])
    end
    return table.concat(parts, "    ")
end

function Arcade:drawCard(w, h)
    local x, y = math.floor((screen.width - w) / 2), math.floor((screen.height - h) / 2)
    ui.panel.draw(x, y, w, h)
    return x, y
end

function Arcade:drawTitle()
    ui.dim(0.45)
    local w = 600
    local font = ui.font("small")
    local rules = self.def.rules or self.info.rules
    local _, lines = font:getWrap(rules or "", w - 60)
    local keys = self:keysLine()
    local _, keyLines = font:getWrap(keys, w - 60)
    local rec = G().records[self.recordName]
    rec = rec and rec > 0 and rec
    -- title, rules, goal, record, keys, "start": the card grows with the text
    local h = math.max(290, 88 + #lines * 24 + 26 + (rec and 26 or 0) + 16 + #keyLines * 24 + 58)
    local x, y = self:drawCard(w, h)
    local cx = screen.width / 2
    ui.print(self.def.title or self.info.title, cx, y + 26, { font = "title", align = "center", color = "accent" })
    for i, line in ipairs(lines) do
        ui.print(line, cx, y + 80 + (i - 1) * 24, { font = "small", align = "center", color = "ink" })
    end
    local gy = y + 88 + #lines * 24
    ui.print(self:goalText(), cx, gy, { font = "small", align = "center", color = "gold" })
    if rec then
        ui.print("Рекорд: " .. rec, cx, gy + 26, { font = "small", align = "center", color = "blue" })
    end
    local ky = math.max(gy + (rec and 52 or 26) + 16, y + h - 58 - #keyLines * 24)
    for i, line in ipairs(keyLines) do
        ui.print(line, cx, ky + (i - 1) * 24, { font = "small", align = "center", color = "faded" })
    end
    local blink = math.floor(self.time * 2) % 2 == 0
    ui.print("[" .. input.keyName("confirm") .. "] начать", cx, y + h - 42,
        { font = "pixel", align = "center", color = "light", alpha = blink and 1 or 0.45 })
end

function Arcade:drawOver()
    local a = math.min(1, self.overTime * 3)
    ui.dim(0.5 * a)
    local lines = self:results()
    local prize = self.won and self.def.prize
    local record = self.newRecord and self.score > 0
    local w = 480
    local h = 176 + #lines * 26 + (record and 30 or 0) + (prize and 44 or 0)
    local x, y = self:drawCard(w, h)
    local cx = screen.width / 2
    ui.print(self.won and "ПОБЕДА!" or "НЕ ВЫШЛО", cx, y + 24, { font = "title", align = "center",
        color = self.won and "gold" or "red" })
    local ly = y + 78
    for _, line in ipairs(lines) do
        ui.print(line, cx, ly, { font = "small", align = "center", color = "ink" })
        ly = ly + 26
    end
    ui.print("Очки: " .. self.score, cx, ly + 2, { font = "body", align = "center", color = "light" })
    ly = ly + 42
    if record then
        ui.print("НОВЫЙ РЕКОРД!", cx, ly, { font = "pixel", align = "center",
            color = math.floor(self.overTime * 5) % 2 == 0 and "gold" or "accent" })
        ly = ly + 30
    end
    if prize then
        local items = G().items
        local parts = {}
        for item, n in pairs(prize) do
            local info = items[item]
            table.insert(parts, { icon = info and info.icon or item, text = "+" .. n .. " " .. (info and info.name or item) })
        end
        local px = cx - #parts * 70
        for _, p in ipairs(parts) do
            ui.icon(p.icon, px, ly - 4, 0.75)
            ui.print(p.text, px + 28, ly, { font = "small", color = "green" })
            px = px + 140
        end
    end
    if self.overTime > 1.2 then
        ui.print("[" .. input.keyName("confirm") .. "] дальше", cx, y + h - 36, { font = "pixel", align = "center",
            color = "light", alpha = math.floor(self.time * 2) % 2 == 0 and 1 or 0.5 })
    end
end

function Arcade:draw()
    local lg = love.graphics
    lg.clear(0, 0, 0, 1)
    if self.background then
        self.background:draw(0, 0)
        if self.info.dim ~= 0 then
            lg.setColor(0, 0, 0.04, self.info.dim or 0.45)
            lg.rectangle("fill", 0, 0, screen.width, screen.height)
        end
    end
    local ox, oy = self:shakeOffset(love.timer.getDelta())
    lg.push()
    lg.translate(math.floor(ox), math.floor(oy))
    lg.setColor(1, 1, 1, 1)
    self:drawGame()
    self.fx:draw()
    lg.pop()
    lg.setColor(1, 1, 1, 1)
    if self.flashT > 0 then
        local c = self.flashColor
        lg.setColor(c[1], c[2], c[3], 0.5 * self.flashT / self.flashMax)
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
        lg.setColor(1, 1, 1, 1)
    end
    for _, b in ipairs(self.banners) do
        local k = math.min(1, b.t * 6)
        local a = math.min(1, (b.life - b.t) * 4)
        lg.push()
        lg.translate(screen.width / 2, screen.height / 2 - 40)
        lg.scale(0.6 + 0.4 * k)
        ui.print(b.text, 0, -16, { font = "title", align = "center", color = b.color, alpha = a, outline = { 0, 0, 0, a } })
        lg.pop()
    end
    if self.phase ~= "title" then
        self:drawHud()
    end
    if self.phase == "title" then
        self:drawTitle()
    elseif self.phase == "over" then
        self:drawOver()
    elseif self.playTime and self.playTime < 6 and self.info.keys and #self.info.keys > 0 and self.info.keysHint ~= false then
        ui.print(self:keysLine(), screen.width / 2, screen.height - 24, { font = "small", align = "center",
            color = "light", alpha = 0.75 * math.min(1, 6 - self.playTime) })
    end
end

-- quads of a sheet: grid(image, w, h) -> q[row][col] (1-based)
function Arcade.grid(image, w, h, ox, oy, gap)
    local q = {}
    ox, oy, gap = ox or 0, oy or 0, gap or 0
    local cols = math.floor((image:getWidth() - ox + gap) / (w + gap))
    local rows = math.floor((image:getHeight() - oy + gap) / (h + gap))
    for r = 1, rows do
        q[r] = {}
        for c = 1, cols do
            q[r][c] = assets.quad(image, ox + (c - 1) * (w + gap), oy + (r - 1) * (h + gap), w, h)
        end
    end
    return q
end

return Arcade
