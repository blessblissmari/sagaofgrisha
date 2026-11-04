-- Actors of the isometric mode (game/modes/iso.lua): the hero, the pet, enemies,
-- flying things, loot and people.
--
-- Positions are iso points: x along the map columns, y along the rows, 16 per tile
-- (the same numbers as point objects in an isometric Tiled map); z = height in
-- levels (a block is 1). The mode keeps them in mode.actors and the map draws
-- them between the tiles.

local engine = require("engine")
local anim = engine.anim
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local shaders = engine.shaders
local util = engine.util

local function G()
    return require("game")
end

local iso = {}

local GRAVITY = 30 -- levels / s^2

-- facing: "se" "sw" "ne" "nw" (screen directions); iso vectors of them
iso.FACE = { se = { 1, 0 }, sw = { 0, 1 }, ne = { 0, -1 }, nw = { -1, 0 } }

-- facing from an iso direction (keeps the old half when the move is straight up/down/left/right)
function iso.faceOf(dx, dy, current)
    local sx, sy = dx - dy, dx + dy
    current = current or "se"
    local ew = sx > 0.05 and "e" or (sx < -0.05 and "w" or current:sub(2, 2))
    local ns = sy > 0.05 and "s" or (sy < -0.05 and "n" or current:sub(1, 1))
    return ns .. ew
end

-- screen input (right, down) -> iso direction
function iso.fromScreen(dx, dy)
    return dx + dy, dy - dx
end

local function norm(x, y)
    local d = math.sqrt(x * x + y * y)
    if d < 1e-6 then
        return 0, 0, 0
    end
    return x / d, y / d, d
end
iso.norm = norm

-- the actor base ------------------------------------------------------------------------

local Actor = class()
iso.Actor = Actor

function Actor:init(mode, x, y)
    self.mode, self.map = mode, mode.map
    self.x, self.y = x, y
    self.z = self.map:groundAt(x, y) or 0
    self.vz = 0
    self.radius = 4
    self.vx, self.vy = 0, 0 -- knockback (iso px / s)
    self.flash, self.invulnerable, self.dodge = 0, 0, 0
    self.facing = "se"
    self.flip = false
    self.shadowSize = 6
    self.height = 26 -- pixels: where effects and emotes go
    self.time = love.math.random() * 10
    self.removed = false
    self.alpha = 1
end

function Actor:remove()
    self.removed = true
end

function Actor:getBox()
    return self.x - self.radius, self.y - self.radius, self.radius * 2, self.radius * 2
end

function Actor:distanceTo(o)
    return math.sqrt((o.x - self.x) ^ 2 + (o.y - self.y) ^ 2)
end

function Actor:ground()
    return self.map:groundAt(self.x, self.y) or self.z
end

-- screen point of the feet (map pixels)
function Actor:screen()
    return self.map:project(self.x, self.y, self.z)
end

-- screen point of the head (emotes, numbers)
function Actor:head()
    local sx, sy = self.map:project(self.x, self.y, self.z)
    return sx, sy - self.height
end

function Actor:move(dx, dy)
    return self.map:move(self, dx, dy, self.moveOpts)
end

function Actor:push(dx, dy, strength)
    local nx, ny = norm(dx, dy)
    self.vx, self.vy = nx * strength, ny * strength
end

-- knockback, falling, ramps
function Actor:physics(dt)
    if self.vx ~= 0 or self.vy ~= 0 then
        self:move(self.vx * dt, self.vy * dt)
        local k = math.exp(-9 * dt)
        self.vx, self.vy = self.vx * k, self.vy * k
        if math.abs(self.vx) + math.abs(self.vy) < 3 then
            self.vx, self.vy = 0, 0
        end
    end
    local g = self.map:groundAt(self.x, self.y)
    if not g then
        return
    end
    if self.vz ~= 0 or self.z > g + 0.3 then
        self.vz = self.vz - GRAVITY * dt
        self.z = self.z + self.vz * dt
        if self.z <= g then
            local speed = -self.vz
            self.z, self.vz = g, 0
            self:landed(speed)
        end
    else
        self.z = g -- walk up steps and down ramps
    end
end

function Actor:landed(speed) end

-- jumps from here to (tx, ty) in `time` seconds (cutscenes, battle start)
function Actor:hopTo(tx, ty, time, height)
    self.hopping = { x0 = self.x, y0 = self.y, z0 = self.z, x1 = tx, y1 = ty,
        z1 = self.map:groundAt(tx, ty) or self.z, t = 0, time = time or 0.4, h = height or 1 }
    self.facing = iso.faceOf(tx - self.x, ty - self.y, self.facing)
end

function Actor:updateHop(dt)
    local h = self.hopping
    h.t = h.t + dt
    local k = math.min(1, h.t / h.time)
    self.x, self.y = util.lerp(h.x0, h.x1, k), util.lerp(h.y0, h.y1, k)
    self.z = util.lerp(h.z0, h.z1, k) + h.h * 4 * k * (1 - k)
    if k >= 1 then
        self.hopping = nil
        self.z = h.z1
        self:landed(3)
        return true
    end
    return false
end

-- plays name.se / name.ne (mirrored for the west), or a plain animation
function Actor:play(name, restart)
    local s = self.sprite
    local half = self.facing:sub(1, 1) == "s" and "se" or "ne"
    local west = self.facing:sub(2, 2) == "w"
    if s:has(name, half) then
        s:play(name, half, restart)
        self.flip = west
    else
        if s:has(name) then
            s:play(name, nil, restart)
        elseif s:has("idle", half) then
            s:play("idle", half, restart)
        else
            s:play("idle", nil, restart)
        end
        self.flip = west ~= (s.def.facesLeft == true)
        if s:has("idle", half) then
            self.flip = west
        end
    end
end

function Actor:drawShadow()
    if not self.shadowSize then
        return
    end
    local g = self:ground()
    local sx, sy = self.map:project(self.x, self.y, g)
    local k = math.max(0.4, 1 - (self.z - g) * 0.35)
    love.graphics.setColor(0, 0, 0, 0.3 * self.alpha)
    love.graphics.ellipse("fill", math.floor(sx + 0.5), math.floor(sy + 0.5), self.shadowSize * k, self.shadowSize * 0.5 * k)
    love.graphics.setColor(1, 1, 1, 1)
end

-- the sprite with the white hit flash and blinking while invulnerable
function Actor:drawSprite(sx, sy, opts)
    opts = opts or {}
    local alpha = self.alpha
    if self.invulnerable > 0 and self.flash <= 0 and math.floor(self.invulnerable * 16) % 2 == 0 then
        alpha = alpha * 0.4
    end
    local tint = self.tint or { 1, 1, 1 }
    opts.color = { tint[1], tint[2], tint[3], alpha }
    opts.flip = self.flip
    opts.scale = opts.scale or self.scale
    local flash = (self.flash > 0 or self.glow) and shaders.get("flash")
    if flash then
        shaders.send(flash, "amount", self.flash > 0 and 1 or self.glow)
        shaders.send(flash, "flashColor", self.flash > 0 and { 1, 1, 1 } or (self.glowColor or { 1, 0.3, 0.2 }))
        love.graphics.setShader(flash)
    end
    self.sprite:draw(sx, sy, opts)
    if flash then
        love.graphics.setShader()
    end
end

function Actor:draw()
    self:drawShadow()
    local sx, sy = self:screen()
    self:drawSprite(sx, sy)
end

function Actor:updateTimers(dt)
    self.time = self.time + dt
    self.flash = math.max(0, self.flash - dt)
    self.invulnerable = math.max(0, self.invulnerable - dt)
    self.dodge = math.max(0, (self.dodge or 0) - dt)
end

-- weapons in the hero's hands -----------------------------------------------------------------

-- rows of assets/sprites/iso/weapons.png (Tiny Tactics weapons, 48x48 frames)
iso.WEAPON_ROWS = { WoodenSword = 0, IronSword = 2, Hatchet = 4, IronAxe = 6, WoodenStaff = 8, Scepter = 10 }
-- item -> picture of the weapon (items can say iso = "Hatchet")
iso.WEAPON_LOOK = { sword = "IronSword", knight_sword = "IronSword", dagger = "WoodenSword", stick = "WoodenStaff",
    axe = "IronAxe", spear = "WoodenStaff", club = "Scepter" }

local weaponQuads = {}
local function weaponQuad(row, frame)
    local key = row * 8 + frame
    if not weaponQuads[key] then
        local image = assets.image("assets/sprites/iso/weapons.png")
        weaponQuads[key] = love.graphics.newQuad((frame - 1) * 48, row * 48, 48, 48, image:getDimensions())
    end
    return weaponQuads[key]
end

-- the hero -------------------------------------------------------------------------------

local Hero = class(Actor)
iso.Hero = Hero

function Hero:init(mode, x, y, spriteName)
    Actor.init(self, mode, x, y)
    self.sprite = anim.new(G().sprite(spriteName or G().player.iso or "grisha_iso"))
    self.speed = 58
    self.state = "move"
    self.aimX, self.aimY = 1, 0
    self.combo, self.queued = 0, false
    self.t = 0
    self.rollCooldown = 0
    self.ghosts = {}
    self.stepTimer = 0
    self.team = "hero"
    self.isHero = true
    self:refreshWeapon()
end

function Hero:refreshWeapon()
    local info, id = G().weapon()
    self.weaponId, self.weaponInfo = id, info
    local look = info.iso or iso.WEAPON_LOOK[id]
    self.weaponRow = look and iso.WEAPON_ROWS[look]
    self.reach = 9 + (info.reach or 14) * 0.45
    self.power = info.power or 1
    self.maxCombo = math.min(3, info.combo or 3)
end

function Hero:busy()
    return self.state ~= "move"
end

-- input from the mode: ix, iy = iso direction (not normalized), actions = { attack = true, ... }
function Hero:control(dt, ix, iy, actions)
    local nx, ny, len = norm(ix, iy)
    if len > 0 then
        self.aimX, self.aimY = nx, ny
    end
    self.rollCooldown = math.max(0, self.rollCooldown - dt)
    if self.state == "dead" then
        return
    end
    if self.state == "move" then
        if len > 0 then
            self:move(nx * self.speed * dt, ny * self.speed * dt)
            self.facing = iso.faceOf(nx, ny, self.facing)
            self:play("walk")
            self.stepTimer = self.stepTimer + dt
            if self.stepTimer > 0.3 then
                self.stepTimer = 0
                self.mode:footstep(self)
            end
        else
            self:play("idle")
        end
        if actions.attack then
            self:startAttack(1, len > 0)
        elseif actions.dash and self.rollCooldown <= 0 then
            self:startRoll(len > 0 and nx or self.aimX, len > 0 and ny or self.aimY)
        elseif actions.throw then
            self:throw()
        end
    elseif self.state == "attack" then
        self.t = self.t + dt
        local lunge = self.combo == 3 and 70 or 40
        if self.t < 0.1 then
            self:move(self.atkX * lunge * dt, self.atkY * lunge * dt)
        end
        if actions.attack and self.t > 0.08 then
            self.queued = true
        end
        if not self.struck and self.t >= 0.11 then
            self.struck = true
            self.mode:heroStrike(self, self.combo)
        end
        if actions.dash and self.struck and self.rollCooldown <= 0 then
            self:startRoll(len > 0 and nx or self.atkX, len > 0 and ny or self.atkY)
        elseif self.t >= 0.27 then
            if self.queued and self.combo < self.maxCombo then
                if len > 0 then
                    self.aimX, self.aimY = nx, ny
                end
                self:startAttack(self.combo + 1, len > 0)
            elseif self.t >= (self.combo == self.maxCombo and 0.42 or 0.3) then
                self.state = "move"
            end
        end
    elseif self.state == "roll" then
        self.t = self.t + dt
        self:move(self.rollX * 170 * dt, self.rollY * 170 * dt)
        if math.floor(self.t * 60) % 2 == 0 then
            table.insert(self.ghosts, { x = self.x, y = self.y, z = self.z, life = 0.18, flip = self.flip,
                quad = self.sprite:getQuad() })
        end
        if self.t >= 0.2 then
            self.state = "move"
            self.rollCooldown = 0.32
        end
    elseif self.state == "hurt" or self.state == "throw" or self.state == "pose" then
        self.t = self.t - dt
        if self.t <= 0 then
            self.state = "move"
        end
    end
end

function Hero:startAttack(step, steering)
    self.state, self.t, self.combo = "attack", 0, step
    self.queued, self.struck = false, false
    self.atkX, self.atkY = self.aimX, self.aimY
    -- a little help with aiming: turn to the closest enemy in front (or anywhere when not steering)
    local ax, ay = self.mode:aimAssist(self, steering)
    if ax then
        self.atkX, self.atkY = ax, ay
        self.aimX, self.aimY = ax, ay
    end
    self.facing = iso.faceOf(self.atkX, self.atkY, self.facing)
    self:play("attack", true)
    self.sprite.speed = step == 3 and 0.85 or 1
    audio.play("swing", { pitch = 0.9 + step * 0.08, volume = 0.6 })
end

function Hero:startRoll(dx, dy)
    local nx, ny = norm(dx, dy)
    if nx == 0 and ny == 0 then
        nx, ny = self.aimX, self.aimY
    end
    self.state, self.t = "roll", 0
    self.rollX, self.rollY = nx, ny
    self.facing = iso.faceOf(nx, ny, self.facing)
    self.dodge = 0.24 -- nothing hurts while dashing (no blinking, unlike after a hit)
    self.sprite.speed = 1
    self:play("walk", true)
    audio.play("dash", { volume = 0.5 })
end

function Hero:throw()
    local st = G().state
    if not st.inventory:has("stone", 1) then
        engine.ui.toast("Нет камней")
        audio.play("error")
        return
    end
    st.inventory:remove("stone", 1)
    self.state, self.t = "throw", 0.22
    self.facing = iso.faceOf(self.aimX, self.aimY, self.facing)
    self:play("release")
    audio.play("throw")
    self.mode:addActor(iso.Shot(self.mode, "stone", self, self.aimX, self.aimY))
end

-- damage from an enemy (hearts: 2 = one heart)
function Hero:hurt(amount, from)
    if self.state == "dead" or self.invulnerable > 0 or self.dodge > 0 or self.mode.cutscene then
        return false
    end
    local st = G().state
    local armor = G().bonus("defense")
    if armor >= 6 and amount > 1 then
        amount = amount - 1
    end
    st.hp = math.max(0, st.hp - amount)
    self.flash = 0.12
    self.invulnerable = 0.9
    if from then
        self:push(self.x - from.x, self.y - from.y, 110)
    end
    self.mode:onHeroHurt(self, amount)
    if st.hp <= 0 then
        self.state, self.t = "dead", 0
        self.facing = "se"
        self:play("dead")
        audio.play("die")
    else
        self.state, self.t = "hurt", 0.25
        self:play("hurt")
        audio.play("hurt")
    end
    return true
end

function Hero:pose(name, time)
    self.state, self.t = "pose", time or 0.6
    self:play(name)
end

function Hero:update(dt)
    self:updateTimers(dt)
    if self.hopping then
        self:updateHop(dt)
    else
        self:physics(dt)
    end
    self.sprite:update(dt)
    for i = #self.ghosts, 1, -1 do
        local g = self.ghosts[i]
        g.life = g.life - dt
        if g.life <= 0 then
            table.remove(self.ghosts, i)
        end
    end
end

function Hero:landed(speed)
    if speed > 4 then
        audio.play("land", { volume = 0.4 })
    end
end

function Hero:draw()
    self:drawShadow()
    for _, g in ipairs(self.ghosts) do
        local gx, gy = self.map:project(g.x, g.y, g.z)
        love.graphics.setColor(0.6, 0.8, 1, g.life / 0.18 * 0.5)
        local s = self.sprite
        love.graphics.draw(s.image, g.quad, math.floor(gx + 0.5), math.floor(gy + 0.5), 0, g.flip and -1 or 1, 1, s.ox, s.oy)
    end
    love.graphics.setColor(1, 1, 1, 1)
    local sx, sy = self:screen()
    self:drawSprite(sx, sy)
    if self.state == "attack" and self.weaponRow and self.sprite.def.isoWeapons then
        local half = self.facing:sub(1, 1) == "s" and 0 or 1
        local frame = self.sprite:getFrame()
        love.graphics.setColor(1, 1, 1, self.alpha)
        love.graphics.draw(assets.image("assets/sprites/iso/weapons.png"), weaponQuad(self.weaponRow + half, frame),
            math.floor(sx + 0.5), math.floor(sy + 0.5), 0, self.flip and -1 or 1, 1, 24, 35)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- the pet (Кашка) ----------------------------------------------------------------------------

local Pet = class(Actor)
iso.Pet = Pet

function Pet:init(mode, id, x, y, trail, index)
    Actor.init(self, mode, x, y)
    local def = G().pets[id] or {}
    self.petId, self.def = id, def
    self.sprite = anim.new(G().sprite(def.sprite or id))
    self.scale = def.isoScale or (self.sprite.scale * 0.5)
    self.trail, self.index = trail, index or 1
    self.spacing = 18 * (index or 1)
    self.shadowSize = 4
    self.height = 18
    self.dir = "down"
    self.idleTime = 0
    self.biteCooldown = 0.6
    self.radius = 3
    self.moveOpts = { step = 1.2 }
end

function Pet:faceScreen(dx, dy)
    local sx, sy = dx - dy, (dx + dy) / 2
    if math.abs(sx) > math.abs(sy) * 1.3 then
        self.dir = sx > 0 and "right" or "left"
    elseif math.abs(sy) > 0.01 then
        self.dir = sy > 0 and "down" or "up"
    end
end

function Pet:walkTo(tx, ty, dt, speed)
    local dx, dy = tx - self.x, ty - self.y
    local nx, ny, d = norm(dx, dy)
    if d < 1.5 then
        return false, d
    end
    local step = math.min(d, (speed or math.max(50, d * 6)) * dt)
    local hx, hy = self:move(nx * step, ny * step)
    if hx and hy then
        -- stuck: hop over
        self.x, self.y = self.x + nx * step, self.y + ny * step
    end
    self:faceScreen(nx, ny)
    return true, d
end

function Pet:update(dt)
    self:updateTimers(dt)
    self.biteCooldown = math.max(0, self.biteCooldown - dt)
    if self.hopping then
        self:updateHop(dt)
        self.sprite:play("walk", self.dir)
        self.sprite:update(dt)
        return
    end
    if self.mode.tech then
        -- the duo tech moves Кашка itself
        self:physics(dt)
        self.sprite:update(dt)
        return
    end
    local moving = false
    local target = self.mode:petTarget(self)
    if target then
        -- battle: run to the enemy and bite it
        local d = self:distanceTo(target)
        if d > target.radius + 8 then
            moving = self:walkTo(target.x, target.y, dt, 75)
        elseif self.biteCooldown <= 0 then
            self.biteCooldown = 1.1
            self:faceScreen(target.x - self.x, target.y - self.y)
            self.vz = 4
            self.z = self.z + 0.05
            self.mode:petBite(self, target)
        end
    else
        local tx, ty, data = self.trail:at(self.spacing)
        if tx then
            local d = math.sqrt((tx - self.x) ^ 2 + (ty - self.y) ^ 2)
            if d > 120 then
                self.x, self.y = tx, ty
                self.z = (data and data.z) or self.map:groundAt(tx, ty) or self.z
            elseif d > 1.5 then
                moving = self:walkTo(tx, ty, dt)
            end
        end
    end
    self:physics(dt)
    if moving then
        self.idleTime = 0
        self.sprite:play("walk", self.dir)
    else
        self.idleTime = self.idleTime + dt
        if self.idleTime > 2.5 and self.sprite:has("sit") then
            self.sprite:play("sit")
        else
            self.sprite:play("idle", self.dir)
        end
    end
    self.sprite:update(dt)
end

function Pet:draw()
    self:drawShadow()
    local sx, sy = self:screen()
    self.flip = false
    self:drawSprite(sx, sy)
end

-- enemies ----------------------------------------------------------------------------------

local Enemy = class(Actor)
iso.Enemy = Enemy

function Enemy:init(mode, kind, x, y, opts)
    Actor.init(self, mode, x, y)
    opts = opts or {}
    local def = G().mobs[kind]
    assert(def, "iso: unknown mob '" .. tostring(kind) .. "'")
    local idef = def.iso or {}
    self.kind, self.def, self.idef = kind, def, idef
    self.name = def.name or kind
    self.sprite = anim.new(G().sprite(idef.sprite or def.sprite))
    self.scale = idef.scale
    self.ai = idef.ai or "melee"
    self.maxHp = idef.hp or def.hp or 3
    self.hp = self.maxHp
    self.speed = idef.speed or def.speed or 40
    self.damage = idef.damage or def.damage or 1
    self.reach = idef.reach or 14
    self.windupTime = idef.windup or 0.45
    self.boss = opts.boss or idef.boss or self.ai == "boss"
    self.radius = self.boss and 5 or 4
    self.group = opts.group
    self.objectId = opts.objectId
    self.homeX, self.homeY = x, y
    self.state, self.t = "idle", love.math.random() * 2
    self.cooldown = 0.6 + love.math.random() * 0.8
    self.side = love.math.random() < 0.5 and -1 or 1
    self.hpShown = 0
    self.tint = idef.tint
    self.armor = idef.armor -- true: a hit does not stop its swing (only a parry does)
    self.poise = 0 -- after a stagger it cannot be staggered again for a while
    self.parryWindow = idef.parry or 0.26 -- the last seconds of the windup: a hit then is a parry
    self.height = idef.height or (self.ai == "hopper" and 18 or 28)
    self.shadowSize = self.ai == "hopper" and 7 or 6
    self.isEnemy = true
    self.facing = ({ "se", "sw", "ne", "nw" })[love.math.random(1, 4)]
    self:play("idle")
end

function Enemy:alive()
    return self.state ~= "dead" and not self.removed
end

-- telegraph: the coming hit glows red more and more
function Enemy:windupGlow()
    if self.state == "windup" then
        local k = 1 - self.t / self.windupLen
        return 0.15 + 0.5 * k
    end
end

function Enemy:faceHero()
    local h = self.mode.hero
    self.facing = iso.faceOf(h.x - self.x, h.y - self.y, self.facing)
end

function Enemy:walkToward(tx, ty, speed, dt)
    local nx, ny, d = norm(tx - self.x, ty - self.y)
    if d < 1 then
        return false
    end
    local step = math.min(d, speed * dt)
    self:move(nx * step, ny * step)
    self.facing = iso.faceOf(nx, ny, self.facing)
    self:play("walk")
    return true
end

function Enemy:update(dt)
    self:updateTimers(dt)
    self.hpShown = math.max(0, self.hpShown - dt)
    self.poise = math.max(0, self.poise - dt)
    self.sprite:update(dt)
    if self.state == "dead" then
        self.t = self.t + dt
        self.alpha = math.max(0, 1 - self.t / 0.5)
        if self.t > 0.5 then
            self:remove()
        end
        return
    end
    if self.hopping then
        self:updateHop(dt)
        return
    end
    self:physics(dt)
    self.glow = self:windupGlow()
    if self.state == "stun" or self.state == "stagger" then
        self.t = self.t - dt
        if self.t <= 0 then
            -- a staggered enemy hits back soon; a stunned one needs a moment
            local staggered = self.state == "stagger"
            self.state = "fight"
            self.cooldown = staggered and math.min(self.cooldown, 0.2 + love.math.random() * 0.2)
                or 0.5 + love.math.random() * 0.5
        end
        return
    end
    if self.mode.cutscene then
        self:play("idle")
        return
    end
    if self.state == "idle" then
        self:wander(dt)
    else
        local brain = Enemy["ai_" .. self.ai] or Enemy.ai_melee
        brain(self, dt)
    end
end

function Enemy:wander(dt)
    self.t = self.t - dt
    if self.wanderX then
        if not self:walkToward(self.wanderX, self.wanderY, self.speed * 0.35, dt) or self.t <= 0 then
            self.wanderX = nil
            self.t = 1.5 + love.math.random() * 2.5
        end
    else
        self:play("idle")
        if self.t <= 0 then
            local a = love.math.random() * math.pi * 2
            local r = 6 + love.math.random() * 16
            local x, y = self.homeX + math.cos(a) * r, self.homeY + math.sin(a) * r
            if self.map:fits(x, y, self.z, self.radius) then
                self.wanderX, self.wanderY = x, y
            end
            self.t = 2.5
        end
    end
end

-- the battle started: it notices the hero
function Enemy:engage()
    if self.state == "idle" then
        self.state = "fight"
        self.cooldown = 0.5 + love.math.random() * 0.9
    end
end

-- melee: walk up, raise the weapon (red glow), lunge and slash
function Enemy:ai_melee(dt)
    local h = self.mode.hero
    local d = self:distanceTo(h)
    if self.state == "fight" then
        self.cooldown = self.cooldown - dt
        if d > self.reach + 3 then
            -- come closer from my own side, so they don't stack up
            local ax, ay = norm(self.x - h.x, self.y - h.y)
            local px, py = -ay * self.side, ax * self.side
            local tx = h.x + (ax * 0.8 + px * 0.6) * self.reach
            local ty = h.y + (ay * 0.8 + py * 0.6) * self.reach
            self:walkToward(tx, ty, self.speed, dt)
        elseif self.cooldown <= 0 then
            self:startWindup(self.windupTime)
        else
            self:faceHero()
            self:play("idle")
        end
    elseif self.state == "windup" then
        self.t = self.t - dt
        self:faceHero()
        if self.t <= 0 then
            self:startStrike()
        end
    elseif self.state == "strike" then
        self.t = self.t + dt
        if self.t < 0.12 then
            self:move(self.atkX * 120 * dt, self.atkY * 120 * dt)
        end
        if not self.struck and self.t >= 0.08 then
            self.struck = true
            self.mode:enemyStrike(self, self.reach + 4)
        end
        if self.t >= 0.3 then
            self.state, self.t = "recover", 0.45
            self:play("idle")
        end
    elseif self.state == "recover" then
        self.t = self.t - dt
        if self.t <= 0 then
            self.state = "fight"
            self.cooldown = 0.7 + love.math.random() * 0.9
            self.side = -self.side
        end
    end
end

function Enemy:startWindup(time)
    self.state, self.t, self.windupLen = "windup", time, time
    self:faceHero()
    self:play("charge")
    self.mode:onWindup(self)
end

function Enemy:startStrike()
    local h = self.mode.hero
    self.state, self.t, self.struck = "strike", 0, false
    self.atkX, self.atkY = norm(h.x - self.x, h.y - self.y)
    self:faceHero()
    self:play("attack", true)
    audio.play("swing", { pitch = 0.75, volume = 0.5 })
end

-- boss: like melee, but chains three slashes and dashes through the field
function Enemy:ai_boss(dt)
    local h = self.mode.hero
    local d = self:distanceTo(h)
    if self.state == "fight" then
        self.cooldown = self.cooldown - dt
        self.chain = 0
        if self.cooldown <= 0 and d > 30 and d < 90 and love.math.random() < 0.5 then
            self.dash = true
            self:startWindup(0.65)
        elseif d > self.reach + 3 then
            self:walkToward(h.x, h.y, self.speed, dt)
        elseif self.cooldown <= 0 then
            self.dash = false
            self:startWindup(self.windupTime)
        else
            self:faceHero()
            self:play("idle")
        end
    elseif self.state == "windup" then
        self.t = self.t - dt
        self:faceHero()
        if self.t <= 0 then
            self:startStrike()
            if self.dash then
                self.state = "dashing"
                self.dashTime = 0
                audio.play("dash", { pitch = 0.7 })
            end
        end
    elseif self.state == "dashing" then
        self.dashTime = self.dashTime + dt
        self:move(self.atkX * 210 * dt, self.atkY * 210 * dt)
        if not self.struck and self:distanceTo(h) < self.radius + h.radius + 6 then
            self.struck = self.mode:enemyStrike(self, self.reach + 6, true)
        end
        if self.dashTime >= 0.32 then
            self.state, self.t = "recover", 0.8
            self:play("idle")
        end
    elseif self.state == "strike" then
        self.t = self.t + dt
        if self.t < 0.1 then
            self:move(self.atkX * 100 * dt, self.atkY * 100 * dt)
        end
        if not self.struck and self.t >= 0.08 then
            self.struck = true
            self.mode:enemyStrike(self, self.reach + 4)
        end
        if self.t >= 0.26 then
            self.chain = (self.chain or 0) + 1
            if self.chain < 3 then
                self:startWindup(0.22)
            else
                self.state, self.t = "recover", 0.7
                self:play("idle")
            end
        end
    elseif self.state == "recover" then
        self.t = self.t - dt
        if self.t <= 0 then
            self.state = "fight"
            self.cooldown = 0.6 + love.math.random() * 0.6
        end
    end
end

-- caster: keeps away, charges and shoots a magic ball (hit it back with the sword!)
function Enemy:ai_caster(dt)
    local h = self.mode.hero
    local d = self:distanceTo(h)
    if self.state == "fight" then
        self.cooldown = self.cooldown - dt
        local ax, ay = norm(self.x - h.x, self.y - h.y)
        if d < 40 then
            self:walkToward(self.x + ax * 20, self.y + ay * 20, self.speed, dt)
        elseif d > 76 then
            self:walkToward(h.x, h.y, self.speed, dt)
        elseif self.cooldown <= 0 then
            self:startWindup(0.8)
        else
            local px, py = -ay * self.side, ax * self.side
            if not self:walkToward(self.x + px * 10, self.y + py * 10, self.speed * 0.5, dt) then
                self.side = -self.side
            end
            self:faceHero()
        end
    elseif self.state == "windup" then
        self.t = self.t - dt
        self:faceHero()
        if love.math.random() < dt * 30 then
            local sx, sy = self:head()
            local a = love.math.random() * math.pi * 2
            self.mode.fx:burst(sx + math.cos(a) * 12, sy + 8 + math.sin(a) * 8, { count = 1, speed = 10,
                color = { 0.8, 0.5, 1 }, life = 0.3, size = 1 })
        end
        if self.t <= 0 then
            self.state, self.t = "cast", 0.35
            self:play("release")
            audio.play("zap", { volume = 0.5 })
            local nx, ny = norm(h.x - self.x, h.y - self.y)
            self.mode:addActor(iso.Shot(self.mode, "orb", self, nx, ny))
        end
    elseif self.state == "cast" then
        self.t = self.t - dt
        if self.t <= 0 then
            self.state = "fight"
            self.cooldown = 1.8 + love.math.random() * 1.2
            self.side = -self.side
        end
    end
end

-- hopper: squashes, then jumps at the hero
function Enemy:ai_hopper(dt)
    local h = self.mode.hero
    if self.state == "fight" then
        self.cooldown = self.cooldown - dt
        self:faceHero()
        self:play("idle")
        if self.cooldown <= 0 then
            self:startWindup(0.35)
        end
    elseif self.state == "windup" then
        self.t = self.t - dt
        if self.t <= 0 then
            local nx, ny, d = norm(h.x - self.x, h.y - self.y)
            local dist = math.min(d, 34)
            self.state = "jump"
            self.vz = 7
            self.z = self.z + 0.05
            self.jx, self.jy = nx * dist / 0.47, ny * dist / 0.47
            self.struck = false
            self:play("walk")
            audio.play("jump", { volume = 0.35, pitch = 1.3 })
        end
    elseif self.state == "jump" then
        self:move(self.jx * dt, self.jy * dt)
        if not self.struck and self:distanceTo(h) < self.radius + h.radius + 3 and math.abs(self.z - h.z) < 1 then
            self.struck = self.mode:enemyStrike(self, 99, true)
        end
    end
end

function Enemy:landed(speed)
    if self.state == "jump" then
        self.state = "fight"
        self.cooldown = 0.7 + love.math.random() * 0.8
        self.mode.fx:burst(self:screen(), select(2, self:screen()), { count = 5, color = { 0.6, 0.9, 0.6 }, speed = 30, life = 0.3 })
    end
end

-- a hit from the hero: returns "parry" / "hit" / nil
function Enemy:hurt(amount, from, opts)
    if not self:alive() or self.invulnerable > 0 then
        return nil
    end
    opts = opts or {}
    local result = "hit"
    local swinging = self.state == "windup" or self.state == "strike" or self.state == "dashing"
    if self.state == "windup" and not opts.noParry then
        if self.t <= self.parryWindow then
            result = "parry" -- right before its blow: the blow is knocked aside
        elseif not self.boss and not self.armor then
            result = "interrupt"
        end
    end
    if result == "parry" then
        amount = amount * 2
    end
    self.hp = self.hp - amount
    self.hpShown = 2.5
    self.flash = 0.12
    self.invulnerable = 0.1
    if from then
        local knock = (opts.knock or 60) * (self.boss and 0.35 or 1)
        if swinging and result == "hit" then
            knock = knock * 0.3
        end
        self:push(self.x - from.x, self.y - from.y, knock)
    end
    if self.hp <= 0 then
        self.state, self.t = "dead", 0
        self.glow = nil
        self:play("dead")
        self.invulnerable = 0
        return result, true
    end
    if result == "parry" then
        self.state, self.t = "stun", self.boss and 1.0 or 1.4
        self:play("weak")
    elseif result == "interrupt" or opts.stun then
        self.state, self.t = "stun", opts.stun or 0.6
        self:play("hurt")
    elseif not self.boss and not swinging and self.state ~= "jump" and not opts.noStagger and self.poise <= 0 then
        self.state, self.t = "stagger", 0.25
        self.poise = 1.6
        self:play("hurt")
    end
    return result, false
end

function Enemy:draw()
    self:drawShadow()
    local sx, sy = self:screen()
    local squash = nil
    if self.ai == "hopper" and self.state == "windup" then
        local k = 1 - self.t / self.windupLen
        squash = { 1 + 0.25 * k, 1 - 0.25 * k }
    end
    if squash then
        local s = self.scale or self.sprite.scale
        love.graphics.push()
        love.graphics.translate(math.floor(sx + 0.5), math.floor(sy + 0.5))
        love.graphics.scale(squash[1], squash[2])
        self:drawSprite(0, 0, { scale = s })
        love.graphics.pop()
    else
        self:drawSprite(sx, sy)
    end
    if self.state == "stun" then
        -- little stars around the head
        local hx, hy = self:head()
        for k = 0, 2 do
            local a = self.time * 5 + k * 2.1
            love.graphics.setColor(1, 0.95, 0.4, 0.9)
            love.graphics.circle("fill", hx + math.cos(a) * 7, hy + 2 + math.sin(a) * 3, 1.2)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- flying things: the hero's stone, the caster's magic ball ----------------------------------------------

local Shot = class(Actor)
iso.Shot = Shot

function Shot:init(mode, kind, owner, dx, dy)
    Actor.init(self, mode, owner.x + dx * 6, owner.y + dy * 6)
    self.kind, self.owner = kind, owner
    self.team = owner.isHero and "hero" or "enemy"
    self.z = owner.z + 0.9
    self.radius = 2
    self.life = kind == "orb" and 2.6 or 1.2
    self.shadowSize = 3
    if kind == "stone" then
        self.vx, self.vy, self.vz = dx * 150, dy * 150, 3
    else
        self.vx, self.vy = dx * 72, dy * 72
        self.float = owner.z + 0.9
    end
    self.isShot = true
end

-- hit back by the hero's sword
function Shot:reflect(by)
    if self.team == "hero" then
        return false
    end
    local target = self.owner
    local nx, ny = norm(target.x - self.x, target.y - self.y)
    if nx == 0 and ny == 0 then
        nx, ny = norm(self.x - by.x, self.y - by.y)
    end
    self.vx, self.vy = nx * 120, ny * 120
    self.team = "hero"
    self.life = 1.6
    self.reflected = true
    return true
end

function Shot:update(dt)
    self.time = self.time + dt
    self.life = self.life - dt
    if self.life <= 0 then
        self:remove()
        return
    end
    local nx, ny = self.x + self.vx * dt, self.y + self.vy * dt
    if self.kind == "stone" then
        self.vz = self.vz - 20 * dt
        self.z = self.z + self.vz * dt
    end
    local g = self.map:groundAt(nx, ny)
    if not g or g > self.z then
        self.mode:shotBroke(self)
        self:remove()
        return
    end
    self.x, self.y = nx, ny
    if self.kind == "orb" then
        self.z = math.max(g + 0.6, self.z)
    elseif self.z <= g then
        self.mode:shotBroke(self)
        self:remove()
        return
    end
    self.mode:shotFly(self)
end

function Shot:draw()
    self:drawShadow()
    local sx, sy = self:screen()
    if self.kind == "stone" then
        love.graphics.setColor(0.25, 0.22, 0.3, 1)
        love.graphics.circle("fill", sx, sy, 2.2)
        love.graphics.setColor(0.75, 0.75, 0.8, 1)
        love.graphics.circle("fill", sx - 0.5, sy - 0.5, 1.4)
    else
        local pulse = 0.5 + 0.5 * math.sin(self.time * 18)
        local c = self.reflected and { 1, 0.85, 0.4 } or { 0.75, 0.45, 1 }
        love.graphics.setBlendMode("add")
        love.graphics.setColor(c[1], c[2], c[3], 0.35)
        love.graphics.circle("fill", sx, sy, 5 + pulse)
        love.graphics.setColor(c[1], c[2], c[3], 0.9)
        love.graphics.circle("fill", sx, sy, 2.5)
        love.graphics.setBlendMode("alpha")
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- things on the ground ---------------------------------------------------------------------------

local Loot = class(Actor)
iso.Loot = Loot

function Loot:init(mode, item, x, y, opts)
    Actor.init(self, mode, x, y)
    opts = opts or {}
    self.item = item
    self.def = G().items[item] or { name = item, icon = item }
    self.count = opts.count or 1
    self.objectId = opts.objectId
    self.auto = opts.auto
    self.magnet = opts.magnet
    self.delay = opts.pop and 0.45 or 0
    self.icon = assets.image("assets/sprites/icons/" .. (self.def.icon or item) .. ".png")
    self.iconScale = item == "coin" and 0.3 or 0.42
    self.shadowSize = 4
    self.pickable = true
    if opts.pop then
        self.vz = 6
        self.z = self.z + 0.1
        local a = love.math.random() * math.pi * 2
        self.vx, self.vy = math.cos(a) * 30, math.sin(a) * 30
    end
end

function Loot:update(dt)
    self.time = self.time + dt
    self.delay = math.max(0, self.delay - dt)
    if self.magnet and self.delay <= 0 then
        local h = self.mode.hero
        local nx, ny, d = norm(h.x - self.x, h.y - self.y)
        local speed = 60 + math.max(0, 120 - d)
        self.x, self.y = self.x + nx * speed * dt, self.y + ny * speed * dt
        self.z = util.lerp(self.z, h.z, math.min(1, dt * 8))
        return
    end
    self:physics(dt)
end

function Loot:draw()
    self:drawShadow()
    local sx, sy = self:screen()
    local bob = (self.vz == 0 and not self.magnet) and math.sin(self.time * 3) * 1.5 or 0
    local s = self.iconScale
    local w, h = self.icon:getWidth() * s, self.icon:getHeight() * s
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.icon, math.floor(sx - w / 2 + 0.5), math.floor(sy - h - 2 - bob + 0.5), 0, s, s)
    local t = (self.time * 0.6) % 1
    if t < 0.15 and not self.magnet then
        local k = t / 0.15
        love.graphics.setColor(1, 1, 0.85, 1 - k)
        love.graphics.circle("fill", sx + w * 0.3, sy - h - bob + 2, 1.5 * (1 - k) + 0.5)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- people: an NPC standing in the world ------------------------------------------------------------------------

local Person = class(Actor)
iso.Person = Person

function Person:init(mode, o)
    local x, y = mode.map:objectPoint(o)
    Actor.init(self, mode, x, y)
    local p = o.properties or {}
    self.name = o.name
    self.sprite = anim.new(G().sprite(p.sprite or "iso_cleric"))
    self.facing = p.facing or "se"
    self.radius = 4
    self:play("idle")
    self.isPerson = true
end

function Person:update(dt)
    self:updateTimers(dt)
    if self.walking or self.hopping then
        if self.hopping then
            self:updateHop(dt)
        end
    else
        self:play("idle")
    end
    self.sprite:update(dt)
end

return iso
