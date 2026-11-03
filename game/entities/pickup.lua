-- An item lying on the ground. Map items come from the "Items" layer
-- (point with property item = "carrot", optional count, optional pickup = "auto"|"press").
-- Two kinds (game.pickupMode): "auto" items are picked up by touch and fly to the
-- hero when he comes close (coins, food); "press" items wait for the interact key.

local Entity = require("engine.entity")
local assets = require("engine.assets")
local audio = require("engine.audio")
local class = require("engine.class")
local ui = require("engine.ui")

local function G()
    return require("game")
end

local Pickup = class(Entity)

-- opts: count, objectId, auto (pick up on touch), pop (jumps out of a mob),
--       scale (icon size, default 0.5)
function Pickup:init(item, x, y, opts)
    Entity.init(self, x, y)
    opts = opts or {}
    self.item = item
    self.def = G().items[item] or { name = item, icon = "coin" }
    self.count = opts.count or 1
    self.objectId = opts.objectId
    self.auto = opts.auto
    self.icon = assets.image("assets/sprites/icons/" .. self.def.icon .. ".png", { filter = "linear" })
    self.iconScale = opts.scale or 0.5
    self.w, self.h = 16, 12
    self.solid = false
    self.reflect = false
    self.shadow = 6
    self.time = love.math.random() * 6
    self.z, self.vz = 0, 0
    self.pickable = true
    if opts.pop then
        self.vz = 110
        local a = love.math.random() * math.pi * 2
        self.vx, self.vy = math.cos(a) * 50, math.sin(a) * 30
        self.friction = 4
        self.delay = 0.5 -- cannot be picked up while flying
    end
end

function Pickup:update(dt)
    Entity.update(self, dt)
    self.time = self.time + dt
    if self.vz ~= 0 or self.z > 0 then
        self.vz = self.vz - 400 * dt
        self.z = self.z + self.vz * dt
        if self.z <= 0 then
            self.z = 0
            self.vz = self.vz < -60 and -self.vz * 0.35 or 0
        end
    end
    if self.delay then
        self.delay = self.delay - dt
        if self.delay <= 0 then
            self.delay = nil
        end
    elseif self.auto then
        local player = self.world.player
        if player and not player.dying then
            local d = self:distanceTo(player)
            if d < 16 then
                self:collect(player)
            elseif d < (self.magnet or 44) and self.z <= 0 then
                -- the magnet: closer = faster, like in Stardew Valley
                local k = math.min(1, dt * (6 + (44 - d) * 0.25))
                self.x = self.x + (player.x - self.x) * k
                self.y = self.y + (player.y - 4 - self.y) * k
            end
        end
    end
end

function Pickup:collect(player)
    local st = G().state
    if self.def.ability then
        st.abilities[self.def.ability] = true
        audio.play("powerup")
        ui.toast("Новая способность: " .. self.def.name, { icon = self.def.icon, color = { 1, 0.9, 0.4 } })
    elseif not st.inventory:add(self.item, self.count) then
        ui.toast("Сумка полна!")
        audio.play("error")
        return false
    else
        audio.play("pickup")
        local text = self.def.name .. (self.count > 1 and (" x" .. self.count) or "")
        ui.toast("Подобрано: " .. text, { icon = self.def.icon })
    end
    self.world.fx:popup(self.x, self.y - self.icon:getHeight() * self.iconScale - 14, "+" .. self.count, { color = { 1, 0.9, 0.45 } })
    self.world.fx:burst(self.x, self.y - 10, { count = 8, color = { 1, 0.95, 0.6 }, speed = 50, life = 0.4 })
    if self.objectId then
        st.collected[self.objectId] = true
    end
    if self.world.scene and self.world.scene.onPickup then
        self.world.scene:onPickup(self)
    end
    self:remove()
    return true
end

function Pickup:draw()
    local bob = self.z > 0 and 0 or math.sin(self.time * 3) * 2
    local s = self.iconScale
    local w, h = self.icon:getWidth() * s, self.icon:getHeight() * s
    if self.def.ability then
        -- abilities are glowing orbs
        local cx, cy = self.x, self.y - h / 2 - 3 - bob - self.z
        local pulse = 0.5 + 0.5 * math.sin(self.time * 4)
        love.graphics.setBlendMode("add")
        for i = 3, 1, -1 do
            love.graphics.setColor(1, 0.85, 0.35, (0.10 + pulse * 0.08) * (4 - i) / 3)
            love.graphics.circle("fill", cx, cy, w * (0.45 + i * 0.22))
        end
        love.graphics.setBlendMode("alpha")
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.icon, math.floor(self.x - w / 2), math.floor(self.y - h - 3 - bob - self.z), 0, s, s)
    -- a little sparkle now and then
    local t = (self.time * 0.7) % 1
    if t < 0.12 then
        love.graphics.setColor(1, 1, 0.85, 1 - t / 0.12)
        local sx, sy = math.floor(self.x + w / 2 - 2), math.floor(self.y - h - bob - self.z)
        love.graphics.rectangle("fill", sx - 2, sy, 5, 1)
        love.graphics.rectangle("fill", sx, sy - 2, 1, 5)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Pickup
