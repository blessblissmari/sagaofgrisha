-- A dice check over the story (like Disco Elysium / Baldur's Gate 3): two dice + the talent
-- against the difficulty. Two sixes always win, two ones always lose.
--   local ok, sum = s:check("wits", 8, "Найти тайник")      -- game/director.lua
--   s:ask("...", { { "Перепрыгнуть", check = { "agility", 9 } } })   -- a check in an answer
-- Talents: game/data/talents.lua. Dice: "32x32 pixel d6 dice roll & results" by adhochero (CC0).

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui

local Check = class()
Check.transparent = true

local ROLL = 1.1 -- seconds the dice tumble

-- chance in % to reach the difficulty with this talent
function Check.chance(value, dc)
    local n = 0
    for a = 1, 6 do
        for b = 1, 6 do
            if (a == 6 and b == 6) or (not (a == 1 and b == 1) and a + b + value >= dc) then
                n = n + 1
            end
        end
    end
    return math.floor(n * 100 / 36 + 0.5)
end

-- opts: talent, dc, label; onDone(ok, sum)
function Check:init(opts, onDone)
    local g = require("game")
    local info = g.talents[opts.talent]
    self.name = info and info.name or tostring(opts.talent)
    self.value = g.state.talents[opts.talent] or 0
    self.dc = opts.dc or 7
    self.label = opts.label
    self.onDone = onDone
    self.d1, self.d2 = love.math.random(1, 6), love.math.random(1, 6)
    self.sum = self.d1 + self.d2 + self.value
    if self.d1 == 6 and self.d2 == 6 then
        self.crit = "win"
    elseif self.d1 == 1 and self.d2 == 1 then
        self.crit = "fail"
    end
    self.ok = self.crit == "win" or (self.crit == nil and self.sum >= self.dc)
    self.chance = Check.chance(self.value, self.dc)
    self.time = 0
    self.faces = assets.image("assets/sprites/arcade/dice_faces.png")
    self.rolls = assets.image("assets/sprites/arcade/dice_roll.png")
    self.faceQuads, self.rollQuads = {}, {}
    for f = 1, 6 do
        self.faceQuads[f] = assets.quad(self.faces, 32, (f - 1) * 32, 32, 32)
    end
    for i = 0, 9 do
        self.rollQuads[i + 1] = assets.quad(self.rolls, (i % 2) * 32, math.floor(i / 2) * 32, 32, 32)
    end
end

function Check:enter()
    audio.play("die_shuffle")
end

function Check:land()
    if self.landed then
        return
    end
    self.landed = true
    self.time = math.max(self.time, ROLL)
    audio.play("die_throw")
end

function Check:close()
    if self.closed then
        return
    end
    self.closed = true
    if scene.top() == self then
        scene.pop()
    end
    if self.onDone then
        self.onDone(self.ok, self.sum)
    end
end

function Check:update(dt)
    self.time = self.time + dt
    if not self.landed and self.time >= ROLL then
        self:land()
    end
    if self.landed and not self.told and self.time >= ROLL + 0.3 then
        self.told = true
        audio.play(self.ok and "bonus" or "ui_error")
    end
    local pressed = input.pressed("confirm") or input.pressed("interact") or input.pressed("cancel")
        or input.mouse.pressed[1]
    if pressed then
        input.consume("confirm")
        input.consume("interact")
        input.consume("cancel")
        input.mouse.pressed[1] = nil
        if not self.landed then
            self:land()
        elseif self.time > ROLL + 0.4 then
            self:close()
        end
    end
end

function Check:draw()
    local lg = love.graphics
    ui.dim(0.5)
    local w, h = 470, 336
    local x, y = math.floor((screen.width - w) / 2), math.floor((screen.height - h) / 2)
    ui.panel.draw(x, y, w, h)
    local cx = screen.width / 2
    ui.print(self.name, cx, y + 22, { font = "title", align = "center", color = "accent" })
    local ty = y + 66
    if self.label then
        ui.print(self.label, cx, ty, { font = "body", align = "center" })
        ty = ty + 34
    end
    ui.print("Сложность " .. self.dc .. "   ·   шанс " .. self.chance .. "%", cx, ty,
        { font = "small", align = "center", color = "faded" })
    -- the dice: they tumble and hop, then lie still
    local s = 3
    local size = 32 * s
    local dyBase = y + 140
    for i, d in ipairs({ self.d1, self.d2 }) do
        local dx = cx + (i == 1 and -size - 16 or 16)
        local dy = dyBase
        lg.setColor(1, 1, 1, 1)
        if self.landed then
            lg.draw(self.faces, self.faceQuads[d], math.floor(dx), math.floor(dy), 0, s, s)
        else
            local k = math.min(1, self.time / ROLL)
            local frame = math.floor(self.time / 0.06 + i * 3) % 10 + 1
            dy = dy - math.abs(math.sin(self.time * 9 + i * 1.3)) * 30 * (1 - k)
            dx = dx + math.sin(self.time * 13 + i * 2) * 8 * (1 - k)
            lg.draw(self.rolls, self.rollQuads[frame], math.floor(dx), math.floor(dy), 0, s, s)
        end
    end
    if self.landed then
        local a = math.min(1, (self.time - ROLL) * 4)
        local sum = self.d1 .. " + " .. self.d2
        if self.value ~= 0 then
            sum = sum .. (self.value > 0 and " + " or " - ") .. math.abs(self.value) .. " (" .. self.name .. ")"
        end
        sum = sum .. " = " .. self.sum
        ui.print(sum, cx, dyBase + size + 12, { font = "body", align = "center", alpha = a })
        local result = self.ok and "Успех!" or "Провал"
        if self.crit == "win" then
            result = "Две шестёрки — успех!"
        elseif self.crit == "fail" then
            result = "Две единицы — провал"
        end
        ui.print(result, cx, dyBase + size + 48, { font = "body", align = "center", color = self.ok and "green" or "red", alpha = a })
        if self.time > ROLL + 0.4 then
            ui.keyHint(cx, y + h + 10, "confirm", "Дальше")
        end
    end
    lg.setColor(1, 1, 1, 1)
end

return Check
