-- Fishing like in Stardew Valley: cast, wait for a bite, hook it and keep the fish inside
-- the green bar until the catch meter is full. Fish: game/data/fish.lua (old engravings from
-- the Public Domain Pack by Drummyfish, CC0); the float: "Fishing Bobbles" by Nelson Yiap
-- (HappyGo Games, CC-BY 4.0).
--
--   game.stage "pier" { kind = "fishing", goal = 3, time = 120 }
--   local r = s:play("fishing", { goal = 1, fish = { "fugu" } })  -- r.win, r.score, r.caught = { ids }
--
--   goal     fish to catch (default 3)
--   fish     only these fish bite (ids from game/data/fish.lua); default: all of them
--   lives    fish that may get away (default 3)
--   bar      size of the green bar 0.15..0.5 (default 0.3, smaller = harder)
-- Every fish goes to the bag ("Рыба") and to the collection (game.state.codex.fish).
-- Keys: hold [Space] to swing and release to cast; when "!" shows - [Space]; then hold
-- [Space] to lift the bar, let it go to drop it.

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

local Fishing = class(Arcade)
Fishing.keymap = "fishing"
Fishing.info = {
    title = "Рыбалка",
    rules = "Зажми и отпусти — заброс. Когда поплавок дёрнется и появится «!», подсекай. Потом держи рыбку в "
        .. "зелёной полосе: зажал — полоса вверх, отпустил — вниз.",
    keys = { { "reel", "забросить / подсечь / тянуть" } },
    background = "cliffs",
    dim = 0,
    music = "calm",
}

local WATER_Y = 360
local METER = { x = 760, y = 90, w = 44, h = 360 }

function Fishing:setup()
    self.atlas = assets.image("assets/sprites/arcade/fish.png")
    self.fishQ = {}
    for i = 1, 17 do
        self.fishQ[i] = assets.quad(self.atlas, ((i - 1) % 5) * 160, math.floor((i - 1) / 5) * 96, 160, 96)
    end
    self.bobberImage = assets.image("assets/sprites/arcade/bobber.png")
    self.bobQ = {}
    for i = 0, 3 do
        self.bobQ[i] = assets.quad(self.bobberImage, (i % 2) * 24, math.floor(i / 2) * 24, 24, 24)
    end
    local sprites = G().sprites
    local hero = sprites[G().player.side or "grisha_side"] or sprites.grisha_side
    self.heroImage = assets.image(hero.image)
    self.heroQ = assets.quad(self.heroImage, 4 * 16, 16, 16, 16) -- Гриша looks right (td_hero row 2)
    self.goal = self.def.goal or 3
    self.barSize = self.def.bar or 0.3
    self.caught = {}
    self.pool = {}
    local all = G().fish
    for id, f in pairs(all) do
        local ok = true
        if self.def.fish then
            ok = false
            for _, x in ipairs(self.def.fish) do if x == id then ok = true end end
        end
        if ok then table.insert(self.pool, id) end
    end
    table.sort(self.pool)
    self.state = "ready"
    self.power = 0
    self.rod = { x = 196, y = 352 }
end

function Fishing:goalText() return "Поймай рыб: " .. self.goal end
function Fishing:progress() return "Улов " .. #self.caught .. "/" .. self.goal end
function Fishing:results()
    self.extraResult = { caught = self.caught }
    local names = {}
    for _, id in ipairs(self.caught) do table.insert(names, G().fish[id].name) end
    return { #names > 0 and ("Улов: " .. table.concat(names, ", ")) or "Ничего не поймал" }
end

function Fishing:pickFish()
    local total = 0
    for _, id in ipairs(self.pool) do total = total + G().fish[id].rarity end
    local r = love.math.random() * total
    for _, id in ipairs(self.pool) do
        r = r - G().fish[id].rarity
        if r <= 0 then return id end
    end
    return self.pool[1]
end

function Fishing:step(dt)
    local st = self.state
    local hold = input.down("reel")
    if st == "ready" then
        if hold then
            self.state, self.power, self.powerDir = "charge", 0, 1
        end
    elseif st == "charge" then
        self.power = self.power + self.powerDir * dt * 1.4
        if self.power >= 1 then self.power, self.powerDir = 1, -1 end
        if self.power <= 0 then self.power, self.powerDir = 0, 1 end
        if not hold then
            local dist = 0.25 + self.power * 0.75
            self.bobber = { x = 260 + dist * 420, y = WATER_Y + 20 + dist * 30, t = 0, fly = 0, fromX = self.rod.x,
                fromY = self.rod.y }
            self.state = "fly"
            audio.play("throw")
            if self.power > 0.92 then self:popup(self.bobber.x, WATER_Y - 40, "Идеально!", { 0.5, 1, 0.5 }) end
            self.bonus = self.power > 0.92 and 1.5 or 1
        end
    elseif st == "fly" then
        local b = self.bobber
        b.fly = b.fly + dt * 1.6
        if b.fly >= 1 then
            b.fly = 1
            self.state = "wait"
            self.waitT = 1.2 + love.math.random() * 3.5 / self.bonus
            self.nibbles = love.math.random(0, 2)
            audio.play("pop", { pitch = 0.7 })
            self.fx:burst(b.x, b.y, { color = { 0.8, 0.95, 1 }, count = 10, speed = 60, life = 0.5, gravity = 200, up = 60 })
        end
    elseif st == "wait" then
        self.bobber.t = self.bobber.t + dt
        self.waitT = self.waitT - dt
        if self.nibbles > 0 and self.waitT < self.nibbles * 0.8 then
            self.nibbles = self.nibbles - 1
            self.bobber.dip = 0.25
            audio.play("blip", { pitch = 0.6 })
        end
        if hold and self.waitT > 0.2 then
            -- pulled too early: the fish is scared away
            self:popup(self.bobber.x, WATER_Y - 30, "Рано!", { 1, 0.6, 0.4 })
            audio.play("ui_error")
            self.state = "ready"
            self.bobber = nil
            return
        end
        if self.waitT <= 0 then
            self.state = "bite"
            self.biteT = 0.9 - self.level * 0.08
            self.fishId = self:pickFish()
            self.bobber.dip = 0.6
            audio.play("zap")
        end
    elseif st == "bite" then
        self.bobber.t = self.bobber.t + dt
        self.biteT = self.biteT - dt
        if input.pressed("reel") then
            self:startReel()
        elseif self.biteT <= 0 then
            self:popup(self.bobber.x, WATER_Y - 30, "Сорвалась...", { 1, 0.6, 0.4 })
            self.state = "ready"
            self.bobber = nil
            audio.play("ui_error")
        end
    elseif st == "reel" then
        self:stepReel(dt, hold)
    elseif st == "show" then
        self.showT = self.showT + dt
        if self.showT > 0.6 and input.pressed("reel") then
            self.state = "ready"
            if #self.caught >= self.goal then self:win() end
        end
    end
    if self.bobber and self.bobber.dip then
        self.bobber.dip = self.bobber.dip - dt
        if self.bobber.dip <= 0 then self.bobber.dip = nil end
    end
end

function Fishing:startReel()
    local f = G().fish[self.fishId]
    self.reel = {
        fish = f, id = self.fishId, fy = 0.2, fv = 0, target = 0.3, retarget = 0,
        by = 0, bv = 0, progress = 0.3, perfect = true,
        size = self.barSize * (1.1 - self.level * 0.05),
    }
    self.state = "reel"
    audio.play("powerup")
end

-- the fish moves on its own: it picks a target height and swims there
function Fishing:moveFish(r, dt)
    local f = r.fish
    local d = f.difficulty / 100
    r.retarget = r.retarget - dt
    if r.retarget <= 0 then
        local b = f.behavior
        local t = love.math.random()
        if b == "sinker" then t = t * 0.6 elseif b == "floater" then t = 0.4 + t * 0.6 end
        r.target = t
        r.retarget = (b == "dart" and 0.35 or 0.8) + love.math.random() * (1.6 - d)
        if b == "dart" and love.math.random() < 0.5 then r.fv = r.fv + (love.math.random() - 0.5) * 4 * d end
    end
    local accel = (r.target - r.fy) * (2 + d * 10)
    if f.behavior == "smooth" then accel = accel * 0.6 end
    r.fv = r.fv + accel * dt
    r.fv = r.fv * (1 - math.min(0.9, dt * (3 - d * 1.5)))
    r.fy = math.max(0, math.min(1, r.fy + r.fv * dt))
end

function Fishing:stepReel(dt, hold)
    local r = self.reel
    self:moveFish(r, dt)
    -- the bar: holding pushes it up, gravity pulls it down, it bounces at the bottom
    r.bv = r.bv + (hold and 2.6 or -2.4) * dt
    r.by = r.by + r.bv * dt
    if r.by < 0 then r.by = 0; r.bv = -r.bv * 0.4 end
    if r.by > 1 - r.size then r.by = 1 - r.size; r.bv = 0 end
    local inside = r.fy >= r.by and r.fy <= r.by + r.size
    r.inside = inside
    if inside then
        r.progress = r.progress + dt * 0.32
    else
        r.progress = r.progress - dt * (0.18 + r.fish.difficulty / 400)
        r.perfect = false
    end
    if math.floor(self.time * 8) % 2 == 0 and inside then audio.play("ui_text") end
    if r.progress >= 1 then
        self:catch(r)
    elseif r.progress <= 0 then
        self.reel = nil
        self.bobber = nil
        self.state = "ready"
        self:popup(560, WATER_Y - 30, "Ушла!", { 1, 0.5, 0.4 })
        self:loseLife()
    end
end

function Fishing:catch(r)
    local f = r.fish
    local size = math.floor(f.size[1] + (f.size[2] - f.size[1]) * love.math.random() ^ 1.5 + 0.5)
    local st = G().state
    local first = true
    if st then
        st.codex = st.codex or {}
        st.codex.fish = st.codex.fish or {}
        local c = st.codex.fish[r.id]
        first = c == nil
        st.codex.fish[r.id] = { count = (c and c.count or 0) + 1, best = math.max(c and c.best or 0, size) }
        st.inventory:add("fish", 1)
    end
    table.insert(self.caught, r.id)
    local pts = math.floor(f.points * (r.perfect and 1.5 or 1) * self.bonus)
    self:addScore(pts)
    self.shown = { id = r.id, fish = f, size = size, first = first, perfect = r.perfect, points = pts }
    self.reel = nil
    self.bobber = nil
    self.state = "show"
    self.showT = 0
    audio.play("fanfare")
end

function Fishing:drawGame()
    local lg = love.graphics
    -- the fisherman on the rock (the side hero) with the rod line
    local hx, hy = 170, 372
    lg.setColor(0.25, 0.2, 0.18, 1)
    lg.polygon("fill", 60, 540, 90, 380, 220, 372, 260, 540)
    lg.setColor(0.35, 0.3, 0.25, 1)
    lg.polygon("fill", 90, 380, 220, 372, 214, 384, 96, 392)
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.heroImage, self.heroQ, hx, hy, 0, 4, 4, 8, 16)
    local tipX, tipY = hx + 44, hy - 76
    lg.setColor(0.45, 0.3, 0.15, 1)
    lg.setLineWidth(4)
    local bend = (self.state == "reel") and 18 or (self.state == "charge" and -self.power * 20 or 0)
    lg.line(hx + 6, hy - 30, (hx + 6 + tipX) / 2 + bend * 0.3, (hy - 30 + tipY) / 2 - bend * 0.2, tipX + bend, tipY + bend * 0.5)
    self.rod.x, self.rod.y = tipX + bend, tipY + bend * 0.5
    local b = self.bobber
    if b then
        local k = b.fly
        local bx = b.fromX + (b.x - b.fromX) * k
        local by = b.fromY + (b.y - b.fromY) * k - math.sin(k * math.pi) * 120
        local bob = (self.state == "wait" or self.state == "bite") and math.sin(b.t * 3) * 2 or 0
        if b.dip then by = by + 6 end
        lg.setColor(1, 1, 1, 0.7)
        lg.setLineWidth(1)
        lg.line(self.rod.x, self.rod.y, (self.rod.x + bx) / 2, math.max(self.rod.y, by) + 20, bx, by + bob - 8)
        lg.setColor(1, 1, 1, 1)
        local frame = (b.dip or self.state == "bite") and (2 + math.floor(self.time * 6) % 2) or math.floor(self.time * 2) % 2
        lg.draw(self.bobberImage, self.bobQ[frame], bx, by + bob, 0, 3, 3, 12, 16)
        if self.state == "bite" then
            ui.print("!", bx, by - 90, { font = "title", align = "center", color = "red", outline = { 1, 1, 1, 1 } })
        end
    end
    if self.state == "charge" then
        ui.bar(120, 300, 140, 14, self.power, 1, self.power > 0.92 and "green" or "gold")
    end
    if self.state == "ready" then
        ui.print("Зажми [" .. input.keyName("reel") .. "]", 330, 300, { font = "small", color = "light", alpha = 0.6 + 0.4 * math.sin(self.time * 4) })
    end
    if self.reel then self:drawMeter() end
    if self.state == "show" then self:drawCatch() end
end

function Fishing:drawMeter()
    local lg = love.graphics
    local r, m = self.reel, METER
    ui.panel.draw(m.x - 14, m.y - 14, m.w + 60, m.h + 28, "small")
    lg.setColor(0.1, 0.25, 0.45, 1)
    lg.rectangle("fill", m.x, m.y, m.w, m.h)
    -- the green bar
    local barY = m.y + m.h * (1 - r.by - r.size)
    lg.setColor(r.inside and { 0.4, 0.95, 0.4, 0.9 } or { 0.3, 0.75, 0.3, 0.75 })
    lg.rectangle("fill", m.x + 3, barY, m.w - 6, m.h * r.size, 4)
    -- the fish
    local fy = m.y + m.h * (1 - r.fy)
    lg.setColor(1, 1, 1, 1)
    local shake = r.inside and 0 or math.sin(self.time * 40) * 2
    ui.icon("fish", m.x + m.w / 2 - 17 + shake, fy - 17, 1)
    -- the catch meter
    local px = m.x + m.w + 14
    lg.setColor(0.05, 0.05, 0.1, 1)
    lg.rectangle("fill", px, m.y, 16, m.h)
    local k = math.max(0, math.min(1, r.progress))
    lg.setColor(1 - k, 0.4 + k * 0.6, 0.2, 1)
    lg.rectangle("fill", px + 2, m.y + m.h * (1 - k), 12, m.h * k)
    lg.setColor(1, 1, 1, 1)
end

function Fishing:drawCatch()
    local s = self.shown
    local w, h = 460, 300
    local x, y = (screen.width - w) / 2, 110
    ui.panel.draw(x, y, w, h)
    local cx = screen.width / 2
    ui.print(s.first and "Новая рыба!" or "Поймал!", cx, y + 18, { font = "pixel", align = "center", color = "gold" })
    local lg = love.graphics
    local k = math.min(1, self.showT * 3)
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.atlas, self.fishQ[s.fish.cell], cx, y + 130, math.sin(self.time * 2) * 0.05, 1.6 * k, 1.6 * k, 80, 48)
    if s.perfect then
        ui.print("Идеально!", cx, y + 46, { font = "small", align = "center", color = "green" })
    end
    ui.print(s.fish.name, cx, y + 214, { font = "body", align = "center", color = "accent" })
    ui.print(s.size .. " см   +" .. s.points .. " очков", cx, y + 250, { font = "small", align = "center", color = "light" })
end

return Fishing
