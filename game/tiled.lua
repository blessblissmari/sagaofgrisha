-- Tiled helpers made from the game data.
--
--   love . --tiled
--       rewrites the Tiled project assets/maps/SagaOfGrisha.tiled-project: the custom
--       types (classes Trigger, Item, Mob, NPC... and lists of mobs, items, stages,
--       music to choose from) and the object templates in assets/maps/templates/
--       (items/, mobs/, npcs/ with pictures, objects/ for spawns, exits, zones).
--       Run it again after adding mobs, items, sprites or stages.
--   love . --map=assets/maps/templates/topdown.tmx
--       plays any map at once. The kind of gameplay is the map's Class (Map >
--       Map Properties > Class: topdown, platformer, raycaster, iso).
--       In Tiled: F5 (the command "Играть карту" of the project).
--
-- The types are described below (CLASSES); defaults there are only what Tiled shows
-- for an empty property, the game itself falls back to the same values.

local M = {}

local PROJECT = "assets/maps/SagaOfGrisha.tiled-project"
local TEMPLATES = "assets/maps/templates/"
local CELL = 32 -- size of the template pictures

-- sprites that get no NPC template (effects)
M.NOT_NPC = { coin = true, sparkle = true, puff = true, saw = true }

local function G()
    return require("game")
end

local function sortedKeys(t, keep)
    local list = {}
    for k, v in pairs(t or {}) do
        if type(k) == "string" and (not keep or keep(k, v)) then
            list[#list + 1] = k
        end
    end
    table.sort(list)
    return list
end

-- the lists (enums) Tiled shows as dropdowns
function M.enums()
    local g = G()
    local abilities, seen = {}, {}
    for _, id in ipairs(sortedKeys(g.items)) do
        local a = g.items[id].ability
        if a and not seen[a] then
            seen[a] = true
            abilities[#abilities + 1] = a
        end
    end
    table.sort(abilities)
    local isTable = function(_, v) return type(v) == "table" end
    return {
        { "Surface", sortedKeys(g.surfaces, isTable) },
        { "MobKind", sortedKeys(g.mobs) },
        { "ItemId", sortedKeys(g.items) },
        { "Ability", abilities },
        { "SpriteName", sortedKeys(g.sprites) },
        { "Stage", sortedKeys(g.stages, function(k) return k:sub(1, 2) ~= "__" end) },
        { "Music", sortedKeys(g.sounds.music) },
        { "Sound", sortedKeys(g.sounds.sounds) },
        { "Transition", sortedKeys(require("engine").scene.transitions) },
        { "Background", sortedKeys(g.backgrounds) },
        { "Facing", { "down", "up", "left", "right", "se", "sw", "ne", "nw" } },
        { "Pickup", { "auto", "press" } },
        { "Ramp", { "ne", "nw", "se", "sw" } },
    }
end

-- classes: { name, useAs, color, members = { { name, type, default }, ... } }
-- type: bool int float string color, or the name of an enum above
M.CLASSES = {
    { "Spawn", { "object" }, "#ff55ff55", {
        { "angle", "float", 0 },          -- dungeon: where the hero looks (0 east, 90 south...)
    } },
    { "Trigger", { "object" }, "#ffff5555", {
        { "dialogue", "string", "" },     -- "Гриша: Привет! | Кашка: Мяу" (lines: | or new line)
        { "go", "Stage", "" },            -- go to that stage
        { "spawn", "string", "" },        -- ... and appear at this Spawn there
        { "transition", "Transition", "" },
        { "interact", "bool", false },    -- wait for [E] instead of firing on enter
        { "prompt", "string", "" },       -- hint while standing inside
        { "once", "bool", false },
        { "requires", "ItemId", "" },     -- doesn't work without this thing in the bag
        { "sound", "Sound", "" },
        { "finish", "bool", false },      -- the stage is won (story.lua decides what's next)
    } },
    { "Item", { "object" }, "#ffffd700", {
        { "item", "ItemId", "" },
        { "count", "int", 1 },
        { "pickup", "Pickup", "" },       -- empty: as the item says (things of the bag: press)
    } },
    { "Mob", { "object" }, "#ffff00ff", {
        { "mob", "MobKind", "" },
        { "group", "string", "" },        -- iso: mobs of one group fight together
        { "boss", "bool", false },
    } },
    { "NPC", { "object" }, "#ff00e5ff", {
        { "sprite", "SpriteName", "" },
        { "facing", "Facing", "" },       -- top-down: down up left right; iso: se sw ne nw
        { "flip", "bool", false },
        { "dialogue", "string", "" },
        { "prompt", "string", "" },
        { "once", "bool", false },
    } },
    { "Gate", { "object" }, "#ff00aaff", {
        { "ability", "Ability", "" },     -- opens for this ability...
        { "item", "ItemId", "" },         -- ... or this thing
        { "consume", "bool", true },
    } },
    { "Tile", { "tile" }, "#ffa0a0a4", {
        { "solid", "bool", false },
        { "surface", "Surface", "" },     -- footsteps
        { "oneway", "bool", false },      -- platformer: jump through from below
        { "hazard", "int", 0 },           -- damage (spikes)
    } },
    { "Wall", { "tile" }, "#ff8a8a8a", {   -- dungeon textures
        { "name", "string", "" },
        { "door", "bool", false },
        { "locked", "bool", false },
    } },
    { "IsoTile", { "tile" }, "#ff7fbf60", {
        { "height", "float", 1 },         -- top above its layer in levels (0.5 slab, 0 flat)
        { "ramp", "Ramp", "" },           -- the surface rises toward that side
        { "low", "float", 0 },            -- ramp: height of the low side
        { "solid", "bool", false },
        { "water", "bool", false },
        { "surface", "Surface", "" },
    } },
    { "Layer", { "layer" }, "#ff9090ff", {
        { "above", "bool", false },       -- drawn over the characters
        { "shader", "string", "" },       -- "water"
    } },
    -- map classes = the kind of gameplay (love . --map=... picks the mode by it)
    { "topdown", { "map" }, nil, {
        { "music", "Music", "" },
    } },
    { "platformer", { "map" }, nil, {
        { "music", "Music", "" },
        { "background", "Background", "hills" },
    } },
    { "raycaster", { "map" }, nil, {
        { "music", "Music", "" },
        { "floor", "int", 13 },           -- textures: index of the tile in walls.tsx
        { "ceiling", "int", 4 },
        { "doorTexture", "int", 6 },
        { "lockedTexture", "int", 12 },
        { "fog", "color", "#ff0f0f17" },
        { "fogDistance", "float", 7 },
    } },
    { "iso", { "map" }, nil, {
        { "music", "Music", "" },
        { "levelHeight", "int", 16 },     -- pixels between height levels
    } },
}

local function memberType(className, prop)
    for _, c in ipairs(M.CLASSES) do
        if c[1] == className then
            for _, mem in ipairs(c[4]) do
                if mem[1] == prop then
                    return mem[2]
                end
            end
        end
    end
end

-- JSON (keys sorted, like Tiled writes it) -------------------------------------------

local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function json(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "string" then
        return quote(v)
    elseif t == "number" then
        return (v == math.floor(v) and math.abs(v) < 2 ^ 53) and string.format("%d", v) or string.format("%.14g", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t ~= "table" then
        return "null"
    end
    local inner = indent .. "    "
    local parts = {}
    if #v > 0 or next(v) == nil then
        if #v == 0 then
            return "[\n" .. indent .. "]"
        end
        for _, x in ipairs(v) do
            parts[#parts + 1] = inner .. json(x, inner)
        end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    for _, k in ipairs(sortedKeys(v)) do
        parts[#parts + 1] = inner .. quote(k) .. ": " .. json(v[k], inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end
M.json = json

-- files -------------------------------------------------------------------------------

local function sourcePath(rel)
    return love.filesystem.getSource() .. "/" .. rel
end

local function write(rel, data)
    local path = sourcePath(rel)
    local f = io.open(path, "wb")
    if not f then
        local dir = path:match("^(.*)/[^/]*$")
        if love.system.getOS() == "Windows" then
            os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
        else
            os.execute("mkdir -p '" .. dir .. "'")
        end
        f = assert(io.open(path, "wb"))
    end
    f:write(data)
    f:close()
end

local function xmlEscape(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("\n", "&#10;"))
end

local ENUMS = nil

-- <property> lines for a template of that class
local function propertiesXML(className, props, pad)
    local keys = sortedKeys(props)
    if #keys == 0 then
        return ""
    end
    local lines = { pad .. "<properties>" }
    for _, k in ipairs(keys) do
        local v = props[k]
        local mt = memberType(className, k) or (type(v) == "boolean" and "bool") or "string"
        local attr = ""
        if mt == "bool" or mt == "int" or mt == "float" or mt == "color" then
            attr = ' type="' .. mt .. '"'
        elseif ENUMS[mt] then
            attr = ' propertytype="' .. mt .. '"'
        end
        lines[#lines + 1] = string.format('%s <property name="%s"%s value="%s"/>', pad, k, attr, xmlEscape(tostring(v)))
    end
    lines[#lines + 1] = pad .. "</properties>"
    return table.concat(lines, "\n") .. "\n"
end

-- an object template (.tx); tile = index of the picture in previews.tsx
local function templateXML(t, previewsPath)
    local attrs = {}
    if t.name then
        attrs[#attrs + 1] = string.format('name="%s"', xmlEscape(t.name))
    end
    attrs[#attrs + 1] = string.format('type="%s"', t.class)
    if t.tile then
        attrs[#attrs + 1] = string.format('gid="%d" width="%d" height="%d"', t.tile + 1, CELL, CELL)
    elseif t.w then
        attrs[#attrs + 1] = string.format('width="%d" height="%d"', t.w, t.h)
    end
    local out = { '<?xml version="1.0" encoding="UTF-8"?>', "<template>" }
    if t.tile then
        out[#out + 1] = string.format(' <tileset firstgid="1" source="%s"/>', previewsPath)
    end
    local body = propertiesXML(t.class, t.props or {}, "  ")
    if body == "" and not t.point then
        out[#out + 1] = " <object " .. table.concat(attrs, " ") .. "/>"
    else
        out[#out + 1] = " <object " .. table.concat(attrs, " ") .. ">"
        if body ~= "" then
            out[#out + 1] = body:sub(1, -2)
        end
        if t.point then
            out[#out + 1] = "  <point/>"
        end
        out[#out + 1] = " </object>"
    end
    out[#out + 1] = "</template>"
    return table.concat(out, "\n") .. "\n"
end

-- pictures of the templates ---------------------------------------------------------

-- draws `draw()` (a picture of w x h) into the cell, cropped to its pixels and fitted
local function fitInto(canvas, cx, cy, w, h, draw)
    local lg = love.graphics
    local tmp = lg.newCanvas(w, h)
    lg.setCanvas(tmp)
    lg.clear(0, 0, 0, 0)
    lg.setColor(1, 1, 1, 1)
    draw()
    lg.setCanvas()
    local data = tmp:newImageData()
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local _, _, _, a = data:getPixel(x, y)
            if a > 0.05 then
                x0, y0 = math.min(x0, x), math.min(y0, y)
                x1, y1 = math.max(x1, x), math.max(y1, y)
            end
        end
    end
    if x1 < 0 then
        return false
    end
    local bw, bh = x1 - x0 + 1, y1 - y0 + 1
    local s = math.min(CELL / bw, CELL / bh)
    if s >= 1 then
        s = math.floor(s)
    end
    lg.setCanvas(canvas)
    local quad = lg.newQuad(x0, y0, bw, bh, w, h)
    lg.draw(tmp, quad, math.floor(cx + (CELL - bw * s) / 2), math.floor(cy + CELL - bh * s), 0, s, s)
    lg.setCanvas()
    return true
end

local function spritePicture(def)
    local anim = require("engine").anim
    local ok, sprite = pcall(anim.new, def)
    if not ok then
        return nil
    end
    local played = false
    for _, sub in ipairs({ "down", "se", "s", "right", "sw" }) do
        if not played and sprite:has("idle", sub) then
            sprite:play("idle", sub)
            played = true
        end
    end
    if not played then
        sprite:play("idle")
    end
    if not sprite.current then
        return nil
    end
    local quad = sprite:getQuad()
    local _, _, qw, qh = quad:getViewport()
    return qw, qh, function()
        love.graphics.draw(sprite.image, quad, 0, 0)
    end
end

-- export ----------------------------------------------------------------------------

local function previewEntries()
    local g = G()
    local engine = require("engine")
    local list = {}
    for _, id in ipairs(sortedKeys(g.items)) do
        local info = g.items[id]
        local path = info.icon and ("assets/sprites/icons/" .. info.icon .. ".png")
        if path and love.filesystem.getInfo(path) then
            local img = engine.assets.image(path)
            list[#list + 1] = { folder = "items", id = id, class = "Item", props = { item = id },
                w = img:getWidth(), h = img:getHeight(), draw = function() love.graphics.draw(img, 0, 0) end }
        end
    end
    for _, kind in ipairs(sortedKeys(g.mobs)) do
        local def = g.mobs[kind].sprite and g.sprites[g.mobs[kind].sprite]
        local w, h, draw = nil, nil, nil
        if def then
            w, h, draw = spritePicture(def)
        end
        if draw then
            list[#list + 1] = { folder = "mobs", id = kind, class = "Mob", props = { mob = kind }, w = w, h = h, draw = draw }
        end
    end
    for _, name in ipairs(sortedKeys(g.sprites)) do
        local def = g.sprites[name]
        -- characters: sprites that can stand and walk (not effects)
        if type(def) == "table" and def.animations and def.animations.idle and def.animations.walk
            and not M.NOT_NPC[name] then
            local w, h, draw = spritePicture(def)
            if draw then
                list[#list + 1] = { folder = "npcs", id = name, class = "NPC", props = { sprite = name }, w = w, h = h, draw = draw }
            end
        end
    end
    return list
end

-- templates without pictures: spawns, exits, zones (and generic item / mob / NPC)
M.OBJECTS = {
    { file = "spawn_player", name = "player", class = "Spawn", point = true },
    { file = "spawn", name = "spawn", class = "Spawn", point = true },
    { file = "exit", name = "exit", class = "Trigger", w = 32, h = 32, props = { go = "menu", transition = "iris" } },
    { file = "zone", class = "Trigger", w = 32, h = 32 },
    { file = "look", name = "look", class = "Trigger", w = 32, h = 32,
        props = { interact = true, prompt = "Осмотреть", dialogue = "Гриша: Интересно..." } },
    { file = "dialogue_once", class = "Trigger", w = 64, h = 64, props = { once = true, dialogue = "Гриша: Где это я?" } },
    { file = "item", class = "Item", point = true, props = { item = "carrot" } },
    { file = "mob", class = "Mob", point = true, props = { mob = "slime" } },
    { file = "npc", name = "npc", class = "NPC", point = true, props = { sprite = "grisha", dialogue = "Привет!" } },
    { file = "gate", class = "Gate", w = 16, h = 48 },
}

function M.export()
    local g = G()
    ENUMS = {}
    local types, id = {}, 0
    for _, e in ipairs(M.enums()) do
        id = id + 1
        ENUMS[e[1]] = true
        types[#types + 1] = { id = id, name = e[1], type = "enum", storageType = "string",
            values = e[2], valuesAsFlags = false }
    end
    for _, c in ipairs(M.CLASSES) do
        id = id + 1
        local members = {}
        for _, mem in ipairs(c[4]) do
            local entry = { name = mem[1], type = mem[2], value = mem[3] }
            if ENUMS[mem[2]] then
                entry.type, entry.propertyType = "string", mem[2]
            end
            members[#members + 1] = entry
        end
        types[#types + 1] = { id = id, name = c[1], type = "class", useAs = c[2],
            color = c[3] or "#ffa0a0a4", drawFill = true, members = members }
    end
    local project = {
        automappingRulesFile = "", extensionsPath = "extensions", compatibilityVersion = 1100,
        folders = { ".", "../tiles" }, properties = {}, propertyTypes = types,
        commands = { {
            name = "Играть карту (LÖVE)", command = "love", arguments = '. "--map=%mapfile"',
            workingDirectory = "%projectpath/../..", shortcut = "F5",
            showOutput = true, saveBeforeExecute = true, enabled = true,
        } },
    }
    write(PROJECT, json(project) .. "\n")

    -- pictures + templates with them
    local entries = previewEntries()
    local cols = 16
    local rows = math.max(1, math.ceil(#entries / cols))
    local canvas = love.graphics.newCanvas(cols * CELL, rows * CELL)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setCanvas()
    local written = {}
    local count = 0
    for i, e in ipairs(entries) do
        local cx, cy = ((i - 1) % cols) * CELL, math.floor((i - 1) / cols) * CELL
        if fitInto(canvas, cx, cy, e.w, e.h, e.draw) then -- (empty pictures are skipped)
            local file = TEMPLATES .. e.folder .. "/" .. e.id .. ".tx"
            write(file, templateXML({ name = e.id, class = e.class, props = e.props, tile = i - 1 }, "../previews.tsx"))
            written[file] = true
            count = count + 1
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    write(TEMPLATES .. "previews.png", canvas:newImageData():encode("png"):getString())
    write(TEMPLATES .. "previews.tsx", table.concat({
        '<?xml version="1.0" encoding="UTF-8"?>',
        string.format('<tileset version="1.10" tiledversion="1.11.0" name="previews" tilewidth="%d" tileheight="%d" tilecount="%d" columns="%d">',
            CELL, CELL, cols * rows, cols),
        string.format(' <image source="previews.png" width="%d" height="%d"/>', cols * CELL, rows * CELL),
        "</tileset>", "",
    }, "\n"))
    for _, t in ipairs(M.OBJECTS) do
        local file = TEMPLATES .. "objects/" .. t.file .. ".tx"
        write(file, templateXML(t))
        written[file] = true
    end
    -- forget templates of things that are gone
    for _, folder in ipairs({ "items", "mobs", "npcs", "objects" }) do
        for _, name in ipairs(love.filesystem.getDirectoryItems(TEMPLATES .. folder)) do
            local file = TEMPLATES .. folder .. "/" .. name
            if name:match("%.tx$") and not written[file] then
                os.remove(sourcePath(file))
            end
        end
    end
    print(string.format("tiled: %s, %d templates with pictures, %d object templates",
        PROJECT, count, #M.OBJECTS))
end

-- love . --map=path -------------------------------------------------------------------

-- an absolute path from Tiled (%mapfile) -> path inside the game folder
function M.gamePath(path)
    path = path:gsub("\\", "/")
    local root = (love.filesystem.getSource() or ""):gsub("\\", "/")
    if root ~= "" and path:sub(1, #root + 1) == root .. "/" then
        return path:sub(#root + 2)
    end
    return path:match("(assets/.+)$") or path
end

-- the kind of gameplay for a map: its Class, else a guess by the look of the map
function M.kindOf(map)
    local g = G()
    if map.class and g.modes[map.class] then
        return map.class
    end
    local p = map.properties or {}
    if p.kind and g.modes[p.kind] then
        return p.kind
    end
    if map.orientation == "isometric" then
        return "iso"
    end
    for _, layer in ipairs(map.layers or {}) do
        if layer.type == "tilelayer" and layer.name == "Walls" then
            return "raycaster"
        end
    end
    return (map.tilewidth or 32) <= 16 and "platformer" or "topdown"
end

-- a stage for that map (named "__map"), returns its name
function M.mapStage(path)
    local g = G()
    path = M.gamePath(path)
    local map = require("engine").tiled.load(path)
    g.stage("__map") { kind = M.kindOf(map), map = path }
    return "__map"
end

-- command line: --tiled (export and quit) or --map=...; returns the stage to start or nil
function M.command(args)
    for _, a in ipairs(args or {}) do
        if a == "--tiled" then
            M.export()
            love.event.quit()
            return false
        end
    end
    for _, a in ipairs(args or {}) do
        local path = a:match("^%-%-map=(.+)$")
        if path then
            return M.mapStage(path)
        end
    end
    return nil
end

return M
