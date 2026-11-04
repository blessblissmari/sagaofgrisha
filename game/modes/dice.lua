-- Dice like in Kingdom Come: Deliverance (Farkle). Throw six dice, put aside the ones that score,
-- then throw the rest again or write the points down. A throw without points burns the turn.
-- Dice: "32x32 pixel d6 dice roll & results" by adhochero (CC0); the faces of the players:
-- "RPG portraits" by Buch (CC0).
--
--   game.stage "tavern_dice" { kind = "dice", goal = 2000, opponent = "monk", prize = { coin = 10 } }
--   local r = s:play("dice", { goal = 1500, opponent = "old" })    -- r.win, r.score, r.enemyScore
--
--   goal      points to win (default 1500 + 500 x level)
--   opponent  "monk", "old", "noble" or your own { name = "...", portrait = "path" or { image, x, y, w, h },
--             risk = 0..1 }
-- Points: 1 = 100, 5 = 50, three of a kind = face x 100 (three 1s = 1000), every extra die of the
-- kind doubles it; 1-2-3-4-5 = 500, 2-3-4-5-6 = 750, 1..6 = 1500.
-- Keys: [←][→] choose, [Space] take a die, [Enter] throw again, [X] write the points down.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Dice = class(Arcade)
Dice.keymap = "dice"
Dice.info = {
    title = "Кости",
    rules = "Брось шесть костей, отложи те, что дают очки, и бросай остальные — или запиши очки. "
        .. "Бросок без очков сгорает вместе со всем ходом. 1 = 100, 5 = 50, три одинаковых = номинал x100.",
    keys = { { "left", "выбор", "[←][→]" }, { "pick", "отложить" }, { "roll", "бросить" }, { "bank", "записать" } },
    background = "black",
    dim = 0,
    music = "calm",
    lives = false,
}
Dice.defaultLives = 0

local PORTRAITS = "assets/sprites/portraits/rpg_portraits.png"   -- 9 x 3 faces of 32x32
local function face(col, row) return { image = PORTRAITS, x = 4 + col * 36, y = 4 + row * 36, w = 32, h = 32 } end

local OPPONENTS = {
    monk = { name = "Брат Фома", portrait = face(4, 1), risk = 0.3,
        bust = { "Господь испытывает...", "Пусто. Бывает." }, big = { "Благодать!", "Вот это бросок." },
        win = { "Помолюсь за тебя." }, lose = { "Ты везучий, отрок." } },
    old = { name = "Дед Архип", portrait = face(2, 0), risk = 0.15,
        bust = { "Эх, старые руки...", "Тьфу ты!" }, big = { "Хе-хе, учись!", "Вот так-то." },
        win = { "Молод ещё со мной тягаться." }, lose = { "Ну уважил старика." } },
    noble = { name = "Пан Казимир", portrait = face(8, 0), risk = 0.6,
        bust = { "Кости кривые!", "Это случайность." }, big = { "Ха! Видал?", "Учись у пана." },
        win = { "Деньги на стол, холоп." }, lose = { "Ты жульничал!" } },
}

local DIE = 64
local TRAY = { x = 250, y = 150, w = 460, h = 250 }

-- the best score of a set of dice; ok = every die gives points
local function scoreOf(vals)
    local c = { 0, 0, 0, 0, 0, 0 }
    for _, v in ipairs(vals) do c[v] = c[v] + 1 end
    local n = #vals
    if n == 0 then return 0, false end
    local function plain(cc)
        local s, unused = 0, 0
        for f = 1, 6 do
            local k = cc[f]
            if k >= 3 then
                s = s + (f == 1 and 1000 or f * 100) * 2 ^ (k - 3)
            elseif f == 1 then s = s + 100 * k
            elseif f == 5 then s = s + 50 * k
            else unused = unused + k end
        end
        return s, unused == 0
    end
    local best, bestOk = plain(c)
    local function try(from, to, pts)
        local cc = { c[1], c[2], c[3], c[4], c[5], c[6] }
        for f = from, to do
            if cc[f] < 1 then return end
            cc[f] = cc[f] - 1
        end
        local s, ok = plain(cc)
        local rest = 0
        for f = 1, 6 do rest = rest + cc[f] end
        if rest == 0 then s, ok = 0, true end
        s = s + pts
        if (ok and not bestOk) or (ok == bestOk and s > best) then best, bestOk = s, ok end
    end
    try(1, 6, 1500)
    try(1, 5, 500)
    try(2, 6, 750)
    return best, bestOk
end

-- the best choice of dice from a throw: score, list of indexes
local function bestPick(vals)
    local n = #vals
    local best, bestSet = 0, nil
    for mask = 1, 2 ^ n - 1 do
        local set, sv = {}, {}
        for i = 1, n do
            if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then
                table.insert(set, i)
                table.insert(sv, vals[i])
            end
        end
        local s, ok = scoreOf(sv)
        if ok and (s > best or (s == best and bestSet and #set < #bestSet)) then best, bestSet = s, set end
    end
    return best, bestSet
end

function Dice:setup()
    -- the faces: a straight and a turned picture of every face; 10 frames of a tumbling die
    self.sheet = assets.image("assets/sprites/arcade/dice_faces.png")
    self.rollSheet = assets.image("assets/sprites/arcade/dice_roll.png")
    self.faces = { straight = {}, turned = {} }
    for f = 1, 6 do
        self.faces.turned[f] = assets.quad(self.sheet, 0, (f - 1) * 32, 32, 32)
        self.faces.straight[f] = assets.quad(self.sheet, 32, (f - 1) * 32, 32, 32)
    end
    self.rolling = {}
    for i = 0, 9 do self.rolling[i + 1] = assets.quad(self.rollSheet, (i % 2) * 32, math.floor(i / 2) * 32, 32, 32) end
    local op = self.def.opponent or "monk"
    self.opp = type(op) == "table" and op or OPPONENTS[op] or OPPONENTS.monk
    local pic = self.opp.portrait or OPPONENTS.monk.portrait
    if type(pic) == "string" then pic = { image = pic } end
    self.portrait = assets.image(pic.image)
    local pw, ph = self.portrait:getDimensions()
    self.portraitQuad = assets.quad(self.portrait, pic.x or 0, pic.y or 0, pic.w or pw, pic.h or ph)
    self.portraitSize = { pic.w or pw, pic.h or ph }
    self.heroName = "Гриша"
    self.goal = self.def.goal or (1500 + 500 * self.level)
    self.totals = { 0, 0 }
    self.turnOf = 1
    self.dice = {}
    self.kept = {}
    self.turnPts = 0
    self.cursor = 1
    self.state = "start"
    self.say = nil
    self.aiT = 0
end

function Dice:goalText() return "Первым набери " .. self.goal .. " очков" end
function Dice:progress() return nil end
function Dice:results()
    self.extraResult = { enemyScore = self.totals[2] }
    return { self.heroName .. ": " .. self.totals[1] .. "   " .. self.opp.name .. ": " .. self.totals[2] }
end

function Dice:onStart()
    self.score = 0
    self:startTurn(1)
end

function Dice:talk(kind)
    local list = self.opp[kind]
    if list and #list > 0 then
        self.say = { text = list[love.math.random(#list)], t = 0 }
    end
end

function Dice:startTurn(who)
    self.turnOf = who
    self.turnPts = 0
    self.kept = {}
    self.dice = {}
    self.state = who == 1 and "start" or "ai"
    self.aiT = 0.9
    self:banner(who == 1 and "Твой ход" or ("Ход: " .. self.opp.name), who == 1 and "gold" or "accent", 1)
end

-- throw n dice (all six for a new turn)
function Dice:throw(n)
    self.dice = {}
    local placed = {}
    for i = 1, n do
        local x, y
        for _ = 1, 40 do
            x = TRAY.x + 50 + love.math.random() * (TRAY.w - 100)
            y = TRAY.y + 50 + love.math.random() * (TRAY.h - 100)
            local free = true
            for _, p in ipairs(placed) do
                if (p[1] - x) ^ 2 + (p[2] - y) ^ 2 < 80 ^ 2 then free = false; break end
            end
            if free then break end
        end
        table.insert(placed, { x, y })
        table.insert(self.dice, { value = love.math.random(6), x = TRAY.x - 80, y = TRAY.y + TRAY.h / 2 + (i - 3.5) * 20,
            tx = x, ty = y, rot = 0, spin = 0, t = 0, show = 1, seed = love.math.random(10), turned = love.math.random() < 0.4 })
    end
    table.sort(self.dice, function(a, b) return a.tx < b.tx end)
    self.rollT = 0.75
    self.state = "rolling"
    self.cursor = 1
    audio.play("die_shuffle")
    self.timer:after(0.15, function() audio.play("die_throw") end)
end

function Dice:values(onlyPicked)
    local v = {}
    for _, d in ipairs(self.dice) do
        if not onlyPicked or d.picked then table.insert(v, d.value) end
    end
    return v
end

function Dice:afterRoll()
    local best = bestPick(self:values())
    if best == 0 then
        self.state = "bust"
        self:popup(TRAY.x + TRAY.w / 2, TRAY.y + 20, "Пусто! Ход сгорел", { 1, 0.45, 0.4 })
        audio.play("ui_error")
        self:shake(4, 0.25)
        if self.turnOf == 2 then self:talk("bust") end
        self.timer:after(1.6, function() self:startTurn(3 - self.turnOf) end)
        return
    end
    self.state = self.turnOf == 1 and "pick" or "ai"
    self.aiT = 0.8
end

function Dice:selection()
    local s, ok = scoreOf(self:values(true))
    return s, ok
end

-- put the picked dice aside; true if the move is allowed
function Dice:keep()
    local s, ok = self:selection()
    if s <= 0 or not ok then
        audio.play("ui_error")
        self:popup(TRAY.x + TRAY.w / 2, TRAY.y + TRAY.h + 10, "Отложи кости, которые дают очки", { 1, 0.6, 0.4 })
        return false
    end
    self.turnPts = self.turnPts + s
    for i = #self.dice, 1, -1 do
        local d = self.dice[i]
        if d.picked then
            table.insert(self.kept, d)
            table.remove(self.dice, i)
        end
    end
    return true
end

function Dice:rollAgain()
    if not self:keep() then return end
    local n = #self.dice
    if n == 0 then
        n = 6
        self.kept = {}
        self:banner("Все кости! Ещё бросок", "green", 1)
        audio.play("bonus")
    end
    self:throw(n)
end

function Dice:bankPoints()
    if not self:keep() then return end
    local who = self.turnOf
    self.totals[who] = self.totals[who] + self.turnPts
    if who == 1 then self.score = self.totals[1] end
    audio.play(self.turnPts >= 1000 and "fanfare" or "coin")
    self:popup(who == 1 and 140 or 140, who == 1 and 440 or 160, "+" .. self.turnPts, { 1, 0.85, 0.3 })
    if who == 2 and self.turnPts >= 800 then self:talk("big") end
    self.state = "banked"
    if self.totals[who] >= self.goal then
        if who == 2 then self:talk("win") else self:talk("lose") end
        self.timer:after(1.2, function() self:gameOver(who == 1) end)
        return
    end
    self.timer:after(1.0, function() self:startTurn(3 - who) end)
end

function Dice:stepAI(dt)
    self.aiT = self.aiT - dt
    if self.aiT > 0 then return end
    self.aiT = 0.75
    if #self.dice == 0 then return self:throw(6) end
    local picked = false
    for _, d in ipairs(self.dice) do if d.picked then picked = true end end
    if not picked then
        local _, set = bestPick(self:values())
        for _, i in ipairs(set or {}) do self.dice[i].picked = true end
        audio.play("card_place")
        return
    end
    local s = self:selection()
    local left = #self.dice - #self:values(true)
    local pts = self.turnPts + s
    local risk = self.opp.risk or 0.3
    local need = ({ [0] = 1e9, 300, 350, 450, 700, 1200, 1e9 })[left] * (0.7 + risk)
    -- behind? take more risks
    if self.totals[1] - self.totals[2] > 1000 then need = need * 1.5 end
    if left == 0 then need = 1e9 end
    if self.totals[2] + pts >= self.goal then need = 0 end
    if pts >= need then self:bankPoints() else self:rollAgain() end
end

function Dice:step(dt)
    if self.say then
        self.say.t = self.say.t + dt
        if self.say.t > 2.4 then self.say = nil end
    end
    for _, d in ipairs(self.dice) do
        d.t = d.t + dt
        local k = math.min(1, d.t / 0.75)
        local e = 1 - (1 - k) ^ 3
        d.x = d.x + (d.tx - d.x) * math.min(1, dt * 8)
        d.y = d.y + (d.ty - d.y) * math.min(1, dt * 8)
        d.rot = d.rot + d.spin * dt * (1 - e)
        d.tumble = k < 1 and (math.floor(d.t * 18 + d.seed) % 10 + 1) or nil
        if k >= 1 then d.show = d.value end
    end
    for i, d in ipairs(self.kept) do
        local tx, ty = 760 + ((i - 1) % 3) * 66, 190 + math.floor((i - 1) / 3) * 66
        d.turned = false
        d.x = d.x + (tx - d.x) * math.min(1, dt * 10)
        d.y = d.y + (ty - d.y) * math.min(1, dt * 10)
        d.rot = d.rot * (1 - math.min(1, dt * 10))
    end
    if self.state == "rolling" then
        self.rollT = self.rollT - dt
        if self.rollT <= 0 then self:afterRoll() end
        return
    end
    if self.state == "ai" then return self:stepAI(dt) end
    if self.state == "start" then
        if input.pressed("roll") or input.pressed("pick") then self:throw(6) end
        return
    end
    if self.state ~= "pick" then return end
    local n = #self.dice
    if input.pressed("left", true) then self.cursor = (self.cursor - 2) % n + 1; audio.play("ui_move") end
    if input.pressed("right", true) then self.cursor = self.cursor % n + 1; audio.play("ui_move") end
    local m = input.mouse
    local over
    for i, d in ipairs(self.dice) do
        if math.abs(m.x - d.x) < DIE / 2 and math.abs(m.y - d.y) < DIE / 2 then over = i end
    end
    if over and m.moved then self.cursor = over end
    if input.pressed("pick") or (over and m.pressed[1]) then
        local d = self.dice[self.cursor]
        if d then
            d.picked = not d.picked
            audio.play(d.picked and "card_place" or "card_slide")
        end
    end
    if input.pressed("roll") then self:rollAgain()
    elseif input.pressed("bank") then self:bankPoints() end
end

-- pixel dice are never turned by code: a rolling die shows the tumbling frames,
-- a lying one its straight or its turned picture; the opponent's dice are reddish
function Dice:drawDie(d, color, alpha)
    local lg = love.graphics
    local image, quad = self.sheet, self.faces[d.turned and "turned" or "straight"][d.show or d.value]
    if d.tumble then image, quad = self.rollSheet, self.rolling[d.tumble] end
    local x, y = math.floor(d.x + 0.5), math.floor(d.y + 0.5) - (d.picked and 8 or 0)
    lg.setColor(0, 0, 0, 0.35 * (alpha or 1))
    lg.draw(image, quad, x + 4, y + 6 + (d.picked and 8 or 0), 0, 2, 2, 16, 16)
    if color == "red" then lg.setColor(1, 0.62, 0.55, alpha or 1) else lg.setColor(1, 1, 1, alpha or 1) end
    lg.draw(image, quad, x, y, 0, 2, 2, 16, 16)
end

function Dice:drawGame()
    local lg = love.graphics
    local W, H = screen.width, screen.height
    -- the tavern table: dark wood planks and a felt tray
    for i = 0, 8 do
        lg.setColor(0.28 + (i % 2) * 0.03, 0.17 + (i % 3) * 0.01, 0.09, 1)
        lg.rectangle("fill", 0, i * 62, W, 62)
        lg.setColor(0.18, 0.1, 0.05, 1)
        lg.rectangle("fill", 0, i * 62 + 60, W, 2)
    end
    lg.setColor(0.16, 0.09, 0.04, 1)
    lg.rectangle("fill", TRAY.x - 14, TRAY.y - 14, TRAY.w + 28, TRAY.h + 28, 18)
    lg.setColor(0.42, 0.12, 0.12, 1)
    lg.rectangle("fill", TRAY.x, TRAY.y, TRAY.w, TRAY.h, 10)
    lg.setColor(1, 1, 1, 0.04)
    lg.rectangle("fill", TRAY.x + 10, TRAY.y + 10, TRAY.w - 20, TRAY.h / 2, 8)
    -- the opponent: portrait, name, score
    lg.setColor(0.12, 0.07, 0.03, 1)
    lg.rectangle("fill", 24, 40, 170, 158, 6)
    lg.setColor(1, 1, 1, 1)
    lg.setColor(0.1, 0.07, 0.14, 1)
    lg.rectangle("fill", 32, 48, 154, 142)
    lg.setColor(1, 1, 1, 1)
    local pk = math.max(1, math.floor(math.min(154 / self.portraitSize[1], 142 / self.portraitSize[2])))
    lg.draw(self.portrait, self.portraitQuad, 32 + math.floor((154 - self.portraitSize[1] * pk) / 2),
        48 + math.floor((142 - self.portraitSize[2] * pk) / 2), 0, pk, pk)
    lg.setColor(0.75, 0.6, 0.3, 1)
    lg.setLineWidth(3)
    lg.rectangle("line", 30, 46, 158, 146, 3)
    lg.setLineWidth(1)
    local oppTurn = self.turnOf == 2
    ui.print(self.opp.name, 32, 204, { font = "small", color = oppTurn and "accent" or "light" })
    ui.print(self.totals[2], 32, 228, { font = "pixel", color = "light" })
    ui.bar(32, 252, 154, 6, self.totals[2], self.goal, "red")
    if self.say then
        local a = math.min(1, (2.4 - self.say.t) * 3)
        ui.panel.draw(200, 60, 240, 60, "small")
        ui.print(self.say.text, 214, 76, { font = "small", color = "ink", width = 212, alpha = a })
    end
    -- the hero
    ui.print(self.heroName, 32, 410, { font = "small", color = (not oppTurn) and "accent" or "light" })
    ui.print(self.totals[1], 32, 434, { font = "pixel", color = "light" })
    ui.bar(32, 458, 154, 6, self.totals[1], self.goal, "gold")
    ui.print("Цель " .. self.goal, 32, 480, { font = "small", color = "faded" })
    -- the dice put aside and the points of the turn
    ui.print("Отложено", 760 - 28, 140, { font = "small", color = "faded" })
    local color = oppTurn and "red" or "white"
    for _, d in ipairs(self.kept) do self:drawDie(d, color, 0.85) end
    ui.print("Ход: " .. self.turnPts, 760 - 28, 330, { font = "body", color = "gold" })
    -- the dice in the tray
    for i, d in ipairs(self.dice) do
        self:drawDie(d, color)
        if self.state == "pick" and i == self.cursor then
            lg.setColor(1, 0.9, 0.4, 0.6 + 0.4 * math.sin(self.time * 8))
            lg.setLineWidth(3)
            lg.rectangle("line", d.x - 34, d.y - 40, 68, 68, 8)
            lg.setLineWidth(1)
        end
    end
    lg.setColor(1, 1, 1, 1)
    -- what the choice gives
    if self.state == "pick" then
        local s, ok = self:selection()
        local text
        if #self:values(true) == 0 then text = "Выбери кости с очками"
        elseif ok then text = "Отложить: +" .. s .. "  (всего за ход " .. (self.turnPts + s) .. ")"
        else text = "Эти кости не все дают очки" end
        ui.print(text, TRAY.x + TRAY.w / 2, TRAY.y + TRAY.h + 24, { font = "small", align = "center",
            color = ok and "accent" or "faded" })
        ui.print("[" .. input.keyName("roll") .. "] бросить ещё    [" .. input.keyName("bank") .. "] записать",
            TRAY.x + TRAY.w / 2, TRAY.y + TRAY.h + 52, { font = "small", align = "center", color = "light", alpha = 0.8 })
    elseif self.state == "start" then
        ui.print("[" .. input.keyName("roll") .. "] бросить кости", TRAY.x + TRAY.w / 2, TRAY.y + TRAY.h / 2 - 10,
            { font = "pixel", align = "center", color = "light", alpha = 0.6 + 0.4 * math.sin(self.time * 4) })
    end
end

return Dice
