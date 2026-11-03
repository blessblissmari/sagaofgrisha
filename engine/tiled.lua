-- Reads Tiled maps (.tmx) and tilesets (.tsx) directly, so a map saved in
-- Tiled works in the game without "Export as Lua".
--
--   local map = tiled.load("assets/maps/island.tmx")   -- table, like Tiled's Lua export
--   local sti = require("libs.sti.sti")(map)          -- STI accepts that table
--
-- Supported: orthogonal maps, CSV and Base64 layers (uncompressed, zlib, gzip),
-- external tilesets (.tsx), tile properties and animations, object layers
-- (rectangles, points, ellipses, polygons, tile objects, templates .tx),
-- image layers, group layers, typed custom properties (string, int, float,
-- bool, color, file, object, class).
-- Not supported: infinite maps and zstd compression (switch them off in Tiled).
-- Tile objects made from a template (.tx with a tile) get the gid of that tile in
-- this map. Color properties become "#rrggbb" ("#rrggbbaa" when not opaque).

local utf8 = require("utf8")

local tiled = {}

-- tiny XML parser -------------------------------------------------------------

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

local function unescape(s)
    return (s:gsub("&(#?x?)(%w+);", function(kind, code)
        if kind == "#" then
            return utf8.char(tonumber(code))
        elseif kind == "#x" then
            return utf8.char(tonumber(code, 16))
        end
        return ENTITIES[code] or ("&" .. code .. ";")
    end))
end

local function parseAttributes(s)
    local attrs = {}
    for name, quote, value in s:gmatch("([%w_:%-%.]+)%s*=%s*([\"'])(.-)%2") do
        attrs[name] = unescape(value)
    end
    return attrs
end

-- Returns the root node: { tag = "map", attrs = {...}, children = {...}, text = "..." }
local function parseXML(source)
    local root = { tag = "#root", attrs = {}, children = {} }
    local stack = { root }
    local pos = 1
    while true do
        local start, finish, close, tag, attrs, empty = source:find("<(/?)([%w_:%-%.%?!]+)(.-)(/?)>", pos)
        if not start then
            break
        end
        local text = source:sub(pos, start - 1)
        local top = stack[#stack]
        if text:find("%S") then
            top.text = (top.text or "") .. unescape(text)
        end
        if tag:sub(1, 3) == "!--" then
            -- comment: skip to its end
            local _, commentEnd = source:find("-->", start + 4, true)
            finish = commentEnd or #source
        elseif tag:sub(1, 1) == "?" or tag:sub(1, 1) == "!" then
            -- <?xml ... ?>, <!DOCTYPE ...>
        elseif close == "/" then
            table.remove(stack)
        else
            local node = { tag = tag, attrs = parseAttributes(attrs), children = {} }
            table.insert(top.children, node)
            if empty ~= "/" then
                table.insert(stack, node)
            end
        end
        pos = finish + 1
    end
    return root
end

local function child(node, tag)
    for _, c in ipairs(node.children) do
        if c.tag == tag then
            return c
        end
    end
end

local function children(node, tag)
    local list = {}
    for _, c in ipairs(node.children) do
        if not tag or c.tag == tag then
            table.insert(list, c)
        end
    end
    return list
end

-- paths --------------------------------------------------------------------------

local function directory(path)
    return path:match("^(.*/)") or ""
end

-- "assets/maps/../sprites/a.png" -> "assets/sprites/a.png"
function tiled.normalize(path)
    local parts = {}
    for part in path:gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
            table.remove(parts)
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    return table.concat(parts, "/")
end

local function resolve(dir, file)
    if not file or file == "" then
        return file
    end
    return tiled.normalize(dir .. file)
end

local function readFile(path)
    local data, err = love.filesystem.read(path)
    if not data then
        error("tiled: can't read '" .. tostring(path) .. "': " .. tostring(err), 0)
    end
    return data
end

-- values ---------------------------------------------------------------------------

local function num(v, default)
    return tonumber(v) or default
end

-- "#aarrggbb" or "#rrggbb" -> { r, g, b, a } (0..255, like the Lua export)
function tiled.color(hex)
    if not hex or hex == "" then
        return nil
    end
    hex = hex:gsub("#", "")
    local a = 255
    if #hex == 8 then
        a = tonumber(hex:sub(1, 2), 16)
        hex = hex:sub(3)
    end
    return { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), a }
end

-- Tiled "#aarrggbb" -> "#rrggbb" / "#rrggbbaa" (the order of util.hexColor)
function tiled.cssColor(hex)
    if type(hex) ~= "string" or hex == "" then
        return hex
    end
    hex = hex:gsub("#", "")
    if #hex == 8 then
        local a = hex:sub(1, 2):lower()
        return "#" .. hex:sub(3) .. (a == "ff" and "" or a)
    end
    return "#" .. hex
end

local function parseProperties(node, dir)
    local result = {}
    local props = node and child(node, "properties")
    if not props then
        return result
    end
    for _, p in ipairs(children(props, "property")) do
        local a = p.attrs
        local t = a.type or "string"
        local value = a.value
        if value == nil then
            value = p.text or ""
        end
        if t == "int" or t == "float" or t == "object" then
            value = tonumber(value) or 0
        elseif t == "bool" then
            value = value == "true"
        elseif t == "color" then
            value = tiled.cssColor(value)
        elseif t == "file" then
            value = resolve(dir, value)
        elseif t == "class" then
            value = parseProperties(p, dir)
            value.__class = a.propertytype
        end
        result[a.name] = value
    end
    return result
end

-- tilesets -----------------------------------------------------------------------

local tilesetCache = {}

local function parseTileset(node, dir)
    local a = node.attrs
    local ts = {
        name = a.name or "tileset",
        class = a.class,
        tilewidth = num(a.tilewidth, 0), tileheight = num(a.tileheight, 0),
        spacing = num(a.spacing, 0), margin = num(a.margin, 0),
        tilecount = num(a.tilecount, 0), columns = num(a.columns, 0),
        objectalignment = a.objectalignment or "unspecified",
        tileoffset = { x = 0, y = 0 },
        grid = { orientation = "orthogonal", width = num(a.tilewidth, 0), height = num(a.tileheight, 0) },
        properties = parseProperties(node, dir),
        tiles = {},
    }
    local offset = child(node, "tileoffset")
    if offset then
        ts.tileoffset = { x = num(offset.attrs.x, 0), y = num(offset.attrs.y, 0) }
    end
    local image = child(node, "image")
    if image then
        ts.image = resolve(dir, image.attrs.source)
        ts.imagewidth = num(image.attrs.width, 0)
        ts.imageheight = num(image.attrs.height, 0)
        if image.attrs.trans then
            ts.transparentcolor = "#" .. image.attrs.trans:gsub("#", "")
        end
        if ts.imagewidth == 0 and love.graphics then
            local ok, img = pcall(love.graphics.newImage, ts.image)
            if ok then
                ts.imagewidth, ts.imageheight = img:getDimensions()
            end
        end
        if ts.columns == 0 and ts.tilewidth > 0 then
            ts.columns = math.floor((ts.imagewidth - ts.margin * 2 + ts.spacing) / (ts.tilewidth + ts.spacing))
        end
    end
    for _, t in ipairs(children(node, "tile")) do
        local tile = {
            id = num(t.attrs.id, 0),
            type = t.attrs.type or t.attrs.class,
            properties = parseProperties(t, dir),
        }
        local img = child(t, "image")
        if img then
            tile.image = resolve(dir, img.attrs.source)
            tile.width, tile.height = num(img.attrs.width, 0), num(img.attrs.height, 0)
        end
        local animation = child(t, "animation")
        if animation then
            tile.animation = {}
            for _, f in ipairs(children(animation, "frame")) do
                table.insert(tile.animation, { tileid = num(f.attrs.tileid, 0), duration = num(f.attrs.duration, 100) })
            end
        end
        local group = child(t, "objectgroup")
        if group then
            tile.objectGroup = { type = "objectgroup", objects = {} }
            for _, o in ipairs(children(group, "object")) do
                table.insert(tile.objectGroup.objects, tiled.parseObject(o, dir))
            end
        end
        table.insert(ts.tiles, tile)
    end
    return ts
end

local function loadTileset(path)
    if not tilesetCache[path] then
        local root = parseXML(readFile(path))
        local node = child(root, "tileset")
        assert(node, "tiled: '" .. path .. "' is not a tileset")
        tilesetCache[path] = parseTileset(node, directory(path))
    end
    return tilesetCache[path]
end

local function copyTileset(ts, firstgid)
    local copy = {}
    for k, v in pairs(ts) do
        copy[k] = v
    end
    copy.firstgid = firstgid
    return copy
end

-- objects -------------------------------------------------------------------------

-- the map being loaded: its tilesets, so tiles of templates get the map's gids
local loading = nil

local FLIPS = { 2 ^ 31, 2 ^ 30, 2 ^ 29, 2 ^ 28 }

-- gid of a template's tile -> gid of the same tile in the map being loaded
local function templateGid(gid, template, path)
    local raw, flags = tonumber(gid) or 0, 0
    for _, f in ipairs(FLIPS) do
        if raw >= f then
            raw, flags = raw - f, flags + f
        end
    end
    local source, first = nil, 1
    for _, t in ipairs(children(template, "tileset")) do
        local f = num(t.attrs.firstgid, 1)
        if raw >= f and f >= first and t.attrs.source then
            source, first = resolve(directory(path), t.attrs.source), f
        end
    end
    if not source or not loading then
        return nil
    end
    local last = nil
    for _, ts in ipairs(loading.tilesets) do
        if ts.source == source then
            return ts.firstgid + raw - first + flags
        end
        last = ts
    end
    -- the map doesn't use that tileset yet: add it at the end (as Tiled does)
    local ts = loading.addTileset(source, last and (last.firstgid + math.max(last.tilecount, 1)) or 1)
    return ts.firstgid + raw - first + flags
end

local function mergeTemplate(attrs, node, dir)
    if not attrs.template then
        return attrs, node
    end
    local path = resolve(dir, attrs.template)
    local root = parseXML(readFile(path))
    local template = child(root, "template")
    local object = template and child(template, "object")
    if not object then
        return attrs, node
    end
    local merged = {}
    for k, v in pairs(object.attrs) do
        merged[k] = v
    end
    if merged.gid then
        merged.gid = templateGid(merged.gid, template, path)
    end
    for k, v in pairs(attrs) do
        merged[k] = v
    end
    -- template properties first, the instance overrides them
    local props = parseProperties(object, directory(path))
    for k, v in pairs(parseProperties(node, dir)) do
        props[k] = v
    end
    local fakeNode = { children = {} }
    for _, c in ipairs(object.children) do
        if c.tag ~= "properties" then
            table.insert(fakeNode.children, c)
        end
    end
    for _, c in ipairs(node.children) do
        if c.tag ~= "properties" then
            table.insert(fakeNode.children, c)
        end
    end
    fakeNode.mergedProperties = props
    return merged, fakeNode
end

local function parsePoints(s)
    local points = {}
    for x, y in s:gmatch("([%-%d%.e]+),([%-%d%.e]+)") do
        table.insert(points, { x = tonumber(x), y = tonumber(y) })
    end
    return points
end

function tiled.parseObject(node, dir)
    local a, n = mergeTemplate(node.attrs, node, dir)
    local o = {
        id = num(a.id, 0),
        name = a.name or "",
        type = a.type or a.class or "",
        shape = "rectangle",
        x = num(a.x, 0), y = num(a.y, 0),
        width = num(a.width, 0), height = num(a.height, 0),
        rotation = num(a.rotation, 0),
        visible = a.visible ~= "0",
        properties = n.mergedProperties or parseProperties(n, dir),
    }
    o.class = o.type
    if a.gid then
        o.gid = num(a.gid, 0)
        o.shape = "rectangle"
    end
    if child(n, "point") then
        o.shape = "point"
    elseif child(n, "ellipse") then
        o.shape = "ellipse"
    elseif child(n, "polygon") then
        o.shape = "polygon"
        o.polygon = parsePoints(child(n, "polygon").attrs.points or "")
    elseif child(n, "polyline") then
        o.shape = "polyline"
        o.polyline = parsePoints(child(n, "polyline").attrs.points or "")
    elseif child(n, "text") then
        local t = child(n, "text")
        o.shape = "text"
        o.text = t.text or ""
    end
    return o
end

-- layers --------------------------------------------------------------------------

local function decodeData(node, width, height, path)
    local encoding = node.attrs.encoding
    local compression = node.attrs.compression
    local data = {}
    if child(node, "chunk") then
        error("tiled: '" .. path .. "' is an infinite map. Uncheck Map > Map Properties > Infinite.", 0)
    end
    if encoding == "csv" then
        for v in (node.text or ""):gmatch("%d+") do
            table.insert(data, tonumber(v))
        end
    elseif encoding == "base64" then
        local raw = love.data.decode("string", "base64", (node.text or ""):gsub("%s", ""))
        if compression == "zlib" or compression == "gzip" then
            raw = love.data.decompress("string", compression, raw)
        elseif compression and compression ~= "" then
            error("tiled: compression '" .. compression .. "' in '" .. path
                .. "' is not supported. Use CSV or Base64 (zlib) in the map properties.", 0)
        end
        for i = 1, #raw - 3, 4 do
            table.insert(data, (love.data.unpack("<I4", raw, i)))
        end
    else
        -- old XML format: <tile gid="..."/>
        for _, t in ipairs(children(node, "tile")) do
            table.insert(data, num(t.attrs.gid, 0))
        end
    end
    for i = #data + 1, width * height do
        data[i] = 0
    end
    return data
end

local function commonLayer(node, dir, kind)
    local a = node.attrs
    return {
        type = kind,
        id = num(a.id, 0),
        name = a.name or "",
        class = a.class or "",
        x = num(a.x, 0), y = num(a.y, 0),
        visible = a.visible ~= "0",
        opacity = num(a.opacity, 1),
        offsetx = num(a.offsetx, 0), offsety = num(a.offsety, 0),
        parallaxx = num(a.parallaxx, 1), parallaxy = num(a.parallaxy, 1),
        tintcolor = tiled.color(a.tintcolor),
        properties = parseProperties(node, dir),
    }
end

local function parseLayers(node, dir, path)
    local layers = {}
    for _, c in ipairs(node.children) do
        if c.tag == "layer" then
            local layer = commonLayer(c, dir, "tilelayer")
            layer.width, layer.height = num(c.attrs.width, 0), num(c.attrs.height, 0)
            layer.encoding = "lua"
            layer.data = decodeData(child(c, "data") or { attrs = {}, children = {} }, layer.width, layer.height, path)
            table.insert(layers, layer)
        elseif c.tag == "objectgroup" then
            local layer = commonLayer(c, dir, "objectgroup")
            layer.draworder = c.attrs.draworder or "topdown"
            layer.color = c.attrs.color
            layer.objects = {}
            for _, o in ipairs(children(c, "object")) do
                table.insert(layer.objects, tiled.parseObject(o, dir))
            end
            table.insert(layers, layer)
        elseif c.tag == "imagelayer" then
            local layer = commonLayer(c, dir, "imagelayer")
            local img = child(c, "image")
            layer.image = img and resolve(dir, img.attrs.source) or ""
            layer.repeatx = c.attrs.repeatx == "1"
            layer.repeaty = c.attrs.repeaty == "1"
            table.insert(layers, layer)
        elseif c.tag == "group" then
            local layer = commonLayer(c, dir, "group")
            layer.layers = parseLayers(c, dir, path)
            table.insert(layers, layer)
        end
    end
    return layers
end

-- map ------------------------------------------------------------------------------

function tiled.load(path)
    local root = parseXML(readFile(path))
    local node = child(root, "map")
    assert(node, "tiled: '" .. path .. "' is not a map")
    local dir = directory(path)
    local a = node.attrs
    if a.infinite == "1" then
        error("tiled: '" .. path .. "' is an infinite map. Uncheck Map > Map Properties > Infinite.", 0)
    end
    local map = {
        version = "1.10", luaversion = "5.1",
        tiledversion = a.tiledversion,
        class = a.class or "",
        orientation = a.orientation or "orthogonal",
        renderorder = a.renderorder or "right-down",
        width = num(a.width, 0), height = num(a.height, 0),
        tilewidth = num(a.tilewidth, 0), tileheight = num(a.tileheight, 0),
        hexsidelength = num(a.hexsidelength), staggeraxis = a.staggeraxis, staggerindex = a.staggerindex,
        nextlayerid = num(a.nextlayerid, 1), nextobjectid = num(a.nextobjectid, 1),
        backgroundcolor = tiled.color(a.backgroundcolor),
        properties = parseProperties(node, dir),
        tilesets = {},
        path = path,
    }
    local function addTileset(source, firstgid)
        local ts = copyTileset(loadTileset(source), firstgid)
        ts.source = source
        table.insert(map.tilesets, ts)
        return ts
    end
    for _, t in ipairs(children(node, "tileset")) do
        local firstgid = num(t.attrs.firstgid, 1)
        if t.attrs.source then
            addTileset(resolve(dir, t.attrs.source), firstgid)
        else
            local ts = parseTileset(t, dir)
            ts.firstgid = firstgid
            table.insert(map.tilesets, ts)
        end
    end
    loading = { tilesets = map.tilesets, addTileset = addTileset }
    local ok, layers = pcall(parseLayers, node, dir, path)
    loading = nil
    if not ok then
        error(layers, 0)
    end
    map.layers = layers
    return map
end

-- Forget cached tilesets (after editing a .tsx while the game runs).
function tiled.flush()
    tilesetCache = {}
end

tiled.parseXML = parseXML

return tiled
