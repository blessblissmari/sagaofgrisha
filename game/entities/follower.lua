-- A pet walking behind the hero in the top-down world. It follows the
-- hero's breadcrumb trail (engine/followers.lua), so it never cuts corners
-- through water or walls, sits down when the hero stands still and snores
-- after a while.

local Entity = require("engine.entity")
local anim = require("engine.anim")
local audio = require("engine.audio")
local class = require("engine.class")
local util = require("engine.util")

local Follower = class(Entity)

local function G()
    return require("game")
end

function Follower:init(id, x, y, trail, index)
    Entity.init(self, x, y)
    local def = G().pets[id] or {}
    self.petId, self.def = id, def
    self.sprite = anim.new(G().sprite(def.sprite or id))
    self.scale = def.scale
    self.trail, self.index = trail, index
    self.spacing = def.spacing or 26
    self.solid = false
    self.w, self.h = 10, 6
    self.shadow = def.flying and 6 or 8
    self.facing = "down"
    self.idleTime = 0
    self.stepTimer = 0
    self.lastX, self.lastY = x, y
    self.time = love.math.random() * 5
end

function Follower:update(dt)
    Entity.update(self, dt)
    self.time = self.time + dt
    local tx, ty = self.trail:at(self.spacing * self.index)
    local moving = false
    if tx then
        local d = util.distance(self.x, self.y, tx, ty)
        if d > 160 then
            self.x, self.y = tx, ty -- left far behind: catch up at once
        elseif d > 0.5 then
            local speed = math.max(60, d * 7)
            local step = math.min(d, speed * dt)
            local nx, ny = (tx - self.x) / d, (ty - self.y) / d
            self.x, self.y = self.x + nx * step, self.y + ny * step
            moving = step > 0.3
            if math.abs(nx) > math.abs(ny) then
                self.facing = nx > 0 and "right" or "left"
            else
                self.facing = ny > 0 and "down" or "up"
            end
        end
    end
    if moving then
        self.idleTime = 0
        self.sprite:play("walk", self.facing)
        self.stepTimer = self.stepTimer + dt
        if self.stepTimer > 0.28 and self.def.steps then
            self.stepTimer = 0
            local s = G().surfaces[self.def.steps]
            if s then
                audio.step(s.folder, { volume = s.volume })
            end
        end
    else
        self.idleTime = self.idleTime + dt
        if self.idleTime > 2.5 and self.sprite:has("sit") then
            self.sprite:play("sit")
        else
            self.sprite:play("idle", self.facing)
        end
        if self.def.snore and self.idleTime > 14 then
            self.idleTime = 2.6
            audio.play("snore", { volume = 0.5 })
            if self.world and self.world.fx then
                self.world.fx:popup(self.x, self.y - 36, "z", { color = { 0.9, 0.9, 1 }, vy = -18, life = 1.4 })
            end
        end
    end
    self.sprite:update(dt)
end

function Follower:draw()
    local flip = false
    if not self.sprite:has("walk", "left") and self.facing == "right" then
        flip = (self.sprite.def.facesLeft == true)
    elseif not self.sprite:has("walk", "left") and self.facing == "left" then
        flip = not (self.sprite.def.facesLeft == true)
    end
    if self.def.flying then
        self.z = 6 + math.sin(self.time * 3) * 3
    end
    self:drawSprite({ flip = flip, scale = self.scale })
end

return Follower
