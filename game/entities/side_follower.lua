-- A pet in side view (platformer). It replays the hero's path a little later
-- (engine/followers.lua), so it jumps exactly where the hero jumped.
-- Size: pet field sideScale (game/data/pets.lua).

local Follower = require("game.entities.follower")
local audio = require("engine.audio")
local class = require("engine.class")
local util = require("engine.util")

local function G()
    return require("game")
end

local SideFollower = class(Follower)

function SideFollower:init(id, x, y, trail, index)
    Follower.init(self, id, x, y, trail, index)
    self.scale = self.def.sideScale or 1
    self.shadow = false
    self.reflect = false
    self.facing = "right"
    self.spacing = self.def.sideSpacing or 18
end

function SideFollower:update(dt)
    self.flash = math.max(0, self.flash - dt)
    self.time = self.time + dt
    local tx, ty = self.trail:at(self.spacing * self.index)
    local moving = false
    if tx then
        local d = util.distance(self.x, self.y, tx, ty)
        if d > 120 then
            self.x, self.y = tx, ty
        elseif d > 0.3 then
            local step = math.min(d, math.max(60, d * 8) * dt)
            local dx = (tx - self.x) / d
            self.x, self.y = self.x + dx * step, self.y + (ty - self.y) / d * step
            if math.abs(dx) > 0.2 then
                self.facing = dx > 0 and "right" or "left"
                moving = true
            end
        end
    end
    if moving then
        self.idleTime = 0
        self.sprite:play("walk", self.facing)
        self.stepTimer = self.stepTimer + dt
        if self.stepTimer > 0.3 and self.def.steps and not self.def.flying then
            self.stepTimer = 0
            local s = G().surfaces[self.def.steps]
            if s then
                audio.step(s.folder, { volume = s.volume * 0.7 })
            end
        end
    else
        self.idleTime = self.idleTime + dt
        if self.idleTime > 2.5 and self.sprite:has("sit") then
            self.sprite:play("sit")
        else
            self.sprite:play("idle", self.facing)
        end
    end
    self.sprite:update(dt)
end

function SideFollower:draw()
    local flip = false
    if not self.sprite:has("walk", "left") then
        local facesLeft = self.sprite.def.facesLeft == true
        flip = (self.facing == "right") == facesLeft
    end
    if self.def.flying then
        self.z = 4 + math.sin(self.time * 3) * 2
    end
    self:drawSprite({ flip = flip, scale = self.scale })
end

return SideFollower
