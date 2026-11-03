-- Enemies for every gameplay type. One entry works everywhere:
--
--   sprite      name from game/data/sprites.lua (or a sprite table)
--   hp          health in real-time modes (top-down, platformer, raycaster)
--   damage      hearts taken from the player on contact / hit (2 = one heart)
--   speed, chaseSpeed, sight   wandering and chasing (top-down, raycaster)
--   touch       "battle": touching it starts a turn-based battle with `party`
--   ai          platformer behaviour: "walker" | "hopper" | "flyer" | "hazard"
--   stomp       platformer: can be killed by jumping on it (default true)
--   battle      stats for the turn-based battle: hp, attack, defense, speed,
--               shield (hits of a weakness to BREAK it), weak = { damage types }
--               (slash chop thrust blunt stone bite magic), skills (game/data/skills.lua),
--               ai = "aggressive" (default) | "support" | "random", evade (0..1),
--               xp, coins = { min, max }
--   drops       { item, chance } rolled when the mob dies

return {
    blob_red = {
        name = "Красный слизень", sprite = "blob_red",
        hp = 3, damage = 1, speed = 28, chaseSpeed = 62, sight = 130,
        ai = "walker", platformSpeed = 30,
        battle = { hp = 26, attack = 7, defense = 2, speed = 5, shield = 3, weak = { "chop", "stone" },
            skills = { "jab", "slam" }, xp = 14, coins = { 2, 5 } },
        drops = { { item = "coin", chance = 0.7 }, { item = "carrot", chance = 0.3 } },
        taunt = "taunt",
    },
    blob_blue = {
        name = "Синий слизень", sprite = "blob_blue",
        hp = 4, damage = 1, speed = 20, chaseSpeed = 45, sight = 110,
        touch = "battle", party = { "blob_blue", "slime", "frog" },
        ai = "hopper", platformSpeed = 40,
        battle = { hp = 34, attack = 6, defense = 3, speed = 4, shield = 4, weak = { "thrust", "blunt" },
            skills = { "jab", "mend", "guard" }, ai = "support", xp = 18, coins = { 3, 6 } },
        drops = { { item = "coin", chance = 1 } },
    },
    slime = {
        name = "Слизь", sprite = "slime", hp = 3, damage = 1, speed = 30, chaseSpeed = 50, sight = 220,
        battle = { hp = 18, attack = 5, defense = 1, speed = 7, shield = 2, weak = { "slash", "stone" },
            skills = { "double", "spit" }, xp = 10, coins = { 1, 3 } },
        drops = { { item = "coin", chance = 0.5 } },
    },
    frog = {
        name = "Робожаб", sprite = "frog", hp = 4, damage = 1, speed = 25, chaseSpeed = 45, sight = 200,
        battle = { hp = 30, attack = 8, defense = 4, speed = 4, shield = 4, weak = { "blunt", "stone" },
            skills = { "feint", "slam" }, xp = 20, coins = { 3, 7 } },
    },
    crab = {
        name = "Рак-отшельник", sprite = "crab", hp = 5, damage = 1, speed = 20, chaseSpeed = 35, sight = 150,
        battle = { hp = 32, attack = 6, defense = 7, speed = 3, shield = 5, weak = { "blunt", "chop" },
            skills = { "double", "guard" }, xp = 18, coins = { 2, 6 } },
    },
    ghost = {
        name = "Призрак", sprite = "ghost", hp = 3, damage = 1, speed = 35, chaseSpeed = 60, sight = 260,
        battle = { hp = 22, attack = 9, defense = 0, speed = 8, shield = 3, weak = { "magic", "stone" },
            evade = 0.15, skills = { "feint", "chill" }, xp = 20, coins = { 2, 5 } },
        drops = { { item = "potion", chance = 0.2 } },
    },
    beetle = {
        name = "Жук", sprite = "beetle", hp = 4, damage = 1, speed = 30, chaseSpeed = 55, sight = 220,
        battle = { hp = 24, attack = 7, defense = 5, speed = 5, shield = 3, weak = { "thrust", "stone" },
            skills = { "jab", "triple" }, xp = 16, coins = { 2, 5 } },
        drops = { { item = "coin", chance = 0.8 } },
    },
    -- platformer
    pumpkin = { name = "Тыквоглав", sprite = "pumpkin", hp = 2, damage = 1, ai = "walker", platformSpeed = 26 },
    ghost_blue = { name = "Привиденьице", sprite = "ghost_blue", hp = 2, damage = 1, ai = "flyer", platformSpeed = 30, stomp = true },
    saw = { name = "Пила", sprite = "saw", hp = 1, damage = 2, ai = "hazard", platformSpeed = 45, stomp = false, invulnerable = true },
    snail = { name = "Улитка", sprite = "snail", hp = 2, damage = 1, ai = "walker", platformSpeed = 12 },
    ninja = { name = "Ниндзя", sprite = "ninja", hp = 2, damage = 1, ai = "hopper", platformSpeed = 50 },
}
