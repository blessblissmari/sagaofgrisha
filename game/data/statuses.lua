-- Status effects in battles. turns = how many own turns it lasts.
--   tick     damage (part of max hp) at the start of the unit's turn
--   speed    timeline speed multiplier, attack / defense / damage multipliers
--   skip     the unit loses its turn
return {
    poison = { name = "Яд", short = "Яд", color = { 0.55, 0.95, 0.35 }, tick = 0.07, turns = 3 },
    stun = { name = "Оглушение", short = "Ош", color = { 1, 0.9, 0.3 }, skip = true, turns = 1 },
    slow = { name = "Замедление", short = "Зм", color = { 0.5, 0.75, 1 }, speed = 0.6, turns = 2 },
    haste = { name = "Ускорение", short = "Уск", color = { 1, 0.6, 0.9 }, speed = 1.5, turns = 3 },
    attack_up = { name = "Ярость", short = "Атк", color = { 1, 0.45, 0.3 }, attack = 1.3, turns = 3 },
    guard = { name = "Защита", short = "Щит", color = { 0.6, 0.85, 1 }, damage = 0.5, turns = 1 },
}
