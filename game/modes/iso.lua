-- Isometric field (kind = "iso"): an isometric Tiled map with height levels,
-- the hero and his pet, and real-time fights right on the map, the way Chrono
-- Trigger starts its battles: walk too close to a group of enemies and they jump
-- into place around you, the music changes and the fight happens where you stand.
--
--   game.stage "meadow" {
--       kind = "iso", map = "assets/maps/iso_meadow.tmx",
--       music = "calm",                -- default: map property "music"
--       battleMusic = "arcade",        -- false: keep the field music in fights
--       zoom = 3,                      -- pixel size
--       triggers = { exit = "menu", sign = function(s, zone) s:say("...") end },
--       on = { battle = function(s, group) end, battleWon = function(s, group) end,
--              kill = function(s, mobKind) end, pickup = function(s, item) end, death = function(s) end },
--   }
--
-- Fighting: [Space] combo of up to 3 hits (the weapon in the bag decides the reach,
-- the power and how it looks), [Shift] dash (nothing can hurt you while dashing),
-- [K] throw a stone, [Q] duo tech with Кашка when the bar is full. An enemy that
-- glows red is about to hit: hit it right then (the white spark) to PARRY it.
-- Hit a magic ball with the sword to send it back.
--
-- In Tiled (an isometric map, tile 32x16; see engine/isomap.lua for the levels and
-- tile properties): object layers Spawns (point "player"), Mobs (property mob, and
-- group: the enemies of one group fight together; boss = true), Items (item, count),
-- NPC (sprite, facing, dialogue), Triggers (rectangles: dialogue, go, interact, prompt, once).
-- Script commands of this mode: walk(who, spawnName | {x, y}), emote(who, "!"), hop(who),
-- face(dir), teleport(spawnName), pan(spawnName | who), panBack(), letterbox(on),
-- camera(zoom), spawn(mob, spawnName), disable(zone), enable(zone), duo(amount).

local engine = require("engine")
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local shaders = engine.shaders
local ui = engine.ui
local util = engine.util
local Camera = engine.Camera
local Trail = engine.Trail
local Triggers = engine.Triggers
local IsoMap = engine.IsoMap
local emote = engine.emote
local Mode = require("game.modes.base")
local hud = require("game.ui.hud")
local iso = require("game.entities.iso")
local rules = require("game.battle.rules")

local function G()
    return require("game")
end

local norm = iso.norm

local Iso = class(Mode)
Iso.liveScripts = true

function Iso:init(def)
    Mode.init(self, def)
    local g = G()
    local st = g.state
    assert(def.map, "stage '" .. tostring(def.name) .. "': kind iso needs map = \"assets/maps/....tmx\"")
    self.map = IsoMap(def.map)
    self.camera = Camera(screen.width, screen.height)
    self.camera.zoom = def.zoom or 3
    local l, t, w, h = self.map:bounds()
    self.camera:setBounds(l - 48, t - 24, w + 96, h + 48)
    self.fx.font = ui.font("tiny")
    self.actors = {}
    local sx, sy = self.map:spawn(def.spawn or "player")
    self.hero = self:addActor(iso.Hero(self, sx, sy, def.heroSprite))
    self.trail = Trail(3, 600)
    self.trail:reset(sx, sy, { z = self.hero.z })
    self.pets = {}
    self:partyChanged()
    self.groups = {}
    self:spawnObjects()
    self.triggers = Triggers(self.map:objectsOf("Triggers"))
    for _, p in ipairs(self.people or {}) do
        self.triggers:add(p.name, p.x - 14, p.y - 14, 28, 28, {
            interact = true, prompt = p.prompt or "Поговорить", dialogue = p.dialogue, once = p.once,
        })
    end
    self.triggers.defaultHandler = function(zone, who, event)
        if event == "leave" then
            return false
        end
        return g.trigger(self, zone, event, who)
    end
    if st.hp <= 0 then
        st.hp = st.maxHp
    end
    self.emotes = emote.List()
    self.duo = 0
    self.bars = 0
    self.walkers = {}
    self.hitstop = 0
    self.freeze = 0
    local hx, hy = self.hero:screen()
    self.camera:lookAt(hx, hy - 12)
end

function Iso:enter()
    local m = self.def.music
    if m == nil then
        m = self.map.properties.music
    end
    self.fieldMusic = m
    if m == false then
        audio.stopMusic(0.5)
    elseif m then
        audio.music(m)
    end
end

function Iso:addActor(a)
    table.insert(self.actors, a)
    return a
end

function Iso:key(o)
    return self.name .. ":" .. tostring(o.id ~= 0 and o.id or o.name)
end

function Iso:spawnObjects()
    local g = G()
    local st = g.state
    local map = self.map
    for _, o in ipairs(map:objectsOf("Items")) do
        local p = o.properties
        local item = p.item or (o.name ~= "" and o.name or nil)
        local key = self:key(o)
        local info = item and g.items[item]
        if item and not st.collected[key] and not (info and info.ability and st.abilities[info.ability]) then
            local x, y = map:objectPoint(o)
            self:addActor(iso.Loot(self, item, x, y, { count = p.count, objectId = key,
                auto = g.pickupMode(item, p.pickup) == "auto" }))
        end
    end
    for _, o in ipairs(map:objectsOf("Mobs")) do
        local p = o.properties
        local kind = p.mob or o.name
        local key = self:key(o)
        if not g.mobs[kind] then
            print("[iso] unknown mob '" .. tostring(kind) .. "' in " .. tostring(self.def.map))
        elseif not st.defeated[key] then
            local x, y = map:objectPoint(o)
            local groupName = (p.group and p.group ~= "") and p.group or key
            local e = self:addActor(iso.Enemy(self, kind, x, y, { group = groupName, objectId = key, boss = p.boss }))
            self:joinGroup(e, groupName)
        end
    end
    self.people = {}
    for _, o in ipairs(map:objectsOf("NPC")) do
        local person = self:addActor(iso.Person(self, o))
        local p = o.properties
        person.prompt, person.dialogue, person.once = p.prompt, p.dialogue, p.once
        table.insert(self.people, person)
    end
end

function Iso:joinGroup(e, name)
    local grp = self.groups[name]
    if not grp then
        grp = { name = name, members = {}, state = "idle" }
        self.groups[name] = grp
    end
    table.insert(grp.members, e)
    e.group = name
end

function Iso:partyChanged()
    for _, p in ipairs(self.pets) do
        p:remove()
    end
    self.pets = {}
    local h = self.hero
    for i, id in ipairs(G().state.party) do
        local x, y = self.trail:at(18 * i)
        local pet = iso.Pet(self, id, x or h.x, y or h.y, self.trail, i)
        self:addActor(pet)
        table.insert(self.pets, pet)
    end
end

-- footsteps by the tile under the feet
function Iso:footstep(a)
    local _, cell = self.map:groundAt(a.x, a.y)
    local name = cell and cell.surface or G().surfaces.default
    local s = G().surfaces[name] or G().surfaces[G().surfaces.default]
    if s then
        audio.step(s.folder, { volume = (s.volume or 0.3) * 0.8 })
    end
end

-- fights ------------------------------------------------------------------------------------

function Iso:aliveMembers(grp)
    local list = {}
    for _, m in ipairs(grp.members) do
        if m:alive() then
            table.insert(list, m)
        end
    end
    return list
end

local SEE_THROUGH = { through = true } -- trees and rocks do not hide the hero, cliffs and water do

function Iso:checkEncounters()
    if self.battle or self.hero.state == "dead" then
        return
    end
    local h = self.hero
    for _, grp in pairs(self.groups) do
        if grp.state == "idle" then
            for _, m in ipairs(grp.members) do
                if m:alive() then
                    local aggro = m.idef.aggro or (m.boss and 72 or 56)
                    local d = m:distanceTo(h)
                    if d < aggro + 36 and math.abs(m.z - h.z) < 1.5 and self.map:clearLine(h.x, h.y, h.z, m.x, m.y, SEE_THROUGH) then
                        if d < aggro then
                            self:startEncounter(grp)
                            return
                        elseif (m.noticed or 0) < self.time - 6 then
                            -- "?": it has heard something and looks at the hero
                            m.noticed = self.time
                            m:faceHero()
                            m:play("idle")
                            m.state, m.t, m.wanderX = "idle", 1.2, nil
                            self.emotes:add(m, "?", 0.9)
                        end
                    end
                end
            end
        end
    end
end

-- a free spot for a jump: walkable, not much higher or lower than z
function Iso:spotNear(x, y, z, radius)
    for _, r in ipairs({ 0, 6, 12, 18 }) do
        for k = 0, 7 do
            local a = k * math.pi / 4
            local px, py = x + math.cos(a) * r, y + math.sin(a) * r
            local ok, g = self.map:walkable(px, py, z + 1.1)
            if ok and math.abs(g - z) <= 1.1 and self.map:fits(px, py, g, radius or 4) then
                return px, py
            end
            if r == 0 then
                break
            end
        end
    end
end

function Iso:startEncounter(grp)
    local h = self.hero
    local members = self:aliveMembers(grp)
    if #members == 0 then
        return
    end
    self.battle = grp
    grp.state, grp.xp, grp.coins = "active", 0, 0
    audio.play("bdoom", { volume = 0.6 })
    local bm = self.def.battleMusic
    if bm == nil then
        bm = "arcade"
    end
    if bm then
        audio.music(bm)
    end
    self.freeze = 0.75
    h.state = "move"
    h:play("idle")
    -- the field of the fight: around the hero and the group
    local mx, my = 0, 0
    for _, m in ipairs(members) do
        mx, my = mx + m.x / #members, my + m.y / #members
    end
    self.arena = { x = (h.x + mx) / 2, y = (h.y + my) / 2, r = 100, t = 0 }
    local ax, ay = norm(mx - h.x, my - h.y)
    if ax == 0 and ay == 0 then
        ax, ay = 1, 0
    end
    h.facing = iso.faceOf(ax, ay, h.facing)
    h.aimX, h.aimY = ax, ay
    local base = math.atan2(ay, ax)
    for k, m in ipairs(members) do
        self.emotes:add(m, "!", 0.9)
        m:engage()
        local r = (m.ai == "caster" and 58) or (m.boss and 34) or 30
        local a = base + (k - (#members + 1) / 2) * 0.75
        local px, py = self:spotNear(h.x + math.cos(a) * r, h.y + math.sin(a) * r, m.z, m.radius)
        if px then
            self.timer:after(0.12 + k * 0.1, function()
                if m:alive() then
                    m:hopTo(px, py, 0.42, 1.3)
                end
            end)
        end
    end
    for i, pet in ipairs(self.pets) do
        local px, py = self:spotNear(h.x - ax * 12 + ay * 10 * i, h.y - ay * 12 - ax * 10 * i, h.z, pet.radius)
        if px then
            self.timer:after(0.2, function()
                pet:hopTo(px, py, 0.35, 0.9)
            end)
        end
        self.emotes:add(pet, "!", 0.7)
    end
    self:fire("battle", grp.name)
end

function Iso:checkVictory()
    local grp = self.battle
    if grp and not self.tech and #self:aliveMembers(grp) == 0 then
        self:victory(grp)
    end
end

function Iso:victory(grp)
    local g = G()
    local st = g.state
    grp.state = "done"
    self.battle, self.arena = nil, nil
    if self.def.battleMusic ~= false and self.fieldMusic then
        audio.music(self.fieldMusic)
    end
    audio.play("fanfare", { volume = 0.6 })
    local lines = {}
    local ups = rules.addXp(st.hero, grp.xp, g.player.battle and g.player.battle.growth)
    if #ups > 0 then
        table.insert(lines, "Гриша: уровень " .. st.hero.level .. "!")
    end
    for _, id in ipairs(st.party) do
        local b = st.pets[id]
        local pdef = g.pets[id] or {}
        if b then
            local pu = rules.addXp(b, grp.xp, pdef.battle and pdef.battle.growth)
            if #pu > 0 then
                table.insert(lines, (pdef.name or id) .. ": уровень " .. b.level .. "!")
            end
        end
    end
    local reward = "+" .. grp.xp .. " опыта"
    if grp.coins > 0 then
        reward = reward .. "   +" .. grp.coins .. " монет"
    end
    self.banner = { title = "Победа!", line = reward, extra = lines, t = 0 }
    if self.hero.state == "move" then
        self.hero:pose("release", 0.7)
    end
    for _, pet in ipairs(self.pets) do
        pet.vz = 5
        pet.z = pet.z + 0.05
    end
    self:fire("battleWon", grp.name)
end

function Iso:addDuo(amount)
    if #self.pets == 0 then
        return
    end
    local was = self.duo
    self.duo = math.min(100, self.duo + amount)
    if was < 100 and self.duo >= 100 then
        audio.play("bell", { volume = 0.5 })
    end
end

-- the direction to the enemy the hero most likely wants to hit (nil: keep his own)
function Iso:aimAssist(h, steering)
    local best, bestScore
    for _, a in ipairs(self.actors) do
        if a.isEnemy and a:alive() and math.abs(a.z - h.z) < 1.3 then
            local dx, dy = a.x - h.x, a.y - h.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < h.reach + a.radius + 14 and d > 0.01 then
                local dot = (dx * h.aimX + dy * h.aimY) / d
                if not steering or dot > 0.45 then
                    local score = d - dot * 10
                    if not bestScore or score < bestScore then
                        best, bestScore = a, score
                    end
                end
            end
        end
    end
    if best then
        local nx, ny = norm(best.x - h.x, best.y - h.y)
        return nx, ny
    end
end

-- the hero's swing hits everything in front of him
function Iso:heroStrike(h, step)
    local reach = h.reach + (step == 3 and 3 or 0)
    local dmg = h.power + (step == 3 and 1 or 0)
    local hit = false
    for _, a in ipairs(self.actors) do
        if a.isEnemy and a:alive() and math.abs(a.z - h.z) < 1.3 then
            local dx, dy = a.x - h.x, a.y - h.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < reach + a.radius and (d < a.radius + 5 or (dx * h.atkX + dy * h.atkY) / math.max(d, 0.01) > 0.2) then
                local result, killed = a:hurt(dmg, h, { knock = step == 3 and 120 or 55 })
                if result then
                    hit = true
                    self:onEnemyHit(a, dmg * (result == "parry" and 2 or 1), result, killed)
                end
            end
        elseif a.isShot and a.team == "enemy" and a:distanceTo(h) < reach + 5 then
            if a:reflect(h) then
                local sx, sy = a:screen()
                self.fx:popup(sx, sy - 8, "Отбил!", { color = { 1, 0.9, 0.4 } })
                audio.play("dzing", { volume = 0.5 })
                self:addDuo(10)
                hit = true
            end
        end
    end
    if hit then
        self.hitstop = step == 3 and 0.08 or 0.045
        audio.play("hit", { pitch = 0.9 + step * 0.1 })
        if step == 3 then
            self.camera:shake(2.5, 0.15)
        end
    end
end

function Iso:onEnemyHit(e, dmg, result, killed)
    local sx, sy = e:head()
    -- numbers that come one after another do not cover each other
    self.popSide = -(self.popSide or 1)
    self.fx:popup(sx + self.popSide * (3 + love.math.random() * 4), sy - love.math.random() * 4, dmg, { color = result == "parry" and { 1, 0.85, 0.3 } or { 1, 1, 1 } })
    self.fx:play("slash", sx, sy + 10, { scale = 0.32 })
    self.fx:burst(sx, sy + 10, { count = 6, color = { 1, 0.95, 0.75 }, speed = 60, life = 0.25, size = 1 })
    if result == "parry" then
        self.fx:popup(sx, sy - 10, "Парирование!", { color = { 1, 0.85, 0.3 }, life = 1.1 })
        audio.play("dzing", { volume = 0.6 })
        self:addDuo(25)
        self.hitstop = 0.12
    elseif result == "interrupt" then
        self.fx:popup(sx, sy - 10, "Сбит!", { color = { 0.8, 0.9, 1 } })
        self:addDuo(12)
    else
        self:addDuo(7)
    end
    if killed then
        self:enemyDied(e)
    end
    -- hit from afar (a stone): the whole group comes for the hero
    local grp = e.group and self.groups[e.group]
    if not self.battle and grp and grp.state == "idle" then
        self:startEncounter(grp)
    end
end

function Iso:enemyDied(e)
    local g = G()
    local st = g.state
    if e.objectId then
        st.defeated[e.objectId] = true
    end
    local sx, sy = e:screen()
    self.fx:burst(sx, sy - 10, { count = 16, color = { 0.6, 0.75, 1 }, speed = 70, life = 0.5, size = 2 })
    audio.play("pop", { volume = 0.6 })
    local grp = self.groups[e.group]
    local xp = e.idef.xp or 4
    local c = e.idef.coins
    local coins = c and love.math.random(c[1], c[2] or c[1]) or 0
    if grp then
        grp.xp = (grp.xp or 0) + xp
        grp.coins = (grp.coins or 0) + coins
    end
    for _ = 1, math.min(coins, 6) do
        self:addActor(iso.Loot(self, "coin", e.x, e.y, { pop = true, magnet = true,
            count = 1 }))
    end
    if coins > 6 then
        self:addActor(iso.Loot(self, "coin", e.x, e.y, { pop = true, magnet = true, count = coins - 6 }))
    end
    for _, d in ipairs(e.def.drops or {}) do
        if love.math.random() < (d.chance or 1) then
            self:addActor(iso.Loot(self, d.item, e.x, e.y, { pop = true, auto = true, count = d.count }))
        end
    end
    self:fire("kill", e.kind)
end

-- an enemy swings: does it reach the hero?
function Iso:enemyStrike(e, reach, anyDirection)
    local h = self.hero
    local dx, dy = h.x - e.x, h.y - e.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > reach + h.radius or math.abs(h.z - e.z) > 1.2 then
        return false
    end
    if not anyDirection and e.atkX and (dx * e.atkX + dy * e.atkY) / math.max(d, 0.01) < 0.1 then
        return false
    end
    if h.state == "roll" then
        local sx, sy = h:head()
        self.fx:popup(sx, sy, "Мимо!", { color = { 0.7, 0.9, 1 } })
        self:addDuo(10)
        return false
    end
    return h:hurt(e.damage, e)
end

function Iso:onWindup(e)
    audio.play("blip", { volume = 0.25, pitch = e.boss and 0.8 or 1.5 })
end

function Iso:onHeroHurt(h, amount)
    local sx, sy = h:head()
    self.fx:popup(sx, sy, "-" .. amount, { color = { 1, 0.45, 0.4 } })
    self.camera:shake(3, 0.2)
    self.hitstop = 0.06
end

function Iso:petTarget(pet)
    if not self.battle or self.tech then
        return nil
    end
    local best, bd = nil, 140
    for _, m in ipairs(self.battle.members) do
        if m:alive() and not m.hopping then
            local d = m:distanceTo(pet)
            if d < bd then
                best, bd = m, d
            end
        end
    end
    return best
end

function Iso:petBite(pet, target)
    -- Кашка only nibbles: no parries, no staggers (that is Гриша's job)
    local result, killed = target:hurt(1, pet, { knock = 35, noParry = true, noStagger = true })
    if result then
        audio.play("punch", { volume = 0.4, pitch = 1.4 })
        self:onEnemyHit(target, 1, result, killed)
    end
end

function Iso:shotFly(s)
    if s.team == "enemy" then
        local h = self.hero
        if s:distanceTo(h) < h.radius + 3 and math.abs(s.z - (h.z + 0.9)) < 1.2 then
            if h:hurt(1, s) then
                self:shotBroke(s)
                s:remove()
            elseif h.state == "roll" then
                -- dashed through it
            end
        end
    else
        for _, a in ipairs(self.actors) do
            if a.isEnemy and a:alive() and s:distanceTo(a) < a.radius + 3 and math.abs(s.z - (a.z + 0.8)) < 1.3 then
                local dmg = s.kind == "stone" and 1 or 2
                local result, killed = a:hurt(dmg, s, { knock = 50, stun = s.kind == "stone" and 1.0 or nil })
                if result then
                    audio.play("hit", { pitch = 1.3 })
                    self:onEnemyHit(a, dmg, result, killed)
                    if not killed and s.kind == "stone" then
                        local hx, hy = a:head()
                        self.fx:popup(hx, hy - 10, "Оглушён!", { color = { 1, 1, 0.6 } })
                    end
                end
                self:shotBroke(s)
                s:remove()
                return
            end
        end
    end
end

function Iso:shotBroke(s)
    local sx, sy = s:screen()
    local c = s.kind == "stone" and { 0.7, 0.7, 0.75 } or { 0.8, 0.55, 1 }
    self.fx:burst(sx, sy, { count = 8, color = c, speed = 40, life = 0.3, size = 1 })
end

-- duo tech: Гриша and Кашка leap from enemy to enemy together, like the double techs
-- of Chrono Trigger (the world darkens, only the fighters stay lit)
function Iso:duoTech()
    local h = self.hero
    if self.tech or h.state == "dead" or #self.pets == 0 then
        return
    end
    if self.duo < 100 then
        audio.play("error", { volume = 0.4 })
        return
    end
    local targets = {}
    for _, a in ipairs(self.battle and self.battle.members or self.actors) do
        if a.isEnemy and a:alive() and not a.hopping and a:distanceTo(h) < 140 and math.abs(a.z - h.z) < 2.5 then
            table.insert(targets, a)
        end
    end
    if #targets == 0 then
        engine.ui.toast("Рядом нет врагов")
        audio.play("error", { volume = 0.4 })
        return
    end
    table.sort(targets, function(a, b)
        return a:distanceTo(h) < b:distanceTo(h)
    end)
    while #targets > 5 do
        table.remove(targets)
    end
    self.duo = 0
    local pet = self.pets[1]
    local start, step = 0.6, 0.36
    local dur = start + #targets * step + 0.55
    self.tech = { name = "Морковный вихрь", t = 0, dur = dur, targets = targets }
    local homeX, homeY = h.x, h.y
    h.state, h.t = "pose", dur + 1
    h.dodge = dur + 0.4
    h:play("charge")
    h.glow, h.glowColor = 0.5, { 1, 0.7, 0.3 }
    audio.play("powerup", { volume = 0.6 })
    local px, py = self:spotNear(h.x + 8, h.y + 8, h.z, pet.radius)
    pet:hopTo(px or h.x, py or h.y, 0.3, 1.2)
    self.emotes:add(pet, "!", 0.5)
    for k, e in ipairs(targets) do
        local t0 = start + (k - 1) * step
        local dx, dy
        self.timer:after(t0, function()
            h.glow = nil
            if not e:alive() then
                return
            end
            -- Гриша lands on this side of the enemy, Кашка on the other
            dx, dy = norm(h.x - e.x, h.y - e.y)
            if dx == 0 and dy == 0 then
                dx, dy = -1, 0
            end
            local r = e.radius + 7
            local hx, hy = self:spotNear(e.x + dx * r, e.y + dy * r, e.z, h.radius)
            h:hopTo(hx or h.x, hy or h.y, 0.14, 0.6)
            h.facing = iso.faceOf(-dx, -dy, h.facing)
            h:play("walk", true)
            audio.play("dash", { volume = 0.45, pitch = 1 + k * 0.07 })
            local qx, qy = self:spotNear(e.x - dx * r, e.y - dy * r, e.z, pet.radius)
            self.timer:after(0.06, function()
                pet:hopTo(qx or pet.x, qy or pet.y, 0.16, 1)
                pet:faceScreen(e.x - (qx or pet.x), e.y - (qy or pet.y))
            end)
        end)
        self.timer:after(t0 + 0.16, function()
            if not e:alive() then
                return
            end
            local fx, fy = norm(e.x - h.x, e.y - h.y)
            h.atkX, h.atkY, h.combo = fx, fy, 3
            h.facing = iso.faceOf(fx, fy, h.facing)
            h:play("attack", true)
            audio.play("swing", { pitch = 1.05 + k * 0.06, volume = 0.55 })
            local sx, sy = e:head()
            self.fx:burst(sx, sy + 8, { count = 10, color = { 1, 0.55, 0.15 }, speed = 120, life = 0.45, size = 2 })
            self.fx:burst(sx, sy + 8, { count = 5, color = { 0.45, 0.9, 0.35 }, speed = 90, life = 0.4, size = 2 })
            local dmg = 3 + (k == #targets and 1 or 0)
            local result, killed = e:hurt(dmg, h, { knock = 50, stun = 1.2 })
            if result then
                self:onEnemyHit(e, dmg * (result == "parry" and 2 or 1), "hit", killed)
            end
            audio.play("hit", { pitch = 1 + k * 0.05 })
            self.hitstop = 0.05
            self.camera:shake(2, 0.12)
        end)
    end
    -- back home
    local back = start + #targets * step + 0.05
    self.timer:after(back, function()
        local hx, hy = self:spotNear(homeX, homeY, h.z, h.radius)
        h:hopTo(hx or h.x, hy or h.y, 0.25, 1)
        local qx, qy = self:spotNear(homeX + 9, homeY + 9, h.z, pet.radius)
        pet:hopTo(qx or pet.x, qy or pet.y, 0.28, 1.1)
    end)
    self.timer:after(dur, function()
        self.tech = nil
        if h.state ~= "dead" then
            h.state = "move"
        end
        h.dodge = 0.3
    end)
end

-- picking things up --------------------------------------------------------------------------

function Iso:collect(loot)
    local g = G()
    local st = g.state
    local def = loot.def
    if def.ability then
        st.abilities[def.ability] = true
        audio.play("powerup")
        ui.toast("Новая способность: " .. def.name, { icon = def.icon, color = { 1, 0.9, 0.4 } })
    elseif not st.inventory:add(loot.item, loot.count) then
        ui.toast("Сумка полна!")
        audio.play("error")
        return false
    elseif loot.item == "coin" then
        audio.play("coin", { volume = 0.4 })
    else
        audio.play("pickup")
        local text = (def.name or loot.item) .. (loot.count > 1 and (" ×" .. loot.count) or "")
        ui.toast("Подобрано: " .. text, { icon = def.icon })
    end
    local sx, sy = loot:screen()
    if loot.item ~= "coin" then
        self.fx:popup(sx, sy - 20, "+" .. loot.count, { color = { 1, 0.9, 0.45 } })
    end
    self.fx:burst(sx, sy - 6, { count = 6, color = { 1, 0.95, 0.6 }, speed = 40, life = 0.35, size = 1 })
    if loot.objectId then
        st.collected[loot.objectId] = true
    end
    loot:remove()
    self:fire("pickup", loot.item, loot.count)
    return true
end

-- the actors push each other apart a little
function Iso:separate()
    local list = {}
    for _, a in ipairs(self.actors) do
        if (a.isEnemy and a:alive() and not a.hopping) or a.isHero or a.isPerson then
            table.insert(list, a)
        end
    end
    for i = 1, #list do
        local a = list[i]
        for j = i + 1, #list do
            local b = list[j]
            local dx, dy = b.x - a.x, b.y - a.y
            local min = a.radius + b.radius
            local d2 = dx * dx + dy * dy
            if d2 < min * min and math.abs(a.z - b.z) < 1 then
                local d = math.sqrt(d2)
                local nx, ny = d > 0.01 and dx / d or 1, d > 0.01 and dy / d or 0
                local push = (min - d)
                local wa = a.isPerson and 0 or (b.isPerson and 1 or 0.5)
                if a.isHero and b.isEnemy then
                    wa = 0.5
                end
                a:move(-nx * push * wa, -ny * push * wa)
                b:move(nx * push * (1 - wa), ny * push * (1 - wa))
            end
        end
    end
end

function Iso:clampToArena(a)
    local ar = self.arena
    local dx, dy = a.x - ar.x, a.y - ar.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > ar.r then
        local tx, ty = ar.x + dx / d * ar.r, ar.y + dy / d * ar.r
        if self.map:fits(tx, ty, a.z, a.radius) then
            a.x, a.y = tx, ty
        end
    end
end

-- script commands ------------------------------------------------------------------------

function Iso:entityOf(who)
    if type(who) == "table" then
        return who
    end
    if who == nil or who == "hero" or who == "player" or who == "grisha" then
        return self.hero
    end
    for _, p in ipairs(self.pets) do
        if p.petId == who then
            return p
        end
    end
    for _, a in ipairs(self.actors) do
        if a.name == who or a.kind == who then
            return a
        end
    end
end

function Iso:pointOf(target)
    if type(target) == "table" and target[1] then
        return target[1], target[2]
    elseif type(target) == "table" then
        return target.x, target.y
    end
    local e = type(target) == "string" and target ~= "hero" and self:entityOf(target)
    if e and e ~= self.hero then
        return e.x, e.y
    end
    return self.map:spawn(target)
end

function Iso:cmd_emote(s, who, kind, duration)
    local e = self:entityOf(who)
    if e then
        self.emotes:add(e, kind, duration)
        audio.play("blip", { volume = 0.5, pitch = kind == "!" and 1.4 or 1 })
    end
end

function Iso:cmd_hop(s, who)
    local e = self:entityOf(who)
    if e then
        e.vz = 5
        e.z = e.z + 0.05
    end
end

function Iso:cmd_face(s, dir, who)
    local e = self:entityOf(who)
    if e then
        e.facing = dir
        e:play("idle")
    end
end

function Iso:cmd_teleport(s, name)
    local x, y = self:pointOf(name)
    local h = self.hero
    h.x, h.y = x, y
    h.z = self.map:groundAt(x, y) or h.z
    self.trail:reset(x, y, { z = h.z })
    for _, p in ipairs(self.pets) do
        p.x, p.y, p.z = x, y, h.z
    end
    local sx, sy = h:screen()
    self.camera:lookAt(sx, sy - 12)
end

function Iso:cmd_walk(s, who, target, speed)
    local e = self:entityOf(who)
    if not e then
        return nil
    end
    local tx, ty = self:pointOf(target)
    table.insert(self.walkers, { e = e, x = tx, y = ty, speed = speed or 45, director = s })
    return "wait"
end

function Iso:updateWalkers(dt)
    for i = #self.walkers, 1, -1 do
        local w = self.walkers[i]
        local e = w.e
        local nx, ny, d = norm(w.x - e.x, w.y - e.y)
        if d < 1.5 then
            e.x, e.y = w.x, w.y
            table.remove(self.walkers, i)
            if e.sprite then
                e:play("idle")
            end
            e.walking = false
            if e == self.hero then
                self.trail:reset(e.x, e.y, { z = e.z })
            end
            w.director:continue()
        else
            local step = math.min(d, w.speed * dt)
            e.x, e.y = e.x + nx * step, e.y + ny * step
            e.z = self.map:groundAt(e.x, e.y) or e.z
            e.facing = iso.faceOf(nx, ny, e.facing)
            e.walking = true
            if e.isPet then
                e:faceScreen(nx, ny)
                e.sprite:play("walk", e.dir)
            else
                e:play("walk")
            end
            if e == self.hero then
                self.trail:push(e.x, e.y, { z = e.z })
            end
        end
    end
end

function Iso:cmd_pan(s, target, time)
    local x, y = self:pointOf(target)
    local sx, sy = self.map:project(x, y, self.map:groundAt(x, y) or 0)
    self.panning = { x = self.camera.x, y = self.camera.y }
    self.timer:tween(time or 1, self.panning, { x = sx, y = sy - 12 }, "quadInOut")
    return time or 1
end

function Iso:cmd_panBack(s, time)
    if self.panning then
        local hx, hy = self.hero:screen()
        self.timer:tween(time or 0.8, self.panning, { x = hx, y = hy - 12 }, "quadInOut", function()
            self.panning = nil
        end)
        return time or 0.8
    end
end

function Iso:cmd_letterbox(s, on)
    self.timer:tween(0.5, self, { bars = on == false and 0 or 1 }, "quadInOut")
end

function Iso:cmd_camera(s, zoom)
    self.timer:tween(0.6, self.camera, { zoom = zoom or 3 }, "quadInOut")
    return 0.6
end

function Iso:cmd_spawn(s, kind, where)
    local x, y = self:pointOf(where or "player")
    local e = self:addActor(iso.Enemy(self, kind, x, y))
    self:joinGroup(e, "script" .. tostring(e))
    local sx, sy = e:screen()
    self.fx:burst(sx, sy - 8, { count = 12, color = { 1, 1, 1 }, speed = 60, life = 0.4 })
    return e
end

function Iso:cmd_disable(s, zoneName)
    local zone = self.triggers:get(zoneName)
    if zone then
        zone.enabled = false
    end
end

function Iso:cmd_enable(s, zoneName)
    local zone = self.triggers:get(zoneName)
    if zone then
        zone.enabled, zone.fired = true, false
    end
end

function Iso:cmd_duo(s, amount)
    self:addDuo(amount or 100)
end

function Iso:textEvent(speaker, name, value)
    local who = speaker and speaker.id
    if name == "emote" or name == "emotion" then
        self:cmd_emote(nil, who, value)
    elseif name == "hop" then
        self:cmd_hop(nil, who)
    elseif name == "shake" or name == "quake" then
        self.camera:shake(tonumber(value) or 4, 0.4)
    elseif name == "sound" then
        audio.play(value)
    end
end

function Iso:gameOver()
    if self:fire("death") then
        return
    end
    local g = G()
    local st = g.state
    st.hp = st.maxHp
    ui.toast("Гриша очнулся. Попробуй ещё раз!", { color = { 1, 0.85, 0.5 } })
    g.go(self.name, { spawn = self.def.spawn, transition = "fade" })
end

-- update -------------------------------------------------------------------------------------

function Iso:updateCamera(dt)
    local h = self.hero
    local tx, ty = h:screen()
    ty = ty - 14
    if self.panning then
        tx, ty = self.panning.x, self.panning.y
    elseif self.arena then
        local ax, ay = self.map:project(self.arena.x, self.arena.y, h.z)
        tx, ty = (tx * 2 + ax) / 3, (ty * 2 + ay - 14) / 3
    end
    self.camera:follow(tx, ty, dt, 7)
    self.camera:update(dt)
end

function Iso:update(dt, fromScript)
    Mode.update(self, dt)
    self.map:update(dt)
    self.emotes:update(dt)
    if self.banner then
        self.banner.t = self.banner.t + dt
        if self.banner.t > 3.2 then
            self.banner = nil
        end
    end
    if fromScript or scene.top() ~= self then
        -- a dialogue is open: the world stands still, but stays alive
        self.cutscene = true
        for _, a in ipairs(self.actors) do
            if a.hopping then
                a:updateHop(dt)
            elseif a.vz ~= 0 and a.physics and not a.isShot then
                a:physics(dt)
            end
            if a.sprite then
                a.sprite:update(dt)
            end
        end
        self:updateWalkers(dt)
        self:updateCamera(dt)
        self.prompt, self.nearby = nil, nil
        return
    end
    self.cutscene = false
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
    if self.hitstop > 0 then
        self.hitstop = self.hitstop - dt
        self.camera:update(dt)
        return
    end

    local h = self.hero
    h:refreshWeapon()
    local ix, iy = iso.fromScreen(input.direction())
    local actions = {
        attack = input.pressed("attack"), dash = input.pressed("dash"), throw = input.pressed("throw"),
    }
    if self.tech then
        self.tech.t = self.tech.t + dt
    end
    if self.freeze > 0 or self.tech then
        self.freeze = math.max(0, self.freeze - dt)
        ix, iy, actions = 0, 0, {}
    end
    if h.state ~= "dead" and not self.tech and input.pressed("tech") then
        self:duoTech()
    end
    h:control(dt, ix, iy, actions)
    for _, a in ipairs(self.actors) do
        if not (self.tech and a.isEnemy and not a.hopping) then
            a:update(dt)
        elseif a.sprite then
            a:updateTimers(dt)
            a.sprite:update(dt)
            a:physics(dt)
        end
    end
    for i = #self.actors, 1, -1 do
        if self.actors[i].removed then
            table.remove(self.actors, i)
        end
    end
    self:separate()
    if self.arena then
        self.arena.t = self.arena.t + dt
        self:clampToArena(h)
        for _, p in ipairs(self.pets) do
            if not p.hopping then
                self:clampToArena(p)
            end
        end
        for _, m in ipairs(self.battle.members) do
            if m:alive() and not m.hopping then
                self:clampToArena(m)
            end
        end
    end
    self.trail:push(h.x, h.y, { z = h.z })
    self:checkEncounters()
    self:checkVictory()

    -- picking up, talking, trigger zones
    local interact = input.pressed("interact")
    self.prompt, self.nearby = nil, nil
    local best, bd = nil, 15
    for _, a in ipairs(self.actors) do
        if a.pickable and not a.removed and (a.delay or 0) <= 0 and h.state ~= "dead" then
            local d = a:distanceTo(h)
            if (a.auto or a.magnet) and d < 8 and math.abs(a.z - h.z) < 1.2 then
                self:collect(a)
            elseif not a.auto and not a.magnet and d < bd then
                best, bd = a, d
            end
        end
    end
    if best then
        self.prompt = "Поднять: " .. (best.def.name or best.item)
        self.nearby = best
        if interact then
            self:collect(best)
            interact = false
        end
    end
    if h.state ~= "dead" and not self.battle then
        local zone = self.triggers:update(h, interact)
        if zone and not self.prompt then
            local p = zone.properties
            self.prompt = (p.prompt and p.prompt ~= "") and p.prompt or "Осмотреть"
            self.nearby = zone
        end
    end

    if h.state == "dead" then
        self.deathTime = (self.deathTime or 0) + dt
        if self.deathTime > 1.8 and not self.deathHandled then
            self.deathHandled = true
            self:gameOver()
        end
    end
    self:updateCamera(dt)
    if engine.debug.enabled then
        local g, cell = self.map:groundAt(h.x, h.y)
        engine.debug.watch("hero", string.format("%.1f, %.1f z=%.2f ground=%s %s", h.x, h.y, h.z, tostring(g),
            tostring(cell and cell.surface)))
    end
end

-- drawing ----------------------------------------------------------------------------------------

-- the field of a fight: a ring of little lights on the ground
function Iso:drawArena()
    local ar = self.arena
    if not ar then
        return
    end
    local k = math.min(1, ar.t / 0.5)
    local n = 56
    for i = 0, n - 1 do
        local a = i / n * math.pi * 2 + ar.t * 0.15
        local x, y = ar.x + math.cos(a) * ar.r * k, ar.y + math.sin(a) * ar.r * k
        local g = self.map:groundAt(x, y)
        if g then
            local sx, sy = self.map:project(x, y, g)
            local pulse = 0.5 + 0.5 * math.sin(ar.t * 4 + i * 0.9)
            love.graphics.setColor(1, 0.85, 0.45, (0.25 + 0.35 * pulse) * k)
            love.graphics.rectangle("fill", math.floor(sx), math.floor(sy) - 1, 1, 1)
            love.graphics.rectangle("fill", math.floor(sx) - 1, math.floor(sy), 3, 1)
            love.graphics.rectangle("fill", math.floor(sx), math.floor(sy) + 1, 1, 1)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- hp bars over hurt enemies, the parry spark, emotes, the "!" over the hero
function Iso:drawWorldUI()
    for _, a in ipairs(self.actors) do
        if a.isEnemy and a:alive() then
            local hx, hy = a:head()
            if (a.hpShown > 0 or (a.boss and self.battle)) and not a.boss then
                local w = 16
                local x, y = math.floor(hx - w / 2), math.floor(hy - 6)
                love.graphics.setColor(0.05, 0.05, 0.1, 0.8)
                love.graphics.rectangle("fill", x - 1, y - 1, w + 2, 4)
                love.graphics.setColor(0.95, 0.35, 0.3, 1)
                love.graphics.rectangle("fill", x, y, math.max(0, math.floor(w * a.hp / a.maxHp + 0.5)), 2)
            end
            if a.state == "windup" and a.t <= a.parryWindow then
                -- the parry window: a white spark over the weapon
                local k = a.t / a.parryWindow
                local r = 2 + 4 * (1 - k)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.setLineWidth(1)
                local cx, cy = math.floor(hx + (a.flip and -7 or 7)), math.floor(hy + 4)
                love.graphics.line(cx - r, cy, cx + r, cy)
                love.graphics.line(cx, cy - r, cx, cy + r)
                love.graphics.circle("fill", cx, cy, 1)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    self.emotes:draw(function(e)
        local hx, hy = e:head()
        return hx, hy - 2
    end, 0.42)
    if self.nearby and self.hero.state ~= "dead" then
        local hx, hy = self.hero:head()
        emote.draw(self.nearby.pickable and "?" or "!", hx, hy - 2, 1 + (self.time % 10), 0.42)
    end
end

-- x-ray: whoever stands behind a tree or a cliff shows through as a silhouette
-- (the hero and his pets in blue, the enemies of the fight in red)
function Iso:drawXray(left, top, w, h)
    local mask, flash = shaders.get("alphamask"), shaders.get("flash")
    if not mask or not flash then
        return
    end
    local list = { self.hero }
    for _, p in ipairs(self.pets) do
        table.insert(list, p)
    end
    if self.battle then
        for _, m in ipairs(self.battle.members) do
            if m:alive() then
                table.insert(list, m)
            end
        end
    end
    local u = self.map.unit
    for _, a in ipairs(list) do
        local sx, sy = a:screen()
        if a.alpha > 0.5 and not a.removed and sx > left - 24 and sx < left + w + 24 and sy > top and sy < top + h + 40 then
            local d0 = math.floor(a.x / u) + math.floor(a.y / u)
            love.graphics.stencil(function()
                love.graphics.setShader(mask)
                self.map:drawFront(sx - 20, sy - 44, 40, 48, d0)
                love.graphics.setShader()
            end, "replace", 1)
            love.graphics.setStencilTest("greater", 0)
            love.graphics.setShader(flash)
            shaders.send(flash, "amount", 1)
            shaders.send(flash, "flashColor", a.isEnemy and { 1, 0.45, 0.5 } or { 0.55, 0.8, 1 })
            a.sprite:draw(sx, sy, { flip = a.flip, scale = a.scale, color = { 1, 1, 1, 0.6 } })
            love.graphics.setShader()
            love.graphics.setStencilTest()
        end
    end
end

function Iso:draw()
    local bg = self.map.background
    love.graphics.setColor(bg[1], bg[2], bg[3], 1)
    love.graphics.rectangle("fill", 0, 0, screen.width, screen.height)
    love.graphics.setColor(1, 1, 1, 1)
    self.camera:attach()
    local left, top, w, h = self.camera:getVisible()
    self.map:draw(left, top, w, h, self.actors)
    self:drawXray(left, top, w, h)
    if self.tech then
        -- the tech: the world darkens, the fighters stay lit (like in Chrono Trigger)
        local t = self.tech
        local k = math.max(0, math.min(1, t.t / 0.25, (t.dur - t.t) / 0.3))
        love.graphics.setColor(0.02, 0.02, 0.07, 0.6 * k)
        love.graphics.rectangle("fill", left - 2, top - 2, w + 4, h + 4)
        love.graphics.setColor(1, 1, 1, 1)
        local lit = { self.hero }
        for _, p in ipairs(self.pets) do
            table.insert(lit, p)
        end
        for _, e in ipairs(t.targets) do
            if not e.removed then
                table.insert(lit, e)
            end
        end
        table.sort(lit, function(p, q)
            return p.x + p.y < q.x + q.y
        end)
        for _, a in ipairs(lit) do
            a:draw()
        end
    end
    self:drawArena()
    self.fx:draw()
    self:drawWorldUI()
    if engine.debug.enabled then
        self.map:drawDebug(left, top, w, h)
    end
    self.camera:detach()
    if self.bars > 0 then
        local bh = math.floor(56 * self.bars)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, 0, screen.width, bh)
        love.graphics.rectangle("fill", 0, screen.height - bh, screen.width, bh)
        love.graphics.setColor(1, 1, 1, 1)
    end
    self:drawHud()
end

-- a small window at the top: tech names, the victory (lines: more text under the title)
local function topWindow(title, lines, alpha, y)
    local font = ui.font("body")
    local small = ui.font("small")
    lines = type(lines) == "string" and { lines } or lines or {}
    local w = font:getWidth(title)
    for _, l in ipairs(lines) do
        w = math.max(w, small:getWidth(l))
    end
    w = w + 48
    local h = font:getHeight() + #lines * (small:getHeight() + 4) + 18 + (#lines > 0 and 2 or 0)
    local x = math.floor(screen.width / 2 - w / 2)
    y = y or 24
    ui.panel.draw(x, y, w, h)
    ui.print(title, screen.width / 2, y + 8, { font = font, align = "center", alpha = alpha })
    for k, l in ipairs(lines) do
        ui.print(l, screen.width / 2, y + 10 + font:getHeight() + (k - 1) * (small:getHeight() + 4),
            { font = small, align = "center", color = k == 1 and "light" or { 1, 0.85, 0.4 }, alpha = alpha })
    end
    return h
end

function Iso:drawHud()
    if scene.top() ~= self then
        return
    end
    local st = G().state
    hud.draw({
        prompt = self.prompt,
        hint = hud.keys({ { "attack", "удар" }, { "dash", "рывок" }, { "throw", "камень" }, { "tech", "дуэт" },
            { "inventory", "сумка" } }),
        owner = self,
    })
    -- the duo gauge next to the hearts
    if #self.pets > 0 then
        local hearts = math.ceil(st.maxHp / 2)
        local x = 16 + hearts * 38 * 0.75 + 14
        local y = 22
        local full = self.duo >= 100
        local w = 92
        love.graphics.setColor(0.05, 0.05, 0.12, 0.75)
        love.graphics.rectangle("fill", x - 1, y - 1, w + 2, 7)
        local pulse = full and (0.75 + 0.25 * math.sin(self.time * 8)) or 1
        love.graphics.setColor(1 * pulse, 0.55 * pulse, 0.25 * pulse, 1)
        love.graphics.rectangle("fill", x, y, math.floor(w * self.duo / 100 + 0.5), 5)
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.rectangle("fill", x, y, math.floor(w * self.duo / 100 + 0.5), 1)
        love.graphics.setColor(1, 1, 1, 1)
        if full then
            ui.print("[" .. input.keyName("tech") .. "] Морковный вихрь", x + w + 10, y - 7,
                { font = "small", color = { 1, 0.75, 0.4 }, shadow = true })
        end
    end
    -- the boss
    if self.battle then
        for _, m in ipairs(self.battle.members) do
            if m.boss and m:alive() then
                local w = 240
                local x, y = math.floor(screen.width / 2 - w / 2), 30
                ui.print(m.name, screen.width / 2, y - 22, { font = "small", align = "center", shadow = true })
                love.graphics.setColor(0.05, 0.05, 0.12, 0.8)
                love.graphics.rectangle("fill", x - 1, y - 1, w + 2, 7)
                love.graphics.setColor(0.9, 0.3, 0.3, 1)
                love.graphics.rectangle("fill", x, y, math.floor(w * m.hp / m.maxHp + 0.5), 5)
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end
    if self.tech then
        topWindow(self.tech.name, nil, 1, 70)
    end
    if self.banner then
        local b = self.banner
        local a = math.min(1, b.t / 0.2, (3.2 - b.t) / 0.4)
        local lines = { b.line }
        if #b.extra > 0 then
            table.insert(lines, table.concat(b.extra, "   "))
        end
        love.graphics.setColor(1, 1, 1, a)
        topWindow(b.title, lines, a, 70)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function Iso:drawScriptOverlay()
    hud.draw({})
end

return Iso
