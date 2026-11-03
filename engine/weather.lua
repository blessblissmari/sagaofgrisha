-- Weather and time of day over any scene (drawn by code):
--   local w = Weather("rain")          -- "rain" | "storm" | "snow" | "leaves" | "fog" | "sparkles" | nil
--   w:setTime("night")                  -- "day" | "morning" | "evening" | "night" | { r, g, b, a }
--   w:update(dt); w:draw(width, height, camX, camY)
-- In stages: weather = "snow", daytime = "evening"; in scripts: s:weather("rain"), s:daytime("night")

local class = require("engine.class")

local Weather = class()

local TINTS = {
    day = nil,
    morning = { 1, 0.85, 0.7, 0.12 },
    evening = { 1, 0.42, 0.15, 0.3 },
    night = { 0.05, 0.08, 0.3, 0.5 },
    dungeon = { 0, 0, 0.05, 0.35 },
}

function Weather:init(kind, opts)
    opts = opts or {}
    self.parts = {}
    self.time = 0
    self.flash = 0
    self.amount = opts.amount or 1
    self:set(kind)
    self:setTime(opts.daytime)
end

function Weather:set(kind)
    self.kind = kind ~= "none" and kind or nil
    self.parts = {}
    local counts = { rain = 160, storm = 260, snow = 130, leaves = 45, fog = 10, sparkles = 40 }
    local n = math.floor((counts[self.kind] or 0) * self.amount)
    for _ = 1, n do
        table.insert(self.parts, self:spawn(true))
    end
end

function Weather:setTime(name)
    self.tint = type(name) == "table" and name or TINTS[name or "day"]
    self.daytime = name
end

function Weather:spawn(anywhere)
    local r = love.math.random
    local p = { x = r() * 1.2 - 0.1, y = anywhere and r() or -0.05, z = 0.4 + r() * 0.6, phase = r() * 6.28 }
    local k = self.kind
    if k == "rain" or k == "storm" then
        p.vy = 1.6 + r() * 0.6
        p.vx = k == "storm" and -0.5 or -0.18
    elseif k == "snow" then
        p.vy = 0.08 + r() * 0.08
        p.vx = -0.02
    elseif k == "leaves" then
        p.vy = 0.1 + r() * 0.06
        p.vx = 0.08
        p.color = ({ { 0.85, 0.45, 0.15 }, { 0.75, 0.6, 0.15 }, { 0.6, 0.3, 0.1 } })[r(1, 3)]
    elseif k == "fog" then
        p.vx = 0.01 + r() * 0.015
        p.vy = 0
        p.y = r()
    elseif k == "sparkles" then
        p.vx, p.vy = 0, -0.02
    end
    return p
end

function Weather:update(dt)
    self.time = self.time + dt
    for i, p in ipairs(self.parts) do
        p.x = p.x + p.vx * dt * p.z
        p.y = p.y + p.vy * dt * p.z
        if p.y > 1.05 or p.x < -0.15 or p.x > 1.15 then
            if self.kind == "fog" then
                p.x = -0.1
            else
                self.parts[i] = self:spawn(false)
            end
        end
    end
    if self.kind == "storm" then
        self.flash = math.max(0, self.flash - dt * 3)
        if love.math.random() < dt * 0.15 then
            self.flash = 1
            local ok, audio = pcall(require, "engine.audio")
            if ok and audio.has and audio.has("thunder") then
                audio.play("thunder")
            end
        end
    end
end

function Weather:draw(w, h, camX, camY)
    local lg = love.graphics
    camX, camY = camX or 0, camY or 0
    if self.tint then
        local t = self.tint
        lg.setColor(t[1], t[2], t[3], t[4] or 0.4)
        lg.rectangle("fill", 0, 0, w, h)
    end
    local k = self.kind
    if k then
        local ox = -(camX * 0.5) % w
        local oy = -(camY * 0.5) % h
        for _, p in ipairs(self.parts) do
            local x = (p.x * w + ox * p.z) % (w * 1.2) - w * 0.1
            local y = (p.y * h + (k == "fog" and 0 or oy * p.z)) % h
            if k == "rain" or k == "storm" then
                lg.setColor(0.7, 0.8, 1, 0.35 * p.z)
                lg.setLineWidth(1 + p.z)
                lg.line(x, y, x + p.vx * 18, y + 18 * p.z)
            elseif k == "snow" then
                lg.setColor(1, 1, 1, 0.5 + 0.5 * p.z)
                local s = 1 + p.z * 2.5
                lg.rectangle("fill", x + math.sin(self.time * 1.5 + p.phase) * 12, y, s, s)
            elseif k == "leaves" then
                local c = p.color
                lg.setColor(c[1], c[2], c[3], 0.9)
                lg.push()
                lg.translate(x + math.sin(self.time * 2 + p.phase) * 20, y)
                lg.rotate(self.time * 2 + p.phase)
                lg.rectangle("fill", -6 * p.z, -3 * p.z, 12 * p.z, 6 * p.z)
                lg.pop()
            elseif k == "fog" then
                lg.setColor(0.85, 0.88, 0.95, 0.07)
                lg.ellipse("fill", x, y, 260 * p.z, 70 * p.z)
            elseif k == "sparkles" then
                local a = (math.sin(self.time * 3 + p.phase) + 1) / 2
                lg.setColor(1, 0.95, 0.6, a * 0.8)
                local s = 1 + a * 2
                lg.rectangle("fill", x - s / 2, y - s / 2, s, s)
            end
        end
        lg.setLineWidth(1)
    end
    if self.flash > 0 then
        lg.setColor(1, 1, 1, self.flash * 0.6)
        lg.rectangle("fill", 0, 0, w, h)
    end
    lg.setColor(1, 1, 1, 1)
end

return Weather
