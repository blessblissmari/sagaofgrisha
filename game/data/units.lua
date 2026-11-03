-- Troops for the tactics battle (Heroes of Might and Magic 3 style hexes).
--   sprite     name from game/data/sprites.lua
--   hp         health of ONE creature (a stack of 10 has 10 x hp)
--   attack, defense   compared like in HoMM3: +5% damage per point of difference
--   damage     { min, max } per creature
--   speed      hexes per turn, also the turn order
--   shots      ranged attacks (shooters); nil = melee only
--   flying     ignores obstacles while moving

return {
    heroes = { name = "Гриша", sprite = "grisha", hp = 40, attack = 7, defense = 5, damage = { 4, 7 }, speed = 5 },
    bunnies = { name = "Кроли", sprite = "bunny", hp = 8, attack = 5, defense = 3, damage = { 1, 3 }, speed = 7 },
    slimes = { name = "Слизики", sprite = "slime", hp = 10, attack = 3, defense = 5, damage = { 1, 2 }, speed = 4 },
    ghosts = { name = "Призраки", sprite = "ghost", hp = 7, attack = 6, defense = 2, damage = { 2, 3 }, speed = 8, flying = true },
    stoners = { name = "Камнеметы", sprite = "robot", hp = 9, attack = 5, defense = 3, damage = { 2, 3 }, speed = 4, shots = 8 },
    radishes = { name = "Редиски", sprite = "radish", hp = 5, attack = 3, defense = 2, damage = { 1, 2 }, speed = 5 },
    crabs = { name = "Раки", sprite = "crab", hp = 14, attack = 4, defense = 7, damage = { 2, 4 }, speed = 3 },
    frogs = { name = "Робожабы", sprite = "frog", hp = 10, attack = 5, defense = 4, damage = { 2, 4 }, speed = 6 },
    owls = { name = "Совы", sprite = "owl", hp = 6, attack = 6, defense = 2, damage = { 1, 3 }, speed = 9, flying = true, shots = 6 },
    beetles = { name = "Жуки", sprite = "beetle", hp = 12, attack = 6, defense = 5, damage = { 2, 5 }, speed = 5 },
}
