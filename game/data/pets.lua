-- Followers: creatures that walk behind the hero (top-down and platformer)
-- and fight next to him in battles. Add one with s:addPet("bunny").
--
--   sprite     name from game/data/sprites.lua; needs "walk" (with left/right/up/down
--              or without directions) and "idle"
--   scale      size in the top-down world and battles (default: the sprite's own)
--   sideScale  size in side view (platformer), default 1
--   steps      footstep sound folder (assets/audio/steps)
--   battle     stats + skills for the turn-based battle
--   unit       stats for the tactics battle (see game/data/units.lua)

return {
    bunny = {
        name = "Кроль", sprite = "bunny", steps = "paws", character = "bunny", sideScale = 0.11,
        snore = true,
        battle = { hp = 24, attack = 5, defense = 1, speed = 7, skills = { "bite", "heal", "defend" } },
        unit = "bunnies",
    },
    slime = {
        name = "Слизик", sprite = "slime", steps = "paws", scale = 1.5, sideScale = 0.9,
        battle = { hp = 18, attack = 4, defense = 2, speed = 4, skills = { "bite", "defend" } },
        unit = "slimes",
    },
    ghost = {
        name = "Призрачок", sprite = "ghost", scale = 1.5, sideScale = 0.8, flying = true,
        battle = { hp = 14, attack = 6, defense = 0, speed = 8, skills = { "attack", "heal" } },
        unit = "ghosts",
    },
}
