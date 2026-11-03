-- Backgrounds by name: novel scenes (s:bg("forest")), battles, the title
-- screen, puzzles and the platformer sky. See engine/background.lua for the
-- layer fields (scale, y, speed, parallax, shader...).
-- Art: ansimuz (mountains, forest, cliffs), GrafxKid (hills) - see CREDITS.md.

local M = "assets/sprites/bg/mountains/"
local F = "assets/sprites/bg/forest/"
local C = "assets/sprites/bg/cliffs/"
local P = "assets/sprites/platformer/"

return {
    mountains = {
        color = { 0.16, 0.12, 0.2 },
        layers = {
            { image = M .. "bg.png", scale = 4, y = -70 },
            { image = M .. "mountain-far.png", scale = 4, y = -70, speed = 2, parallax = 0.05 },
            { image = M .. "mountains.png", scale = 4, y = -70, speed = 5, parallax = 0.1 },
            { image = M .. "trees.png", scale = 4, y = -70, speed = 10, parallax = 0.2 },
            { image = M .. "foreground-trees.png", scale = 4, y = -70, speed = 18, parallax = 0.35, shader = "sway", sway = 1 },
        },
    },
    forest = {
        color = { 0.1, 0.16, 0.12 },
        layers = {
            { image = F .. "back-trees.png", scale = 4, y = -80, speed = 2, parallax = 0.05 },
            { image = F .. "lights.png", scale = 4, y = -80, speed = 4, blend = "add", alpha = 0.7 },
            { image = F .. "middle-trees.png", scale = 4, y = -80, speed = 6, parallax = 0.15, shader = "sway", sway = 0.6 },
            { image = F .. "front-trees.png", scale = 4, y = -80, speed = 10, parallax = 0.3, shader = "sway", sway = 1 },
        },
    },
    cliffs = {
        color = { 0.36, 0.6, 0.78 },
        layers = {
            { image = C .. "sky.png", scale = 2, y = -268 },
            { image = C .. "clouds.png", scale = 2, y = -110, speed = 6, parallax = 0.05 },
            { image = C .. "sea.png", scale = 2, y = 340, tileY = true, shader = "water", parallax = 0.1 },
            { image = C .. "far-grounds.png", scale = 2, y = 420, speed = 3, parallax = 0.2 },
        },
    },
    -- GrafxKid "Arcade Platformer Assets": a sky with hills (160x128)
    hills = {
        color = { 71 / 255, 130 / 255, 183 / 255 },
        layers = {
            { image = P .. "bg_hills.png", scale = 4, y = 28, speed = 4, parallax = 0.15,
                fill = { 63 / 255, 143 / 255, 110 / 255 } },
        },
    },
    snowy = {
        color = { 74 / 255, 114 / 255, 180 / 255 },
        layers = {
            { image = P .. "bg_mountains.png", scale = 4, y = 28, speed = 4, parallax = 0.15,
                fill = { 116 / 255, 137 / 255, 145 / 255 } },
        },
    },
    black = { color = { 0, 0, 0 }, layers = {} },
    night = { color = { 0.05, 0.05, 0.1 }, layers = {} },
}
