-- Battle skills (party and enemies). The battle is a timeline (like Grandia):
-- a unit runs WAIT -> COM (chooses what to do) -> CAST (the action charges) -> ACT.
-- A hit with `interrupt` on a casting unit cancels its action and knocks it back.
--
--   name, icon, description
--   kind      "attack" | "heal" | "defend" | "item" | "flee" | "duo" | "buff"
--   target    "enemy" | "enemies" (all) | "ally" | "allies" | "self"
--   type      damage type: "weapon" (from the hero's weapon) | "slash" | "chop" | "thrust"
--             | "blunt" | "stone" | "bite" | "magic". Enemies are weak to some types.
--   power     damage multiplier per hit
--   hits      { min, max }: a combo - every well-timed press adds a hit (max = weapon's combo)
--   qte       action command: "chain" (rings one after another), "ring" (one ring),
--             "bar" (a marker runs over a bar), "mash" (press fast), "hold" (hold and release)
--   cast      how fast the action charges after the choice (1 = normal, 2 = quick, 0 = instant)
--   cost      { bp = 2 } brave points (+1 every turn, max 5) or { item = "stone" }
--   interrupt cancels the target's action if it is casting; knock = timeline knock-back
--   shield    shield points taken per hit when the type is a weakness (default 1)
--   status    { id = "poison", chance = 0.5, turns = 3 } (see game/data/statuses.lua)
--   heal      part of max hp (0.35) for kind "heal"
-- Enemy attacks: windup = seconds until the blow (the ring the player parries),
--   rhythm = { 0.5, 0.35 } several blows, feint = a pause in the middle of the swing,
--   ranged = a projectile instead of walking up, weight = how often the AI picks it.

return {
    -- the hero -------------------------------------------------------------------
    attack = { name = "Атака", icon = "skill_attack", kind = "attack", target = "enemy", type = "weapon",
        power = 1.0, hits = { 1, 3 }, qte = "chain", cast = 1.8,
        description = "Серия ударов: жми, когда круг сойдётся — каждый точный удар добавляет ещё один." },
    smash = { name = "Сбить", icon = "skill_attack", kind = "attack", target = "enemy", type = "weapon",
        power = 1.5, qte = "ring", cast = 0.8, interrupt = true, knock = 0.3,
        description = "Тяжёлый удар. Медленно, но сбивает врага, который готовит атаку." },
    defend = { name = "Защита", icon = "skill_defend", kind = "defend", target = "self", cast = 0,
        description = "Вдвое меньше урона до следующего хода, +1 очко отваги, следующий ход раньше." },
    item = { name = "Предмет", icon = "potion", kind = "item", target = "ally", cast = 0,
        description = "Использовать предмет из сумки." },
    flee = { name = "Бежать", icon = "skill_run", kind = "flee", target = "self", cast = 0, chance = 0.6,
        description = "Попробовать сбежать. Чем ты быстрее врагов, тем легче." },
    stone = { name = "Камень", icon = "skill_stone", kind = "attack", target = "enemy", type = "stone",
        power = 1.3, qte = "bar", cast = 2.2, ranged = true, interrupt = "perfect", knock = 0.2,
        cost = { item = "stone" },
        description = "Бросок камнем: останови бегунок в центре. Точный бросок сбивает подготовку врага." },
    -- weapon skills (the hero gets the skill of the weapon in hand)
    whirl = { name = "Вихрь", icon = "sword", kind = "attack", target = "enemies", type = "slash",
        power = 0.85, qte = "ring", cast = 1.0, cost = { bp = 2 },
        description = "Удар мечом по всем врагам сразу." },
    cleave = { name = "Раскол", icon = "axe", kind = "attack", target = "enemy", type = "chop",
        power = 1.2, qte = "mash", cast = 0.9, cost = { bp = 2 }, shield = 2,
        description = "Жми быстро-быстро! Раскалывает щит врага: -2 щита." },
    pierce = { name = "Пронзить", icon = "spear", kind = "attack", target = "enemy", type = "thrust",
        power = 1.7, qte = "hold", cast = 1.0, cost = { bp = 2 }, pierce = true,
        description = "Держи и отпусти в зелёной зоне. Пробивает защиту насквозь." },
    venom = { name = "Ядовитый укол", icon = "dagger", kind = "attack", target = "enemy", type = "thrust",
        power = 0.9, qte = "ring", cast = 2.0, cost = { bp = 1 }, status = { id = "poison", chance = 0.9, turns = 3 },
        description = "Быстрый укол кинжалом. Отравляет." },
    bonk = { name = "Оплеуха", icon = "fist", kind = "attack", target = "enemy", type = "blunt",
        power = 1.1, qte = "ring", cast = 1.4, cost = { bp = 1 }, status = { id = "stun", chance = 0.5, turns = 1 },
        interrupt = true, knock = 0.15,
        description = "Звонкая оплеуха. Может оглушить." },
    rally = { name = "Боевой клич", icon = "skill_defend", kind = "buff", target = "allies", cast = 1.5,
        cost = { bp = 2 }, status = { id = "attack_up", chance = 1, turns = 3 },
        description = "Атака всего отряда +30% на 3 хода." },

    -- the pet (Кашка) --------------------------------------------------------------
    bite = { name = "Укус", icon = "skill_bite", kind = "attack", target = "enemy", type = "bite",
        power = 0.8, hits = { 1, 3 }, qte = "chain", cast = 2.2,
        description = "Кусь-кусь-кусь! Серия укусов." },
    hop = { name = "Прыг-скок", icon = "skill_run", kind = "attack", target = "enemy", type = "blunt",
        power = 1.0, qte = "ring", cast = 1.6, cost = { bp = 1 }, interrupt = true, knock = 0.25,
        description = "Прыжок на голову врагу: сбивает подготовку атаки." },
    heal = { name = "Морковная магия", icon = "skill_heal", kind = "heal", target = "ally", heal = 0.4,
        qte = "bar", cast = 1.2, cost = { bp = 2 },
        description = "Лечит союзника. Точнее бегунок — сильнее лечение." },

    -- together ----------------------------------------------------------------------
    duo = { name = "Морковный вихрь", icon = "carrot", kind = "duo", target = "enemies", type = "magic",
        power = 1.6, qte = "mash", cast = 0, shield = 2,
        description = "Гриша и Кашка вместе! Жми быстро. Шкала «Дружба» должна быть полной." },

    -- enemies -----------------------------------------------------------------------
    jab = { name = "Тычок", kind = "attack", target = "enemy", type = "blunt", power = 1.0,
        windup = 0.55, cast = 1.4, weight = 3 },
    slam = { name = "Шмяк", kind = "attack", target = "enemy", type = "blunt", power = 1.5,
        windup = 0.95, cast = 0.7, weight = 2, knock = 0.15 },
    double = { name = "Двойной укус", kind = "attack", target = "enemy", type = "bite", power = 0.7,
        rhythm = { 0.5, 0.32 }, cast = 1.2, weight = 2 },
    triple = { name = "Тройной удар", kind = "attack", target = "enemy", type = "slash", power = 0.6,
        rhythm = { 0.55, 0.3, 0.3 }, cast = 1.0, weight = 2 },
    feint = { name = "Обманный прыжок", kind = "attack", target = "enemy", type = "blunt", power = 1.3,
        windup = 0.75, feint = 0.4, cast = 1.0, weight = 2 },
    spit = { name = "Плевок", kind = "attack", target = "enemy", type = "magic", power = 0.8, ranged = true,
        windup = 0.7, cast = 1.2, weight = 2, status = { id = "poison", chance = 0.4, turns = 3 } },
    chill = { name = "Холодок", kind = "attack", target = "enemy", type = "magic", power = 0.9, ranged = true,
        windup = 0.8, cast = 0.9, weight = 2, status = { id = "slow", chance = 0.5, turns = 2 } },
    guard = { name = "Панцирь", kind = "defend", target = "self", cast = 2.0, weight = 1, restore = 2 },
    mend = { name = "Слизелечение", kind = "heal", target = "ally", heal = 0.3, cast = 0.8, weight = 0,
        when = "allyHurt" },
    roar = { name = "Рык", kind = "buff", target = "allies", cast = 0.8, weight = 1,
        status = { id = "attack_up", chance = 1, turns = 2 } },
}
