-- Isometric Tiled maps with height levels (Map > Orientation: Isometric).
--
--   local map = IsoMap("assets/maps/iso_meadow.tmx")
--   map:groundAt(x, y)            -- height of the ground (in levels) under a point
--   map:project(x, y, z)          -- iso point -> map pixels on the screen
--   map:draw(left, top, w, h, actors, hooks)
--
-- Coordinates: like Tiled objects in an isometric map. x runs along the map
-- columns, y along the rows, map.unit (= tile height, 16) pixels per tile, so a
-- point object placed in Tiled has the same x, y here. z is the height in levels.
--
-- Levels: every tile layer is one height level. Set the layer's Vertical offset
-- in Tiled to -16 * level (or the property level = 1). The first tile layer is
-- the floor. A 32x32 block placed on layer 0 stands on the ground, its top is
-- level 1; a block on layer 1 stands on top of it.
--
-- Tile properties (tileset editor):
--   height    top of the tile above its layer, in levels (default 1 = a block;
--             0.5 = a slab, 0 = flat decoration: flowers, shadows)
--   ramp      "ne" | "nw" | "se" | "sw": the surface rises toward that side
--             (stairs, slopes); low = height at the low side (default 0)
--   solid     can't walk through (trees, rocks, fences)
--   water     water: can't walk, splashes
--   surface   footstep sounds (grass, stone, wood... see game/data/surfaces.lua)
-- Directions: ne = up-right on the screen (-y), nw = up-left (-x),
-- se = down-right (+x), sw = down-left (+y).

local assets = require("engine.assets")
local class = require("engine.class")
local tiled = require("engine.tiled")

local IsoMap = class()

IsoMap.DIRS = { ne = { 0, -1 }, nw = { -1, 0 }, se = { 1, 0 }, sw = { 0, 1 } }
IsoMap.STEP = 0.55 -- how high a walker can step up (levels)

local FLIP_H, FLIP_V, FLIP_D = 2147483648, 1073741824, 536870912

local function bool(v)
    return v == true or v == "true" or v == 1
end

function IsoMap:init(path)
    local map = tiled.load(path)
    assert(map.orientation == "isometric",
        "isomap: '" .. path .. "' is " .. tostring(map.orientation) .. ", set Map > Orientation to Isometric")
    self.path, self.map = path, map
    self.width, self.height = map.width, map.height
    self.tw, self.th = map.tilewidth, map.tileheight
    self.unit = self.th
    self.properties = map.properties or {}
    self.lh = tonumber(self.properties.levelHeight) or self.th
    self.originX = self.height * self.tw / 2
    local bg = map.backgroundcolor
    self.background = bg and { bg[1] / 255, bg[2] / 255, bg[3] / 255 } or { 0.12, 0.14, 0.22 }
    self.time = 0
    self:loadTiles()
    self.layers, self.objectLayers = {}, {}
    self:loadLayers(map.layers, 0, 0, true)
    self:buildCells()
end

-- tiles ------------------------------------------------------------------------------

function IsoMap:loadTiles()
    self.tiles = {}
    for _, ts in ipairs(self.map.tilesets) do
        local perTile = {}
        for _, t in ipairs(ts.tiles or {}) do
            perTile[t.id] = t
        end
        local image = ts.image and ts.image ~= "" and assets.image(ts.image)
        local count = ts.tilecount or 0
        if count == 0 and image then
            count = ts.columns * math.floor((image:getHeight() - ts.margin * 2 + ts.spacing) / (ts.tileheight + ts.spacing))
        end
        local function quadOf(id)
            local c, r = id % ts.columns, math.floor(id / ts.columns)
            return love.graphics.newQuad(ts.margin + c * (ts.tilewidth + ts.spacing),
                ts.margin + r * (ts.tileheight + ts.spacing), ts.tilewidth, ts.tileheight, image:getDimensions())
        end
        local ids = {}
        if image then
            for id = 0, count - 1 do
                ids[#ids + 1] = id
            end
        else
            for id in pairs(perTile) do
                ids[#ids + 1] = id
            end
        end
        for _, id in ipairs(ids) do
            local t = perTile[id] or {}
            local p = t.properties or {}
            local info = {
                id = id, tileset = ts, props = p,
                ox = ts.tileoffset and ts.tileoffset.x or 0, oy = ts.tileoffset and ts.tileoffset.y or 0,
                height = tonumber(p.height) or 1,
                ramp = p.ramp ~= "" and p.ramp or nil,
                low = tonumber(p.low) or 0,
                solid = bool(p.solid), water = bool(p.water),
                surface = p.surface ~= "" and p.surface or nil,
            }
            if t.image then
                info.image = assets.image(t.image)
                info.w, info.h = info.image:getDimensions()
                info.quad = love.graphics.newQuad(0, 0, info.w, info.h, info.w, info.h)
            elseif image then
                info.image, info.quad = image, quadOf(id)
                info.w, info.h = ts.tilewidth, ts.tileheight
            end
            if t.animation and #t.animation > 0 and image then
                info.frames, info.total = {}, 0
                for _, f in ipairs(t.animation) do
                    info.frames[#info.frames + 1] = { quad = quadOf(f.tileid), duration = f.duration / 1000 }
                    info.total = info.total + f.duration / 1000
                end
            end
            if info.image then
                self.tiles[ts.firstgid + id] = info
            end
        end
    end
end

-- layers -----------------------------------------------------------------------------

-- object Class -> the list it goes to (objectsOf("Mobs") also gets Mob objects of any layer)
local CLASS_LAYERS = { Spawn = "Spawns", Item = "Items", Mob = "Mobs", NPC = "NPC", Trigger = "Triggers" }
local LAYER_ALIASES = { NPCs = "NPC" }

function IsoMap:loadLayers(list, ox, oy, visible)
    for _, layer in ipairs(list) do
        local lx, ly = ox + (layer.offsetx or 0), oy + (layer.offsety or 0)
        local shown = visible and layer.visible ~= false
        if layer.type == "group" then
            self:loadLayers(layer.layers, lx, ly, shown)
        elseif layer.type == "tilelayer" then
            local p = layer.properties or {}
            table.insert(self.layers, {
                name = layer.name, data = layer.data, width = layer.width, ox = lx, oy = ly,
                level = tonumber(p.level) or -ly / self.lh,
                visible = shown, opacity = layer.opacity or 1, properties = p,
            })
        elseif layer.type == "objectgroup" then
            for _, o in ipairs(layer.objects) do
                o.layer = layer.name
                o.properties = o.properties or {}
                -- the object's Class (from a template) wins over the name of its layer
                local c = (o.type and o.type ~= "") and o.type or o.class
                local bucket = CLASS_LAYERS[c or ""] or LAYER_ALIASES[layer.name] or layer.name
                self.objectLayers[bucket] = self.objectLayers[bucket] or {}
                table.insert(self.objectLayers[bucket], o)
            end
        end
    end
end

-- objects of a layer ("Mobs", "Items", "Triggers"...) or of that Class in any layer
function IsoMap:objectsOf(name)
    return self.objectLayers[name] or {}
end

-- a named point (layer "Spawns" or any object with that name): x, y
function IsoMap:spawn(name)
    for _, o in ipairs(self:objectsOf("Spawns")) do
        if o.name == name then
            return self:objectPoint(o)
        end
    end
    for _, list in pairs(self.objectLayers) do
        for _, o in ipairs(list) do
            if o.name == name then
                return self:objectPoint(o)
            end
        end
    end
    return self.width * self.unit / 2, self.height * self.unit / 2
end

function IsoMap:objectPoint(o)
    -- points; tile objects (a template with a picture) stand on their bottom-center
    if o.shape == "point" or (o.width or 0) == 0 or o.gid then
        return o.x, o.y
    end
    return o.x + o.width / 2, o.y + o.height / 2
end

-- cells: what stands where -------------------------------------------------------------

local function decode(gid)
    local flip = false
    if gid >= FLIP_H then
        gid, flip = gid - FLIP_H, true
    end
    if gid >= FLIP_V then
        gid = gid - FLIP_V
    end
    if gid >= FLIP_D then
        gid = gid - FLIP_D
    end
    return gid, flip
end

function IsoMap:buildCells()
    local W, H = self.width, self.height
    self.cells = {}
    self.floor = self.layers[1]
    self.maxLevel = 0
    for li, layer in ipairs(self.layers) do
        self.maxLevel = math.max(self.maxLevel, layer.level + 1)
        for j = 0, H - 1 do
            for i = 0, W - 1 do
                local raw = layer.data[j * layer.width + i + 1] or 0
                if raw > 0 then
                    local gid, flip = decode(raw)
                    local tile = self.tiles[gid]
                    if tile then
                        local idx = j * W + i + 1
                        local cell = self.cells[idx]
                        if not cell then
                            cell = { i = i, j = j, list = {}, z = nil }
                            self.cells[idx] = cell
                        end
                        table.insert(cell.list, { tile = tile, flip = flip, layer = layer, index = li })
                    end
                end
            end
        end
    end
    for _, cell in pairs(self.cells) do
        self:refreshCell(cell)
    end
end

-- ground height, ramp, walls of a cell from its tiles
function IsoMap:refreshCell(cell)
    cell.z, cell.ramp, cell.solid, cell.water, cell.surface = nil, nil, false, false, nil
    for _, e in ipairs(cell.list) do
        local t, level = e.tile, e.layer.level
        if t.height > 0 or t.ramp then
            local top = level + t.height
            if not cell.z or top >= cell.z then
                cell.z = top
                cell.ramp = t.ramp and { dir = t.ramp, low = level + t.low, high = top } or nil
                cell.water = t.water
                cell.surface = t.surface or cell.surface
            end
        end
        if t.solid then
            cell.solid = true
        end
        if t.surface and t.height == 0 then
            cell.surface = t.surface
        end
    end
end

function IsoMap:cell(i, j)
    if i < 0 or j < 0 or i >= self.width or j >= self.height then
        return nil
    end
    return self.cells[j * self.width + i + 1]
end

function IsoMap:cellAt(x, y)
    return self:cell(math.floor(x / self.unit), math.floor(y / self.unit))
end

-- height of the ground under a point (nil = nothing there)
function IsoMap:groundAt(x, y)
    local u = self.unit
    local cell = self:cellAt(x, y)
    if not cell or not cell.z then
        return nil, cell
    end
    local r = cell.ramp
    if r then
        local fx, fy = x / u - cell.i, y / u - cell.j
        local t = (r.dir == "se" and fx) or (r.dir == "nw" and 1 - fx) or (r.dir == "sw" and fy) or (1 - fy)
        return r.low + (r.high - r.low) * t, cell
    end
    return cell.z, cell
end

-- can a walker at height z stand at x, y? (not water, not a wall, not too high)
function IsoMap:walkable(x, y, z, opts)
    local g, cell = self:groundAt(x, y)
    if not g or (cell.solid and not (opts and opts.through)) then
        return false
    end
    if cell.water and not (opts and opts.swim) then
        return false
    end
    return g <= z + (opts and opts.step or IsoMap.STEP), g
end

-- a circle of radius r: the center and four points around it
function IsoMap:fits(x, y, z, r, opts)
    if not self:walkable(x, y, z, opts) then
        return false
    end
    local k = r * 0.72
    return self:walkable(x + r, y, z, opts) and self:walkable(x - r, y, z, opts)
        and self:walkable(x, y + r, z, opts) and self:walkable(x, y - r, z, opts)
        and self:walkable(x + k, y + k, z, opts) and self:walkable(x - k, y - k, z, opts)
        and self:walkable(x + k, y - k, z, opts) and self:walkable(x - k, y + k, z, opts)
end

-- moves a walker { x, y, z, radius } by dx, dy, sliding along walls. Returns hitX, hitY.
function IsoMap:move(e, dx, dy, opts)
    local r = e.radius or 4
    local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / (r * 0.8)))
    local hitX, hitY = false, false
    dx, dy = dx / steps, dy / steps
    for _ = 1, steps do
        if dx ~= 0 then
            if self:fits(e.x + dx, e.y, e.z, r, opts) then
                e.x = e.x + dx
            else
                hitX = true
            end
        end
        if dy ~= 0 then
            if self:fits(e.x, e.y + dy, e.z, r, opts) then
                e.y = e.y + dy
            else
                hitY = true
            end
        end
    end
    return hitX, hitY
end

-- is there a clear walk (no walls, no water, no cliffs up) from a to b?
-- opts.through = true: solid things (trees, rocks) do not count, only the ground
function IsoMap:clearLine(x1, y1, z1, x2, y2, opts)
    local d = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local n = math.max(1, math.ceil(d / (self.unit / 3)))
    local z = z1
    for k = 1, n do
        local x, y = x1 + (x2 - x1) * k / n, y1 + (y2 - y1) * k / n
        local ok, g = self:walkable(x, y, z, opts)
        if not ok then
            return false
        end
        z = g
    end
    return true
end

-- projection ---------------------------------------------------------------------------

-- iso point -> map pixels (before the camera)
function IsoMap:project(x, y, z)
    local u = self.unit
    return (x - y) / u * self.tw / 2 + self.originX, (x + y) / u * self.th / 2 - (z or 0) * self.lh
end

-- map pixels at height z -> iso point
function IsoMap:unproject(sx, sy, z)
    local u = self.unit
    local a = (sx - self.originX) / (self.tw / 2) -- fi - fj
    local b = (sy + (z or 0) * self.lh) / (self.th / 2) -- fi + fj
    return (a + b) / 2 * u, (b - a) / 2 * u
end

-- size of the whole map in map pixels: left, top, width, height
function IsoMap:bounds()
    local top = -self.maxLevel * self.lh - self.th
    return 0, top, (self.width + self.height) * self.tw / 2, (self.width + self.height) * self.th / 2 - top + self.th
end

-- drawing ------------------------------------------------------------------------------

function IsoMap:update(dt)
    self.time = self.time + dt
end

local function drawEntry(self, e, i, j)
    local t, layer = e.tile, e.layer
    local vx = (i - j) * self.tw / 2 + self.originX
    local vy = (i + j) * self.th / 2
    local x = vx - self.tw / 2 + t.ox + layer.ox
    local y = vy + self.th - t.h + t.oy + layer.oy
    local quad = t.quad
    if t.frames then
        local k = self.time % t.total
        for _, f in ipairs(t.frames) do
            if k < f.duration then
                quad = f.quad
                break
            end
            k = k - f.duration
        end
    end
    if e.flip then
        love.graphics.draw(t.image, quad, x + t.w, y, 0, -1, 1)
    else
        love.graphics.draw(t.image, quad, x, y)
    end
end

-- Draws the part of the map inside the view (map pixels), with the actors sorted
-- between the tiles. actors: list of { x, y, z, draw = function(self) end }.
-- hooks.floor(): called after the floor layer (shadows on the ground, markers).
function IsoMap:draw(left, top, w, h, actors, hooks)
    hooks = hooks or {}
    local W, H = self.width, self.height
    local hw, hh = self.tw / 2, self.th / 2
    local margin = 64
    local dmin = math.max(0, math.floor((top - margin) / hh) - 2)
    local dmax = math.min(W + H - 2, math.ceil((top + h + margin + self.maxLevel * self.lh) / hh) + 2)
    local floor = self.floor
    local function range(d)
        -- columns i of diagonal d (i + j = d) visible horizontally
        local a = (left - margin - self.originX) / hw
        local b = (left + w + margin - self.originX) / hw
        local i0 = math.max(0, d - (H - 1), math.floor((a + d) / 2))
        local i1 = math.min(W - 1, d, math.ceil((b + d) / 2))
        return i0, i1
    end
    -- 1. the floor: under everything
    if floor and floor.visible then
        love.graphics.setColor(1, 1, 1, floor.opacity)
        for d = dmin, dmax do
            local i0, i1 = range(d)
            for i = i0, i1 do
                local j = d - i
                local cell = self.cells[j * W + i + 1]
                if cell then
                    for _, e in ipairs(cell.list) do
                        if e.layer == floor then
                            drawEntry(self, e, i, j)
                        end
                    end
                end
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
    if hooks.floor then
        hooks.floor()
    end
    -- 2. everything above the floor and the actors, back to front
    local buckets = {}
    local u = self.unit
    for _, a in ipairs(actors or {}) do
        local d = math.floor(a.x / u) + math.floor(a.y / u)
        d = math.max(dmin, math.min(dmax, d))
        local b = buckets[d]
        if not b then
            b = {}
            buckets[d] = b
        end
        b[#b + 1] = a
    end
    for d = dmin, dmax do
        local i0, i1 = range(d)
        for i = i0, i1 do
            local j = d - i
            local cell = self.cells[j * W + i + 1]
            if cell then
                for _, e in ipairs(cell.list) do
                    if e.layer ~= floor and e.layer.visible then
                        if e.layer.opacity < 1 then
                            love.graphics.setColor(1, 1, 1, e.layer.opacity)
                        end
                        drawEntry(self, e, i, j)
                        love.graphics.setColor(1, 1, 1, 1)
                    end
                end
            end
        end
        local b = buckets[d]
        if b then
            table.sort(b, function(p, q)
                local dp, dq = p.x + p.y, q.x + q.y
                if math.abs(dp - dq) > 0.01 then
                    return dp < dq
                end
                return (p.z or 0) < (q.z or 0)
            end)
            for _, a in ipairs(b) do
                a:draw()
            end
        end
    end
end

-- only what stands in front of diagonal d0 (cells with i + j > d0, no floor, no actors):
-- used to find which part of an actor is hidden behind trees and cliffs
function IsoMap:drawFront(left, top, w, h, d0)
    local W, H = self.width, self.height
    local hw, hh = self.tw / 2, self.th / 2
    local floor = self.floor
    local dmin = math.max(d0 + 1, math.floor((top - 16) / hh) - 2)
    local dmax = math.min(W + H - 2, math.ceil((top + h + 16 + self.maxLevel * self.lh) / hh) + 2)
    local a = (left - 32 - self.originX) / hw
    local b = (left + w + 32 - self.originX) / hw
    for d = dmin, dmax do
        local i0 = math.max(0, d - (H - 1), math.floor((a + d) / 2))
        local i1 = math.min(W - 1, d, math.ceil((b + d) / 2))
        for i = i0, i1 do
            local cell = self.cells[(d - i) * W + i + 1]
            if cell then
                for _, e in ipairs(cell.list) do
                    if e.layer ~= floor and e.layer.visible then
                        drawEntry(self, e, i, d - i)
                    end
                end
            end
        end
    end
end

-- debug: walkable cells and heights
function IsoMap:drawDebug(left, top, w, h)
    local font = love.graphics.getFont()
    for _, cell in pairs(self.cells) do
        if cell.z then
            local x, y = self:project((cell.i + 0.5) * self.unit, (cell.j + 0.5) * self.unit, cell.z)
            if x > left - 32 and x < left + w + 32 and y > top - 32 and y < top + h + 32 then
                if cell.solid or cell.water then
                    love.graphics.setColor(1, 0.3, 0.3, 0.7)
                else
                    love.graphics.setColor(0.3, 1, 0.4, 0.7)
                end
                love.graphics.print(string.format("%g", cell.z), x - 6, y - 6, 0, 0.5, 0.5)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return IsoMap
