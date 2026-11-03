-- Action commands ("QTE") of the battle: small timing games that make every
-- action depend on the player. Each one: q = qte.ring{...}; q:update(dt) -> true
-- when it is over, q.result ("perfect" | "good" | "miss" ...), q.quality (0..1);
-- q:draw(battle) draws it on top of the field.
--
--   ring   a ring closes on the target: press [attack] when it touches the circle
--   bar    a marker runs over a bar: stop it in the middle
--   mash   press [attack] as fast as you can
--   hold   hold [attack], release in the green zone
--   parry  an enemy blow: [parry] right at the hit = no damage + counter,
--          a bit off = block (half damage), [dodge] = jump away. Too early = locked out.

local input = require("engine.input")
local ui = require("engine.ui")
local audio = require("engine.audio")

local qte = {}

local function G()
    return require("game")
end

local function timing()
    return (G().battle and G().battle.timing) or 1
end

local function auto()
    return G().battle and G().battle.auto
end

local function keyCap(x, y, action, alpha, pulse)
    local font = ui.font("small")
    local key = input.keyName(action)
    local w = math.max(font:getWidth(key) + 16, font:getHeight() + 6)
    local h = font:getHeight() + 6
    local s = pulse and (1 + 0.12 * math.abs(math.sin(love.timer.getTime() * 10))) or 1
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(s, s)
    ui.panel.draw(-w / 2, -h / 2, w, h, "small")
    ui.print(key, 0, -h / 2 + 3, { font = font, align = "center", alpha = alpha or 1 })
    love.graphics.pop()
end
qte.keyCap = keyCap

local function unitPoint(b, u)
    local sx, sy, s = b:project(u.x, u.y, 0)
    return sx, sy - 26 * s, s
end

-- ring ------------------------------------------------------------------------------

local Ring = {}
Ring.__index = Ring

-- opts: target (unit), duration (seconds until the ring closes), action ("attack")
function qte.ring(opts)
    local q = setmetatable({ t = 0, kind = "ring" }, Ring)
    q.target, q.duration = opts.target, opts.duration or 0.6
    q.action = opts.action or "attack"
    q.perfect, q.good = 0.065 * timing(), 0.15 * timing()
    return q
end

function Ring:update(dt)
    self.t = self.t + dt
    local diff = self.t - self.duration
    if auto() and diff >= 0 then
        self.result, self.quality = "perfect", 1
        return true
    end
    if input.pressed(self.action) then
        input.consume(self.action)
        input.consume("confirm")
        local d = math.abs(diff)
        self.result = d <= self.perfect and "perfect" or (d <= self.good and "good" or "miss")
        self.quality = self.result == "perfect" and 1 or (self.result == "good" and 0.6 or 0)
        self.pressedAt = diff
        return true
    end
    if diff > self.good then
        self.result, self.quality = "miss", 0
        return true
    end
    return false
end

function Ring:draw(b)
    local lg = love.graphics
    local x, y, s = unitPoint(b, self.target)
    local k = math.max(0, 1 - self.t / self.duration)
    local r0 = 22 * s
    local r = r0 + k * 90
    lg.setLineWidth(3)
    lg.setColor(1, 1, 1, 0.55)
    lg.circle("line", x, y, r0)
    local close = math.abs(self.t - self.duration) <= self.good
    if close then
        lg.setColor(0.5, 1, 0.5, 0.95)
    else
        lg.setColor(1, 0.85, 0.3, 0.95)
    end
    lg.circle("line", x, y, r)
    lg.setLineWidth(1)
    keyCap(x, y - r0 - 30, self.action, 1, close)
end

-- bar -------------------------------------------------------------------------------

local Bar = {}
Bar.__index = Bar

-- opts: speed (runs per second), label
function qte.bar(opts)
    opts = opts or {}
    local q = setmetatable({ t = 0, x = 0, dir = 1, kind = "bar" }, Bar)
    q.speed = opts.speed or 1.35
    q.label = opts.label or "Останови в центре!"
    q.action = opts.action or "attack"
    q.perfect, q.good = 0.05 * timing(), 0.17 * timing()
    return q
end

function Bar:update(dt)
    self.t = self.t + dt
    self.x = self.x + self.dir * self.speed * dt
    if self.x > 1 then
        self.x, self.dir = 2 - self.x, -1
    elseif self.x < 0 then
        self.x, self.dir = -self.x, 1
    end
    if auto() and math.abs(self.x - 0.5) < 0.02 then
        self.result, self.quality = "perfect", 1
        return true
    end
    if input.pressed(self.action) or self.t > 4 then
        input.consume(self.action)
        input.consume("confirm")
        local d = math.abs(self.x - 0.5)
        self.result = d <= self.perfect and "perfect" or (d <= self.good and "good" or "miss")
        self.quality = math.max(0, 1 - d * 2)
        self.stopped = self.x
        return true
    end
    return false
end

function Bar:draw(b)
    local lg = love.graphics
    local W = 360
    local x0, y0 = math.floor(480 - W / 2), 330
    ui.panel.draw(x0 - 16, y0 - 40, W + 32, 84, "small")
    ui.print(self.label, 480, y0 - 32, { font = "small", align = "center", color = "accent" })
    lg.setColor(0.15, 0.1, 0.12, 1)
    lg.rectangle("fill", x0, y0, W, 18)
    lg.setColor(0.9, 0.75, 0.25, 0.9)
    lg.rectangle("fill", x0 + W * (0.5 - self.good), y0, W * self.good * 2, 18)
    lg.setColor(0.45, 1, 0.45, 1)
    lg.rectangle("fill", x0 + W * (0.5 - self.perfect), y0, W * self.perfect * 2, 18)
    lg.setColor(1, 1, 1, 1)
    local mx = x0 + W * self.x
    lg.polygon("fill", mx - 7, y0 - 8, mx + 7, y0 - 8, mx, y0 + 2)
    lg.rectangle("fill", mx - 1, y0, 3, 18)
    keyCap(480, y0 + 32, self.action, 1, true)
end

-- mash ------------------------------------------------------------------------------

local Mash = {}
Mash.__index = Mash

function qte.mash(opts)
    opts = opts or {}
    local q = setmetatable({ t = 0, fill = 0, presses = 0, kind = "mash" }, Mash)
    q.duration = opts.duration or 2.0
    q.label = opts.label or "Жми быстро!"
    q.action = opts.action or "attack"
    q.step = 0.075 / math.sqrt(timing())
    return q
end

function Mash:update(dt)
    self.t = self.t + dt
    self.fill = math.max(0, self.fill - dt * 0.2)
    if input.pressed(self.action) or (auto() and self.t * 14 > self.presses) then
        input.consume(self.action)
        input.consume("confirm")
        self.presses = self.presses + 1
        self.fill = math.min(1.0, self.fill + self.step * (1 / timing() * 0.4 + 0.6))
        self.bump = 0.08
        audio.play("ui_move", { volume = 0.5, pitch = 0.8 + self.fill * 0.8 })
    end
    self.bump = math.max(0, (self.bump or 0) - dt)
    if self.t >= self.duration then
        local f = self.fill
        self.quality = f
        self.result = f >= 0.85 and "perfect" or (f >= 0.45 and "good" or "miss")
        return true
    end
    return false
end

function Mash:draw(b)
    local lg = love.graphics
    local W = 320
    local x0, y0 = math.floor(480 - W / 2), 330
    ui.panel.draw(x0 - 16, y0 - 40, W + 32, 88, "small")
    ui.print(self.label, 480, y0 - 32, { font = "small", align = "center", color = "accent" })
    ui.bar(x0, y0, W, 18, self.fill, 1, self.fill >= 0.85 and "green" or "gold")
    lg.setColor(1, 1, 1, 0.7)
    lg.rectangle("fill", x0 + W * 0.85, y0 - 4, 2, 26)
    local s = 1 + (self.bump or 0) * 4
    lg.push()
    lg.translate(480, y0 + 36)
    lg.scale(s, s)
    keyCap(0, 0, self.action, 1, false)
    lg.pop()
    ui.print(string.format("%.1f", math.max(0, self.duration - self.t)), x0 + W, y0 + 26, { font = "small", align = "right", color = "light" })
end

-- hold ------------------------------------------------------------------------------

local Hold = {}
Hold.__index = Hold

function qte.hold(opts)
    opts = opts or {}
    local q = setmetatable({ t = 0, charge = 0, kind = "hold" }, Hold)
    q.label = opts.label or "Держи и отпусти в зелёной зоне!"
    q.action = opts.action or "attack"
    local w = 0.1 * timing()
    q.lo, q.hi = 0.8 - w, 0.8 + w * 0.8
    return q
end

function Hold:update(dt)
    self.t = self.t + dt
    local down = input.down(self.action) or (auto() and self.charge < 0.8)
    if down and not self.released then
        self.holding = true
        self.charge = self.charge + dt / 1.1
        if self.charge > 1.08 then
            self.result, self.quality = "miss", 0.2
            return true
        end
    elseif self.holding then
        local c = self.charge
        if c >= self.lo and c <= self.hi then
            self.result, self.quality = "perfect", 1
        elseif c >= self.lo - 0.2 then
            self.result, self.quality = "good", 0.65
        else
            self.result, self.quality = "miss", math.max(0.2, c)
        end
        return true
    end
    if self.t > 3 and not self.holding then
        self.result, self.quality = "miss", 0.2
        return true
    end
    return false
end

function Hold:draw(b)
    local lg = love.graphics
    local W = 320
    local x0, y0 = math.floor(480 - W / 2), 330
    ui.panel.draw(x0 - 16, y0 - 40, W + 32, 88, "small")
    ui.print(self.label, 480, y0 - 32, { font = "small", align = "center", color = "accent" })
    lg.setColor(0.15, 0.1, 0.12, 1)
    lg.rectangle("fill", x0, y0, W, 18)
    lg.setColor(0.45, 1, 0.45, 1)
    lg.rectangle("fill", x0 + W * self.lo, y0, W * (self.hi - self.lo), 18)
    local c = math.min(1, self.charge)
    lg.setColor(1, 0.8 - c * 0.5, 0.3, 0.9)
    lg.rectangle("fill", x0, y0 + 5, W * c, 8)
    lg.setColor(1, 1, 1, 1)
    keyCap(480, y0 + 36, self.action, 1, not self.holding)
end

-- parry -----------------------------------------------------------------------------

local Parry = {}
Parry.__index = Parry

-- opts: target (the defender), windup (seconds until the blow), feint (pause in the middle)
function qte.parry(opts)
    local q = setmetatable({ t = 0, kind = "parry" }, Parry)
    q.target = opts.target
    q.windup = opts.windup or 0.6
    q.feint = opts.feint
    q.impact = q.windup + (q.feint or 0)
    q.perfect, q.good, q.dodge = 0.075 * timing(), 0.17 * timing(), 0.14 * timing()
    return q
end

-- the ring size: closes during the windup, stops for the feint
function Parry:ringK()
    local t = self.t
    if self.feint then
        local half = self.windup * 0.55
        if t < half then
            return 1 - t / self.windup
        elseif t < half + self.feint then
            return 1 - half / self.windup
        end
        t = t - self.feint
    end
    return math.max(0, 1 - t / self.windup)
end

function Parry:update(dt)
    self.t = self.t + dt
    local diff = self.t - self.impact
    if auto() and diff >= 0 then
        self.result = "parry"
        return true
    end
    if not self.locked then
        if input.pressed("parry") then
            input.consume("parry")
            input.consume("attack")
            input.consume("confirm")
            local d = math.abs(diff)
            if d <= self.perfect then
                self.result = "parry"
                return true
            elseif d <= self.good then
                self.result = "block"
                return true
            end
            self.locked = diff < 0 and "early" or "late"
        elseif input.pressed("dodge") then
            input.consume("dodge")
            if math.abs(diff) <= self.dodge then
                self.result = "dodge"
                return true
            end
            self.locked = diff < 0 and "early" or "late"
        end
    end
    if diff > self.good then
        self.result = self.locked or "none"
        return true
    end
    return false
end

function Parry:draw(b)
    local lg = love.graphics
    local x, y, s = unitPoint(b, self.target)
    local r0 = 22 * s
    local r = r0 + self:ringK() * 95
    lg.setLineWidth(3)
    lg.setColor(1, 1, 1, 0.5)
    lg.circle("line", x, y, r0)
    if self.locked then
        lg.setColor(0.5, 0.5, 0.5, 0.8)
    else
        lg.setColor(1, 0.3, 0.25, 0.95)
    end
    lg.circle("line", x, y, r)
    lg.setLineWidth(1)
    if self.locked then
        ui.print(self.locked == "early" and "Рано!" or "Поздно!", x, y - r0 - 44, { font = "small", align = "center", color = "faded" })
    else
        keyCap(x, y - r0 - 32, "parry", 1, math.abs(self.t - self.impact) <= self.good)
    end
end

return qte
