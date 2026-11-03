-- Top-down world (Zelda style): a Tiled map, the hero, pets walking behind
-- him, items, mobs, trigger zones, real-time combat and turn-based battles.
--
--   game.stage "island" {
--       kind = "topdown", map = "assets/maps/island.tmx",
--       music = "calm",              -- default: map property "music"
--       zoom = 2,                    -- camera zoom (pixel size)
--       battle = "battle",           -- stage used when a mob starts a battle
--       triggers = {                 -- zone name in Tiled -> what happens
--           cave = "cave",                                   -- go to a stage
--           sign = function(s, zone) s:say("sign", "...") end, -- a script
--       },
--       on = { kill = function(s, mobKind) end, pickup = function(s, item) end,
--              battleWon = function(s, mobKind) end, death = function(s) end },
--   }
--
-- In Tiled (see README): tile property surface (footsteps) and solid,
-- object layers Spawns, Items (item, count), Mobs (mob), Triggers, NPCs.
-- Script commands of this mode: spawn(mob, x, y | spawnName), teleport(spawnName),
-- face(dir), disable(zone), enable(zone), camera(zoom).

local engine = require("engine")
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui
local util = engine.util
local Camera = engine.Camera
local Entity = engine.Entity
local Trail = engine.Trail
local World = engine.World
local anim = engine.anim
local Mode = require("game.modes.base")
local Player = require("game.entities.player")
local Mob = require("game.entities.mob")
local Pickup = require("game.entities.pickup")
local Follower = require("game.entities.follower")
local hud = require("game.ui.hud")

local function G()
    return require("game")
end

-- a character standing in the world (NPC layer: property sprite, dialogue)
local NPC = class(Entity)

function NPC:init(o)
    local x, y = o.x + (o.width or 0) / 2, o.y + (o.height or 0)
    Entity.init(self, x, y)
    local p = o.properties or {}
    local g = G()
    local spriteName = p.sprite or (g.sprites[o.name] and o.name) or "grisha"
    self.sprite = anim.new(g.sprite(spriteName))
    self.sprite:play("idle", p.facing or "down")
    self.w, self.h = 14, 8
    self.solid = false
    self.flipX = p.flip
end

function NPC:update(dt)
    Entity.update(self, dt)
    self.sprite:update(dt)
end

local TopDown = class(Mode)
TopDown.liveScripts = true

function TopDown:init(def)
    Mode.init(self, def)
    local g = G()
    local st = g.state
    assert(def.map, "stage '" .. tostring(def.name) .. "': kind topdown needs map = \"assets/maps/....tmx\"")
    local world = World(def.map, { reflections = def.reflections })
    self.world = world
    world.scene, world.fx = self, self.fx
    self.camera = Camera(screen.width, screen.height)
    self.camera.zoom = def.zoom or 2
    self.camera:setBounds(0, 0, world.width, world.height)
    world.camera = self.camera

    local sx, sy = world:spawn(def.spawn or "player")
    self.player = world:add(Player(sx, sy, { sprite = def.playerSprite }))
    world.player = self.player
    self.camera:lookAt(sx, sy - 12)
    self.trail = Trail(3, 800)
    self.trail:reset(sx, sy)
    self.followers = {}
    self:partyChanged()
    self:spawnObjects()

    world.triggers.defaultHandler = function(zone, who, event)
        if event == "leave" then
            return false
        end
        return g.trigger(self, zone, event, who)
    end
    self.deathTime = nil
    if st.hp <= 0 then
        st.hp = st.maxHp
        self.player.hp = st.hp
    end
end

function TopDown:enter()
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

-- unique key of a map object: "island:12"
function TopDown:key(o)
    return self.name .. ":" .. tostring(o.id ~= 0 and o.id or o.name)
end

local function objectPoint(o)
    if o.shape == "point" then
        return o.x, o.y
    elseif o.gid then
        return o.x + (o.width or 0) / 2, o.y -- tile objects are anchored at the bottom
    end
    return o.x + (o.width or 0) / 2, o.y + (o.height or 0)
end
TopDown.objectPoint = objectPoint

function TopDown:spawnObjects()
    local g = G()
    local st = g.state
    local world = self.world
    for _, o in ipairs(world:objectsOf("Item")) do
        local p = o.properties or {}
        local item = p.item or (o.name ~= "" and o.name or nil)
        local key = self:key(o)
        if item and not st.collected[key] and not (g.items[item] and g.items[item].ability and st.abilities[g.items[item].ability]) then
            local x, y = objectPoint(o)
            world:add(Pickup(item, x, y, { count = p.count, objectId = key }))
        end
    end
    for _, o in ipairs(world:objectsOf("Mob")) do
        local p = o.properties or {}
        local kind = p.mob or o.name
        local key = self:key(o)
        if g.mobs[kind] and not st.defeated[key] then
            local x, y = objectPoint(o)
            world:add(Mob(kind, x, y, key))
        elseif not g.mobs[kind] then
            print("[topdown] unknown mob '" .. tostring(kind) .. "' in " .. tostring(self.def.map))
        end
    end
    for _, o in ipairs(world:objectsOf("NPC")) do
        local npc = world:add(NPC(o))
        local p = o.properties or {}
        world.triggers:add(o.name, npc.x - 22, npc.y - 30, 44, 44, {
            interact = true, prompt = p.prompt or "Поговорить", dialogue = p.dialogue, once = p.once,
        })
    end
end

-- party ------------------------------------------------------------------------------

function TopDown:partyChanged()
    for _, f in ipairs(self.followers) do
        f:remove()
    end
    self.followers = {}
    local p = self.player
    for i, id in ipairs(G().state.party) do
        local x, y = self.trail:at(26 * i)
        local f = Follower(id, x or p.x, y or p.y, self.trail, i)
        f.spacing = (G().pets[id] and G().pets[id].spacing) or 26
        f.index = i
        self.world:add(f)
        table.insert(self.followers, f)
    end
end

function TopDown:syncPlayer()
    local st = G().state
    self.player.hp, self.player.maxHp = st.hp, st.maxHp
end

-- events from entities -----------------------------------------------------------

function TopDown:onPickup(pickup)
    self:fire("pickup", pickup.item, pickup.count)
end

function TopDown:dropLoot(mob)
    for _, d in ipairs(mob.def.drops or {}) do
        if love.math.random() < (d.chance or 1) then
            self.world:add(Pickup(d.item, mob.x, mob.y, { pop = true, auto = true, count = d.count }))
        end
    end
end

function TopDown:onMobKilled(mob)
    local st = G().state
    if mob.objectId then
        st.defeated[mob.objectId] = true
    end
    self:dropLoot(mob)
    self:fire("kill", mob.kind)
end

function TopDown:startBattle(mob, opts)
    if self.battleMob or scene.top() ~= self or scene.isTransitioning() then
        return
    end
    opts = opts or {}
    self.battleMob = mob
    audio.play("bdoom")
    local g = G()
    local enemies = mob.def.party or { mob.kind }
    g.play(self.def.battle or "battle", {
        enemies = enemies, advantage = opts.advantage, transition = "battle",
        background = self.def.battleBackground,
    }, function(result)
        self:battleOver(mob, result or {})
    end)
end

function TopDown:battleOver(mob, result)
    local st = G().state
    self.battleMob = nil
    if result.win then
        if mob.objectId then
            st.defeated[mob.objectId] = true
        end
        self.fx:burst(mob.x, mob.y - 10, { count = 18, color = { 0.5, 0.7, 1 }, speed = 90, life = 0.6, size = 3 })
        self:dropLoot(mob)
        mob:remove()
        self:fire("battleWon", mob.kind)
    elseif result.fled then
        mob.stunned = 3
        self.player.invulnerable = 2
        self.player:push(self.player.x - mob.x, self.player.y - mob.y, 260)
    else
        self:gameOver()
    end
end

function TopDown:gameOver()
    if self:fire("death") then
        return
    end
    local g = G()
    local st = g.state
    st.hp = st.maxHp
    if st.hero then
        st.hero.hp = st.hero.maxHp or st.hero.hp
    end
    for _, b in pairs(st.pets or {}) do
        b.hp = b.maxHp or b.hp
    end
    ui.toast("Гриша очнулся. Попробуй ещё раз!", { color = { 1, 0.85, 0.5 } })
    g.go(self.name, { spawn = self.def.spawn, transition = "fade" })
end

-- script commands ----------------------------------------------------------------

function TopDown:cmd_spawn(s, kind, x, y)
    if type(x) == "string" or x == nil then
        x, y = self.world:spawn(x or "player")
    end
    local mob = self.world:add(Mob(kind, x, y))
    self.fx:burst(x, y - 8, { count = 12, color = { 1, 1, 1 }, speed = 60, life = 0.4 })
    return mob
end

function TopDown:cmd_teleport(s, name, y)
    local x
    if type(name) == "number" then
        x = name
    else
        x, y = self.world:spawn(name)
    end
    self.player.x, self.player.y = x, y
    self.trail:reset(x, y)
    for _, f in ipairs(self.followers) do
        f.x, f.y = x, y
    end
    self.camera:lookAt(x, y)
end

function TopDown:cmd_face(s, dir)
    self.player.facing = dir
    self.player.sprite:play("idle", dir)
end

function TopDown:cmd_disable(s, zoneName)
    local zone = self.world.triggers:get(zoneName)
    if zone then
        zone.enabled = false
    end
end

function TopDown:cmd_enable(s, zoneName)
    local zone = self.world.triggers:get(zoneName)
    if zone then
        zone.enabled, zone.fired = true, false
    end
end

function TopDown:cmd_camera(s, zoom)
    self.timer:tween(0.6, self.camera, { zoom = zoom or 2 }, "quadInOut")
    return 0.6
end

-- callbacks ----------------------------------------------------------------------

function TopDown:update(dt, fromScript)
    Mode.update(self, dt)
    local world, player = self.world, self.player
    if fromScript or scene.top() ~= self then
        -- a dialogue is open: the world stands still, but stays alive
        world.map:update(dt)
        for _, f in ipairs(self.followers) do
            f.sprite:update(dt)
        end
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

    world:update(dt)
    self.trail:push(player.x, player.y)

    -- interact: pick up the nearest item, otherwise the trigger zones
    local interact = input.pressed("interact")
    self.prompt = nil
    local pickup = world:nearest(player.x, player.y - 4, 22, function(e)
        return e.pickable and not e.auto and not e.delay
    end)
    if pickup and not player.dying then
        self.prompt = "Поднять"
        if interact then
            pickup:collect(player)
            interact = false
        end
    end
    if not player.dying then
        local zone = world.triggers:update(player, interact)
        if zone and not self.prompt then
            local p = zone.properties
            self.prompt = (p.prompt and p.prompt ~= "") and p.prompt or "Осмотреть"
        end
    end

    -- the hero fell: wake up at the entrance
    if player.dying then
        self.deathTime = (self.deathTime or 0) + dt
        if self.deathTime > 1.6 and not self.deathHandled then
            self.deathHandled = true
            self:gameOver()
        end
    end

    self.camera:follow(player.x, player.y - 12, dt, 8)
    self.camera:update(dt)
    if engine.debug.enabled then
        engine.debug.watch("player", string.format("%d, %d  %s", player.x, player.y, tostring(world:surfaceAt(player.x, player.y - 2))))
    end
end

function TopDown:draw()
    self.world:draw(self.camera, {
        overlay = function()
            self.fx:draw()
        end,
    })
    if engine.debug.enabled then
        self.world:drawDebug(self.camera)
    end
    self:drawHud()
end

function TopDown:drawHud()
    if scene.top() ~= self then
        return
    end
    hud.draw({
        prompt = self.prompt,
        hint = hud.keys({ { "attack", "удар" }, { "throw", "камень" }, { "inventory", "сумка" }, { "pause", "пауза" } }),
    })
end

function TopDown:drawScriptOverlay()
    hud.draw({})
end

return TopDown
