-- The world map in 3D, like the world maps of Final Fantasy VII-IX: a small round
-- planet (the ground bends down with the distance and the world wraps around: walk off
-- the east edge and come back from the west), the PlayStation 1 look of engine/r3d.lua,
-- places to enter, a boat for the sea and random battles on the way.
--
--   game.stage "world" {
--       kind = "world", map = "assets/maps/world.tmx", music = "calm",
--       battle = "fight_world",          -- stage of the random battles (kind battle)
--       encounters = {                   -- ground group -> enemies (game/data/grounds.lua)
--           plains = { "blob_blue", "slime" }, forest = { "frog", "beetle" },
--       },
--       encounterRate = 1,               -- 0 = no random battles, 2 = twice as often
--       triggers = {                     -- place name in Tiled -> what happens (as in topdown)
--           island = { "island", spawn = "from_world" },
--           castle = function(s, place) s:say("Ворота закрыты.") end,
--       },
--   }
--
-- The Tiled map (assets/maps/world.tmx, orthogonal, 1 tile = 1 world unit) is painted with
-- the tiles of assets/maps/world.tsx: every tile has the property ground (deep, sea, beach,
-- grass, forest, mountain...: game/data/grounds.lua). Object layers (point objects):
--   Places   name, title (shown near it), prefab (game/data/prefabs.lua), prompt ("Войти")
--   Props    prefab, rot (degrees): docks, big trees, rocks...
--   Spawns   where Гриша appears (stage option spawn = "name"); "start"; "boat" = the boat
-- Keys (game.controls.world): WASD walk, Shift run, Q/E turn the camera, V near/far view,
-- M map, F enter / board the boat / go ashore, N journal, I bag, Esc pause.
-- Script commands: teleport(spawn), boat(spawn) (puts the boat there), camera(yaw, view),
-- emote(who, "!"), hop(who).
-- Stage options: curve (how round the world is, 0.005), fog = { start, end }, sky (a name
-- from game/data/skies.lua, default "world"), heroSprite, encounterSkies = { plains = "day" }.

local engine = require("engine")
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui
local anim = engine.anim
local emote = engine.emote
local tiled = engine.tiled
local util = engine.util
local r3d = require("engine.r3d")
local Mode = require("game.modes.base")
local hud = require("game.ui.hud")

local function G()
    return require("game")
end

local World = class(Mode)
World.liveScripts = true

local CW, CH = 320, 180          -- the PS1 canvas, scaled up to the screen
local CHUNK = 16                 -- tiles per side of a chunk: one mesh for the ground of each
local TEXELS = 24                -- sprite pixels per world unit
local FOV = 0.9
local VIEWS = {                  -- [V] switches between them
    { dist = 7.2, pitch = 0.5 },
    { dist = 12, pitch = 0.85 },
}
local WALK, RUN, ROW = 2.6, 1.65, 4.4   -- speeds: walking, running (x), the boat
local SKIES = { plains = "day", forest = "forest", hills = "meadow", desert = "sunset", snow = "snow" }
local BOAT_MODEL = "assets/models/boat/rowboat.obj"
local BOAT_TEXTURE = "assets/models/kenney/Textures/planks.png"
local TREES = { big = "assets/models/kenney/tree-large.obj", small = "assets/models/kenney/tree-shrub.obj" }

local TAU = math.pi * 2

local function clamp(v, a, b)
    return v < a and a or (v > b and b or v)
end

-- the shortest way from a to a + d on a world that wraps every n units
local function wrapDelta(d, n)
    return d - n * math.floor(d / n + 0.5)
end

local function wrapAngle(a)
    return (a + math.pi) % TAU - math.pi
end

-- smooth noise that wraps around with the world (a circle in 4D noise for each axis)
local function torusNoise(u, v, W, H, cells, seed)
    local a, b = u / W * TAU, v / H * TAU
    local r = cells / TAU
    return love.math.noise(math.cos(a) * r + seed, math.sin(a) * r + seed * 0.37,
        math.cos(b) * r + seed * 0.71, math.sin(b) * r)
end

-- the same random number for the same tile on every run
local function hash(i, j, seed)
    local x = math.sin(i * 127.1 + j * 311.7 + (seed or 0) * 74.7) * 43758.5453
    return x - math.floor(x)
end

-- sprite direction from where somebody goes and where the camera looks
local function facing(heading, yaw)
    local rel = wrapAngle(heading - yaw)
    if math.abs(rel) < math.pi / 4 then
        return "up"
    elseif math.abs(rel) > math.pi * 3 / 4 then
        return "down"
    end
    return rel > 0 and "right" or "left"
end

-- setup ----------------------------------------------------------------------------------

function World:init(def)
    Mode.init(self, def)
    local g = G()
    assert(def.map, "stage '" .. tostring(def.name) .. "': kind world needs map = \"assets/maps/....tmx\"")
    self.grounds = def.grounds or g.grounds
    self.prefabs = def.prefabs or g.prefabs
    -- more contrast on the ground than on the models: the slopes of the hills show
    self.light = { sun = r3d.light.sun, ambient = 0.42, diffuse = 0.78 }
    self:loadMap(def.map)
    self:buildHeights()
    self:buildTextures()
    self:buildVertices()
    self:buildChunks()
    self:buildMinimap()

    local skyDef = def.sky or "world"
    if type(skyDef) == "string" then
        skyDef = g.skies[skyDef] or g.skies.day
    end
    self.sky = engine.Sky(skyDef, g.backgrounds)
    self.fogColor = self.sky.horizon
    self.view = r3d.View(CW, CH, {
        fov = FOV, near = 0.1, far = 90, curve = def.curve or 0.005,
        fog = def.fog or { 12, 26 }, fogColor = self.fogColor, affine = 0.5,
    })
    self.ok = self.view.ok

    -- Гриша, the pets, the boat
    local st = g.state
    st.world = st.world or {}
    local saved = st.world
    local hero = anim.new(g.sprite(def.heroSprite or g.player.sprite or "grisha"))
    self.hero = { x = 0, z = 0, y = 0, heading = math.pi, sprite = hero, size = hero.frameWidth / TEXELS, height = 0.7 }
    local spawn = def.spawn and self.spawns[def.spawn]
    local x, z
    if spawn then
        x, z = spawn.x, spawn.z
    elseif saved.x and saved.stage == self.name then
        x, z = saved.x, saved.z
    else
        local s = self.spawns.start or self.spawns.player or next(self.spawns) and select(2, next(self.spawns))
        x, z = s and s.x or self.W / 2, s and s.z or self.H / 2
    end
    local boatSpawn = self.spawns.boat
    if saved.boat and saved.stage == self.name then
        self.boat = { x = saved.boat.x, z = saved.boat.z, rot = saved.boat.rot or 0 }
    elseif boatSpawn then
        self.boat = { x = boatSpawn.x, z = boatSpawn.z, rot = 0 }
    end
    self.inBoat = (not spawn) and saved.inBoat and self.boat ~= nil and saved.stage == self.name
    if def.spawn == "boat" and self.boat then
        -- arriving by the sea: Гриша sits in the boat
        self.inBoat = true
        x, z = self.boat.x, self.boat.z
        if spawn then
            self.boat.x, self.boat.z = spawn.x, spawn.z
            x, z = spawn.x, spawn.z
        end
    end
    self.yaw = saved.stage == self.name and saved.yaw or def.yaw or 0
    self.viewIndex = 1
    self.camDist, self.camPitch = VIEWS[1].dist, VIEWS[1].pitch
    self.trail = {}
    self:placeHero(x, z)
    self:partyChanged()
    self.camY = self.hero.y + 0.45
    self:updateCamera(0)

    self.batches = {
        shadow = r3d.Batch(self:shadowImage(), 16),
        hero = r3d.Batch(hero.image, 4),
    }
    self.emotes = emote.List()
    self.mapMode = 1           -- 1 = the small map in the corner, 2 = the big map, 0 = none
    self.danger = 0            -- walked on dangerous ground since the last battle
    self.nextBattle = self:battleDistance()
    self.safeTime = 2.5        -- no battles right after arriving
    self.titleAlpha = 0
    -- from now on a saved game returns to this very spot (st.world), not to the arrival spawn
    self:remember()
    st.spawn = nil
end

function World:enter()
    local m = self.def.music
    if m == nil then
        m = self.map.properties.music
    end
    if m == false then
        audio.stopMusic(0.5)
    elseif m then
        audio.music(m)
    end
end

-- the Tiled map: grounds, places, props, spawns
function World:loadMap(path)
    local map = tiled.load(path)
    self.map = map
    local W, H = map.width, map.height
    self.W, self.H = W, H
    local tw, th = map.tilewidth, map.tileheight
    local types = self.grounds.types
    local byGid, titles = {}, {}
    for _, ts in ipairs(map.tilesets) do
        for _, t in ipairs(ts.tiles or {}) do
            local name = t.properties and t.properties.ground
            if name then
                byGid[ts.firstgid + t.id] = name
                titles[name] = t.properties.title
            end
        end
    end
    self.titles = titles
    local layer
    for _, l in ipairs(map.layers) do
        if l.type == "tilelayer" and (l.name == "Ground" or not layer) then
            layer = l
        end
    end
    assert(layer, "world map " .. path .. ": needs a tile layer \"Ground\"")
    local fallback = types.deep and "deep" or next(types)
    self.tiles, self.tileNames = {}, {}
    for k = 1, W * H do
        local gid = (layer.data[k] or 0) % 0x10000000 -- without the flip bits
        local name = byGid[gid] or fallback
        if not types[name] then
            print("[world] unknown ground '" .. tostring(name) .. "'")
            name = fallback
        end
        self.tileNames[k] = name
        self.tiles[k] = types[name]
    end
    self.spawns, self.places, self.props = {}, {}, {}
    local kinds = { Spawns = "Spawn", Places = "Place", Props = "Prop" }
    for _, l in ipairs(map.layers) do
        if l.type == "objectgroup" then
            for _, o in ipairs(l.objects) do
                local x, z = o.x / tw, o.y / th
                if o.shape ~= "point" then
                    x, z = (o.x + o.width / 2) / tw, (o.y + o.height / 2) / th
                end
                local p = o.properties or {}
                local kind = (o.type ~= "" and o.type) or kinds[l.name]
                if kind == "Spawn" then
                    self.spawns[o.name] = { x = x, z = z }
                elseif kind == "Place" or kind == "Prop" or p.prefab then
                    local prefab = p.prefab and self.prefabs[p.prefab]
                    if p.prefab and not prefab then
                        print("[world] unknown prefab '" .. tostring(p.prefab) .. "'")
                    end
                    table.insert(kind == "Place" and self.places or self.props, {
                        name = o.name, x = x, z = z, rot = math.rad(tonumber(p.rot) or 0),
                        prefab = prefab, radius = prefab and prefab.radius,
                        title = p.title, prompt = p.prompt, properties = p,
                    })
                end
            end
        end
    end
end

function World:index(i, j)
    return (j % self.H) * self.W + (i % self.W) + 1
end

-- the ground type under a point (tile i covers x = i .. i + 1)
function World:groundAt(x, z)
    local k = self:index(math.floor(x), math.floor(z))
    return self.tiles[k], self.tileNames[k]
end

-- heights: one vertex in the middle of every tile
function World:buildHeights()
    local W, H = self.W, self.H
    local raw = {}
    for j = 0, H - 1 do
        for i = 0, W - 1 do
            local k = j * W + i + 1
            local t = self.tiles[k]
            local n = (torusNoise(i, j, W, H, 12, 1.3) - 0.5) * 1.6 + (torusNoise(i, j, W, H, 37, 4.1) - 0.5) * 0.8
            raw[k] = t.height + n * (t.rough or 0)
        end
    end
    local h = {}
    for j = 0, H - 1 do
        for i = 0, W - 1 do
            local k = j * W + i + 1
            local around = (raw[self:index(i - 1, j)] + raw[self:index(i + 1, j)]
                + raw[self:index(i, j - 1)] + raw[self:index(i, j + 1)]) * 0.25
            local v = raw[k] * 0.55 + around * 0.45
            -- the coast stays where the map has it
            if self.tiles[k].water then
                v = math.min(v, -0.15)
            else
                v = math.max(v, 0.08)
            end
            h[k] = v
        end
    end
    self.heights = h
    -- flat ground under the buildings
    for _, list in ipairs({ self.places, self.props }) do
        for _, e in ipairs(list) do
            if e.radius then
                local r = e.radius + 0.9
                local ci, cj = math.floor(e.x), math.floor(e.z)
                local hc = math.max(0.1, self:height(e.x, e.z))
                local n = math.ceil(r) + 1
                for dj = -n, n do
                    for di = -n, n do
                        local vx, vz = ci + di + 0.5, cj + dj + 0.5
                        local d = math.sqrt((vx - e.x) ^ 2 + (vz - e.z) ^ 2)
                        local w = clamp((r - d) / 0.7, 0, 1)
                        if w > 0 then
                            local k = self:index(ci + di, cj + dj)
                            if not self.tiles[k].water then
                                h[k] = h[k] + (hc - h[k]) * w
                            end
                        end
                    end
                end
            end
        end
    end
    for _, list in ipairs({ self.places, self.props }) do
        for _, e in ipairs(list) do
            e.y = math.max(0, self:height(e.x, e.z))
        end
    end
end

-- the exact height of the ground (the same triangles as the mesh)
function World:height(x, z)
    local fx, fz = x - 0.5, z - 0.5
    local i, j = math.floor(fx), math.floor(fz)
    fx, fz = fx - i, fz - j
    local hs = self.heights
    local ha = hs[self:index(i, j)]
    local hb = hs[self:index(i + 1, j)]
    local hc = hs[self:index(i + 1, j + 1)]
    local hd = hs[self:index(i, j + 1)]
    if fx >= fz then
        return ha + (hb - ha) * fx + (hc - hb) * fz
    end
    return ha + (hc - hd) * fx + (hd - ha) * fz
end

function World:normal(i, j)
    local hs = self.heights
    local dx = hs[self:index(i + 1, j)] - hs[self:index(i - 1, j)]
    local dz = hs[self:index(i, j + 1)] - hs[self:index(i, j - 1)]
    local nx, ny, nz = -dx * 0.5, 1, -dz * 0.5
    local l = math.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / l, ny / l, nz / l
end

-- the ground textures (cut from the OGA tilesets) and the water in one image
function World:buildTextures()
    local data = self.grounds
    local atlas = r3d.Atlas(512)
    local images = {}
    local function source(path)
        if not images[path] then
            images[path] = love.image.newImageData(path)
        end
        return images[path]
    end
    self.layers, self.layerIndex = {}, {}
    for i, t in ipairs(data.textures) do
        if i > 8 then
            print("[world] only 8 ground textures are used")
            break
        end
        local src = source(t.image)
        local r = t.rect or { 0, 0, src:getWidth(), src:getHeight() }
        local img = love.image.newImageData(r[3], r[4])
        img:paste(src, 0, 0, r[1], r[2], r[3], r[4])
        if t.gray or t.tint then
            local k = t.gray or 0
            local tint = t.tint or { 1, 1, 1 }
            img:mapPixel(function(_, _, cr, cg, cb, ca)
                local l = 0.3 * cr + 0.59 * cg + 0.11 * cb
                return clamp((cr + (l - cr) * k) * tint[1], 0, 1), clamp((cg + (l - cg) * k) * tint[2], 0, 1),
                    clamp((cb + (l - cb) * k) * tint[3], 0, 1), ca
            end)
        end
        -- the average colour (for the map)
        local sr, sg, sb, n = 0, 0, 0, 0
        for y = 0, r[4] - 1, 2 do
            for x = 0, r[3] - 1, 2 do
                local cr, cg, cb = img:getPixel(x, y)
                sr, sg, sb, n = sr + cr, sg + cg, sb + cb, n + 1
            end
        end
        self.layers[i] = { rect = atlas:rect(img), rep = t.rep or 1, name = t.name, color = { sr / n, sg / n, sb / n },
            texels = r[3] / (t.rep or 1) }
        self.layerIndex[t.name] = i
    end
    self.waterRect = atlas:rect(source(data.water.image))
    self.groundImage = atlas:image()
end

function World:sendUniforms()
    local sh = r3d.shader("terrain")
    if sh then
        local rects, reps = {}, {}
        for i = 1, 8 do
            local l = self.layers[i] or self.layers[1]
            rects[i] = { l.rect[1], l.rect[2], l.rect[3], l.rect[4] }
            reps[i] = l.rep
        end
        r3d.send(sh, "u_layer", unpack(rects))
        r3d.send(sh, "u_repeat", unpack(reps))
        r3d.send(sh, "u_period", { self.W, self.H })
        r3d.send(sh, "u_texels", self.layers[1].texels)
        r3d.send(sh, "u_edge", 0.45)
    end
    local ws = r3d.shader("water")
    if ws then
        local w = self.grounds.water
        local r = self.waterRect
        r3d.send(ws, "u_waterRect", { r[1], r[2], r[3], r[4] })
        r3d.send(ws, "u_waterRepeat", w.rep or 2)
        r3d.send(ws, "u_deep", w.deep or { 0.12, 0.3, 0.55 })
        r3d.send(ws, "u_shallow", w.shallow or { 0.3, 0.62, 0.68 })
    end
end

-- colour, light and the ground textures of every vertex
function World:buildVertices()
    local W, H = self.W, self.H
    local hs = self.heights
    local data = self.grounds
    local rock, snow = self.layerIndex.rock, self.layerIndex.snow
    local rockSlope, snowLine = data.rockSlope or 0.9, data.snowLine or 3.3
    self.vdata = {}
    for j = 0, H - 1 do
        for i = 0, W - 1 do
            local k = j * W + i + 1
            local t = self.tiles[k]
            local y = hs[k]
            local nx, ny, nz = self:normal(i, j)
            local shade = r3d.shade(nx, ny, nz, self.light)
            local tint = t.tint or { 1, 1, 1 }
            local r, g, b = shade * tint[1], shade * tint[2], shade * tint[3]
            if y < 0 then
                -- deeper = darker and bluer
                local d = clamp(-y / 2.5, 0, 1)
                r, g, b = r * (1 - d * 0.5), g * (1 - d * 0.38), b * (1 - d * 0.2)
            end
            local w = { 0, 0, 0, 0, 0, 0, 0, 0 }
            w[self.layerIndex[t.texture] or 1] = 1
            local slope = math.max(math.abs(y - hs[self:index(i - 1, j)]), math.abs(y - hs[self:index(i + 1, j)]),
                math.abs(y - hs[self:index(i, j - 1)]), math.abs(y - hs[self:index(i, j + 1)]))
            if rock and slope > rockSlope and y > 0 then
                w[rock] = math.max(w[rock], clamp((slope - rockSlope) / 0.5, 0, 1) * 1.15)
            end
            if snow and y > snowLine then
                w[snow] = math.max(w[snow], clamp((y - snowLine) / 0.5, 0, 1) * 1.2)
            end
            self.vdata[k] = { y = y, r = clamp(r, 0, 1), g = clamp(g, 0, 1), b = clamp(b, 0, 1), w = w,
                depth = clamp(-y / 1.6, 0, 1) }
        end
    end
end

-- buildings and trees keep away from each other
function World:nearBuilding(x, z, extra)
    for _, list in ipairs({ self.places, self.props }) do
        for _, e in ipairs(list) do
            local r = (e.radius or 0.4) + (extra or 0)
            local dx, dz = wrapDelta(x - e.x, self.W), wrapDelta(z - e.z, self.H)
            if dx * dx + dz * dz < r * r then
                return e
            end
        end
    end
    return nil
end

-- the meshes: ground, water and objects for every chunk of 16 x 16 tiles
function World:buildChunks()
    local W, H = self.W, self.H
    local atlas = r3d.Atlas(1024)
    self.modelAtlas = atlas
    self.chunks = {}
    local byKey = {}
    for z0 = 0, H - 1, CHUNK do
        for x0 = 0, W - 1, CHUNK do
            local c = { x0 = x0, z0 = z0, w = math.min(CHUNK, W - x0), d = math.min(CHUNK, H - z0) }
            c.mx, c.mz = x0 + c.w / 2 + 0.5, z0 + c.d / 2 + 0.5
            c.radius = math.sqrt(c.w * c.w + c.d * c.d) / 2
            c.builder = r3d.Builder(atlas)
            table.insert(self.chunks, c)
            byKey[math.floor(x0 / CHUNK) .. ":" .. math.floor(z0 / CHUNK)] = c
            self:buildGround(c)
        end
    end
    local function chunkOf(x, z)
        return byKey[math.floor((x % W) / CHUNK) .. ":" .. math.floor((z % H) / CHUNK)]
    end
    -- buildings
    for _, list in ipairs({ self.places, self.props }) do
        for _, e in ipairs(list) do
            if e.prefab then
                chunkOf(e.x, e.z).builder:prefab(e.prefab, { x = e.x % W, y = e.y, z = e.z % H, rot = e.rot })
            end
        end
    end
    -- trees of the forests (and a few in the fields)
    local big, small = r3d.model(TREES.big), r3d.model(TREES.small)
    for j = 0, H - 1 do
        for i = 0, W - 1 do
            local t = self.tiles[j * W + i + 1]
            local p = t.trees or 0
            for n = 1, 2 do
                if p > 0 and hash(i, j, n) < p / n then
                    local x = i + 0.15 + hash(i, j, 10 + n) * 0.7
                    local z = j + 0.15 + hash(i, j, 20 + n) * 0.7
                    local y = self:height(x, z)
                    if y > 0.05 and not self:nearBuilding(x, z, 0.6) then
                        local tall = hash(i, j, 30 + n) > 0.35
                        local shade = 0.85 + hash(i, j, 40 + n) * 0.25
                        chunkOf(x, z).builder:model(tall and big or small, {
                            x = x, y = y - 0.03, z = z, rot = hash(i, j, 50 + n) * TAU,
                            scale = (tall and 0.75 or 0.85) + hash(i, j, 60 + n) * 0.4,
                            tint = { shade, shade, shade * 0.95 },
                        })
                    end
                end
            end
        end
    end
    -- the boat
    local boat = r3d.Builder(atlas)
    boat:model(r3d.model(BOAT_MODEL, { texture = BOAT_TEXTURE }), { scale = self.def.boatScale or 0.16, center = true, base = true })
    -- now every texture is in the atlas: the meshes
    for _, c in ipairs(self.chunks) do
        c.objects = c.builder:build()
        c.builder = nil
    end
    self.boatMesh = boat:build()
end

function World:buildGround(c)
    local verts, map = {}, {}
    local row = c.w + 1
    for j = 0, c.d do
        for i = 0, c.w do
            local gi, gj = c.x0 + i, c.z0 + j
            local v = self.vdata[self:index(gi, gj)]
            local w = v.w
            verts[#verts + 1] = { gi + 0.5, v.y, gj + 0.5, gi + 0.5, gj + 0.5, v.r, v.g, v.b, 1,
                w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8] }
        end
    end
    for j = 0, c.d - 1 do
        for i = 0, c.w - 1 do
            local a = j * row + i + 1
            local b, cc, d = a + 1, a + row + 1, a + row
            map[#map + 1], map[#map + 2], map[#map + 3] = a, b, cc
            map[#map + 1], map[#map + 2], map[#map + 3] = a, cc, d
        end
    end
    c.terrain = love.graphics.newMesh(r3d.TERRAIN_FORMAT, verts, "triangles", "static")
    c.terrain:setVertexMap(map)
    c.terrain:setTexture(self.groundImage)
    -- the water: every cell with a corner under the sea level
    local water = {}
    local hs = self.heights
    for j = 0, c.d - 1 do
        for i = 0, c.w - 1 do
            local gi, gj = c.x0 + i, c.z0 + j
            local ka, kb, kc, kd = self:index(gi, gj), self:index(gi + 1, gj), self:index(gi + 1, gj + 1), self:index(gi, gj + 1)
            if math.min(hs[ka], hs[kb], hs[kc], hs[kd]) < 0.03 then
                local function V(x, z, k)
                    return { x, 0, z, x, z, 1, 1, 1, self.vdata[k].depth, 0, 0, 0, 0 }
                end
                local a, b = V(gi + 0.5, gj + 0.5, ka), V(gi + 1.5, gj + 0.5, kb)
                local cc, d = V(gi + 1.5, gj + 1.5, kc), V(gi + 0.5, gj + 1.5, kd)
                water[#water + 1], water[#water + 2], water[#water + 3] = a, b, cc
                water[#water + 1], water[#water + 2], water[#water + 3] = a, cc, d
            end
        end
    end
    if #water > 0 then
        c.water = love.graphics.newMesh(r3d.FORMAT, water, "triangles", "static")
        c.water:setTexture(self.groundImage)
    end
end

-- the map picture: one pixel per tile
function World:buildMinimap()
    local W, H = self.W, self.H
    local img = love.image.newImageData(W, H)
    local water = self.grounds.water
    local deep, shallow = water.deep or { 0.12, 0.3, 0.55 }, water.shallow or { 0.3, 0.62, 0.68 }
    for j = 0, H - 1 do
        for i = 0, W - 1 do
            local k = j * W + i + 1
            local t = self.tiles[k]
            local y = self.heights[k]
            local r, g, b
            if t.water then
                local d = clamp(-y / 2.2, 0, 1)
                r = shallow[1] + (deep[1] - shallow[1]) * d
                g = shallow[2] + (deep[2] - shallow[2]) * d
                b = shallow[3] + (deep[3] - shallow[3]) * d
            else
                local l = self.layers[self.layerIndex[t.texture] or 1].color
                local tint = t.tint or { 1, 1, 1 }
                local nx, ny, nz = self:normal(i, j)
                local s = r3d.shade(nx, ny, nz, self.light) * 1.1
                if t.trees and t.trees > 0.2 then
                    s = s * 0.72
                end
                r, g, b = l[1] * tint[1] * s, l[2] * tint[2] * s, l[3] * tint[3] * s
            end
            img:setPixel(i, j, clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1), 1)
        end
    end
    self.minimap = love.graphics.newImage(img)
    self.minimap:setFilter("nearest", "nearest")
end

function World:shadowImage()
    local d = love.image.newImageData(16, 16)
    d:mapPixel(function(x, y)
        local dx, dy = (x + 0.5 - 8) / 8, (y + 0.5 - 8) / 8
        local a = (dx * dx + dy * dy < 1) and 0.55 or 0
        return 0, 0, 0, a
    end)
    local img = love.graphics.newImage(d)
    img:setFilter("nearest", "nearest")
    self.shadowQuad = love.graphics.newQuad(0, 0, 16, 16, 16, 16)
    return img
end

-- the hero, pets, boat ------------------------------------------------------------------

function World:placeHero(x, z)
    local h = self.hero
    h.x, h.z = x, z
    if self.inBoat and self.boat then
        self.boat.x, self.boat.z = x % self.W, z % self.H
    end
    h.y = self:standY(x, z)
    -- the pets stand behind (if there is ground there)
    local bx, bz = x - math.sin(h.heading) * 1.2, z + math.cos(h.heading) * 1.2
    if self.inBoat or not self:walkable(bx, bz) then
        bx, bz = x, z
    end
    self.trail = { { x = x, z = z }, { x = bx, z = bz } }
    for i, p in ipairs(self.pets or {}) do
        p.x, p.z = self:trailAt(p.spacing)
        p.y = self:standY(p.x, p.z)
        p.heading = h.heading
    end
end

-- where feet are: the ground, or the boat
function World:standY(x, z)
    if self.inBoat then
        return self:boatY() + 0.12
    end
    return self:deckAt(x, z) or math.max(self:height(x, z), -0.3)
end

function World:boatY()
    return -0.1 + math.sin(self.time * 2.1) * 0.025
end

function World:partyChanged()
    local g = G()
    self.pets = {}
    for i, id in ipairs(g.state.party or {}) do
        local def = g.pets[id]
        if def then
            local name = def.worldSprite or def.sprite
            local sdef = g.sprites[name] and g.sprite(name)
            if sdef then
                local s = anim.new(sdef)
                local h = self.hero
                local pet = {
                    id = id, sprite = s, heading = h.heading,
                    size = s.frameWidth / TEXELS * (def.worldScale or 1),
                    spacing = 1.0 * i, image = s.image,
                }
                pet.x, pet.z = self:trailAt(pet.spacing)
                pet.y = self:standY(pet.x, pet.z)
                table.insert(self.pets, pet)
            end
        end
    end
end

-- a point of the trail behind the hero (pets walk there)
function World:trailAt(dist)
    local t = self.trail
    local left = dist
    for i = 1, #t - 1 do
        local a, b = t[i], t[i + 1]
        local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
        if d >= left then
            local k = left / math.max(d, 1e-6)
            return a.x + (b.x - a.x) * k, a.z + (b.z - a.z) * k
        end
        left = left - d
    end
    local last = t[#t]
    return last.x, last.z
end

function World:pushTrail(x, z)
    local t = self.trail
    local f = t[1]
    if not f or (f.x - x) ^ 2 + (f.z - z) ^ 2 > 0.01 then
        table.insert(t, 1, { x = x, z = z })
        if #t > 60 then
            t[#t] = nil
        end
    end
end

-- the floor of a dock under a point: its height (or nil)
function World:deckAt(x, z)
    for _, e in ipairs(self.props) do
        local deck = e.prefab and e.prefab.deck
        if deck then
            local S = e.prefab.scale or 1
            local dx, dz = wrapDelta(x - e.x, self.W), wrapDelta(z - e.z, self.H)
            local c, s = math.cos(e.rot), math.sin(e.rot)
            local px, pz = (dx * c - dz * s) / S, (dx * s + dz * c) / S
            if px >= deck[1] and px <= deck[3] and pz >= deck[2] and pz <= deck[4] then
                return e.y + (deck.y or 0) * S
            end
        end
    end
    return nil
end

-- can somebody stand here? boat = true: can the boat sail here?
function World:walkable(x, z, boat)
    local y = self:height(x, z)
    if boat then
        return y < -0.12 and not self:deckAt(x, z)
    end
    if self:deckAt(x, z) then
        return true
    end
    local t = self:groundAt(x, z)
    if t.solid or t.water or y < 0.03 then
        return false
    end
    for _, list in ipairs({ self.places, self.props }) do
        for _, e in ipairs(list) do
            if e.radius then
                local dx, dz = wrapDelta(x - e.x, self.W), wrapDelta(z - e.z, self.H)
                if dx * dx + dz * dz < e.radius * e.radius then
                    return false
                end
            end
        end
    end
    return true
end

-- a dry point next to the boat (to go ashore)
function World:shore()
    local h = self.hero
    local best, bestD
    for a = 0, 15 do
        local ang = a / 16 * TAU
        for _, r in ipairs({ 0.8, 1.1, 1.4 }) do
            local x, z = h.x + math.sin(ang) * r, h.z - math.cos(ang) * r
            if self:walkable(x, z) then
                local d = math.abs(wrapAngle(ang - h.heading)) + r * 0.3
                if not bestD or d < bestD then
                    best, bestD = { x = x, z = z }, d
                end
                break
            end
        end
    end
    return best
end

function World:battleDistance()
    local rate = self.def.encounterRate or 1
    if rate <= 0 then
        return math.huge
    end
    return (18 + love.math.random() * 20) / rate
end

-- camera -----------------------------------------------------------------------------

function World:updateCamera(dt)
    local v = VIEWS[self.viewIndex]
    local k = dt > 0 and (1 - math.exp(-dt * 6)) or 1
    self.camDist = self.camDist + (v.dist - self.camDist) * k
    self.camPitch = self.camPitch + (v.pitch - self.camPitch) * k
    local h = self.hero
    local ty = h.y + 0.45
    self.camY = self.camY + (ty - self.camY) * (dt > 0 and (1 - math.exp(-dt * 5)) or 1)
    local fx, fz = math.sin(self.yaw), -math.cos(self.yaw)
    local cp, sp = math.cos(self.camPitch), math.sin(self.camPitch)
    local ex, ez = h.x - fx * self.camDist * cp, h.z - fz * self.camDist * cp
    local ey = self.camY + self.camDist * sp
    ey = math.max(ey, math.max(0, self:height(ex, ez)) + 0.8)
    self.view:look(ex, ey, ez, h.x, self.camY, h.z)
    local fog = self.def.fog
    self.view.fog = fog or { self.camDist + 5, self.camDist + 19 }
end

-- the sky's horizon goes where the round edge of the world is seen
function World:skyPitch()
    local eye, c = self.view.eye, self.view.center
    local dx, dz = eye[1] - c[1], eye[3] - c[3]
    local D0 = math.sqrt(dx * dx + dz * dz)
    local pitch = math.atan2(eye[2] - c[2], D0)
    local curve = self.view.curve
    if curve <= 0 then
        return -pitch
    end
    local Hh = math.max(0.5, eye[2])
    local d = -D0 + math.sqrt(D0 * D0 + Hh / curve)
    local y = -curve * d * d
    local a = math.atan((Hh - y) / (D0 + d))
    return a - pitch
end

-- update -----------------------------------------------------------------------------

function World:update(dt, fromScript)
    Mode.update(self, dt)
    self.view.time = self.time
    self.emotes:update(dt)
    self.sky:update(dt)
    for _, e in ipairs({ self.hero, unpack(self.pets) }) do
        e.sprite:update(dt)
        if e.hop then
            e.hop = e.hop - dt
            if e.hop <= 0 then
                e.hop = nil
            end
        end
    end
    if fromScript or scene.top() ~= self then
        self.prompt, self.nearby = nil, nil
        self:idle()
        if self.inBoat then
            self.hero.y = self:standY(self.hero.x, self.hero.z)
        end
        self:updateCamera(dt)
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
    if input.pressed("map") then
        self.mapMode = (self.mapMode + 1) % 3
    end
    if input.pressed("view") then
        self.viewIndex = self.viewIndex % #VIEWS + 1
    end
    local turn = 0
    if input.down("camLeft") then turn = turn - 1 end
    if input.down("camRight") then turn = turn + 1 end
    self.yaw = wrapAngle(self.yaw + turn * dt * 1.9)
    self.safeTime = math.max(0, self.safeTime - dt)

    local moved = self:move(dt)
    self:followers(dt)
    self:checkPlaces()
    if input.pressed("interact") and self.action then
        input.consume("interact")
        self.action()
    elseif moved > 0 then
        self:encounters(moved)
    end
    self:updateCamera(dt)
    self:remember()
    if engine.debug.enabled then
        local _, name = self:groundAt(self.hero.x, self.hero.z)
        engine.debug.watch("world", string.format("%.1f, %.1f  %s  h=%.2f  danger %.0f/%.0f", self.hero.x % self.W,
            self.hero.z % self.H, name, self:height(self.hero.x, self.hero.z), self.danger, self.nextBattle))
    end
end

function World:idle()
    local h = self.hero
    h.sprite:play("idle", facing(h.heading, self.yaw))
    for _, p in ipairs(self.pets) do
        p.sprite:play("idle", facing(p.heading, self.yaw))
    end
end

-- WASD: walk (or row) the way the camera looks; returns the distance
function World:move(dt)
    local h = self.hero
    local ix, iy = input.direction()
    if ix == 0 and iy == 0 then
        h.sprite:play("idle", facing(h.heading, self.yaw))
        h.sprite.speed = 1
        h.y = self:standY(h.x, h.z)
        return 0
    end
    local fx, fz = math.sin(self.yaw), -math.cos(self.yaw)
    local rx, rz = math.cos(self.yaw), math.sin(self.yaw)
    local dx, dz = rx * ix - fx * iy, rz * ix - fz * iy
    local l = math.sqrt(dx * dx + dz * dz)
    dx, dz = dx / l, dz / l
    local target = math.atan2(dx, -dz)
    local speed
    if self.inBoat then
        speed = ROW
        -- the boat turns smoothly
        h.heading = h.heading + wrapAngle(target - h.heading) * math.min(1, dt * 7)
    else
        local ground = self:groundAt(h.x, h.z)
        local run = input.down("run")
        speed = WALK * (ground.speed or 1) * (run and RUN or 1)
        h.sprite.speed = run and 1.5 or 1
        h.heading = target
    end
    local step = speed * dt
    local nx, nz = h.x + dx * step, h.z + dz * step
    local boat = self.inBoat
    local ox, oz = h.x, h.z
    if self:walkable(nx, nz, boat) then
        h.x, h.z = nx, nz
    elseif self:walkable(nx, h.z, boat) then
        h.x = nx
    elseif self:walkable(h.x, nz, boat) then
        h.z = nz
    end
    local moved = math.sqrt((h.x - ox) ^ 2 + (h.z - oz) ^ 2)
    if self.inBoat then
        self.boat.x, self.boat.z = h.x % self.W, h.z % self.H
        self.boat.rot = -h.heading
        h.sprite:play("idle", facing(h.heading, self.yaw))
    else
        h.sprite:play(moved > 0 and "walk" or "idle", facing(h.heading, self.yaw))
    end
    h.y = self:standY(h.x, h.z)
    self:pushTrail(h.x, h.z)
    return moved
end

function World:followers(dt)
    local h = self.hero
    for i, p in ipairs(self.pets) do
        if self.inBoat then
            -- in the boat, at the bow, looking ahead
            local ahead = 0.3 + (i - 1) * 0.12
            p.x = h.x + math.sin(h.heading) * ahead
            p.z = h.z - math.cos(h.heading) * ahead
            p.y = self:boatY() + 0.1
            p.heading = h.heading
            p.sprite:play("idle", facing(p.heading, self.yaw))
        else
            local tx, tz = self:trailAt(p.spacing)
            local dx, dz = tx - p.x, tz - p.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d > 0.02 then
                local k = math.min(1, dt * 10)
                p.x, p.z = p.x + dx * k, p.z + dz * k
                p.heading = math.atan2(dx, -dz)
                p.sprite:play("walk", facing(p.heading, self.yaw))
            else
                p.sprite:play("idle", facing(p.heading, self.yaw))
            end
            p.y = self:deckAt(p.x, p.z) or math.max(self:height(p.x, p.z), -0.3)
        end
    end
end

-- the places around: titles, prompts, what [F] does
function World:checkPlaces()
    local h = self.hero
    self.prompt, self.nearby, self.action = nil, nil, nil
    local W, H = self.W, self.H
    local near, nearD
    for _, p in ipairs(self.places) do
        local dx, dz = wrapDelta(p.x - h.x, W), wrapDelta(p.z - h.z, H)
        local d = math.sqrt(dx * dx + dz * dz)
        if not nearD or d < nearD then
            near, nearD = p, d
        end
    end
    -- the title of a place when Гриша is close to it
    self.titlePlace = (near and nearD < (near.radius or 0.5) + 3.5) and near or nil
    if self.inBoat then
        local shore = self:shore()
        if shore then
            self.prompt, self.nearby = "Сойти на берег", true
            self.action = function()
                self.inBoat = false
                self.hero.x, self.hero.z = shore.x, shore.z
                self.hero.y = self:standY(shore.x, shore.z)
                self.trail = { { x = shore.x, z = shore.z } }
                audio.play("step")
            end
        end
        return
    end
    if near and nearD < (near.radius or 0.5) + 1.25 then
        self.prompt = (near.prompt and near.prompt ~= "") and near.prompt or "Войти"
        self.nearby = near
        self.action = function()
            self:remember()
            G().trigger(self, { name = near.name, properties = near.properties }, "interact")
        end
        return
    end
    if self.boat then
        local dx, dz = wrapDelta(self.boat.x - h.x, W), wrapDelta(self.boat.z - h.z, H)
        if dx * dx + dz * dz < 1.4 * 1.4 then
            self.prompt, self.nearby = "Сесть в лодку", self.boat
            self.action = function()
                self.inBoat = true
                h.x, h.z = h.x + dx, h.z + dz
                h.heading = -self.boat.rot
                h.y = self:standY(h.x, h.z)
                audio.play("jump")
            end
        end
    end
end

-- random battles on dangerous ground
function World:encounters(moved)
    if self.inBoat or self.safeTime > 0 then
        return
    end
    local ground = self:groundAt(self.hero.x, self.hero.z)
    local group = ground.encounter
    local list = group and self.def.encounters and self.def.encounters[group]
    if not list or #list == 0 then
        return
    end
    self.danger = self.danger + moved
    if self.danger < self.nextBattle or scene.isTransitioning() then
        return
    end
    self.danger = 0
    self.nextBattle = self:battleDistance()
    local n = love.math.random(1, math.min(3, #list + 1))
    local enemies = {}
    for i = 1, n do
        enemies[i] = list[love.math.random(#list)]
    end
    audio.play("bdoom")
    self:idle()
    local skies = self.def.encounterSkies or {}
    G().play(self.def.battle or "battle", {
        enemies = enemies, transition = "battle", sky = skies[group] or SKIES[group] or "day",
    }, function(result)
        result = result or {}
        self.safeTime = 3
        if result.win == false and not result.fled then
            self:gameOver()
        else
            self:fire("battleWon", group)
        end
    end)
end

function World:gameOver()
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
    g.go(self.name, { spawn = self.def.respawn or "start", transition = "fade" })
end

-- where the hero is: saved with the game
function World:remember()
    local st = G().state
    local w = st.world or {}
    st.world = w
    w.stage = self.name
    w.x, w.z = self.hero.x % self.W, self.hero.z % self.H
    w.yaw = self.yaw
    w.inBoat = self.inBoat or nil
    if self.boat then
        w.boat = { x = self.boat.x, z = self.boat.z, rot = self.boat.rot }
    end
end

-- script commands ------------------------------------------------------------------------

function World:cmd_teleport(s, name)
    local p = self.spawns[name]
    if not p then
        print("[world] no spawn '" .. tostring(name) .. "'")
        return
    end
    self.inBoat = false
    self:placeHero(p.x, p.z)
    self:updateCamera(0)
end

function World:cmd_boat(s, name)
    local p = name and self.spawns[name]
    if p then
        self.boat = { x = p.x, z = p.z, rot = 0 }
    end
end

function World:cmd_camera(s, yaw, view)
    if yaw then
        self.yaw = yaw
    end
    if view then
        self.viewIndex = clamp(view, 1, #VIEWS)
    end
end

function World:entityOf(who)
    if who == nil or who == "hero" or who == "grisha" or who == G().player.speaker then
        return self.hero
    end
    for _, p in ipairs(self.pets) do
        if p.id == who then
            return p
        end
    end
    return self.hero
end

function World:cmd_emote(s, who, kind, duration)
    self.emotes:add(self:entityOf(who), kind, duration)
end

function World:cmd_hop(s, who)
    local e = self:entityOf(who)
    e.hop = 0.3
end

-- {@emote=heart} in dialogue text: the speaker reacts
function World:textEvent(speaker, name, value)
    if name == "emote" or name == "emotion" then
        self:cmd_emote(nil, speaker, value)
    elseif name == "hop" then
        self:cmd_hop(nil, speaker)
    end
end

-- draw -----------------------------------------------------------------------------------

function World:visibleChunks()
    local c = self.view.center
    local fx, fz = math.sin(self.yaw), -math.cos(self.yaw)
    local far = (self.view.fog[2] or 30) + 4
    local list = {}
    for _, ch in ipairs(self.chunks) do
        local dx = wrapDelta(ch.mx - c[1], self.W)
        local dz = wrapDelta(ch.mz - c[3], self.H)
        local d = math.sqrt(dx * dx + dz * dz) - ch.radius
        if d < far and dx * fx + dz * fz > -(ch.radius + self.camDist + 2) then
            ch.ox, ch.oz = c[1] + dx - ch.mx, c[3] + dz - ch.mz
            list[#list + 1] = ch
        end
    end
    return list
end

-- the nearest copy of a point of the base world (0..W) to the camera
function World:near(x, z)
    local c = self.view.center
    return c[1] + wrapDelta(x - c[1], self.W), c[3] + wrapDelta(z - c[3], self.H)
end

function World:drawSprites()
    local view = self.view
    local rx, rz = math.cos(self.yaw), math.sin(self.yaw)
    local shadow = self.batches.shadow
    shadow:clear()
    local function quadOf(sprite)
        return sprite:getQuad()
    end
    -- who is drawn: the hero and the pets
    local list = { self.hero }
    for _, p in ipairs(self.pets) do
        list[#list + 1] = p
    end
    for _, e in ipairs(list) do
        if not self.inBoat then
            shadow:addFlat(e.x, e.y + 0.04, e.z, e.size * 0.75, e.size * 0.45, self.shadowQuad, -self.yaw)
        end
    end
    if shadow:flush() then
        view:draw(shadow.mesh, "model")
    end
    -- one batch per texture
    local batches = {}
    for _, e in ipairs(list) do
        local img = e.sprite.image
        local b = self.batches[img]
        if not b then
            b = r3d.Batch(img, 8)
            self.batches[img] = b
        end
        if not batches[b] then
            b:clear()
            batches[b] = true
        end
        local s = e.sprite
        local w = e.size
        local hgt = s.frameHeight / s.frameWidth * w
        local lift = (s.frameHeight - s.oy) / s.frameWidth * w
        local hop = e.hop and math.sin(math.min(1, (0.3 - e.hop) / 0.3) * math.pi) * 0.25 or 0
        b:add(e.x, e.y - lift + hop, e.z, w, hgt, quadOf(s), rx, rz)
        e.top = e.y + hgt - lift
    end
    for b in pairs(batches) do
        if b:flush() then
            view:draw(b.mesh, "model")
        end
    end
end

function World:draw()
    local lg = love.graphics
    local view = self.view
    if not self.ok then
        lg.clear(0.1, 0.1, 0.15)
        ui.print("Карта мира не может включиться: нет шейдеров", screen.width / 2, screen.height / 2,
            { align = "center", color = "light" })
        return
    end
    self:sendUniforms()
    view:begin(self.fogColor)
    view:background(function(w, h)
        self.sky:draw(math.pi - self.yaw, self:skyPitch(), FOV, w, h, true)
    end)
    local chunks = self:visibleChunks()
    for _, ch in ipairs(chunks) do
        view:draw(ch.terrain, "terrain", ch.ox, 0, ch.oz)
    end
    -- trees and houses in front of Гриша are see-through around him
    local h = self.hero
    local fx, fy, fd = view:project(h.x, h.y + 0.35, h.z)
    if fx then
        view:focus(fx, fy, 30, fd - 0.7)
    end
    for _, ch in ipairs(chunks) do
        if ch.objects then
            view:draw(ch.objects, "model", ch.ox, 0, ch.oz)
        end
    end
    view:focus()
    if self.boat and self.boatMesh then
        local bx, bz = self:near(self.boat.x, self.boat.z)
        view:draw(self.boatMesh, "model", bx, self:boatY(), bz, self.boat.rot)
    end
    self:drawSprites()
    for _, ch in ipairs(chunks) do
        if ch.water then
            view:draw(ch.water, "water", ch.ox, 0, ch.oz)
        end
    end
    view:finish()
    lg.setColor(1, 1, 1, 1)
    lg.draw(view.canvas, 0, 0, 0, screen.width / CW, screen.height / CH)
    self:drawOverlay()
end

-- canvas point -> screen
function World:toScreen(x, y, z)
    local px, py = self.view:project(x, y, z)
    if not px then
        return nil
    end
    return px * screen.width / CW, py * screen.height / CH
end

function World:drawOverlay()
    local top = scene.top() == self
    -- FF9-like "!" over the hero when something can be done here
    if top and self.nearby then
        local h = self.hero
        local x, y = self:toScreen(h.x, (h.top or h.y + 0.7) + 0.1, h.z)
        if x then
            emote.draw("!", x, y, 1 + (self.time % 10), 0.8)
        end
    end
    self.emotes:draw(function(e)
        local x, y = self:toScreen(e.x, (e.top or e.y + 0.7) + 0.1, e.z)
        return x or -100, y or -100
    end, 0.8)
    -- the name of the place nearby
    local dt = love.timer.getDelta()
    if self.titlePlace and self.titlePlace.title then
        self.titleText = self.titlePlace.title
        self.titleAlpha = math.min(1, self.titleAlpha + dt * 3)
    else
        self.titleAlpha = math.max(0, self.titleAlpha - dt * 3)
    end
    if self.titleAlpha > 0 and self.titleText then
        local font = ui.font("body")
        local w = font:getWidth(self.titleText) + 70
        love.graphics.push()
        local k = 0.85 + 0.15 * self.titleAlpha
        love.graphics.translate(screen.width / 2, 22 - (1 - self.titleAlpha) * 12)
        love.graphics.scale(k, k)
        ui.banner(self.titleText, 0, 0, w)
        love.graphics.pop()
    end
    if self.mapMode > 0 then
        self:drawMap(self.mapMode == 2)
    end
    if top then
        self:drawHud()
    end
end

function World:drawHud()
    hud.draw({
        prompt = self.prompt,
        hint = string.format("[%s/%s] камера   [%s] вид   [%s] карта   [%s] сумка   [%s] пауза",
            input.keyName("camLeft"), input.keyName("camRight"), input.keyName("view"), input.keyName("map"),
            input.keyName("inventory"), input.keyName("pause")),
        owner = self,
    })
end

function World:drawScriptOverlay()
    hud.draw({})
end

-- the map: small in the corner or big in the middle (north is up)
function World:drawMap(big)
    local lg = love.graphics
    local W, H = self.W, self.H
    local scale = big and 4 or 2
    local mw, mh = big and math.min(W * scale, 400) or 132, big and math.min(H * scale, 400) or 132
    local mx = big and math.floor((screen.width - mw) / 2) or screen.width - mw - 14
    local my = big and math.floor((screen.height - mh) / 2) or 14
    local h = self.hero
    local cx, cz = h.x % W, h.z % H
    if big then
        lg.setColor(0, 0, 0, 0.45)
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    lg.setColor(0.05, 0.06, 0.1, 0.85)
    lg.rectangle("fill", mx - 4, my - 4, mw + 8, mh + 8, 4)
    lg.setScissor(mx, my, mw, mh)
    local ox, oy = mx + mw / 2 - cx * scale, my + mh / 2 - cz * scale
    lg.setColor(1, 1, 1, big and 1 or 0.92)
    for a = -1, 1 do
        for b = -1, 1 do
            lg.draw(self.minimap, ox + a * W * scale, oy + b * H * scale, 0, scale, scale)
        end
    end
    local function at(x, z)
        local dx, dz = wrapDelta(x - cx, W), wrapDelta(z - cz, H)
        return mx + mw / 2 + dx * scale, my + mh / 2 + dz * scale
    end
    -- places
    for _, p in ipairs(self.places) do
        local x, y = at(p.x, p.z)
        lg.setColor(0.15, 0.1, 0.05, 1)
        lg.rectangle("fill", x - 3, y - 3, 6, 6)
        lg.setColor(1, 0.85, 0.3, 1)
        lg.rectangle("fill", x - 2, y - 2, 4, 4)
        if big and p.title then
            ui.print(p.title, x, y + 5, { font = "small", align = "center", color = "light", shadow = true })
        end
    end
    if self.boat and not self.inBoat then
        local x, y = at(self.boat.x, self.boat.z)
        lg.setColor(0.55, 0.32, 0.15, 1)
        lg.rectangle("fill", x - 2, y - 2, 4, 4)
    end
    -- the hero: an arrow where he goes, the camera: a light wedge
    local x, y = mx + mw / 2, my + mh / 2
    local a = h.heading
    lg.setColor(1, 1, 1, 0.25)
    local fov = 0.6
    local r = big and 40 or 26
    lg.polygon("fill", x, y, x + math.sin(self.yaw - fov) * r, y - math.cos(self.yaw - fov) * r,
        x + math.sin(self.yaw + fov) * r, y - math.cos(self.yaw + fov) * r)
    lg.setColor(0.9, 0.15, 0.1, 1)
    local s = big and 7 or 5
    lg.polygon("fill", x + math.sin(a) * s, y - math.cos(a) * s,
        x + math.sin(a + 2.5) * s, y - math.cos(a + 2.5) * s,
        x + math.sin(a - 2.5) * s, y - math.cos(a - 2.5) * s)
    lg.setScissor()
    lg.setColor(1, 1, 1, 1)
    -- the ground under the feet
    if not big then
        local _, name = self:groundAt(h.x, h.z)
        local title = self.inBoat and "Лодка" or (self.titles[name] or "")
        ui.print(title, mx + mw / 2, my + mh + 8, { font = "small", align = "center", color = "light", shadow = true })
    end
end

return World
