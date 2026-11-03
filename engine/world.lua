-- A level made in Tiled + the entities living in it.
--
--   local world = World("assets/maps/island.tmx")    -- .tmx (Tiled) or .lua (export)
--   world:add(Player(world:spawn("player")))
--   world:update(dt)
--   world:draw(camera)
--
-- What the map can contain (all optional):
--   tile layers           drawn in order; property above = true -> over entities,
--                         property shader = "water" -> drawn through that shader
--   tile properties       surface = "grass" (footsteps), solid = true / false,
--                         oneway = true (platformer: jump through from below),
--                         hazard = true or damage (spikes)
--                         (the top-most tile that has the property decides)
--   "Spawns" layer        points: player, pet ... -> world:spawn(name)
--   "Collision" layer     extra solid rectangles
--   "Surfaces" layer      rectangles with property surface (override tiles)
--   "Triggers" layer      zones, see engine/triggers.lua
--   any other object layer -> world:objects(name) for the game code

local sti = require("libs.sti.sti")
local class = require("engine.class")
local tiled = require("engine.tiled")
local shaders = require("engine.shaders")
local Triggers = require("engine.triggers")
local util = require("engine.util")

local World = class()

-- opts: reflections (default true), openBottom (nothing solid below the map)
function World:init(path, opts)
    opts = opts or {}
    if type(path) == "string" and path:match("%.tmx$") then
        self.map = sti(tiled.load(path))
    else
        self.map = sti(path)
    end
    self.path = path
    local map = self.map
    self.tileWidth, self.tileHeight = map.tilewidth, map.tileheight
    self.cols, self.rows = map.width, map.height
    self.width, self.height = map.width * map.tilewidth, map.height * map.tileheight
    self.entities = {}
    self.reflections = opts.reflections ~= false
    self.openBottom = opts.openBottom
    self.below, self.above, self.shaded = {}, {}, {}
    for _, layer in ipairs(map.layers) do
        if layer.type == "tilelayer" then
            local p = layer.properties or {}
            if p.shader then
                table.insert(self.shaded, layer)
            elseif p.above then
                table.insert(self.above, layer)
            else
                table.insert(self.below, layer)
            end
        elseif layer.type == "objectgroup" then
            layer.visible = false
        end
    end
    self:buildGrids()
    self.solidRects, self.surfaceRects = {}, {}
    for _, o in ipairs(self:objects("Collision")) do
        table.insert(self.solidRects, { x = o.x, y = o.y, w = o.width, h = o.height })
    end
    for _, o in ipairs(self:objects("Surfaces")) do
        table.insert(self.surfaceRects, {
            x = o.x, y = o.y, w = o.width, h = o.height,
            surface = (o.properties or {}).surface or o.type,
        })
    end
    self.triggers = Triggers(self:objectsOf("Trigger"))
end

-- tiles -----------------------------------------------------------------------

function World:buildGrids()
    self.solid, self.surface, self.oneway, self.hazard = {}, {}, {}, {}
    local layers = {}
    for i = #self.map.layers, 1, -1 do -- top to bottom
        local layer = self.map.layers[i]
        if layer.type == "tilelayer" then
            table.insert(layers, layer)
        end
    end
    for row = 1, self.rows do
        for col = 1, self.cols do
            local index = (row - 1) * self.cols + col
            local solid, surface, oneway, hazard = nil, nil, nil, nil
            for _, layer in ipairs(layers) do
                local tile = layer.data[row] and layer.data[row][col]
                local p = tile and tile.properties
                if p then
                    if solid == nil and p.solid ~= nil then
                        solid = p.solid
                    end
                    if surface == nil and p.surface ~= nil then
                        surface = p.surface
                    end
                    if oneway == nil and p.oneway ~= nil then
                        oneway = p.oneway
                    end
                    if hazard == nil and p.hazard ~= nil then
                        hazard = p.hazard
                    end
                end
            end
            self.solid[index] = solid == true
            self.surface[index] = surface
            self.oneway[index] = oneway == true and solid ~= true  -- platform you can jump through from below
            self.hazard[index] = hazard ~= nil and hazard ~= false and hazard or nil -- spikes: true or damage
        end
    end
end

function World:tileAt(x, y)
    return math.floor(x / self.tileWidth) + 1, math.floor(y / self.tileHeight) + 1
end

function World:isSolidTile(col, row)
    if row > self.rows and self.openBottom then
        return false -- platformer: you can fall into a pit below the map
    end
    if col < 1 or row < 1 or col > self.cols or row > self.rows then
        return true
    end
    return self.solid[(row - 1) * self.cols + col]
end

function World:isOnewayTile(col, row)
    if col < 1 or row < 1 or col > self.cols or row > self.rows then
        return false
    end
    return self.oneway[(row - 1) * self.cols + col]
end

function World:hazardAt(x, y)
    local col, row = self:tileAt(x, y)
    if col < 1 or row < 1 or col > self.cols or row > self.rows then
        return nil
    end
    return self.hazard[(row - 1) * self.cols + col]
end

function World:surfaceAt(x, y)
    for _, r in ipairs(self.surfaceRects) do
        if util.pointInRect(x, y, r.x, r.y, r.w, r.h) then
            return r.surface
        end
    end
    local col, row = self:tileAt(x, y)
    if col < 1 or row < 1 or col > self.cols or row > self.rows then
        return nil
    end
    return self.surface[(row - 1) * self.cols + col]
end

-- Is any part of the rectangle inside a wall?
function World:isBlocked(x, y, w, h)
    local tw, th = self.tileWidth, self.tileHeight
    local c1, c2 = math.floor(x / tw) + 1, math.floor((x + w - 0.01) / tw) + 1
    local r1, r2 = math.floor(y / th) + 1, math.floor((y + h - 0.01) / th) + 1
    for row = r1, r2 do
        for col = c1, c2 do
            if self:isSolidTile(col, row) then
                return true
            end
        end
    end
    for _, r in ipairs(self.solidRects) do
        if util.overlaps(x, y, w, h, r.x, r.y, r.w, r.h) then
            return true
        end
    end
    return false
end

local function sweep(world, e, dx, dy)
    local total = math.abs(dx) + math.abs(dy)
    local moved = 0
    while moved < total do
        local step = math.min(1, total - moved)
        local nx = e.x + util.sign(dx) * step
        local ny = e.y + util.sign(dy) * step
        if world:isBlocked(nx - e.w / 2, ny - e.h, e.w, e.h) then
            return true
        end
        e.x, e.y = nx, ny
        moved = moved + step
    end
    return false
end

-- Moves an entity, sliding along walls. Returns hitX, hitY.
function World:move(e, dx, dy)
    if not e.solid or self:isBlocked(e.x - e.w / 2, e.y - e.h, e.w, e.h) then
        e.x, e.y = e.x + dx, e.y + dy -- not solid or stuck inside a wall: let it out
        return false, false
    end
    local hitX = dx ~= 0 and sweep(self, e, dx, 0)
    local hitY = dy ~= 0 and sweep(self, e, 0, dy)
    return hitX, hitY
end

-- Can a straight line be walked/shot without hitting a wall?
function World:lineOfSight(x1, y1, x2, y2)
    local d = util.distance(x1, y1, x2, y2)
    local steps = math.ceil(d / 4)
    for i = 1, steps do
        local t = i / steps
        local x, y = util.lerp(x1, x2, t), util.lerp(y1, y2, t)
        local col, row = self:tileAt(x, y)
        if self:isSolidTile(col, row) then
            return false
        end
    end
    return true
end

-- objects -------------------------------------------------------------------

function World:objects(layerName)
    local layer = self.map.layers[layerName]
    return layer and layer.objects or {}
end

-- Objects of a class from ANY object layer. The class is the Tiled "Class"
-- (or "Type") field; objects without one get it from the name of their
-- layer: Spawns -> Spawn, Items -> Item, Mobs -> Mob, Triggers -> Trigger,
-- Gates -> Gate, NPCs -> NPC. So both ways of marking up a map work.
local LAYER_CLASSES = {
    Spawns = "Spawn", Items = "Item", Mobs = "Mob", Triggers = "Trigger",
    Gates = "Gate", NPCs = "NPC", NPC = "NPC", Collision = "Collision", Surfaces = "Surface",
}

function World:objectsOf(className)
    local result = {}
    local function scan(layers)
        for _, layer in ipairs(layers) do
            if layer.type == "objectgroup" then
                for _, o in ipairs(layer.objects or {}) do
                    local c = o.type ~= "" and o.type or o.class
                    if c == nil or c == "" then
                        c = LAYER_CLASSES[layer.name] or layer.class
                    end
                    if c == className then
                        table.insert(result, o)
                    end
                end
            elseif layer.type == "group" and layer.layers then
                scan(layer.layers)
            end
        end
    end
    scan(self.map.layers)
    return result
end

-- Position of a point object in the "Spawns" layer.
function World:spawn(name, defaultX, defaultY)
    for _, o in ipairs(self:objectsOf("Spawn")) do
        if o.name == name then
            return o.x, o.y
        end
    end
    return defaultX or self.width / 2, defaultY or self.height / 2
end

-- entities ------------------------------------------------------------------

function World:add(e)
    table.insert(self.entities, e)
    e.world = self
    if e.added then
        e:added(self)
    end
    return e
end

function World:remove(e)
    e.removed = true
end

function World:each(filter)
    local result = {}
    for _, e in ipairs(self.entities) do
        if not e.removed and (not filter or filter(e)) then
            table.insert(result, e)
        end
    end
    return result
end

-- Entities whose collision box overlaps the rectangle.
function World:query(x, y, w, h, filter)
    local result = {}
    for _, e in ipairs(self.entities) do
        if not e.removed and (not filter or filter(e)) then
            local ex, ey, ew, eh = e:getBox()
            if util.overlaps(x, y, w, h, ex, ey, ew, eh) then
                table.insert(result, e)
            end
        end
    end
    return result
end

function World:nearest(x, y, radius, filter)
    local best, bestDistance = nil, radius or math.huge
    for _, e in ipairs(self.entities) do
        if not e.removed and (not filter or filter(e)) then
            local d = util.distance(x, y, e.x, e.y)
            if d < bestDistance then
                best, bestDistance = e, d
            end
        end
    end
    return best, bestDistance
end

function World:update(dt)
    self.map:update(dt)
    local list = {}
    for i, e in ipairs(self.entities) do
        list[i] = e
    end
    for _, e in ipairs(list) do
        if not e.removed then
            e:update(dt)
        end
    end
    for i = #self.entities, 1, -1 do
        local e = self.entities[i]
        if e.removed then
            table.remove(self.entities, i)
            if e.onRemove then
                e:onRemove()
            end
        end
    end
end

-- drawing -------------------------------------------------------------------

local function sortByDepth(a, b)
    if a.y == b.y then
        return a.id < b.id
    end
    return a.y < b.y
end

-- Shaded layers are drawn to a canvas first, then through the shader,
-- together with a second canvas of mirrored entities (reflections).
function World:drawShaded(camera)
    local lg = love.graphics
    local w, h = camera.width, camera.height
    if not self.canvas or self.canvas:getWidth() ~= w or self.canvas:getHeight() ~= h then
        self.canvas = lg.newCanvas(w, h)
        self.reflectionCanvas = lg.newCanvas(w, h)
        self.canvas:setFilter("nearest", "nearest")
        self.reflectionCanvas:setFilter("nearest", "nearest")
    end
    lg.push("all")
    lg.setCanvas(self.canvas)
    lg.clear(0, 0, 0, 0)
    camera:attach()
    for _, layer in ipairs(self.shaded) do
        self.map:drawLayer(layer)
    end
    camera:detach()
    lg.setCanvas(self.reflectionCanvas)
    lg.clear(0, 0, 0, 0)
    if self.reflections then
        camera:attach()
        for _, e in ipairs(self.entities) do
            if e.reflect and not e.removed and e.drawReflection then
                e:drawReflection()
            end
        end
        camera:detach()
    end
    lg.pop()

    local props = self.shaded[1].properties
    local shader = shaders.get(props.shader)
    if shader then
        local left, top = camera:getTopLeft()
        shaders.send(shader, "canvasSize", { w, h })
        shaders.send(shader, "worldOffset", { left, top })
        shaders.send(shader, "zoom", camera.zoom)
        shaders.send(shader, "maskMode", props.mask == "all" and 0 or 1)
        shaders.send(shader, "waveHeight", props.waveHeight or 1.2)
        shaders.send(shader, "reflectionStrength", self.reflections and (props.reflection or 0.5) or 0)
        shaders.send(shader, "reflection", self.reflectionCanvas)
        lg.setShader(shader)
    end
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.canvas, 0, 0)
    lg.setShader()
end

-- hooks (optional): beforeEntities(), afterEntities(), overlay() - world space
function World:draw(camera, hooks)
    hooks = hooks or {}
    if #self.shaded > 0 then
        self:drawShaded(camera)
    end
    camera:attach()
    for _, layer in ipairs(self.below) do
        self.map:drawLayer(layer)
    end
    if hooks.beforeEntities then
        hooks.beforeEntities()
    end
    local sorted = {}
    for _, e in ipairs(self.entities) do
        if not e.removed then
            table.insert(sorted, e)
        end
    end
    table.sort(sorted, sortByDepth)
    for _, e in ipairs(sorted) do
        e:drawShadow()
    end
    for _, e in ipairs(sorted) do
        e:draw()
    end
    if hooks.afterEntities then
        hooks.afterEntities()
    end
    for _, layer in ipairs(self.above) do
        self.map:drawLayer(layer)
    end
    if hooks.overlay then
        hooks.overlay()
    end
    camera:detach()
end

-- Collision grid, boxes and triggers (F1).
function World:drawDebug(camera)
    local lg = love.graphics
    camera:attach()
    lg.setLineWidth(1)
    for row = 1, self.rows do
        for col = 1, self.cols do
            local index = (row - 1) * self.cols + col
            if self.solid[index] then
                lg.setColor(1, 0, 0, 0.25)
                lg.rectangle("fill", (col - 1) * self.tileWidth, (row - 1) * self.tileHeight,
                    self.tileWidth, self.tileHeight)
            elseif self.oneway[index] then
                lg.setColor(1, 1, 0, 0.6)
                lg.rectangle("fill", (col - 1) * self.tileWidth, (row - 1) * self.tileHeight, self.tileWidth, 2)
            end
        end
    end
    lg.setColor(1, 0.2, 0.2, 0.8)
    for _, r in ipairs(self.solidRects) do
        lg.rectangle("line", r.x, r.y, r.w, r.h)
    end
    for _, zone in ipairs(self.triggers.zones) do
        lg.setColor(zone.inside and { 0.2, 1, 0.2, 0.9 } or { 1, 1, 0.2, 0.8 })
        lg.rectangle("line", zone.x, zone.y, zone.w, zone.h)
        lg.print(zone.name or "?", zone.x + 2, zone.y - 14)
    end
    lg.setColor(0.3, 0.8, 1, 0.9)
    for _, e in ipairs(self.entities) do
        local x, y, w, h = e:getBox()
        lg.rectangle("line", x, y, w, h)
    end
    lg.setColor(1, 1, 1, 1)
    camera:detach()
end

return World
