-- Battle commands. kind:
--   melee   walk up and hit one enemy (press [Space] in time for a critical hit)
--   ranged  aim (the camera goes behind the hero), then a timing bar
--   heal    restore hp of an ally
--   defend  half damage until the next turn
--   item    use something from the bag
--   flee    try to run away
-- cost: { item = "stone" } uses up an item

return {
    attack = { name = "Атака", icon = "skill_attack", kind = "melee", power = 1.0, fx = "slash",
        description = "Удар по одному врагу. Нажми [Пробел] в момент удара — крит!" },
    stone = { name = "Камень", icon = "skill_stone", kind = "ranged", power = 1.5, fx = "magic",
        cost = { item = "stone" }, description = "Прицелиться и бросить камень. Нужен камень." },
    defend = { name = "Защита", icon = "skill_defend", kind = "defend", fx = "shield",
        description = "Получать вдвое меньше урона до следующего хода." },
    item = { name = "Предмет", icon = "potion", kind = "item", description = "Использовать предмет из сумки." },
    flee = { name = "Бежать", icon = "skill_run", kind = "flee", chance = 0.6,
        description = "Попробовать сбежать из боя." },
    bite = { name = "Укус", icon = "skill_bite", kind = "melee", power = 0.8, fx = "slash",
        description = "Кусь! Больно." },
    heal = { name = "Лечение", icon = "skill_heal", kind = "heal", power = 10, fx = "shield",
        description = "Морковная магия лечит союзника." },
}
