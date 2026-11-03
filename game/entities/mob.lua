-- An enemy in the world. What it is (looks, speed, damage, drops) comes
-- from game/data/mobs.lua, so a new enemy is just a new entry there and a
-- point in the "Mobs" layer of the map (property mob = "blob_red").
--
-- Behaviour: wanders around its spawn point, chases the player when he is
-- close, hurts him on touch. Mobs with world.touch = "battle" start a
-- turn-based battle instead (the scene decides what happens, see onTouch).

local Entity = require("engine.entity")
local anim = require("engine.anim")
local audio = require("engine.audio")
local class = require("engine.class")
local util = require("engine.util")

local function G()
    return require("game")
end

local Mob = class(Entity)

function Mob:init(kind, x, y, objectId)
    Entity.init(self, x, y)
    local def = assert(G().mobs[kind], "unknown mob: " .. tostring(kind))
    self.kind, self.def = kind, def
    self.objectId = objectId
    local sprite = G().sprite(def.sprite or kind)
    self.sprite = anim.new(sprite)
    self.facesLeft = def.facesLeft or sprite.facesLeft
    local w = def
    self.hp = w.hp or 3
    self.maxHp = self.hp
    self.speed = w.speed or 30
    self.chaseSpeed = w.chaseSpeed or 60
    self.sight = w.sight or 120
    self.damage = w.damage or 1
    self.touch = w.touch
    self.team = "enemy"
    self.w, self.h = 16, 8
    self.height = 26
    self.shadow = 9
    self.iframes = 0.35
    self.homeX, self.homeY = x, y
    self.mode = "wander"
    self.timer = love.math.random() * 2
    self.dirX, self.dirY = 0, 0
    self.hop = 0
    self.stunned = 0
end

function Mob:startChase()
    self.mode = "chase"
    if self.def.taunt then
        audio.play(self.def.taunt, { volume = 0.5 })
    end
    if self.world then
        self.world.fx:popup(self.x, self.y - 40, "!", { color = { 1, 0.85, 0.3 }, vy = -50, life = 0.7 })
    end
end

function Mob:update(dt)
    Entity.update(self, dt)
    self.sprite:update(dt)
    if self.dying then
        self.dying = self.dying - dt
        if self.dying <= 0 then
            self:remove()
        end
        return
    end
    self.stunned = math.max(0, self.stunned - dt)
    local player = self.world.player
    local d = player and self:distanceTo(player) or math.huge
    local canSee = player and not player.dying and d < self.sight and self.stunned <= 0
        and self.world:lineOfSight(self.x, self.y - 4, player.x, player.y - 4)

    local mx, my, speed = 0, 0, 0
    if canSee then
        if self.mode ~= "chase" then
            self:startChase()
        end
        mx, my = util.normalize(player.x - self.x, player.y - self.y)
        speed = self.chaseSpeed
    else
        if self.mode == "chase" then
            self.mode = "wander"
            self.timer = 0
        end
        self.timer = self.timer - dt
        if self.timer <= 0 then
            self.timer = 1 + love.math.random() * 2
            if love.math.random() < 0.35 then
                self.dirX, self.dirY = 0, 0
            else
                local a = love.math.random() * math.pi * 2
                self.dirX, self.dirY = math.cos(a), math.sin(a)
                -- do not walk too far from home
                if util.distance(self.x, self.y, self.homeX, self.homeY) > 70 then
                    self.dirX, self.dirY = util.normalize(self.homeX - self.x, self.homeY - self.y)
                end
            end
        end
        mx, my, speed = self.dirX, self.dirY, self.speed
    end
    if self.vx ~= 0 or self.vy ~= 0 or self.stunned > 0 then
        speed = 0 -- flying back after a hit
    end
    if speed > 0 and (mx ~= 0 or my ~= 0) then
        local hitX, hitY = self:moveBy(mx * speed * dt, my * speed * dt)
        if (hitX or hitY) and self.mode == "wander" then
            self.timer = 0 -- bumped into a wall: choose another way
        end
        if mx ~= 0 then
            self.flipX = (mx > 0) == (self.facesLeft == true)
        end
        self.hop = self.hop + dt * 9
        self.sprite:play("walk")
    else
        self.sprite:play("idle")
    end
    if self.flash > 0 then
        self.sprite:play("hurt")
    end

    -- touching the player
    if player and not player.dying and self.stunned <= 0 then
        local px, py, pw, ph = player:getBox()
        local x, y, w, h = self:getBox()
        if util.overlaps(px - 2, py - 2, pw + 4, ph + 4, x, y, w, h) then
            self:onTouch(player)
        end
    end
end

function Mob:onTouch(player)
    if self.touch == "battle" then
        if self.world.scene and self.world.scene.startBattle then
            self.world.scene:startBattle(self)
        end
        return
    end
    if player:hurt(self.damage, { from = self, knockback = 260 }) then
        self.sprite:play("attack", nil, true)
        self.stunned = 0.4
    end
end

function Mob:onHurt(amount, opts)
    if self.touch == "battle" then
        -- hitting the blue blob starts the battle with the first move for the party
        self.hp = self.maxHp
        if self.world.scene and self.world.scene.startBattle then
            self.world.scene:startBattle(self, { advantage = true })
        end
        return
    end
    audio.play("hit")
    self.stunned = 0.3
    self.world.fx:popup(self.x, self.y - 34, "-" .. amount, { color = { 1, 0.9, 0.4 } })
end

function Mob:onDeath()
    self.dying = 0.45
    self.team = nil
    self.sprite:play("dead")
    audio.play("pop")
    self.world.fx:burst(self.x, self.y - 8, { count = 14, color = { 0.95, 0.35, 0.3 }, speed = 90, life = 0.5, size = 3 })
    if self.world.scene and self.world.scene.onMobKilled then
        self.world.scene:onMobKilled(self)
    end
end

function Mob:draw()
    local bounce = 0
    if self.sprite.name == "walk" then
        bounce = math.abs(math.sin(self.hop)) * 2
    end
    local alpha = self.dying and math.max(0, self.dying / 0.45) or 1
    self.z = bounce
    self:drawSprite({ flip = self.flipX, color = alpha < 1 and { 1, 1, 1, alpha } or nil })
end

return Mob
