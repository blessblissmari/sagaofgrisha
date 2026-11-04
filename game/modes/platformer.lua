-- Platformer (Mario / metroidvania): a side view Tiled map with gravity,
-- one-way platforms, stomping, pets running behind the hero and abilities
-- that open new paths (double jump, dash, wall jump).
--
--   game.stage "cave" {
--       kind = "platformer", map = "assets/maps/cave.tmx",
--       background = "hills",   -- default: map property "background" (game/data/backgrounds.lua)
--       music = "calm",         -- default: map property "music"
--       zoom = 3,               -- camera zoom (pixel size)
--       triggers = { exit = { "island", spawn = "from_cave" },
--                    high_ledge = function(s, zone) ... end },
--       on = { kill = function(s, mobKind) end, pickup = function(s, item) end,
--              gate = function(s, requirement) end, death = function(s) end },
--   }
--
-- In Tiled (see README):
--   tile properties  solid, oneway (jump through from below), surface, hazard
--   Spawns           points: player, ... (s:go("cave", { spawn = "exit" }))
--   Items            points: item = "coin" or ability = "dash" (a glowing orb)
--   Mobs             points: mob = "pumpkin" (game/data/mobs.lua: ai, platformSpeed...)
--   Gates            tile objects that block the way: ability = "dash" (broken by
--                    dashing into it) or item = "key" (opened with the key, consume = false
--                    keeps it). Touching gates of one kind open together.
--   Triggers         zones; property finish = true ends the stage (win)
-- Script commands of this mode: teleport(spawn), spawn(mob, x, y), camera(zoom),
-- face("left" | "right"), disable(zone), enable(zone), openGates(requirement).

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui
local util = engine.util
local Background = engine.Background
local Camera = engine.Camera
local Entity = engine.Entity
local Trail = engine.Trail
local World = engine.World
local physics = engine.physics
local Mode = require("game.modes.base")
local Hero = require("game.entities.hero_side")
local SideMob = require("game.entities.side_mob")
local SideFollower = require("game.entities.side_follower")
local Pickup = require("game.entities.pickup")
local hud = require("game.ui.hud")

local function G()
    return require("game")
end

-- a block that is solid until its requirement is met ------------------------------

local Gate = class(Entity)

function Gate:init(o, key, map)
    local w, h = o.width or 16, o.height or 16
    local top = o.gid and (o.y - h) or o.y
    Entity.init(self, o.x + w / 2, top + h)
    self.w, self.h = w, h
    self.rect = { x = o.x, y = top, w = w, h = h }
    local p = o.properties or {}
    self.ability, self.item = p.ability, p.item
    self.requirement = p.ability or p.item
    self.consume = p.consume ~= false
    self.key = key
    self.solid, self.shadow, self.reflect = false, false, false
    local tile = o.gid and map.tiles[o.gid]
    if tile then
        self.quad = tile.quad
        self.image = map.tilesets[tile.tileset].image
    end
end

function Gate:draw()
    local r = self.rect
    if self.image then
        love.graphics.draw(self.image, self.quad, r.x, r.y)
    else
        love.graphics.setColor(0.4, 0.6, 0.9, 1)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- a thrown stone ----------------------------------------------------------------

local Stone = class(Entity)

function Stone:init(x, y, dir)
    Entity.init(self, x, y)
    self.w, self.h = 4, 4
    self.vx, self.vy = dir * 230, -110
    self.shadow, self.reflect = false, false
    self.icon = assets.image("assets/sprites/icons/stone.png", { filter = "linear" })
    self.time = 0
end

function Stone:update(dt)
    self.time = self.time + dt
    self.vy = self.vy + 600 * dt
    local world, level = self.world, self.world.scene
    local hitX = physics.moveX(world, self, self.vx * dt)
    local landed, hitCeiling = physics.moveY(world, self, self.vy * dt, true)
    local hits = world:query(self.x - 4, self.y - 6, 8, 8, function(e)
        return e.team == "enemy" and not e.dying
    end)
    if hits[1] then
        if hits[1]:hurt(1, { from = self, knockback = 120 }) then
            level.fx:play("slash", hits[1].x, hits[1].y - 8, { scale = 0.2 })
        end
        self:remove()
    elseif hitX or landed or hitCeiling or self.time > 2 then
        level.fx:play("puff", self.x, self.y - 2, { scale = 0.6 })
        audio.play("land", { volume = 0.4 })
        self:remove()
    end
end

function Stone:draw()
    local s = 0.25
    love.graphics.draw(self.icon, self.x, self.y - 2, self.time * 10, s, s, 17, 17)
end

-- the mode ----------------------------------------------------------------------

local Platformer = class(Mode)
Platformer.liveScripts = true

function Platformer:init(def)
    Mode.init(self, def)
    local g = G()
    local st = g.state
    assert(def.map, "stage '" .. tostring(def.name) .. "': kind platformer needs map = \"assets/maps/....tmx\"")
    local world = World(def.map, { openBottom = true, reflections = false })
    self.world = world
    world.scene, world.fx = self, self.fx
    self.fx.font = ui.font("tiny") -- crisp text at zoom 3
    local props = world.map.properties or {}
    local bgName = def.background or props.background or "hills"
    self.background = Background(type(bgName) == "table" and bgName or g.backgrounds[bgName])
    self.camera = Camera(screen.width, screen.height)
    self.camera.zoom = def.zoom or 3
    self.camera:setBounds(0, 0, world.width, world.height)
    world.camera = self.camera

    if st.hp <= 0 then
        st.hp = st.maxHp
    end
    local sx, sy = world:spawn(def.spawn or "player")
    self.hero = world:add(Hero(sx, sy, { sprite = def.playerSprite }))
    self.player = self.hero
    world.player = self.hero
    self.lookAhead = 0
    self.camera:lookAt(sx, sy - 20)
    self.trail = Trail(2, 600)
    self.trail:reset(sx, sy)
    self.followers = {}
    self:partyChanged()
    self.gates = {}
    self:spawnObjects()
    self.hintTime = 0

    world.triggers.defaultHandler = function(zone, who, event)
        if event == "leave" then
            return false
        end
        return g.trigger(self, zone, event, who)
    end
end

function Platformer:enter()
    local m = self.def.music
    if m == nil then
        m = self.world.map.properties.music
    end
    if m == false then
        audio.stopMusic(0.5)
    elseif m then
        audio.music(m)
    end
end

function Platformer:key(o)
    return self.name .. ":" .. tostring(o.id ~= 0 and o.id or o.name)
end

local function objectPoint(o)
    if o.shape == "point" then
        return o.x, o.y
    elseif o.gid then
        return o.x + (o.width or 0) / 2, o.y
    end
    return o.x + (o.width or 0) / 2, o.y + (o.height or 0)
end

function Platformer:spawnObjects()
    local g = G()
    local st = g.state
    local world = self.world
    for _, o in ipairs(world:objectsOf("Item")) do
        local p = o.properties or {}
        local item = p.item or p.ability or (o.name ~= "" and o.name or nil)
        local key = self:key(o)
        local info = item and g.items[item]
        if item and not st.collected[key] and not (info and info.ability and st.abilities[info.ability]) then
            local x, y = objectPoint(o)
            local pickup = world:add(Pickup(item, x, y - 2, { count = p.count, objectId = key, scale = info and info.ability and 0.45 or 0.32 }))
            pickup.press = not (info and info.ability) and g.pickupMode(item, p.pickup) == "press"
            pickup.shadow = false
        end
    end
    for _, o in ipairs(world:objectsOf("Mob")) do
        local p = o.properties or {}
        local kind = p.mob or o.name
        local key = self:key(o)
        if g.mobs[kind] and not st.defeated[key] then
            local x, y = objectPoint(o)
            world:add(SideMob(kind, x, y, key))
        elseif not g.mobs[kind] then
            print("[platformer] unknown mob '" .. tostring(kind) .. "' in " .. tostring(self.def.map))
        end
    end
    for _, o in ipairs(world:objectsOf("Gate")) do
        local key = self:key(o)
        if not st.collected[key] then
            local gate = world:add(Gate(o, key, world.map))
            table.insert(self.gates, gate)
            table.insert(world.solidRects, gate.rect)
        end
    end
end

-- party ---------------------------------------------------------------------------

function Platformer:partyChanged()
    for _, f in ipairs(self.followers) do
        f:remove()
    end
    self.followers = {}
    local h = self.hero
    for i, id in ipairs(G().state.party) do
        local f = SideFollower(id, h.x, h.y, self.trail, i)
        self.world:add(f)
        table.insert(self.followers, f)
    end
end

function Platformer:syncPlayer()
    local st = G().state
    self.hero.hp, self.hero.maxHp = st.hp, st.maxHp
end

-- gates ---------------------------------------------------------------------------

-- all closed gates that touch `gate` (directly or through others) and need the same
function Platformer:gateGroup(gate)
    local group, seen, queue = {}, { [gate] = true }, { gate }
    while #queue > 0 do
        local a = table.remove(queue)
        table.insert(group, a)
        for _, b in ipairs(self.gates) do
            if not seen[b] and not b.open and b.requirement == a.requirement then
                local ra, rb = a.rect, b.rect
                if util.overlaps(ra.x - 1, ra.y - 1, ra.w + 2, ra.h + 2, rb.x, rb.y, rb.w, rb.h) then
                    seen[b] = true
                    table.insert(queue, b)
                end
            end
        end
    end
    return group
end

function Platformer:openGate(gate, how)
    local st = G().state
    local group = self:gateGroup(gate)
    for _, gt in ipairs(group) do
        gt.open = true
        st.collected[gt.key] = true
        util.removeValue(self.world.solidRects, gt.rect)
        gt:remove()
        local r = gt.rect
        if how == "break" then
            self.fx:burst(r.x + r.w / 2, r.y + r.h / 2, { count = 10, color = { 0.45, 0.75, 0.7 }, speed = 90,
                life = 0.6, size = 2, gravity = 300 })
            self.fx:play("puff", r.x + r.w / 2, r.y + r.h / 2)
        else
            self.fx:burst(r.x + r.w / 2, r.y + r.h / 2, { count = 6, color = { 0.8, 0.95, 1 }, speed = 40, life = 0.5, size = 1 })
            self.fx:play("sparkle", r.x + r.w / 2, r.y + r.h / 2)
        end
    end
    util.removeValue(self.gates, gate)
    for i = #self.gates, 1, -1 do
        if self.gates[i].open then
            table.remove(self.gates, i)
        end
    end
    if how == "break" then
        audio.play("crumble")
        self.camera:shake(3, 0.2)
    else
        audio.play("unlock")
    end
    self:fire("gate", gate.requirement)
end

-- the hero dashed into a wall: break dash gates there
function Platformer:dashInto(hero, dir)
    local x = dir > 0 and hero.x + hero.w / 2 or hero.x - hero.w / 2 - 2
    for _, gate in ipairs(self.gates) do
        local r = gate.rect
        if not gate.open and gate.ability == "dash"
            and util.overlaps(x, hero.y - hero.h, 2, hero.h, r.x, r.y, r.w, r.h) then
            self:openGate(gate, "break")
            hero.dashTime = Hero.DASH_TIME * 0.5 -- keep going through the hole
            return true
        end
    end
    return false
end

-- the hero touches a gate: open it with the key, or explain what is needed
function Platformer:touchGates(hero, dt)
    self.hintTime = math.max(0, self.hintTime - dt)
    local g = G()
    local x, y, w, h = hero:getBox()
    for _, gate in ipairs(self.gates) do
        local r = gate.rect
        if not gate.open and util.overlaps(x - 2, y, w + 4, h, r.x, r.y, r.w, r.h) then
            if gate.item and g.state.inventory:has(gate.item) then
                if gate.consume then
                    g.state.inventory:remove(gate.item, 1)
                end
                local info = g.items[gate.item]
                ui.toast("Открыто: " .. (info and info.name or gate.item), { icon = info and info.icon })
                self:openGate(gate, "open")
                return
            elseif self.hintTime <= 0 then
                self.hintTime = 4
                local info = g.items[gate.requirement]
                local name = info and info.name or gate.requirement
                if gate.ability and g.state.abilities[gate.ability] then
                    ui.toast("Треснувший блок. " .. name .. ": [" .. input.keyName(gate.ability) .. "]", { icon = info and info.icon })
                else
                    ui.toast("Здесь нужно: " .. name, { icon = info and info.icon })
                end
            end
        end
    end
end

-- events --------------------------------------------------------------------------

function Platformer:throwStone(x, y, dir)
    self.world:add(Stone(x, y, dir))
end

function Platformer:onPickup(pickup)
    if pickup.def.ability and pickup.def.description then
        ui.toast(pickup.def.description, { color = { 1, 1, 0.8 }, time = 5 })
    end
    if pickup.item == "coin" then
        audio.play("coin")
    end
    self:fire("pickup", pickup.item, pickup.count)
end

function Platformer:dropLoot(mob)
    for _, d in ipairs(mob.def.drops or {}) do
        if love.math.random() < (d.chance or 1) then
            local p = self.world:add(Pickup(d.item, mob.x, mob.y - 4, { count = d.count, scale = 0.32 }))
            p.shadow = false
            p.dropped = true
        end
    end
end

function Platformer:onMobKilled(mob)
    local st = G().state
    if mob.objectId then
        st.defeated[mob.objectId] = true
    end
    self:dropLoot(mob)
    self:fire("kill", mob.kind)
end

function Platformer:startBattle(mob, advantage)
    if self.battleMob or scene.top() ~= self or scene.isTransitioning() then
        return
    end
    self.battleMob = mob
    audio.play("bdoom")
    local g = G()
    g.play(self.def.battle or "battle", {
        enemies = mob.def.party or { mob.kind }, advantage = advantage, transition = "battle",
        background = self.def.battleBackground,
    }, function(result)
        result = result or {}
        self.battleMob = nil
        if result.win then
            if mob.objectId then
                g.state.defeated[mob.objectId] = true
            end
            mob.team = nil
            mob:remove()
            self:dropLoot(mob)
            self:fire("battleWon", mob.kind)
        elseif result.fled then
            self.hero.invulnerable = 2
            self.hero.vx = (self.hero.x < mob.x and -1 or 1) * 160
            self.hero.vy = -150
            mob.knockTime = 1
        else
            self:gameOver()
        end
        self:syncPlayer()
    end)
end

function Platformer:gameOver()
    if self:fire("death") then
        return
    end
    local g = G()
    local st = g.state
    st.hp = st.maxHp
    if st.hero then
        st.hero.hp = st.hero.maxHp or st.hero.hp
    end
    ui.toast("Гриша очнулся у входа. Ещё разок!", { color = { 1, 0.85, 0.5 } })
    g.go(self.name, { spawn = self.def.spawn, transition = "fade" })
end

-- the hero against mobs, pits and spikes
function Platformer:checkHero(dt)
    local hero, world = self.hero, self.world
    if hero.dying then
        return
    end
    local x, y, w, h = hero:getBox()
    for _, m in ipairs(world:query(x, y, w, h, function(e) return e.team == "enemy" and not e.dying end)) do
        local mobTop = m.y - m.h
        local falling = hero.vy > 0 or (hero.prevVy or 0) > 0
        if falling and (hero.prevY or hero.y) <= mobTop + 5 and m.stompable then
            hero.vy = input.down("jump") and -Hero.STOMP_BOUNCE * 1.35 or -Hero.STOMP_BOUNCE
            hero.usedDouble, hero.usedDash = false, false
            hero.onGround = false
            if m.def.touch == "battle" then
                audio.play("stomp")
                self:startBattle(m, "party")
            else
                m:stomped()
                self.camera:shake(2, 0.1)
            end
        elseif m.def.touch == "battle" then
            self:startBattle(m)
        elseif hero.invulnerable <= 0 then
            hero:hurt(m.damage, { from = m })
        end
    end
    -- spikes
    local hazard = world:hazardAt(hero.x, hero.y + 1) or world:hazardAt(hero.x, hero.y - hero.h / 2)
    if hazard and hero.invulnerable <= 0 then
        hero:hurt(type(hazard) == "number" and hazard or 1, { from = { x = hero.x + hero.facing * 6, y = hero.y } })
    end
    -- pits
    if hero.y > world.height + 24 then
        audio.play("fall")
        local st = G().state
        hero.x, hero.y, hero.vx, hero.vy = hero.safeX, hero.safeY, 0, 0
        self.trail:reset(hero.x, hero.y)
        for _, f in ipairs(self.followers) do
            f.x, f.y = hero.x, hero.y
        end
        self.camera:lookAt(hero.x, hero.y - 20)
        hero.invulnerable = 0
        hero:hurt(2, { iframes = 1.5 })
        st.hp = hero.hp
    end
end

-- script commands -------------------------------------------------------------------

function Platformer:cmd_teleport(s, name, y)
    local x
    if type(name) == "number" then
        x = name
    else
        x, y = self.world:spawn(name)
    end
    local h = self.hero
    h.x, h.y, h.vx, h.vy = x, y, 0, 0
    self.trail:reset(x, y)
    for _, f in ipairs(self.followers) do
        f.x, f.y = x, y
    end
    self.camera:lookAt(x, y - 20)
end

function Platformer:cmd_spawn(s, kind, x, y)
    if type(x) == "string" or x == nil then
        x, y = self.world:spawn(x or "player")
    end
    local mob = self.world:add(SideMob(kind, x, y))
    self.fx:play("puff", x, y - 8)
    return mob
end

function Platformer:cmd_face(s, dir)
    self.hero.facing = (dir == "left" or dir == -1) and -1 or 1
end

function Platformer:cmd_camera(s, zoom)
    self.timer:tween(0.6, self.camera, { zoom = zoom or 3 }, "quadInOut")
    return 0.6
end

function Platformer:cmd_disable(s, zoneName)
    local zone = self.world.triggers:get(zoneName)
    if zone then
        zone.enabled = false
    end
end

function Platformer:cmd_enable(s, zoneName)
    local zone = self.world.triggers:get(zoneName)
    if zone then
        zone.enabled, zone.fired = true, false
    end
end

function Platformer:cmd_openGates(s, requirement)
    for _, gate in ipairs(util.copy(self.gates)) do
        if not gate.open and (requirement == nil or gate.requirement == requirement) then
            self:openGate(gate, "open")
        end
    end
end

-- callbacks -------------------------------------------------------------------------

function Platformer:update(dt, fromScript)
    Mode.update(self, dt)
    local world, hero = self.world, self.hero
    self.background:update(dt)
    if fromScript or scene.top() ~= self then
        world.map:update(dt)
        for _, f in ipairs(self.followers) do
            f.sprite:update(dt)
        end
        hero:animate()
        hero.sprite:update(dt)
        self.camera:update(dt)
        self.prompt = nil
        return
    end
    if self:pausePressed() then
        input.consume("pause")
        self:openPause()
        return
    end
    if input.pressed("inventory") then
        local Bag = require("game.ui.inventory")
        scene.push(Bag(self))
        return
    end
    if input.pressed("journal") then
        local Journal = require("game.ui.journal")
        scene.push(Journal(self))
        return
    end

    hero.prevY, hero.prevVy = hero.y, hero.vy
    world:update(dt)
    self.trail:push(hero.x, hero.y)
    self:checkHero(dt)
    self:touchGates(hero, dt)

    -- pick up items: "auto" ones by touching them, the others with [E]
    local x, y, w, h = hero:getBox()
    local interact = input.pressed("interact")
    self.prompt = nil
    for _, p in ipairs(world:query(x - 2, y - 2, w + 4, h + 4, function(e) return e.pickable and not e.delay end)) do
        if not p.press then
            p:collect(hero)
        elseif not hero.dying then
            self.prompt = "Поднять: " .. (p.def.name or p.item)
            if interact then
                p:collect(hero)
                input.consume("interact")
            end
        end
    end

    -- trigger zones
    if not hero.dying then
        local zone = world.triggers:update(hero, not self.prompt and input.pressed("interact"))
        if zone and not self.prompt then
            local p = zone.properties
            self.prompt = (p.prompt and p.prompt ~= "") and p.prompt or "Осмотреть"
        end
    else
        self.deathTime = (self.deathTime or 0) + dt
        if self.deathTime > 1.6 and not self.deathHandled then
            self.deathHandled = true
            self:gameOver()
        end
    end

    -- the camera looks a bit ahead of the hero
    self.lookAhead = util.damp(self.lookAhead, hero.facing * 28, 2.5, dt)
    self.camera:follow(hero.x + self.lookAhead, hero.y - 20, dt, 7)
    self.camera:update(dt)
    if engine.debug.enabled then
        engine.debug.watch("hero", string.format("%d, %d  ground=%s  %s", hero.x, hero.y, tostring(hero.onGround),
            tostring(hero:surface())))
    end
end

function Platformer:draw()
    local cam = self.camera
    local left, top = cam:getTopLeft()
    self.background:draw(left * cam.zoom, top * cam.zoom)
    self.world:draw(cam, {
        overlay = function()
            self.fx:draw()
        end,
    })
    if engine.debug.enabled then
        self.world:drawDebug(cam)
    end
    self:drawHud()
end

function Platformer:drawAbilities()
    local g = G()
    local x = screen.width - 46
    for _, id in ipairs({ "wall_jump", "dash", "double_jump" }) do
        if g.state.abilities[id] then
            local info = g.items[id]
            if info then
                ui.icon(info.icon, x, 10, 0.75)
                x = x - 32
            end
        end
    end
end

function Platformer:drawHud()
    if scene.top() ~= self then
        return
    end
    self:drawAbilities()
    local keys = { { "jump", "прыжок" }, { "punch", "удар" }, { "throw", "камень" } }
    if G().state.abilities.dash then
        table.insert(keys, { "dash", "рывок" })
    end
    table.insert(keys, { "pause", "пауза" })
    hud.draw({ prompt = self.prompt, hint = hud.keys(keys), owner = self })
end

function Platformer:drawScriptOverlay()
    hud.draw({})
end

return Platformer
