-- Grounds of the 3D world map (stage kind "world", see game/modes/world.lua).
-- Every tile of assets/maps/world.tsx has the property ground = one of the types below,
-- so the map is painted in Tiled with these tiles (the palette: assets/sprites/world/grounds.png).
--
-- textures   the pictures of the ground (max 8, cut from OGA tilesets, see CREDITS.md):
--   image, rect = { x, y, w, h } in the image, rep = world units per picture (1 unit = 1 tile),
--   gray = 0..1 how much of the colour becomes grey, tint = { r, g, b } after that
-- water      the sea: texture, rep, colours of the open sea and of the shallows
-- types      ground -> how it looks and plays:
--   height    height of the land (world units; the sea surface is 0)
--   rough     how hilly (random height at every vertex, the same on every run)
--   texture   a name from textures (the sea floor too)
--   tint      colour of the ground ({ r, g, b }, darker forest)
--   speed     walking speed (1 = normal), solid = true: nobody walks there (mountains)
--   trees     trees per tile (0..1), encounter = group of the stage's encounters (or none)
--   water     the sea: only the boat sails there
-- On steep slopes the ground turns into "rock", high up into "snow" (rockSlope, snowLine).

local SHEET = "assets/sprites/ground_tiles.png"      -- Whispers of Avalon (Leonard Pabin)
local PATHS = "assets/sprites/PathAndObjects.png"   -- Zabin: cobble stone paths

return {
    textures = {
        { name = "grass", image = PATHS, rect = { 32, 352, 32, 32 }, rep = 1 },
        { name = "meadow", image = SHEET, rect = { 32, 64, 64, 64 }, rep = 2 },
        { name = "sand", image = SHEET, rect = { 32, 160, 96, 96 }, rep = 3 },
        { name = "rock", image = SHEET, rect = { 32, 288, 64, 64 }, rep = 2, gray = 0.85, tint = { 0.86, 0.8, 0.74 } },
        { name = "snow", image = SHEET, rect = { 160, 608, 64, 64 }, rep = 2, gray = 1, tint = { 1.08, 1.12, 1.2 } },
        { name = "dirt", image = PATHS, rect = { 224, 32, 32, 32 }, rep = 1 },
        { name = "cobble", image = PATHS, rect = { 32, 32, 32, 32 }, rep = 1 },
        { name = "stones", image = SHEET, rect = { 32, 416, 64, 64 }, rep = 2 },
    },
    water = {
        image = "assets/models/kenney/Textures/water.png", rep = 2,
        deep = { 0.12, 0.3, 0.55 }, shallow = { 0.3, 0.62, 0.68 },
    },
    rockSlope = 0.9,  -- height difference to a neighbour vertex that makes rock
    snowLine = 3.3,   -- above it: snow
    types = {
        deep = { height = -2.6, texture = "sand", water = true, tint = { 0.5, 0.55, 0.6 } },
        sea = { height = -1.3, texture = "sand", water = true, tint = { 0.7, 0.75, 0.75 } },
        shallow = { height = -0.35, texture = "sand", water = true },
        beach = { height = 0.14, rough = 0.05, texture = "sand" },
        grass = { height = 0.32, rough = 0.18, texture = "grass", encounter = "plains" },
        meadow = { height = 0.3, rough = 0.12, texture = "meadow", encounter = "plains" },
        forest = { height = 0.42, rough = 0.22, texture = "grass", tint = { 0.72, 0.84, 0.7 },
            trees = 0.55, speed = 0.85, encounter = "forest" },
        hills = { height = 1.05, rough = 0.6, texture = "grass", tint = { 1.04, 1.0, 0.84 },
            speed = 0.75, encounter = "hills" },
        mountain = { height = 2.8, rough = 2.0, texture = "rock", solid = true },
        peak = { height = 4.4, rough = 1.4, texture = "snow", solid = true },
        road = { height = 0.3, rough = 0.04, texture = "dirt", speed = 1.15 },
        town = { height = 0.3, texture = "cobble", speed = 1.1 },
        desert = { height = 0.34, rough = 0.3, texture = "sand", tint = { 1.04, 0.95, 0.8 }, encounter = "desert" },
        snowfield = { height = 0.5, rough = 0.3, texture = "snow", encounter = "snow" },
        rocks = { height = 0.6, rough = 0.45, texture = "stones", speed = 0.9, encounter = "hills" },
    },
}
