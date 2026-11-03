-- Sprite sheets of the game. Every entry is an animation description for
-- engine/anim.lua; mobs, pets, characters and story.lua refer to them by name:
--
--   game.sprites.cat = game.sheet("assets/sprites/cat.png", 32, 32, {
--       idle = { "1-4", 1, 0.2 },          -- columns, row, seconds per frame
--       walk = { "1-6", 2, 0.1 },
--   })
--
-- Directional sprites use sub-animations (walk.left, walk.right, ...).
-- facesLeft = true when the art looks to the left (it is mirrored for "right").

local HERO_TD = "assets/sprites/td_hero.png"                      -- user's hero
local PET = "assets/sprites/td_pet.png"                           -- user's bunny
local HEROES = "assets/sprites/s_hero_friends.png"                -- GrafxKid, CC0
local CREATURES = "assets/sprites/mobs/creatures.png"             -- GrafxKid, CC0
local CREATURES_KEY = { { 157, 142, 135 }, { 145, 112, 92 } }      -- sheet colors -> transparent
local PLATFORMER = "assets/sprites/platformer/arcade_platformer.png" -- GrafxKid, CC0

-- GrafxKid "Various Creatures": one creature per row, 5 frames (columns 3-7)
local function creature(row, opts)
    opts = opts or {}
    return {
        image = CREATURES, colorKey = CREATURES_KEY, frame = { 32, 32 }, origin = { 16, 31 },
        scale = opts.scale or 2, facesLeft = opts.facesLeft, default = "idle",
        animations = {
            idle = { "3-6", row, 0.16 },
            walk = { "3-7", row, 0.12 },
            attack = { "5-6", row, 0.12 },
            hurt = { 7, row, 0.2 },
        },
    }
end

-- 16x16 enemy of the arcade platformer sheet: frames in one row
local function arcade(cols, row, opts)
    opts = opts or {}
    return {
        image = PLATFORMER, frame = { opts.w or 16, opts.h or 16 }, origin = opts.origin or { 8, 16 },
        scale = opts.scale or 1, facesLeft = opts.facesLeft, default = "idle",
        animations = {
            idle = { cols, row, opts.speed or 0.15 },
            walk = { cols, row, opts.speed or 0.12 },
            hurt = { opts.hurt or cols, row, 0.2 },
        },
    }
end

-- Isometric characters (kind = "iso"): rows for SE and NE, mirrored for SW and NW.
-- "Tiny Tactics - Battle Kit I" by tiopalada (CC0): 4 columns x 9 rows of 32x32
-- (see tools/build_iso_assets.py)
local function tinyTactics(name)
    return {
        image = "assets/sprites/iso/" .. name .. ".png", frame = { 32, 32 }, origin = { 16, 27 }, default = "idle.se",
        animations = {
            idle = { se = { "1-4", 1, 0.2 }, ne = { "1-4", 4, 0.2 } },
            walk = { se = { "1-4", 2, 0.11 }, ne = { "1-4", 5, 0.11 } },
            attack = { se = { "1-4", 3, 0.06, "pauseAtEnd" }, ne = { "1-4", 6, 0.06, "pauseAtEnd" } },
            charge = { se = { 1, 7, 1 }, ne = { 2, 8, 1 } },
            hurt = { se = { 2, 7, 1 }, ne = { 3, 8, 1 } },
            dead = { se = { 3, 7, 1 }, ne = { 4, 8, 1 } },
            release = { se = { 4, 7, 1 }, ne = { 1, 9, 1 } },
            weak = { se = { 1, 8, 1 }, ne = { 2, 9, 1 } },
        },
    }
end

-- "Isometric Classic Hero" by DezrasDragons (CC0, after GrafxKid's Classic Hero):
-- 11 characters side by side, each 4 columns x 7 rows of 32x32
local function classicHero(index)
    return {
        image = "assets/sprites/iso/classic_heroes.png", frame = { 32, 32 }, left = index * 128,
        origin = { 17, 31 }, default = "idle.se",
        animations = {
            idle = { se = { "1-4", 1, 0.2 }, ne = { "1-4", 4, 0.2 } },
            walk = { se = { "1-4", 2, 0.11 }, ne = { "1-4", 5, 0.11 } },
            attack = { se = { "1-3", 3, 0.08, "pauseAtEnd" }, ne = { "1-3", 6, 0.08, "pauseAtEnd" } },
            charge = { se = { 1, 3, 1 }, ne = { 1, 6, 1 } },
            hurt = { se = { 1, 1, 1 }, ne = { 1, 4, 1 } },
        },
    }
end

return {
    -- Гриша from above (top-down modes)
    grisha = {
        image = HERO_TD, frame = { 16, 16 }, origin = { 8, 16 }, scale = 2, default = "idle.down",
        animations = {
            idle = { up = { 1, 1, 1 }, down = { 5, 1, 1 }, left = { 1, 2, 1 }, right = { 5, 2, 1 } },
            walk = {
                up = { "1-4", 1, 0.14 }, down = { "5-8", 1, 0.14 },
                left = { "1-4", 2, 0.14 }, right = { "5-8", 2, 0.14 },
            },
            hit = {
                left = { "1-2", 3, 0.09, "pauseAtEnd" }, right = { "3-4", 3, 0.09, "pauseAtEnd" },
                up = { "5-6", 3, 0.09, "pauseAtEnd" }, down = { "7-8", 3, 0.09, "pauseAtEnd" },
            },
        },
    },

    -- side view hero (platformer, battles): GrafxKid "Classic hero"
    hero_side = {
        image = HEROES, frame = { 16, 16 }, origin = { 8, 16 }, scale = 1, default = "idle",
        animations = {
            idle = { "2-5", 8, 0.18 },
            walk = { "2-4", 10, 0.1 },
            run = { "9-10", 17, 0.08 },
            jump = { 2, 13, 1 },
            fall = { 3, 13, 1 },
            hurt = { 2, 15, 1 },
            punch = { "2-5", 17, 0.06, "pauseAtEnd" },
            kick = { 12, 17, 0.2 },
            push = { "2-4", 19, 0.14 },
        },
    },

    -- the bunny: rows right / up / down / left / sitting
    bunny = {
        image = PET, frame = { 128, 128 }, origin = { 64, 118 }, scale = 0.4, default = "idle.down",
        animations = {
            walk = { right = { "1-3", 1, 0.12 }, up = { "1-3", 2, 0.12 }, down = { "1-3", 3, 0.12 }, left = { "1-3", 4, 0.12 } },
            idle = { right = { 1, 1, 1 }, up = { 1, 2, 1 }, down = { 1, 3, 1 }, left = { 1, 4, 1 } },
            sit = { "1-3", 5, 0.3, "pauseAtEnd" },
        },
    },

    -- blobs (top-down and side view at once)
    blob_red = {
        image = HEROES, frame = { 16, 16 }, origin = { 8, 16 }, scale = 2, facesLeft = true, default = "idle",
        animations = {
            idle = { "7-8", 8, 0.35 }, walk = { "7-12", 10, 0.09 }, jump = { "6-7", 13, 0.2 },
            attack = { 11, 13, 0.3 }, hurt = { 6, 15, 0.2 }, dead = { 9, 15, 1 },
        },
    },
    blob_blue = {
        image = HEROES, frame = { 16, 16 }, origin = { 8, 16 }, scale = 2, facesLeft = true, default = "idle",
        animations = {
            idle = { "10-11", 8, 0.35 }, walk = { "7-12", 11, 0.1 }, jump = { "8-9", 13, 0.2 },
            attack = { 12, 13, 0.3 }, hurt = { 7, 15, 0.2 }, dead = { 9, 15, 1 },
        },
    },

    -- GrafxKid "Various Creatures"
    radish = creature(2), crab = creature(3, { facesLeft = true }), balloon = creature(4),
    frog = creature(5), slime = creature(6), owl = creature(7), beetle = creature(8),
    robot = creature(9), ghost = creature(10),

    -- GrafxKid "Arcade Platformer Assets" (16x16, scale 1 in the platformer)
    ghost_blue = arcade("7-9", 1),
    pumpkin = arcade("10-13", 1),
    saw = { image = PLATFORMER, frame = { 16, 16 }, origin = { 8, 16 }, default = "idle",
        animations = { idle = { 13, "2-3", 0.08 }, walk = { 13, "2-3", 0.08 }, hurt = { 13, 2, 0.2 } } },
    radish_white = { image = PLATFORMER, frame = { 16, 32 }, top = 16, origin = { 8, 32 }, default = "idle",
        animations = { idle = { "7-9", 1, 0.2 }, walk = { "7-9", 1, 0.14 }, hurt = { 9, 1, 0.2 } } },
    pillar = { image = PLATFORMER, frame = { 16, 32 }, top = 16, origin = { 8, 32 }, default = "idle",
        animations = { idle = { "10-12", 1, 0.2 }, walk = { "10-12", 1, 0.14 }, hurt = { 12, 1, 0.2 } } },
    crab_purple = { image = PLATFORMER, frame = { 32, 16 }, left = 16, origin = { 16, 16 }, default = "idle",
        animations = { idle = { "4-6", 7, 0.15 }, walk = { "4-6", 7, 0.12 }, hurt = { 6, 7, 0.2 } } },
    snail = arcade("12-13", 6, { speed = 0.3, facesLeft = true }),
    soldier = arcade("5-7", 6),
    ninja = arcade("10-12", 4),
    beet = arcade("10-12", 5),
    coin = arcade("5-8", 8, { speed = 0.1 }),
    sparkle = arcade("9-12", 8, { speed = 0.08 }),
    puff = arcade("1-5", 9, { speed = 0.06 }),

    -- isometric mode
    iso_hero = tinyTactics("fighter"),
    iso_mage = tinyTactics("mage"),
    iso_cleric = tinyTactics("cleric"),
    iso_bald = classicHero(0), iso_ninja = classicHero(1), iso_knight = classicHero(2),
    iso_viking = classicHero(3), iso_adventurer = classicHero(4), iso_hood = classicHero(5),
    iso_pirate = classicHero(6), iso_samurai = classicHero(7), iso_spearman = classicHero(8),
    iso_gunner = classicHero(9), iso_spartan = classicHero(10),
}
