-- Lock picking like in Skyrim: move the pick, then try to turn the lock. The closer the pick is to
-- the hidden sweet spot, the further the lock turns; at the spot it opens. Forcing the lock bends
-- the pick until it breaks. The lock is drawn by code; the key icon: "496 pixel art icons" (CC0).
--
--   game.stage "chest_lock" { kind = "lockpick", goal = 1, lives = 3, level = 3 }
--   local r = s:play("lockpick", { goal = 1, lives = 2, intro = false })   -- r.win, r.picksLeft
--
--   goal     locks to open (default 3)
--   lives    lock picks (default 3; s:play can pass game.state.inventory:count("pick"))
--   level    1 easy (wide sweet spot) .. 5 master (tiny)
--   time     time limit (default none)
-- Keys: [←][→] (or the mouse) move the pick, hold [Space] to turn the lock.

local engine = require("engine")
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Lockpick = class(Arcade)
Lockpick.info = {
    title = "Взлом",
    rules = "Двигай отмычку и пробуй повернуть замок. Чем ближе к нужной точке, тем дальше он поворачивается. "
        .. "Не дави слишком долго — отмычка сломается.",
    keys = { { "left", "отмычка", "[←][→]" }, { "fire", "крутить (держать)" } },
    background = "black",
    dim = 0,
    lives = false,
    music = false,
}
Lockpick.defaultLives = 3

local ZONES = { 20, 14, 9, 6, 4 }   -- half width of the sweet spot in degrees by level
local CX, CY, R = 480, 300, 150

function Lockpick:setup()
    self.goal = self.def.goal or 3
    self.opened = 0
    self:newLock()
    self.pickHealth = 1
    self.brokeT = 0
end

function Lockpick:newLock()
    local lv = math.max(1, math.min(5, self.level + math.floor(self.opened / 2)))
    self.lock = {
        sweet = love.math.random(-80, 80), zone = ZONES[lv], range = 70 - lv * 6,
        angle = 0, pick = 0, shake = 0, t = 0, level = lv,
    }
    self.lockT = 0
end

function Lockpick:goalText()
    return "Открой замков: " .. self.goal
end

function Lockpick:progress()
    return "Замки " .. self.opened .. "/" .. self.goal
end

function Lockpick:results()
    self.extraResult = { picksLeft = self.lives }
    return { "Открыто замков: " .. self.opened .. "   Отмычек осталось: " .. math.max(0, self.lives) }
end

-- how far (0..90 degrees) the lock may turn with the pick at its angle
function Lockpick:allowed()
    local l = self.lock
    local d = math.abs(l.pick - l.sweet)
    if d <= l.zone then return 90 end
    return math.max(0, 90 * (1 - (d - l.zone) / l.range))
end

function Lockpick:step(dt)
    local l = self.lock
    l.t = l.t + dt
    self.lockT = self.lockT + dt
    if self.brokeT > 0 then
        self.brokeT = self.brokeT - dt
        l.angle = math.max(0, l.angle - 300 * dt)
        return
    end
    if self.unlocking then
        l.angle = math.min(90, l.angle + 240 * dt)
        return
    end
    local turning = input.down("fire")
    -- the pick moves only while the lock is not turned
    if not turning or l.angle < 2 then
        local dir = (input.down("right") and 1 or 0) - (input.down("left") and 1 or 0)
        l.pick = math.max(-90, math.min(90, l.pick + dir * 70 * dt))
        local m = input.mouse
        if m.moved then
            local a = math.deg(math.atan2(m.x - CX, -(m.y - CY)))
            l.pick = math.max(-90, math.min(90, a))
        end
        if dir ~= 0 and math.floor(l.t * 10) ~= math.floor((l.t - dt) * 10) then audio.play("t_move", { volume = 0.2 }) end
    end
    if turning then
        local max = self:allowed()
        if l.angle < max then
            l.angle = math.min(max, l.angle + 160 * dt)
            l.shake = 0
            if math.floor(l.angle / 15) ~= math.floor((l.angle - 160 * dt) / 15) then audio.play("t_rotate", { volume = 0.3 }) end
        else
            -- forcing it: the pick bends
            l.shake = 1
            self.pickHealth = self.pickHealth - dt * (0.9 + l.level * 0.15)
            if math.floor(l.t * 6) ~= math.floor((l.t - dt) * 6) then audio.play("stomp", { volume = 0.25, pitch = 1.8 }) end
            if self.pickHealth <= 0 then return self:breakPick() end
        end
        if l.angle >= 89.5 then return self:open() end
    else
        l.shake = 0
        l.angle = math.max(0, l.angle - 300 * dt)
    end
end

function Lockpick:breakPick()
    audio.play("crumble")
    self:shake(6, 0.3)
    self:popup(CX, CY - R - 40, "Отмычка сломалась!", { 1, 0.5, 0.4 })
    self.fx:burst(CX + math.sin(math.rad(self.lock.pick)) * 40, CY - math.cos(math.rad(self.lock.pick)) * 40,
        { color = { 0.8, 0.8, 0.85 }, count = 10, speed = 120, life = 0.5, size = 2, gravity = 300 })
    self.pickHealth = 1
    self.brokeT = 0.8
    self.lock.shake = 0
    self:loseLife()
end

function Lockpick:open()
    self.unlocking = true
    audio.play("unlock")
    local bonus = math.max(0, math.floor(300 - self.lockT * 20)) + self.lock.level * 100
    self:addScore(200 + bonus, CX, CY - R - 30)
    self:flash({ 1, 0.9, 0.5 }, 0.25)
    self.timer:after(0.7, function()
        self.unlocking = false
        self.opened = self.opened + 1
        if self.opened >= self.goal then
            self:win()
        else
            self:banner("ОТКРЫТО!", "gold", 1)
            self:newLock()
        end
    end)
end

function Lockpick:drawGame()
    local lg = love.graphics
    local l = self.lock
    local shake = l.shake > 0 and math.sin(self.time * 60) * 2.5 or 0
    -- a door of dark wood around the lock
    lg.setColor(0.2, 0.12, 0.07, 1)
    lg.rectangle("fill", CX - 330, 40, 660, 500)
    for i = 0, 5 do
        lg.setColor(0.24 + (i % 2) * 0.03, 0.15, 0.08, 1)
        lg.rectangle("fill", CX - 330 + i * 110, 40, 106, 500)
    end
    lg.setColor(0.4, 0.4, 0.42, 1)
    for _, y in ipairs({ 110, 480 }) do
        lg.rectangle("fill", CX - 330, y, 660, 26)
        lg.setColor(0.3, 0.3, 0.32, 1)
        for x = CX - 300, CX + 300, 100 do lg.circle("fill", x, y + 13, 6) end
        lg.setColor(0.4, 0.4, 0.42, 1)
    end
    lg.push()
    lg.translate(CX + shake, CY)
    -- the brass plate
    for i = 6, 0, -1 do
        local k = i / 6
        lg.setColor(0.55 + 0.35 * (1 - k), 0.42 + 0.3 * (1 - k), 0.15 + 0.15 * (1 - k), 1)
        lg.circle("fill", 0, 0, R + 30 - i * 2)
    end
    lg.setColor(0.32, 0.22, 0.08, 1)
    lg.setLineWidth(4)
    lg.circle("line", 0, 0, R + 30)
    for i = 0, 7 do
        local a = i / 8 * math.pi * 2
        lg.setColor(0.35, 0.25, 0.1, 1)
        lg.circle("fill", math.cos(a) * (R + 14), math.sin(a) * (R + 14), 6)
        lg.setColor(0.95, 0.85, 0.5, 1)
        lg.circle("fill", math.cos(a) * (R + 14) - 1.5, math.sin(a) * (R + 14) - 1.5, 2.5)
    end
    -- the cylinder turns
    lg.push()
    lg.rotate(math.rad(l.angle))
    lg.setColor(0.42, 0.32, 0.12, 1)
    lg.circle("fill", 0, 0, R * 0.55)
    lg.setColor(0.6, 0.48, 0.2, 1)
    lg.circle("line", 0, 0, R * 0.55)
    -- the keyhole
    lg.setColor(0.04, 0.03, 0.02, 1)
    lg.circle("fill", 0, -14, 16)
    lg.polygon("fill", -9, -6, 9, -6, 15, 44, -15, 44)
    lg.pop()
    -- the tension wrench at the bottom turns with the cylinder
    lg.push()
    lg.rotate(math.rad(l.angle))
    lg.setColor(0.25, 0.25, 0.28, 1)
    lg.rectangle("fill", -4, 30, 8, 30)
    lg.rectangle("fill", -4, 56, 110, 8)
    lg.setColor(0.6, 0.6, 0.65, 1)
    lg.rectangle("fill", -3, 31, 2, 28)
    lg.rectangle("fill", -3, 57, 108, 2)
    lg.pop()
    -- the pick: from the keyhole out at its angle; it gets red when it bends
    local a = math.rad(l.pick)
    local bend = (1 - self.pickHealth)
    if self.brokeT <= 0 then
        local len = 290
        local dx, dy = math.sin(a), -math.cos(a)
        local px, py = -dy, dx
        local wob = l.shake > 0 and math.sin(self.time * 70) * 3 * bend or 0
        lg.setLineWidth(5)
        lg.setColor(0.65 + bend * 0.35, 0.65 - bend * 0.4, 0.7 - bend * 0.45, 1)
        local mx, my = dx * len * 0.5 + px * (wob + bend * 10), dy * len * 0.5 + py * (wob + bend * 10)
        lg.line(0, -10, mx, my, dx * len, dy * len)
        lg.setColor(0.35, 0.2, 0.1, 1)
        lg.setLineWidth(12)
        lg.line(dx * len * 0.75, dy * len * 0.75, dx * len, dy * len)
    end
    lg.setLineWidth(1)
    lg.pop()
    -- picks left
    for i = 1, self.lives do
        lg.setColor(0.7, 0.7, 0.75, 1)
        lg.setLineWidth(3)
        lg.line(40 + i * 18, screen.height - 70, 40 + i * 18, screen.height - 30)
        lg.setColor(0.35, 0.2, 0.1, 1)
        lg.rectangle("fill", 37 + i * 18, screen.height - 42, 6, 14)
    end
    lg.setLineWidth(1)
    ui.print("Отмычки", 52, screen.height - 26, { font = "small", color = "faded" })
    local names = { "Простой", "Новичок", "Подмастерье", "Эксперт", "Мастер" }
    ui.print("Замок: " .. names[l.level], screen.width - 40, screen.height - 50, { font = "small", align = "right",
        color = "accent" })
    lg.setColor(1, 1, 1, 1)
end

return Lockpick
