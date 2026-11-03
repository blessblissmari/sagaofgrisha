-- Items. Icons: assets/sprites/icons/<icon>.png (34x34, "496 pixel art icons", CC0).
--   heal      restores hp (2 = one heart; in battle x4)
--   throwable can be thrown (top-down: [K])
--   stack     max count in one slot
--   quest     can't be used or thrown away
--   ability   picking it up unlocks an ability instead of going to the bag

return {
    carrot = { name = "Морковь", icon = "carrot", heal = 2, stack = 9,
        description = "Любимая еда Кроля. Лечит 1 сердце." },
    stone = { name = "Камень", icon = "stone", throwable = true, stack = 20,
        description = "Бросить: [K] в мире или «Камень» в бою." },
    potion = { name = "Зелье", icon = "potion", heal = 99, stack = 5,
        description = "Красное и горькое. Лечит полностью." },
    clover = { name = "Клевер", icon = "clover", stack = 9,
        description = "Четыре листика. В бою чаще бывают криты." },
    key = { name = "Ключ", icon = "key", stack = 3, quest = true,
        description = "Старый ключ. Открывает запертые двери." },
    mushroom = { name = "Гриб", icon = "mushroom", heal = 1, stack = 9,
        description = "Подозрительный гриб. Лечит половинку сердца." },
    coin = { name = "Монета", icon = "coin", stack = 999,
        description = "Блестит. Слизни их почему-то любят." },
    -- abilities (platformer): picked up as glowing orbs
    double_jump = { name = "Двойной прыжок", icon = "skill_run", ability = "double_jump",
        description = "Прыжок ещё раз прямо в воздухе." },
    dash = { name = "Рывок", icon = "skill_attack", ability = "dash",
        description = "[Shift]: рывок вперёд, ломает треснувшие блоки." },
    wall_jump = { name = "Прыжок от стены", icon = "skill_defend", ability = "wall_jump",
        description = "Прыжок, оттолкнувшись от стены." },
}
