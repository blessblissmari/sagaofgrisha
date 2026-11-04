-- Buildings of the 3D world map (game/modes/world.lua): groups of 3D models.
-- The Tiled map uses them by name: objects in the layers Places and Props have the
-- property prefab = "castle" (and rot = degrees).
--
--   name = {
--       scale = 0.8,     -- size of the whole group (the Kenney pieces are 1 x 1 x 1)
--       radius = 1.6,    -- nobody walks closer to the centre (world units, after scale)
--       parts = {        -- { model, x, z, y = 0, rot = radians, scale = 1, tint = { r, g, b } }
--           { "kenney/tower-base", -1.5, -1.5 },
--       },
--   }
-- model = a file in assets/models without ".obj" (OBJ + MTL, textures next to them).
-- Models: Kenney "Retro Medieval Kit" (CC0), "PSX Medieval House" by _Creature_ (CC0).

local HOUSE = "psx/medieval_house"
local HOUSE_TEX = "assets/models/psx/houseTexture.png"

local function house(x, z, rot, scale)
    return { HOUSE, x, z, rot = rot, scale = scale or 0.16, texture = HOUSE_TEX, center = true }
end

-- a tower: base, n middle pieces, the top with the battlements
local function tower(x, z, n, paint, list, scale)
    list = list or {}
    local s = scale or 1
    local base = paint and "kenney/tower-paint-base" or "kenney/tower-base"
    local mid = paint and "kenney/tower-paint" or "kenney/tower"
    table.insert(list, { base, x, z, scale = s })
    for i = 1, n do
        table.insert(list, { mid, x, z, y = i * s, scale = s })
    end
    table.insert(list, { "kenney/tower-top", x, z, y = (n + 1) * s, scale = s })
    return list
end

local function add(list, more)
    for _, p in ipairs(more) do
        table.insert(list, p)
    end
    return list
end

-- the castle: four corner towers, thick walls, a gate to the south, the keep
local function castle()
    local parts = {}
    for _, c in ipairs({ { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } }) do
        tower(c[1], c[2], 1, false, parts)
    end
    for i = -1, 1 do
        table.insert(parts, { "kenney/wall-fortified", i, -1.5 })
        table.insert(parts, { "kenney/wall-fortified", -1.5, i, rot = math.pi / 2 })
        table.insert(parts, { "kenney/wall-fortified", 1.5, i, rot = math.pi / 2 })
        table.insert(parts, { i == 0 and "kenney/wall-fortified-gate" or "kenney/wall-fortified", i, 1.5 })
    end
    tower(0, -0.3, 2, true, parts, 1.1)
    return parts
end

-- a fence around a w x d yard
local function fence(w, d)
    local parts = {}
    for i = 0, w - 1 do
        local x = i - (w - 1) / 2
        table.insert(parts, { "kenney/fence", x, -d / 2 })
        if math.abs(x) > 0.6 then
            table.insert(parts, { "kenney/fence", x, d / 2 })
        end
    end
    for i = 0, d - 1 do
        local z = i - (d - 1) / 2
        table.insert(parts, { "kenney/fence", -w / 2, z, rot = math.pi / 2 })
        table.insert(parts, { "kenney/fence", w / 2, z, rot = math.pi / 2 })
    end
    return parts
end

return {
    -- Гришина хижина на острове
    hut = {
        radius = 0.85,
        parts = {
            house(0, 0, math.pi + 0.35, 0.2),
            { "kenney/barrels", 0.75, 0.45, rot = 0.4, scale = 0.8 },
            { "kenney/detail-crate", -0.7, 0.55, rot = 0.2, scale = 1.2 },
        },
    },

    -- деревня Морковкино: дома вокруг площади
    village = {
        radius = 0.9,
        parts = {
            house(-1.0, -0.7, 0.5),
            house(1.05, -0.8, -0.45),
            house(-0.15, -1.45, 0.05, 0.18),
            house(1.5, 0.75, -1.3, 0.14),
            { "kenney/barrels", 0.35, 0.2, rot = 0.3, scale = 0.8 },
            { "kenney/detail-crate", -0.45, 0.35, scale = 1.2 },
            { "kenney/detail-crate-ropes", -0.6, 0.6, rot = 0.6, scale = 1.2 },
            { "kenney/tree-large", -1.7, 0.4, scale = 0.8 },
            { "kenney/tree-large", 1.8, -1.6, scale = 0.7 },
            { "kenney/fence", -1.4, 1.0, rot = 0.2, scale = 0.7 },
            { "kenney/fence", -0.8, 1.15, rot = 0.1, scale = 0.7 },
        },
    },

    -- ферма у луга: дом, загон, бочки
    farm = {
        radius = 0.6,
        parts = add({
            house(-0.2, -0.7, 0.15, 0.15),
            { "kenney/barrels", 0.7, -0.5, scale = 0.8 },
            { "kenney/detail-barrel", 0.9, -0.2, scale = 1.2 },
            { "kenney/tree-large", -1.2, -1.0, scale = 0.8 },
            { "kenney/structure", 1.25, 0.9, scale = 0.6 },
        }, (function()
            local f = fence(3, 2)
            for _, p in ipairs(f) do
                p[2], p[3] = p[2] * 0.7 + 0.4, p[3] * 0.7 + 0.9
                p.scale = 0.7
            end
            return f
        end)()),
    },

    -- замок Короля Слизней у подножия гор
    castle = { scale = 0.8, radius = 1.65, parts = castle() },

    -- башня в западном лесу
    tower = {
        scale = 0.7, radius = 0.5,
        parts = add(tower(0, 0, 2, false), {
            { "kenney/detail-crate", 0.75, 0.4 },
            { "kenney/detail-barrel", 0.6, 0.75 },
        }),
    },

    -- шахта в горах: ворота, леса, ящики
    mine = {
        scale = 0.7, radius = 0.7,
        parts = {
            { "kenney/wall-fortified-gate", 0, -0.2 },
            { "kenney/wall-fortified", -1, -0.2 },
            { "kenney/wall-fortified", 1, -0.2 },
            { "kenney/structure", 1.1, 0.9 },
            { "kenney/pulley-crate", 1.1, 1.15, y = 0.95, rot = math.pi },
            { "kenney/detail-crate", -0.8, 0.8, rot = 0.3 },
            { "kenney/detail-crate-ropes", -0.55, 1.0 },
            { "kenney/detail-barrel", -1.0, 1.1 },
            { "kenney/ladder", 1.6, 0.45, rot = -math.pi / 2 },
        },
    },

    -- древние руины в пустыне
    ruins = {
        scale = 0.9, radius = 0.6,
        parts = {
            { "kenney/floor", 0, 0, scale = 1.6 },
            { "kenney/column-damaged", -0.9, -0.9 },
            { "kenney/column", 0.9, -0.9 },
            { "kenney/column-paint-damaged", -0.9, 0.9 },
            { "kenney/column-damaged", 0.9, 0.9, rot = 1.3 },
            { "kenney/column", 0, -1.2, scale = 1.2 },
            { "kenney/bricks", 0.3, 0.3, rot = 0.5, scale = 1.4 },
            { "kenney/bricks", -0.4, 1.3, rot = 2.1, scale = 1.2 },
            { "kenney/stairs-stone", 0, 1.3, rot = math.pi, scale = 0.6 },
        },
    },

    -- маяк на северо-восточном острове
    lighthouse = {
        scale = 0.6, radius = 0.45,
        parts = add(tower(0, 0, 3, true), {
            { "kenney/detail-barrel", 0.8, 0.5 },
            { "kenney/detail-crate", 0.65, 0.85 },
        }),
        light = 4.6, -- the light at the top (height in pieces)
    },

    -- причал (rot: куда он смотрит в море); deck = где по нему можно ходить
    -- { x0, z0, x1, z1, y = высота настила } в долях деталей (до scale)
    dock = {
        scale = 0.6,
        deck = { -0.5, -2.55, 0.5, 0.5, y = 0.2 },
        parts = {
            { "kenney/dock-side", 0, 0, y = -0.3 },
            { "kenney/dock-side", 0, -1, y = -0.3 },
            { "kenney/dock-corner", 0, -2, y = -0.3 },
        },
    },

    bigtree = { radius = 0.3, parts = { { "kenney/tree-large", 0, 0, scale = 1.6 } } },
    rocks = {
        radius = 0.4,
        parts = {
            { "kenney/bricks", 0, 0, scale = 2.2 },
            { "kenney/bricks", 0.5, 0.3, rot = 1.7, scale = 1.8 },
            { "kenney/column-damaged", -0.4, 0.2, rot = 0.8 },
        },
    },
    columns = {
        radius = 0.3,
        parts = {
            { "kenney/column-damaged", 0, 0 },
            { "kenney/column", 0.6, 0.2 },
            { "kenney/column-paint-damaged", -0.3, 0.6, rot = 0.7 },
        },
    },
    barrels = {
        radius = 0.25,
        parts = {
            { "kenney/barrels", 0, 0, scale = 0.9 },
            { "kenney/detail-crate", 0.45, 0.2, scale = 1.2 },
        },
    },
}
