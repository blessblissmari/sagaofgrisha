-- Dungeon crawler in pseudo-3D (Eye of the Beholder / Legend of Grimrock style):
-- you move by cells and turn by 90 degrees, walls are textured, monsters are
-- billboards, the automap remembers where you have been. Combat is real-time
-- and first-person like in Daggerfall: drag the mouse to swing the weapon from
-- the bag (left-right = slash, down = chop, up = thrust) or press [Space].
--
--   game.stage "dungeon" {
--       kind = "raycaster", map = "assets/maps/dungeon.tmx",
--       music = "calm", battle = "battle",          -- mobs with touch = "battle" start a turn-based battle
--       floor = 13, ceiling = 4, fog = "#101018",   -- textures (index in the atlas) and fog color
--       triggers = { exit = { "island", spawn = "from_dungeon" } },
--   }
--
-- Tiled: tile layer "Walls" (tile = texture of the atlas, empty = floor), objects:
--   Spawn (name "player", property angle 0 / 90 / 180 / 270), Mob (mob), Item (item, count),
--   Trigger (zones: dialogue, go, prompt, interact, once - like in the top-down world).
-- Texture 6 = door (opens with [F]), texture 12 = locked door (needs a key).
--
-- Controls: [W/S] or arrows step, [A/D] strafe, [Q/E] or [←/→] turn, [F] use,
-- [Space] / mouse drag attack, [Shift] / right mouse block, [M] map, [I] bag.
-- Raycasting: Lode Vandevenne's tutorial https://lodev.org/cgtutor/raycasting.html
-- (DDA walls, z-buffered sprites; the floor and ceiling are drawn by a shader).

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local shaders = engine.shaders
local ui = engine.ui
local util = engine.util
local anim = engine.anim
local tiled = engine.tiled
local Mode = require("game.modes.base")
local hud = require("game.ui.hud")

local function G()
    return require("game")
end

local Raycaster = class(Mode)
Raycaster.liveScripts = true

local DIRS = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } -- east, south, west, north
local COMPASS = { "В", "Ю", "З", "С" }
local STEP_TIME, TURN_TIME = 0.2, 0.16

local function toColor(c, default)
    if type(c) == "string" then
        return util.hexColor(c)
    end
    return c or default
end

-- the hand frames: "Fantasy FPS Hands" by Ragnar Random (CC0), reduced to 24 colors
-- The weapon is held between two layers of the hand: the fist, then the weapon, then
-- fist_N_front (the fingers in front of the handle, cut out of the same frame), so the
-- guard rests on the fist and the handle goes inside it.
local HANDS = {
    fist = { "assets/sprites/fp/fist_1.png", "assets/sprites/fp/fist_2.png", "assets/sprites/fp/fist_3.png" },
    front = { "assets/sprites/fp/fist_1_front.png", "assets/sprites/fp/fist_2_front.png", "assets/sprites/fp/fist_3_front.png" },
    open = "assets/sprites/fp/hand_open.png",
}
-- where the handle goes into each fist frame: the hollow between the thumb and the index
-- finger (the front layer is everything of the hand below it, so the thumb and the fingers
-- close over the handle). The icons have the blade up-left; they are turned blade up.
-- Items set grip = { x, y }: the point of their 34x34 icon that sits there (on the handle,
-- just under the guard). tools/fp_masks.py cuts the front layers along the same lines.
local AUTOMAP = {}
local GRIP = { { 71, 55 }, { 65, 46 }, { 75, 53 } }
local UPRIGHT = math.pi / 4 - 0.4 -- icon blade up-left -> up, leaning a bit to the left

-- The walls get mipmaps: far walls are smaller than their 64 px texture, and without the
-- smaller copies the texture pixels jump from column to column while walking (the walls
-- shimmer, as if loading, every time a big room comes into view). Power-of-two sheets only
-- (WebGL 1); nil when the GPU says no.
local mipmapCache = {}
function Raycaster.mipmapped(path)
    if mipmapCache[path] ~= nil then
        return mipmapCache[path] or nil
    end
    local function pot(n) return n > 0 and 2 ^ math.floor(math.log(n) / math.log(2) + 0.5) == n end
    local ok, image = pcall(love.graphics.newImage, path, { mipmaps = true })
    if ok and image and pot(image:getWidth()) and pot(image:getHeight()) then
        image:setFilter("nearest", "nearest")
        pcall(image.setMipmapFilter, image, "linear")
    else
        image = false
    end
    mipmapCache[path] = image
    return image or nil
end

function Raycaster:init(def)
    Mode.init(self, def)
    local g = G()
    local st = g.state
    assert(def.map, "stage '" .. tostring(def.name) .. "': kind raycaster needs map = \"assets/maps/....tmx\"")
    self.W, self.H = def.width or 320, def.height or 180
    self.canvas = love.graphics.newCanvas(self.W, self.H)
    self.canvas:setFilter("nearest", "nearest")
    local map = tiled.load(def.map)
    self.map = map
    self.cols, self.rows = map.width, map.height
    self.tile = map.tilewidth
    local p = map.properties or {}
    local texPath = def.textures or p.textures or "assets/sprites/walls/walls.png"
    self.atlas = assets.image(texPath) -- the floor and the ceiling (shader) read this one
    self.wallAtlas = Raycaster.mipmapped(texPath) or self.atlas
    self.ts = def.textureSize or p.textureSize or 64
    self.atlasCols = math.floor(self.atlas:getWidth() / self.ts)
    self.floorTex = def.floor or p.floor or 13
    self.ceilTex = def.ceiling or p.ceiling or 4
    self.fogColor = toColor(def.fog or p.fog, { 0.06, 0.06, 0.09 })
    self.fogDist = def.fogDistance or p.fogDistance or 7
    self.doorTex = def.doorTexture or p.doorTexture or 6
    self.lockedTex = def.lockedTexture or p.lockedTexture or 12
    self.battleStage = def.battle or "battle"
    self.quads = {}
    self.batch = love.graphics.newSpriteBatch(self.wallAtlas, self.W * 2 + 8, "stream") -- walls + an opening door
    self.zbuf = {}
    self.white = love.graphics.newImage(love.image.newImageData(1, 1, "rgba8", string.char(255, 255, 255, 255)))
    self.spriteQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    -- the grid
    self.grid = {}
    local layer
    for _, l in ipairs(map.layers) do
        if l.type == "tilelayer" and (l.name == "Walls" or not layer) then
            layer = l
        end
    end
    local firstgid = map.tilesets[1] and map.tilesets[1].firstgid or 1
    for y = 0, self.rows - 1 do
        self.grid[y] = {}
        for x = 0, self.cols - 1 do
            local gid = layer and layer.data[y * self.cols + x + 1] or 0
            self.grid[y][x] = gid > 0 and (gid - firstgid) or false
        end
    end
    -- doors opened earlier stay open
    for y = 0, self.rows - 1 do
        for x = 0, self.cols - 1 do
            if self.grid[y][x] and self:isDoor(self.grid[y][x]) and st.collected[self.name .. ":door:" .. x .. ":" .. y] then
                self.grid[y][x] = false
            end
        end
    end
    -- the automap is remembered while the game runs
    AUTOMAP[self.name] = AUTOMAP[self.name] or {}
    self.visited = AUTOMAP[self.name]
    self.mobs, self.items, self.zones, self.spawns = {}, {}, {}, {}
    self:loadObjects()
    -- the hero
    local spawn = self.spawns[def.spawn or "player"] or self.spawns.player or { 1, 1, 1 }
    self.cx, self.cy, self.dir = spawn[1], spawn[2], spawn[3]
    self.px, self.py = self.cx + 0.5, self.cy + 0.5
    self.angle = (self.dir - 1) * math.pi / 2
    self.moveT, self.queued = nil, nil
    self.bob, self.walkPhase = 0, 0
    self.hp = st.hp
    self.swing, self.blockK = nil, 0
    self.hurtFlash, self.hurtCooldown = 0, 0
    self.flicker = 1
    self.showMap = false
    self:markVisited()
    if st.hp <= 0 then
        st.hp = st.maxHp
    end
end

function Raycaster:enter()
    local m = self.def.music
    if m == nil then
        m = self.map.properties and self.map.properties.music
    end
    if m then
        audio.music(m)
    end
end

-- map -------------------------------------------------------------------------------

function Raycaster:key(o)
    return self.name .. ":" .. tostring(o.id ~= 0 and o.id or o.name)
end

function Raycaster:loadObjects()
    local g = G()
    local st = g.state
    local ts = self.tile
    local CLASSES = { Spawns = "Spawn", Items = "Item", Mobs = "Mob", Triggers = "Trigger", NPCs = "NPC", Decor = "Decor" }
    local function scan(layers)
        for _, l in ipairs(layers) do
            if l.type == "group" then
                scan(l.layers or {})
            elseif l.type == "objectgroup" then
                for _, o in ipairs(l.objects or {}) do
                    local c = (o.type and o.type ~= "") and o.type or o.class
                    if not c or c == "" then
                        c = CLASSES[l.name]
                    end
                    local props = o.properties or {}
                    local w, h = o.width or 0, o.height or 0
                    local top = o.gid and (o.y - h) or o.y -- tile objects: y is the bottom
                    local cx, cy = math.floor((o.x + w / 2) / ts), math.floor((top + h / 2) / ts)
                    if c == "Spawn" then
                        local a = tonumber(props.angle) or 0
                        local dir = ({ [0] = 1, [90] = 2, [180] = 3, [270] = 4 })[math.floor(a % 360)] or 1
                        self.spawns[o.name] = { cx, cy, dir }
                    elseif c == "Mob" then
                        local kind = props.mob or o.name
                        if g.mobs[kind] and not st.defeated[self:key(o)] then
                            self:addMob(kind, cx, cy, self:key(o))
                        end
                    elseif c == "Item" then
                        local item = props.item or o.name
                        if item and item ~= "" and not st.collected[self:key(o)] then
                            table.insert(self.items, { item = item, count = props.count or 1, cx = cx, cy = cy,
                                key = self:key(o), phase = love.math.random() * 6,
                                press = g.pickupMode(item, props.pickup) == "press" })
                        end
                    elseif c == "Trigger" or c == "NPC" then
                        local zone = { name = o.name, properties = props, cells = {} }
                        local x0, y0 = math.floor(o.x / ts), math.floor(top / ts)
                        local x1 = math.max(x0, math.ceil((o.x + w) / ts) - 1)
                        local y1 = math.max(y0, math.ceil((top + h) / ts) - 1)
                        for yy = y0, y1 do
                            for xx = x0, x1 do
                                zone.cells[yy * 1000 + xx] = true
                            end
                        end
                        table.insert(self.zones, zone)
                    end
                end
            end
        end
    end
    scan(self.map.layers)
end

function Raycaster:cell(x, y)
    if x < 0 or y < 0 or x >= self.cols or y >= self.rows then
        return 0
    end
    return self.grid[y][x]
end

function Raycaster:isDoor(tex)
    return tex == self.doorTex or tex == self.lockedTex
end

function Raycaster:mobAt(x, y)
    for _, m in ipairs(self.mobs) do
        if m.cx == x and m.cy == y and not m.dead then
            return m
        end
    end
end

function Raycaster:free(x, y, ignore)
    if self:cell(x, y) then
        return false
    end
    local m = self:mobAt(x, y)
    if m and m ~= ignore then
        return false
    end
    return not (x == self.cx and y == self.cy)
end

function Raycaster:markVisited()
    for dy = -1, 1 do
        for dx = -1, 1 do
            self.visited[(self.cy + dy) * 1000 + self.cx + dx] = true
        end
    end
end

function Raycaster:zonesAt(x, y)
    local list = {}
    for _, z in ipairs(self.zones) do
        if z.cells[y * 1000 + x] and z.enabled ~= false then
            table.insert(list, z)
        end
    end
    return list
end

-- mobs ------------------------------------------------------------------------------

function Raycaster:addMob(kind, cx, cy, key)
    local g = G()
    local def = g.mobs[kind]
    local sprite = anim.new(g.sprite(def.sprite or kind))
    sprite:play("idle", "down")
    local m = {
        kind = kind, def = def, cx = cx, cy = cy, x = cx + 0.5, y = cy + 0.5, key = key,
        hp = (def.rc and def.rc.hp) or (def.hp or 3) * 2, sprite = sprite,
        timer = 0.5 + love.math.random(), state = "idle", flash = 0, alpha = 1,
        scale = (def.rc and def.rc.scale) or def.rcScale or 0.55,
        float = (def.rc and def.rc.float) or ((def.ai == "flyer" or kind:find("ghost")) and 0.18 or 0),
        damage = def.damage or 1, sight = (def.rc and def.rc.sight) or 6,
        moveTime = (def.rc and def.rc.moveTime) or 0.9, windup = (def.rc and def.rc.windup) or 0.65,
    }
    table.insert(self.mobs, m)
    return m
end

local function sign(v)
    return v > 0 and 1 or (v < 0 and -1 or 0)
end

function Raycaster:canSee(m)
    local dx, dy = self.cx - m.cx, self.cy - m.cy
    if math.abs(dx) + math.abs(dy) > m.sight then
        return false
    end
    -- walk the line between the mob and the hero
    local steps = math.max(math.abs(dx), math.abs(dy))
    for i = 1, steps - 1 do
        local x = math.floor(m.cx + 0.5 + dx * i / steps)
        local y = math.floor(m.cy + 0.5 + dy * i / steps)
        if self:cell(x, y) then
            return false
        end
    end
    return true
end

function Raycaster:updateMob(m, dt)
    m.sprite:update(dt)
    m.flash = math.max(0, m.flash - dt)
    m.x = util.approach(m.x, m.cx + 0.5, dt * 4)
    m.y = util.approach(m.y, m.cy + 0.5, dt * 4)
    if m.dead then
        m.alpha = math.max(0, m.alpha - dt * 2)
        return
    end
    if m.stunned then
        m.stunned = m.stunned - dt
        if m.stunned <= 0 then
            m.stunned = nil
        end
        return
    end
    m.timer = m.timer - dt
    local dx, dy = self.cx - m.cx, self.cy - m.cy
    local adjacent = math.abs(dx) + math.abs(dy) == 1
    if m.state == "windup" then
        if m.timer <= 0 then
            m.state = "idle"
            m.timer = m.moveTime
            if adjacent then
                self:hurtHero(m)
            else
                audio.play("swing", { volume = 0.5, pitch = 0.8 })
            end
        end
        return
    end
    if m.timer > 0 then
        return
    end
    m.timer = m.moveTime * (0.85 + love.math.random() * 0.3)
    if adjacent then
        if m.def.touch == "battle" then
            self:startBattle(m)
            return
        end
        m.state = "windup"
        m.timer = m.windup
        audio.play("blip", { volume = 0.6, pitch = 0.6 })
        return
    end
    if self:canSee(m) then
        m.alert = true
        local options = {}
        if math.abs(dx) >= math.abs(dy) then
            options = { { sign(dx), 0 }, { 0, sign(dy) } }
        else
            options = { { 0, sign(dy) }, { sign(dx), 0 } }
        end
        for _, o in ipairs(options) do
            if (o[1] ~= 0 or o[2] ~= 0) and self:free(m.cx + o[1], m.cy + o[2], m) then
                m.cx, m.cy = m.cx + o[1], m.cy + o[2]
                m.sprite:play("walk", "down")
                break
            end
        end
    elseif love.math.random() < 0.3 then
        local d = DIRS[love.math.random(1, 4)]
        if self:free(m.cx + d[1], m.cy + d[2], m) then
            m.cx, m.cy = m.cx + d[1], m.cy + d[2]
        end
    end
end

function Raycaster:hurtHero(m)
    local st = G().state
    local dmg = m.damage
    if self.blocking then
        dmg = math.max(0, math.floor(dmg * 0.3))
        audio.play("hit", { pitch = 1.4, volume = 0.6 })
        self.blockFlash = 0.25
        if dmg == 0 then
            return
        end
    end
    -- armor softens blows: every 4 defense = -1
    dmg = math.max(1, dmg - math.floor(G().bonus("defense") / 4))
    st.hp = math.max(0, st.hp - dmg)
    self.hurtFlash = 0.5
    audio.play("hurt")
    self:cmd_shake(nil, 4, 0.3)
    if st.hp <= 0 then
        self.dying = true
        audio.play("death")
        self.timer:after(1.4, function() self:gameOver() end)
    end
end

function Raycaster:killMob(m)
    local g = G()
    m.dead = true
    audio.play("pop")
    if m.key then
        g.state.defeated[m.key] = true
    end
    for _, d in ipairs(m.def.drops or {}) do
        if love.math.random() < (d.chance or 1) then
            table.insert(self.items, { item = d.item, count = d.count or 1, cx = m.cx, cy = m.cy, phase = 0 })
        end
    end
    self:fire("kill", m.kind)
end

function Raycaster:startBattle(m)
    if self.inBattle or scene.top() ~= self then
        return
    end
    self.inBattle = m
    audio.play("bdoom")
    local g = G()
    g.play(self.battleStage, {
        enemies = m.def.party or { m.kind }, transition = "battle", background = self.def.battleBackground,
        sky = self.def.battleSky,
    }, function(result)
        self.inBattle = nil
        result = result or {}
        if result.win then
            self:killMob(m)
            m.alpha = 0
        elseif result.fled then
            m.stunned = 3
            local d = DIRS[self.dir]
            if self:free(m.cx + d[1], m.cy + d[2], m) then
                m.cx, m.cy = m.cx + d[1], m.cy + d[2]
            end
        else
            self:gameOver()
        end
    end)
end

function Raycaster:gameOver()
    if self:fire("death") then
        return
    end
    local g = G()
    local st = g.state
    st.hp = st.maxHp
    if st.hero then
        st.hero.hp = st.hero.maxHp or st.hero.hp
    end
    ui.toast("Гриша очнулся у входа в подземелье", { color = { 1, 0.85, 0.5 } })
    g.go(self.name, { spawn = self.def.spawn, transition = "fade" })
end

-- the hero ------------------------------------------------------------------------

function Raycaster:tryMove(dx, dy)
    local nx, ny = self.cx + dx, self.cy + dy
    local tex = self:cell(nx, ny)
    if tex or self:mobAt(nx, ny) then
        -- bumping into a wall (the hint "[F] Открыть" is shown under a door all the time)
        if (self.bump or 0) <= 0 then
            audio.play("stomp", { volume = 0.25, pitch = 0.7 })
        end
        self.bump = 0.15
        return
    end
    self.cx, self.cy = nx, ny
    self.moveFrom = { self.px, self.py }
    self.moveT = 0
    audio.step("boots", { volume = 0.35 })
    self:markVisited()
end

function Raycaster:turn(d)
    self.dir = (self.dir - 1 + d) % 4 + 1
    self.turnFrom = self.angle
    self.turnTo = self.angle + d * math.pi / 2
    self.turnT = 0
end

function Raycaster:enterCell()
    local g = G()
    -- "auto" items are picked up by walking over them, the others with [F]
    for i = #self.items, 1, -1 do
        local it = self.items[i]
        if it.cx == self.cx and it.cy == self.cy and not it.press then
            self:pickItem(it)
        end
    end
    for _, z in ipairs(self:zonesAt(self.cx, self.cy)) do
        local p = z.properties
        if not p.interact and not (p.once and z.fired) then
            z.fired = true
            g.trigger(self, z, "enter", self)
            return
        end
    end
end

function Raycaster:pickItem(it)
    local g = G()
    local info = g.items[it.item] or { name = it.item }
    if not g.state.inventory:add(it.item, it.count) then
        audio.play("error")
        ui.toast("Сумка полна!")
        return false
    end
    for i, other in ipairs(self.items) do
        if other == it then
            table.remove(self.items, i)
            break
        end
    end
    if it.key then
        g.state.collected[it.key] = true
    end
    audio.play(it.item == "coin" and "coin" or "pickup")
    ui.toast("Подобрано: " .. (info.name or it.item) .. (it.count > 1 and (" ×" .. it.count) or ""), { icon = info.icon })
    self:fire("pickup", it.item, it.count)
    return true
end

-- what is in front: a door, a zone to use, an NPC zone
function Raycaster:facing()
    local d = DIRS[self.dir]
    return self.cx + d[1], self.cy + d[2]
end

function Raycaster:useTarget()
    local fx, fy = self:facing()
    -- an item to pick up: under the feet or right in front
    for _, it in ipairs(self.items) do
        if it.press and ((it.cx == self.cx and it.cy == self.cy) or (it.cx == fx and it.cy == fy)) then
            return "item", it
        end
    end
    local tex = self:cell(fx, fy)
    if tex and self:isDoor(tex) then
        return "door", fx, fy, tex
    end
    for _, list in ipairs({ self:zonesAt(self.cx, self.cy), self:zonesAt(fx, fy) }) do
        for _, z in ipairs(list) do
            if z.properties.interact and not (z.properties.once and z.fired) then
                return "zone", z
            end
        end
    end
end

function Raycaster:use()
    local g = G()
    local kind, a, b, tex = self:useTarget()
    if kind == "door" then
        if tex == self.lockedTex then
            if g.state.inventory:has("key") then
                g.state.inventory:remove("key", 1)
                audio.play("unlock")
                ui.toast("Ключ подошёл!", { icon = "key" })
            else
                audio.play("error")
                ui.toast("Заперто. Нужен ключ", { icon = "key" })
                return
            end
        end
        self:openDoor(a, b)
    elseif kind == "item" then
        self:pickItem(a)
    elseif kind == "zone" then
        a.fired = true
        g.trigger(self, a, "interact", self)
    else
        audio.play("stomp", { volume = 0.2 })
    end
end

function Raycaster:openDoor(x, y)
    audio.play("door")
    self.opening = { x = x, y = y, tex = self.grid[y][x], k = 0 }
    self.grid[y][x] = false
    G().state.collected[self.name .. ":door:" .. x .. ":" .. y] = true -- stays open after saving
    self:fire("door", x, y)
end

-- first-person combat ----------------------------------------------------------------
-- swings: slash (left-right), chop (from above), thrust (forward); weapon.swing is the default

local SWINGS = {
    slash = { time = 0.42, hit = 0.45, power = 1, reach = 1 },
    chop = { time = 0.55, hit = 0.55, power = 1.5, reach = 1 },
    thrust = { time = 0.34, hit = 0.4, power = 0.8, reach = 2 },
}

function Raycaster:attack(kind)
    if self.swing or self.dying then
        return
    end
    local weapon = G().weapon()
    kind = kind or weapon.swing or "slash"
    local s = SWINGS[kind] or SWINGS.slash
    local speed = 1 + (weapon.speed or 0) * 0.08
    self.swing = { kind = kind, t = 0, time = s.time / speed, hitAt = s.hit, power = s.power, reach = s.reach, done = false }
    audio.play("swing", { pitch = kind == "chop" and 0.8 or (kind == "thrust" and 1.25 or 1) })
end

function Raycaster:resolveHit(sw)
    local weapon = G().weapon()
    local d = DIRS[self.dir]
    local reach = sw.reach >= 2 and (weapon.reach or 18) >= 26 and 2 or 1
    for r = 1, reach do
        local x, y = self.cx + d[1] * r, self.cy + d[2] * r
        if self:cell(x, y) then
            if r == 1 then
                audio.play("stomp", { volume = 0.4, pitch = 1.3 })
                self:cmd_shake(nil, 2, 0.15)
            end
            return
        end
        local m = self:mobAt(x, y)
        if m then
            local dmg = math.max(1, math.floor(((weapon.power or 1) + (G().bonus("attack") / 3)) * sw.power + 0.5))
            if m.state == "windup" then
                dmg = dmg + 1 -- hit it while it winds up: interrupt
                m.state = "idle"
                m.timer = m.moveTime
            end
            m.hp = m.hp - dmg
            m.flash = 0.18
            audio.play("hit")
            self:cmd_shake(nil, 3, 0.15)
            self.hitText = { text = "-" .. dmg, t = 0.7, x = m.x, y = m.y }
            if m.hp <= 0 then
                self:killMob(m)
            else
                -- knock back one cell
                if sw.kind == "chop" or sw.kind == "thrust" then
                    if self:free(m.cx + d[1], m.cy + d[2], m) then
                        m.cx, m.cy = m.cx + d[1], m.cy + d[2]
                    end
                end
                m.timer = math.max(m.timer, 0.4)
            end
            return
        end
    end
end

-- input -------------------------------------------------------------------------------

function Raycaster:handleInput(dt)
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
    if input.pressed("map") then
        self.showMap = not self.showMap
        audio.play(self.showMap and "card_flip" or "ui_back")
    end
    -- block: hold [Shift] or the right mouse button
    self.blocking = (input.down("block") or love.mouse.isDown(2)) and not self.swing
    -- attacks: mouse drag (Daggerfall) or keys
    local m = input.mouse
    if m.pressed[1] then
        self.drag = { x = m.x, y = m.y }
    end
    if self.drag and (m.released[1] or not love.mouse.isDown(1)) then
        local dx, dy = m.x - self.drag.x, m.y - self.drag.y
        self.drag = nil
        if math.abs(dx) < 12 and math.abs(dy) < 12 then
            self:attack()
        elseif math.abs(dx) > math.abs(dy) then
            self:attack("slash")
        elseif dy > 0 then
            self:attack("chop")
        else
            self:attack("thrust")
        end
    end
    if input.pressed("attack") then
        self:attack()
    end
    if input.pressed("use") then
        self:use()
    end
    -- movement (one command can wait while the previous one finishes)
    local cmd
    if input.pressed("forward", true) then cmd = "forward"
    elseif input.pressed("back", true) then cmd = "back"
    elseif input.pressed("strafeLeft", true) then cmd = "left"
    elseif input.pressed("strafeRight", true) then cmd = "right"
    elseif input.pressed("turnLeft", true) then cmd = "turnL"
    elseif input.pressed("turnRight", true) then cmd = "turnR"
    end
    -- holding a key keeps walking
    if not cmd and not self.moveT and not self.turnT then
        if input.down("forward") and not input.down("turnLeft") then cmd = "forward"
        elseif input.down("back") then cmd = "back" end
    end
    if cmd then
        self.queued = cmd
    end
    if self.queued and not self.moveT and not self.turnT then
        local c = self.queued
        self.queued = nil
        local d = DIRS[self.dir]
        if c == "forward" then self:tryMove(d[1], d[2])
        elseif c == "back" then self:tryMove(-d[1], -d[2])
        elseif c == "left" then self:tryMove(d[2], -d[1])
        elseif c == "right" then self:tryMove(-d[2], d[1])
        elseif c == "turnL" then self:turn(-1)
        elseif c == "turnR" then self:turn(1)
        end
    end
end

function Raycaster:update(dt, fromScript)
    Mode.update(self, dt)
    local st = G().state
    self.flicker = 0.92 + math.sin(self.time * 7) * 0.03 + math.sin(self.time * 13.3) * 0.02
    self.hurtFlash = math.max(0, self.hurtFlash - dt)
    self.blockFlash = math.max(0, (self.blockFlash or 0) - dt)
    self.bump = math.max(0, (self.bump or 0) - dt)
    if self.hitText then
        self.hitText.t = self.hitText.t - dt
        if self.hitText.t <= 0 then
            self.hitText = nil
        end
    end
    if self.opening then
        self.opening.k = self.opening.k + dt * 2.5
        if self.opening.k >= 1 then
            self.opening = nil
        end
    end
    -- smooth steps and turns
    if self.moveT then
        self.moveT = self.moveT + dt / STEP_TIME
        local k = math.min(1, self.moveT)
        local e = 1 - (1 - k) * (1 - k)
        self.px = util.lerp(self.moveFrom[1], self.cx + 0.5, e)
        self.py = util.lerp(self.moveFrom[2], self.cy + 0.5, e)
        self.walkPhase = self.walkPhase + dt * 14
        if k >= 1 then
            self.moveT = nil
            self:enterCell()
        end
    end
    if self.turnT then
        self.turnT = self.turnT + dt / TURN_TIME
        local k = math.min(1, self.turnT)
        self.angle = util.lerp(self.turnFrom, self.turnTo, k * k * (3 - 2 * k))
        if k >= 1 then
            self.turnT = nil
            self.angle = (self.dir - 1) * math.pi / 2
        end
    end
    self.bob = self.moveT and math.sin(self.walkPhase) * 1.5 or self.bob * 0.8
    self.blockK = util.approach(self.blockK, self.blocking and 1 or 0, dt * 8)
    if self.swing then
        local sw = self.swing
        sw.t = sw.t + dt / sw.time
        if not sw.done and sw.t >= sw.hitAt then
            sw.done = true
            self:resolveHit(sw)
        end
        if sw.t >= 1 then
            self.swing = nil
        end
    end
    for _, m in ipairs(self.mobs) do
        if fromScript or scene.top() ~= self or self.dying then
            m.sprite:update(dt)
        else
            self:updateMob(m, dt)
        end
    end
    for i = #self.mobs, 1, -1 do
        if self.mobs[i].dead and self.mobs[i].alpha <= 0 then
            table.remove(self.mobs, i)
        end
    end
    if fromScript or scene.top() ~= self or self.dying then
        return
    end
    self:handleInput(dt)
end

-- script commands ----------------------------------------------------------------------

function Raycaster:cmd_teleport(s, name)
    local sp = self.spawns[name]
    if sp then
        self.cx, self.cy, self.dir = sp[1], sp[2], sp[3]
        self.px, self.py = self.cx + 0.5, self.cy + 0.5
        self.angle = (self.dir - 1) * math.pi / 2
        self:markVisited()
    end
end

function Raycaster:cmd_face(s, dir)
    local d = ({ east = 1, right = 1, south = 2, down = 2, west = 3, left = 3, north = 4, up = 4 })[dir]
    if d then
        self.dir = d
        self.angle = (d - 1) * math.pi / 2
    end
end

function Raycaster:cmd_spawn(s, kind, cx, cy)
    if type(cx) == "string" then
        local sp = self.spawns[cx]
        cx, cy = sp[1], sp[2]
    end
    return self:addMob(kind, cx, cy)
end

function Raycaster:cmd_open(s, cx, cy)
    if self.grid[cy] and self.grid[cy][cx] then
        self:openDoor(cx, cy)
    end
end

function Raycaster:cmd_wall(s, cx, cy, tex)
    self.grid[cy][cx] = tex or 0
end

function Raycaster:cmd_disable(s, name)
    for _, z in ipairs(self.zones) do
        if z.name == name then
            z.enabled = false
        end
    end
end

-- rendering ------------------------------------------------------------------------------

function Raycaster:texQuad(tex, col)
    local key = tex * 1024 + col
    local q = self.quads[key]
    if not q then
        local ts = self.ts
        local tx = (tex % self.atlasCols) * ts
        local ty = math.floor(tex / self.atlasCols) * ts
        q = love.graphics.newQuad(tx + col, ty, 1, ts, self.atlas:getDimensions())
        self.quads[key] = q
    end
    return q
end

function Raycaster:texRect(tex)
    local ts = self.ts
    local aw, ah = self.atlas:getDimensions()
    return { (tex % self.atlasCols) * ts / aw, math.floor(tex / self.atlasCols) * ts / ah, ts / aw, ts / ah }
end

function Raycaster:render()
    local lg = love.graphics
    local W, H = self.W, self.H
    local posX, posY = self.px, self.py
    local a = self.angle
    local dirX, dirY = math.cos(a), math.sin(a)
    local planeX, planeY = -dirY * 0.66, dirX * 0.66
    local horizon = H / 2 + self.bob
    local fog = self.fogColor
    lg.setCanvas(self.canvas)
    lg.clear(fog[1], fog[2], fog[3], 1)
    lg.origin()
    -- floor and ceiling
    local floorShader = shaders.get("ray_floor")
    if floorShader then
        shaders.send(floorShader, "atlas", self.atlas)
        shaders.send(floorShader, "pos", { posX, posY })
        shaders.send(floorShader, "dir", { dirX, dirY })
        shaders.send(floorShader, "plane", { planeX, planeY })
        shaders.send(floorShader, "size", { W, H })
        shaders.send(floorShader, "horizon", horizon)
        shaders.send(floorShader, "floorRect", self:texRect(self.floorTex))
        shaders.send(floorShader, "ceilRect", self:texRect(self.ceilTex))
        shaders.send(floorShader, "fogColor", { fog[1], fog[2], fog[3] })
        shaders.send(floorShader, "fogDist", self.fogDist)
        shaders.send(floorShader, "light", self.flicker)
        lg.setShader(floorShader)
        lg.draw(self.white, 0, 0, 0, W, H)
        lg.setShader()
    else
        lg.setColor(0.22, 0.2, 0.2)
        lg.rectangle("fill", 0, horizon, W, H - horizon)
        lg.setColor(1, 1, 1)
    end
    -- walls: one textured column per screen column (DDA)
    local batch = self.batch
    batch:clear()
    local ts = self.ts
    local zbuf = self.zbuf
    local fogDist = self.fogDist
    local opening = self.opening
    local seen, seeDist = self.visited, math.min(5, fogDist * 0.7)
    -- distance -> texture column and height of one wall slice
    local function slice(perp, side, rdx, rdy)
        if perp < 0.0001 then
            perp = 0.0001
        end
        local wallX = side == 0 and (posY + perp * rdy) or (posX + perp * rdx)
        wallX = wallX - math.floor(wallX)
        local texX = math.floor(wallX * ts)
        if (side == 0 and rdx > 0) or (side == 1 and rdy < 0) then
            texX = ts - 1 - texX
        end
        return perp, texX, H / perp
    end
    for x = 0, W - 1 do
        local camX = 2 * x / W - 1
        local rdx, rdy = dirX + planeX * camX, dirY + planeY * camX
        local mapX, mapY = math.floor(posX), math.floor(posY)
        local ddx = rdx == 0 and 1e30 or math.abs(1 / rdx)
        local ddy = rdy == 0 and 1e30 or math.abs(1 / rdy)
        local stepX, stepY, sideX, sideY
        if rdx < 0 then stepX, sideX = -1, (posX - mapX) * ddx else stepX, sideX = 1, (mapX + 1 - posX) * ddx end
        if rdy < 0 then stepY, sideY = -1, (posY - mapY) * ddy else stepY, sideY = 1, (mapY + 1 - posY) * ddy end
        local side, tex = 0, nil
        local doorPerp, doorSide = nil, nil
        for _ = 1, 64 do
            if sideX < sideY then
                sideX = sideX + ddx
                mapX = mapX + stepX
                side = 0
            else
                sideY = sideY + ddy
                mapY = mapY + stepY
                side = 1
            end
            -- the automap remembers everything that was seen close enough
            if (side == 0 and sideX - ddx or sideY - ddy) < seeDist then
                seen[mapY * 1000 + mapX] = true
            end
            tex = self:cell(mapX, mapY)
            if tex then
                break
            end
            if opening and not doorPerp and opening.x == mapX and opening.y == mapY then
                -- the opening door: remember it and look further, the room behind it is
                -- drawn first (no black gap under the rising door)
                doorPerp, doorSide = side == 0 and (sideX - ddx) or (sideY - ddy), side
            end
        end
        local perp, texX, lineH = slice(side == 0 and (sideX - ddx) or (sideY - ddy), side, rdx, rdy)
        local top = horizon - lineH / 2
        batch:setColor((side == 1 and 0.75 or 1) * self.flicker, math.min(1, perp / fogDist), 0, 1)
        batch:add(self:texQuad(tex or 0, texX), x, top, 0, 1, lineH / ts)
        zbuf[x + 1] = perp
        if doorPerp then
            -- the door slides up into the ceiling
            local dPerp, dTexX, dLineH = slice(doorPerp, doorSide, rdx, rdy)
            local visible = 1 - opening.k
            if visible > 0 then
                batch:setColor((doorSide == 1 and 0.75 or 1) * self.flicker, math.min(1, dPerp / fogDist), 0, 1)
                batch:add(self:texQuad(opening.tex or 0, dTexX), x, horizon - dLineH / 2, 0, 1, dLineH * visible / ts)
            end
            if visible > 0.5 then
                zbuf[x + 1] = dPerp
            end
        end
    end
    local fogShader = shaders.get("ray_fog")
    if fogShader then
        shaders.send(fogShader, "fogColor", { fog[1], fog[2], fog[3] })
        lg.setShader(fogShader)
    end
    lg.setColor(1, 1, 1, 1)
    lg.draw(batch)
    -- sprites: mobs and items, far to near, column runs hidden behind walls are skipped
    local sprites = {}
    local invDet = 1 / (planeX * dirY - dirX * planeY)
    local function add(x, y, image, qx, qy, qw, qh, scale, float, flash, alpha)
        local sx, sy = x - posX, y - posY
        local tx = invDet * (dirY * sx - dirX * sy)
        local ty = invDet * (-planeY * sx + planeX * sy)
        if ty > 0.15 then
            table.insert(sprites, { tx = tx, ty = ty, image = image, qx = qx, qy = qy, qw = qw, qh = qh,
                scale = scale, float = float or 0, flash = flash or 0, alpha = alpha or 1 })
        end
    end
    for _, m in ipairs(self.mobs) do
        local q = m.sprite:getQuad()
        local qx, qy, qw, qh = q:getViewport()
        local lean = m.state == "windup" and 1.12 or 1
        add(m.x, m.y, m.sprite.image, qx, qy, qw, qh, m.scale * lean, m.float + (m.float > 0 and math.sin(self.time * 3) * 0.04 or 0),
            m.flash > 0 and 0.8 or (m.state == "windup" and (math.floor(self.time * 12) % 2) * 0.35 or 0), m.alpha)
    end
    local g = G()
    for _, it in ipairs(self.items) do
        local info = g.items[it.item] or {}
        local image = assets.image(ui.theme.icons .. (info.icon or "coin") .. ".png")
        local w, h = image:getDimensions()
        add(it.cx + 0.5, it.cy + 0.5, image, 0, 0, w, h, 0.22, 0.05 + math.abs(math.sin(self.time * 2 + it.phase)) * 0.05, 0, 1)
    end
    table.sort(sprites, function(p, q) return p.ty > q.ty end)
    local sq = self.spriteQuad
    for _, s in ipairs(sprites) do
        local screenX = W / 2 * (1 + s.tx / s.ty)
        local size = H / s.ty
        local sh = size * s.scale
        local sw = sh * s.qw / s.qh
        local bottom = horizon + (H / 2) / s.ty - s.float * size
        local top = bottom - sh
        local left = screenX - sw / 2
        local f = math.min(1, s.ty / fogDist)
        lg.setColor(self.flicker, f, s.flash, s.alpha)
        local x0, x1 = math.max(0, math.floor(left)), math.min(W - 1, math.floor(left + sw))
        local start = nil
        local iw, ih = s.image:getDimensions()
        for x = x0, x1 + 1 do
            local visible = x <= x1 and zbuf[x + 1] and zbuf[x + 1] > s.ty
            if visible and not start then
                start = x
            elseif not visible and start then
                local u0 = (start - left) / sw
                local u1 = (x - left) / sw
                u0, u1 = math.max(0, u0), math.min(1, u1)
                if u1 > u0 then
                    sq:setViewport(s.qx + u0 * s.qw, s.qy, (u1 - u0) * s.qw, s.qh, iw, ih)
                    lg.draw(s.image, sq, left + u0 * sw, top, 0, sw / s.qw, sh / s.qh)
                end
                start = nil
            end
        end
    end
    lg.setShader()
    lg.setColor(1, 1, 1, 1)
    self:drawWeapon()
    lg.setCanvas()
end

-- the hand with the weapon from the bag
function Raycaster:drawWeapon()
    local lg = love.graphics
    local g = G()
    local weapon, id = g.weapon()
    local W, H = self.W, self.H
    local frame = 1
    local dx, dy, rot = 0, 0, 0
    local sw = self.swing
    if sw then
        local k = sw.t
        local function curve(a, b, c)
            -- wind-up (0..0.3) -> strike (..0.6) -> back
            if k < 0.3 then
                return util.lerp(0, a, k / 0.3)
            elseif k < 0.6 then
                return util.lerp(a, b, (k - 0.3) / 0.3)
            end
            return util.lerp(b, c or 0, (k - 0.6) / 0.4)
        end
        if sw.kind == "slash" then
            dx, dy, rot = curve(30, -150), curve(-12, 10), curve(0.35, -0.7)
        elseif sw.kind == "chop" then
            dx, dy, rot = curve(-20, -50), curve(-70, 25), curve(0.6, -0.5)
        else
            dx, dy, rot = curve(10, -70), curve(6, -34), curve(0.1, -0.15)
        end
        frame = k < 0.3 and 1 or (k < 0.65 and 2 or 3)
    else
        dx = math.sin(self.walkPhase * 0.5) * 3
        dy = math.abs(math.cos(self.walkPhase * 0.5)) * 3 + math.sin(self.time * 2) * 1.5
    end
    -- block: the weapon goes across the screen
    local b = self.blockK
    dx, dy, rot = dx - 80 * b, dy - 26 * b, rot - 1.0 * b
    local hand = assets.image(HANDS.fist[frame])
    local hx, hy = W - hand:getWidth() + 18 + dx, H - hand:getHeight() + 12 + dy
    local grip = GRIP[frame]
    lg.setColor(1, 1, 1, 1)
    if weapon.fp then
        local image = assets.image(weapon.fp)
        lg.draw(image, W - image:getWidth() + dx, H - image:getHeight() + dy)
        return
    end
    lg.push()
    lg.translate(hx + grip[1], hy + grip[2])
    lg.rotate(rot * 0.5)
    lg.draw(hand, -grip[1], -grip[2])
    -- the sleeve continues below the frame when the arm is raised
    local hw, hh = hand:getDimensions()
    self.sleeveQuad = self.sleeveQuad or love.graphics.newQuad(0, hh - 2, hw, 2, hw, hh)
    lg.draw(hand, self.sleeveQuad, -grip[1], -grip[2] + hh - 1, 0, 1, 60)
    if id ~= "fists" and weapon.icon then
        -- the weapon icon from the bag, then the fingers over its handle
        local icon = assets.image(ui.theme.icons .. weapon.icon .. ".png")
        local wg = weapon.grip or { 26, 26 }
        lg.draw(icon, 0, 0, UPRIGHT + rot * 0.6, 2.4, 2.4, wg[1], wg[2])
        lg.draw(assets.image(HANDS.front[frame]), -grip[1], -grip[2])
    end
    lg.pop()
    if self.blockFlash > 0 then
        lg.setColor(1, 1, 1, self.blockFlash * 2)
        lg.rectangle("fill", 0, 0, W, H)
        lg.setColor(1, 1, 1, 1)
    end
end

function Raycaster:draw()
    local lg = love.graphics
    local prev = lg.getCanvas()
    self:render()
    lg.setCanvas(prev)
    local ox, oy = self:shakeOffset(love.timer.getDelta())
    local s = math.min(screen.width / self.W, screen.height / self.H)
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.canvas, math.floor((screen.width - self.W * s) / 2 + ox), math.floor((screen.height - self.H * s) / 2 + oy), 0, s, s)
    if self.hurtFlash > 0 then
        lg.setColor(0.8, 0, 0, self.hurtFlash * 0.7)
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
        lg.setColor(1, 1, 1, 1)
    end
    self:drawHud()
end

function Raycaster:drawMinimap(x, y, cell, radius, full)
    local lg = love.graphics
    local n = radius * 2 + 1
    local cx0, cy0 = self.cx - radius, self.cy - radius
    if full then
        cx0, cy0 = 0, 0
    end
    local cols = full and self.cols or n
    local rows = full and self.rows or n
    for yy = 0, rows - 1 do
        for xx = 0, cols - 1 do
            local mx, my = cx0 + xx, cy0 + yy
            if full and not self.visited[my * 1000 + mx] then
                -- unexplored: a faint dot shows how big the level is
                lg.setColor(1, 1, 1, 0.12)
                lg.rectangle("fill", x + xx * cell + cell / 2 - 1, y + yy * cell + cell / 2 - 1, 2, 2)
            elseif self.visited[my * 1000 + mx] then
                local tex = self:cell(mx, my)
                if tex then
                    if self:isDoor(tex) then
                        lg.setColor(0.85, 0.6, 0.25, 0.95)
                    else
                        lg.setColor(0.55, 0.6, 0.85, 0.9)
                    end
                else
                    lg.setColor(0.08, 0.1, 0.25, 0.85)
                end
                lg.rectangle("fill", x + xx * cell, y + yy * cell, cell - 1, cell - 1)
            end
        end
    end
    -- items and mobs that were seen
    for _, it in ipairs(self.items) do
        if self.visited[it.cy * 1000 + it.cx] then
            local xx, yy = it.cx - cx0, it.cy - cy0
            if xx >= 0 and yy >= 0 and xx < cols and yy < rows then
                lg.setColor(1, 0.85, 0.3, 1)
                lg.circle("fill", x + xx * cell + cell / 2, y + yy * cell + cell / 2, cell / 4)
            end
        end
    end
    -- the hero arrow
    local px, py = x + (self.cx - cx0) * cell + cell / 2, y + (self.cy - cy0) * cell + cell / 2
    local a = self.angle
    lg.setColor(1, 1, 1, 1)
    lg.polygon("fill", px + math.cos(a) * cell * 0.45, py + math.sin(a) * cell * 0.45,
        px + math.cos(a + 2.4) * cell * 0.4, py + math.sin(a + 2.4) * cell * 0.4,
        px + math.cos(a - 2.4) * cell * 0.4, py + math.sin(a - 2.4) * cell * 0.4)
end

function Raycaster:drawHud()
    local lg = love.graphics
    local st = G().state
    ui.hearts(16, 14, st.hp, st.maxHp, 0.75)
    -- minimap (north is up: a small "С" over it is the compass)
    if not self.showMap then
        local r, cell = 4, 12
        local size = (r * 2 + 1) * cell
        local mx, my = screen.width - size - 16, 16
        lg.setColor(0.02, 0.03, 0.12, 0.55)
        lg.rectangle("fill", mx - 4, my - 4, size + 8, size + 8, 4, 4)
        self:drawMinimap(mx, my, cell, r, false)
        ui.print("С", mx + size / 2, my - 4, { font = "small", align = "center", color = "accent" })
    end
    -- weapon and hints
    local weapon = G().weapon()
    if scene.top() == self and not self.showMap then
        local kind, a, b, tex = self:useTarget()
        if kind then
            local label = "Осмотреть"
            if kind == "door" then
                label = tex == self.lockedTex and (G().state.inventory:has("key") and "Открыть ключом" or "Заперто: нужен ключ") or "Открыть"
            elseif kind == "item" then
                label = "Поднять: " .. ((G().items[a.item] or {}).name or a.item)
            elseif kind == "zone" and a.properties.prompt and a.properties.prompt ~= "" then
                label = a.properties.prompt
            end
            ui.keyHint(screen.width / 2, screen.height - 92, "use", label)
        end
        ui.print(weapon.name or "", 16, screen.height - 36, { font = "small", color = "accent", alpha = 0.8 })
        local keys = "[" .. input.keyName("attack") .. "] / мышь — удар   [" .. input.keyName("block") .. "] блок   ["
            .. input.keyName("map") .. "] карта   [" .. input.keyName("inventory") .. "] сумка"
        local alpha = hud.hintAlpha(keys, self)
        if alpha > 0 then
            ui.print(keys, screen.width - 16, screen.height - 36, { font = "small", color = "light", align = "right", alpha = 0.75 * alpha })
        end
    end
    if self.hitText then
        ui.print(self.hitText.text, screen.width / 2, screen.height / 2 - 60 - (0.7 - self.hitText.t) * 60,
            { font = "body", align = "center", color = "gold", alpha = math.min(1, self.hitText.t * 3) })
    end
    -- the big map
    if self.showMap then
        ui.dim(0.5)
        local c = math.floor(math.min((screen.height - 150) / self.rows, (screen.width - 300) / self.cols))
        local w, h = self.cols * c, self.rows * c
        local x, y = math.floor((screen.width - w) / 2), math.floor((screen.height - h) / 2)
        ui.panel.draw(x - 20, y - 50, w + 40, h + 100)
        ui.print(self.def.title or "Карта подземелья", screen.width / 2, y - 40, { font = "small", align = "center", color = "accent" })
        self:drawMinimap(x, y, c, 0, true)
        ui.keyHints(screen.width / 2, y + h + 10, { { "map", "закрыть" } }, "center")
    end
    lg.setColor(1, 1, 1, 1)
end

function Raycaster:drawScriptOverlay()
end

return Raycaster
