-- Followers: creatures that walk behind the hero (top-down and platformer)
-- and fight next to him in battles. Add one with s:addPet("bunny").
--
--   sprite     name from game/data/sprites.lua; needs "walk" (with left/right/up/down
--              or without directions) and "idle"
--   scale      size in the top-down world and battles (default: the sprite's own)
--   sideScale  size in side view (platformer), default 1
--   worldSprite  sprite on the 3D world map (default: sprite), worldScale = its size
--   steps      footstep sound folder (assets/audio/steps)
--   battle     stats + skills for the turn-based battle
--   unit       stats for the tactics battle (see game/data/units.lua)

return {
    bunny = {
        name = "Кашка", sprite = "bunny", worldSprite = "bunny_world", worldScale = 0.8, steps = "paws", character = "bunny", sideScale = 0.11, isoScale = 0.14,
        snore = true,
        battle = { hp = 30, attack = 6, defense = 3, speed = 8, skills = { "bite", "hop", "heal", "defend" },
            growth = { hp = 4, attack = 0.9, defense = 0.5, speed = 0.2 } },
        unit = "kashka",
    },
    slime = {
        name = "Слизик", sprite = "slime", steps = "paws", scale = 1.5, sideScale = 0.9,
        battle = { hp = 26, attack = 5, defense = 4, speed = 5, skills = { "bite", "defend" } },
        unit = "slimes",
    },
    ghost = {
        name = "Призрачок", sprite = "ghost", scale = 1.5, sideScale = 0.8, flying = true,
        battle = { hp = 20, attack = 7, defense = 1, speed = 9, skills = { "bite", "heal" } },
        unit = "ghosts",
    },
}
