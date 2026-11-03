-- 2D camera: follows a point, stays inside the map, zooms and shakes.
--
--   local cam = Camera(screen.width, screen.height)
--   cam:setBounds(0, 0, mapWidth, mapHeight)
--   cam:follow(player.x, player.y, dt)    -- smooth
--   cam:shake(4, 0.3)
--   cam:attach() ... draw the world ... cam:detach()
--   local wx, wy = cam:toWorld(mouseX, mouseY)

local class = require("engine.class")
local util = require("engine.util")

local Camera = class()

function Camera:init(width, height)
    self.width, self.height = width, height
    self.x, self.y = 0, 0 -- world point in the center of the screen
    self.zoom = 1
    self.bounds = nil
    self.shakeAmount, self.shakeTime, self.shakeDuration = 0, 0, 0
    self.offsetX, self.offsetY = 0, 0
end

function Camera:setBounds(x, y, w, h)
    self.bounds = x and { x = x, y = y, w = w, h = h } or nil
    self:clamp()
end

function Camera:clamp()
    local b = self.bounds
    if not b then
        return
    end
    local halfW, halfH = self.width / 2 / self.zoom, self.height / 2 / self.zoom
    if b.w <= halfW * 2 then
        self.x = b.x + b.w / 2
    else
        self.x = util.clamp(self.x, b.x + halfW, b.x + b.w - halfW)
    end
    if b.h <= halfH * 2 then
        self.y = b.y + b.h / 2
    else
        self.y = util.clamp(self.y, b.y + halfH, b.y + b.h - halfH)
    end
end

function Camera:lookAt(x, y)
    self.x, self.y = x, y
    self:clamp()
end

-- speed: ~10 snappy, ~3 lazy
function Camera:follow(x, y, dt, speed)
    self.x = util.damp(self.x, x, speed or 6, dt)
    self.y = util.damp(self.y, y, speed or 6, dt)
    self:clamp()
end

function Camera:shake(amount, duration)
    if amount >= self.shakeAmount * (self.shakeTime / math.max(self.shakeDuration, 1e-6)) then
        self.shakeAmount, self.shakeTime, self.shakeDuration = amount, duration, duration
    end
end

function Camera:update(dt)
    if self.shakeTime > 0 then
        self.shakeTime = math.max(0, self.shakeTime - dt)
        local power = self.shakeAmount * self.shakeTime / self.shakeDuration
        self.offsetX = (love.math.random() * 2 - 1) * power
        self.offsetY = (love.math.random() * 2 - 1) * power
    else
        self.offsetX, self.offsetY = 0, 0
    end
end

-- World coordinates of the top left screen corner, snapped to screen pixels
-- so pixel art never shimmers.
function Camera:getTopLeft()
    local z = self.zoom
    local left = self.x + self.offsetX - self.width / 2 / z
    local top = self.y + self.offsetY - self.height / 2 / z
    return math.floor(left * z + 0.5) / z, math.floor(top * z + 0.5) / z
end

function Camera:getVisible()
    local left, top = self:getTopLeft()
    return left, top, self.width / self.zoom, self.height / self.zoom
end

function Camera:attach()
    local left, top = self:getTopLeft()
    love.graphics.push()
    love.graphics.scale(self.zoom)
    love.graphics.translate(-left, -top)
end

function Camera:detach()
    love.graphics.pop()
end

function Camera:toWorld(sx, sy)
    local left, top = self:getTopLeft()
    return sx / self.zoom + left, sy / self.zoom + top
end

function Camera:toScreen(wx, wy)
    local left, top = self:getTopLeft()
    return (wx - left) * self.zoom, (wy - top) * self.zoom
end

return Camera
