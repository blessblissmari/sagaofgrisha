-- Items. Icons: assets/sprites/icons/<icon>.png (34x34, "496 pixel art icons", CC0).
-- The bag has tabs by kind:
--   kind      "item" (default) | "weapon" | "armor" | "key" (quest things, can't be thrown away)
--   heal      restores hp (2 = one heart; in battle x4)
--   throwable can be thrown (top-down: [K])
--   stack     max count in one slot
--   ability   picking it up unlocks an ability instead of going to the bag
-- Weapons and armor (put on in the bag, used EVERYWHERE: top-down, battles, the dungeon):
--   slot      "weapon" | "body" | "head" | "feet" | "accessory"
--   attack, defense, speed   bonuses
--   reach     top-down swing distance (pixels), power = damage in the world
--   swing     first-person style: "slash" (sword), "chop" (axe, club), "thrust" (spear, dagger)
--   fp        first-person picture (an image path); without it the icon is drawn big

return {
    carrot = { name = "Морковь", icon = "carrot", heal = 2, stack = 9,
        description = "Любимая еда Кашки. Лечит 1 сердце." },
    bread = { name = "Хлеб", icon = "bread", heal = 4, stack = 9,
        description = "Тёплый каравай. Лечит 2 сердца." },
    stone = { name = "Камень", icon = "stone", throwable = true, stack = 20,
        description = "Бросить: [K] в мире или «Камень» в бою." },
    potion = { name = "Зелье", icon = "potion", heal = 99, stack = 5,
        description = "Красное и горькое. Лечит полностью." },
    ether = { name = "Эфир", icon = "ether", heal = 6, stack = 5,
        description = "Синее зелье. Лечит 3 сердца." },
    clover = { name = "Клевер", icon = "clover", stack = 9,
        description = "Четыре листика. В бою чаще бывают криты." },
    mushroom = { name = "Гриб", icon = "mushroom", heal = 1, stack = 9,
        description = "Подозрительный гриб. Лечит половинку сердца." },
    coin = { name = "Монета", icon = "coin", stack = 999,
        description = "Блестит. Слизни их почему-то любят." },
    torch = { name = "Факел", icon = "torch", stack = 5,
        description = "Светит в подземелье." },

    -- weapons
    fists = { name = "Кулаки", icon = "fist", kind = "weapon", slot = "weapon", attack = 0, reach = 14,
        power = 1, swing = "thrust", description = "Ничего в руках. Зато руки свободны." },
    stick = { name = "Палка", icon = "club", kind = "weapon", slot = "weapon", attack = 1, reach = 18,
        power = 1, swing = "chop", description = "Крепкая палка с пляжа. Атака +1." },
    sword = { name = "Меч", icon = "sword", kind = "weapon", slot = "weapon", attack = 4, reach = 22,
        power = 2, swing = "slash", description = "Простой железный меч. Атака +4." },
    knight_sword = { name = "Рыцарский меч", icon = "knight_sword", kind = "weapon", slot = "weapon", attack = 7,
        reach = 24, power = 3, swing = "slash", description = "Тяжёлый и надёжный. Атака +7." },
    dagger = { name = "Кинжал", icon = "dagger", kind = "weapon", slot = "weapon", attack = 2, speed = 2,
        reach = 16, power = 1, swing = "thrust", description = "Быстрый удар. Атака +2, скорость +2." },
    axe = { name = "Топор", icon = "axe", kind = "weapon", slot = "weapon", attack = 6, speed = -1,
        reach = 20, power = 3, swing = "chop", description = "Рубит с плеча. Атака +6, скорость -1." },
    spear = { name = "Копьё", icon = "spear", kind = "weapon", slot = "weapon", attack = 5,
        reach = 30, power = 2, swing = "thrust", description = "Длинное. Достаёт издалека. Атака +5." },

    -- armor
    tunic = { name = "Рубаха", icon = "tunic", kind = "armor", slot = "body", defense = 1,
        description = "Льняная рубаха. Защита +1." },
    leather = { name = "Кожаная куртка", icon = "leather", kind = "armor", slot = "body", defense = 3,
        description = "Потёртая, но крепкая. Защита +3." },
    mail = { name = "Кольчуга", icon = "mail", kind = "armor", slot = "body", defense = 6, speed = -1,
        description = "Звенит при ходьбе. Защита +6, скорость -1." },
    helmet = { name = "Шлем", icon = "helmet", kind = "armor", slot = "head", defense = 2,
        description = "Бронзовый шлем. Защита +2." },
    hat = { name = "Шляпа мага", icon = "hat", kind = "armor", slot = "head", defense = 1, attack = 1,
        description = "Немного волшебная. Защита +1, атака +1." },
    boots = { name = "Сапоги", icon = "boots", kind = "armor", slot = "feet", defense = 1, speed = 1,
        description = "Удобные. Защита +1, скорость +1." },
    ring = { name = "Кольцо", icon = "ring", kind = "armor", slot = "accessory", attack = 1, defense = 1,
        description = "Тёплое на ощупь. Атака +1, защита +1." },

    -- key items
    key = { name = "Ключ", icon = "key", stack = 3, kind = "key",
        description = "Старый ключ. Открывает запертые двери." },
    gold_key = { name = "Золотой ключ", icon = "gold_key", kind = "key",
        description = "Ключ от сокровищницы подземелья." },
    letter = { name = "Письмо", icon = "letter", kind = "key", read = "letter",
        text = "«Гриша! Если ты читаешь это, значит, остров уже проснулся. Найди старый мост, "
            .. "а за ним — пещеру. Не бойся слизней: они больше шумят, чем кусаются.»\n\n{faded}— без подписи{/}",
        description = "Письмо без подписи. [Enter] — прочитать." },
    map = { name = "Карта", icon = "map", kind = "key",
        description = "Карта острова. Мир круглый: уйдёшь на запад — придёшь с востока." },

    -- abilities (platformer): picked up as glowing orbs
    double_jump = { name = "Двойной прыжок", icon = "skill_run", ability = "double_jump",
        description = "Прыжок ещё раз прямо в воздухе." },
    dash = { name = "Рывок", icon = "skill_attack", ability = "dash",
        description = "[Shift]: рывок вперёд, ломает треснувшие блоки." },
    wall_jump = { name = "Прыжок от стены", icon = "skill_defend", ability = "wall_jump",
        description = "Прыжок, оттолкнувшись от стены." },
}
