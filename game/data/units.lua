-- Troops for the tactics battle (Heroes of Might and Magic 3 style hexes, game/modes/tactics.lua).
--   sprite     name from game/data/sprites.lua (scale: size on the field, default the sprite's own)
--   hp         health of ONE creature (a stack of 10 has 10 x hp)
--   attack, defense   compared like in HoMM3: +5% damage per point of attack over defense,
--              -2.5% per point of defense over attack
--   damage     { min, max } per creature
--   speed      hexes per turn, also the turn order
--   shots      ranged attacks (shooters); nil = melee only
--   flying     flies over obstacles and other stacks
-- Abilities:
--   noRetaliation  the target does not strike back       retaliations  strikes back N times a round
--   strikes = 2    hits twice                            hitAndRun     goes back after the blow
--   breath         also hits the stack behind the target sticky        the target is slower next round
--   value      how much a creature is worth (score, AI); default hp
--   single     a hero, not a troop: always one creature

return {
    -- the heroes of the story: one creature each (single), Гриша has the spell book
    grisha = { name = "Гриша", sprite = "grisha", scale = 3, hp = 40, attack = 7, defense = 5, damage = { 4, 7 },
        speed = 5, retaliations = 2, hero = true, single = true },
    kashka = { name = "Кашка", sprite = "bunny", scale = 0.36, hp = 26, attack = 6, defense = 4, damage = { 3, 5 },
        speed = 8, hitAndRun = true, single = true },
    -- troops
    slimes = { name = "Слизики", sprite = "slime", hp = 10, attack = 3, defense = 5, damage = { 1, 2 }, speed = 4,
        sticky = true },
    ghosts = { name = "Призраки", sprite = "ghost", hp = 7, attack = 6, defense = 2, damage = { 2, 3 }, speed = 8,
        flying = true, noRetaliation = true },
    stoners = { name = "Камнеметы", sprite = "robot", hp = 9, attack = 5, defense = 3, damage = { 2, 3 }, speed = 4,
        shots = 8, missile = "stone" },
    radishes = { name = "Редиски", sprite = "radish", hp = 5, attack = 3, defense = 2, damage = { 1, 2 }, speed = 5 },
    crabs = { name = "Раки", sprite = "crab", hp = 14, attack = 4, defense = 7, damage = { 2, 4 }, speed = 3,
        retaliations = 2 },
    frogs = { name = "Робожабы", sprite = "frog", hp = 10, attack = 5, defense = 4, damage = { 2, 4 }, speed = 6,
        breath = true },
    owls = { name = "Совы", sprite = "owl", hp = 6, attack = 6, defense = 2, damage = { 1, 3 }, speed = 9, flying = true,
        shots = 6, missile = "feather" },
    beetles = { name = "Жуки", sprite = "beetle", hp = 12, attack = 6, defense = 5, damage = { 2, 5 }, speed = 5,
        strikes = 2 },
}
