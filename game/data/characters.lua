-- Who speaks in dialogues: s:say("bunny", "...").
--   name      shown on the name plate
--   color     color of the name ({ r, g, b } or "#rrggbb")
--   voice     synthesized voice (engine/voice.lua): "male" "female" "kid" "old" "monster"
--             "alien" "robot" "ghost" "animal" "narrator" "beep", or a table:
--             { preset = "male", pitch = 95, spread = 3 } (pitch in Hz); a number = old click sound
--   speed     letters per second (default 45)
--   portrait  small picture in the dialogue box: { image, x, y, w, h, scale }
--             (x, y, w, h = a frame of a sprite sheet; without them the whole image)
--   figure    big picture for the visual novel (same format)

local HERO = "assets/sprites/td_hero.png"
local PET = "assets/sprites/td_pet.png"
local BLOBS = "assets/sprites/s_hero_friends.png"
local CREATURES = "assets/sprites/mobs/creatures.png"
local CREATURES_KEY = { { 157, 142, 135 }, { 145, 112, 92 } }

return {
    grisha = {
        name = "Гриша", color = { 0.2, 0.34, 0.68 }, voice = { preset = "male", pitch = 150 },
        portrait = { image = HERO, x = 64, y = 0, w = 16, h = 16, scale = 6 },
        figure = { image = HERO, x = 64, y = 0, w = 16, h = 16, scale = 18 },
    },
    bunny = {
        name = "Кашка", color = { 0.66, 0.24, 0.4 }, voice = "animal",
        portrait = { image = PET, x = 0, y = 512, w = 128, h = 128, scale = 0.8 },
        figure = { image = PET, x = 0, y = 512, w = 128, h = 128, scale = 2.6 },
    },
    blob = {
        name = "Слизень", color = { 0.7, 0.18, 0.15 }, voice = "monster",
        portrait = { image = BLOBS, x = 96, y = 112, w = 16, h = 16, scale = 6 },
        figure = { image = BLOBS, x = 96, y = 112, w = 16, h = 16, scale = 16 },
    },
    ghost = {
        name = "Призрак", color = { 0.45, 0.45, 0.6 }, voice = "ghost",
        portrait = { image = CREATURES, colorKey = CREATURES_KEY, x = 64, y = 288, w = 32, h = 32, scale = 3 },
        figure = { image = CREATURES, colorKey = CREATURES_KEY, x = 64, y = 288, w = 32, h = 32, scale = 9 },
    },
    voice = { name = "Голос", color = { 0.42, 0.28, 0.6 }, voice = "alien" },
    sign = { name = "Табличка", color = { 0.45, 0.32, 0.18 }, voice = "beep" },
}
