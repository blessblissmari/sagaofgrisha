-- Talents of Гриша for checks in dialogues (like Disco Elysium / Baldur's Gate 3):
--   s:check("wits", 8, "Найти тайник")            -- throws 2d6 + talent, true if >= 8
--   s:ask("Как пройти?", { "Обойти", { "Перепрыгнуть", check = { "agility", 9 } } })
--   s:talent("charm", 1)                           -- the talent grows (+1), s:talent("charm") -> value
-- Two sixes always win, two ones always lose. The journal [N] shows the talents (order, text).
-- Add your own talents here or in story.lua:
--   game.talents.magic = { name = "Магия", start = 0, order = 5, text = "Чары и заговоры." }
return {
    strength = { name = "Сила", start = 1, order = 1, text = "Поднять, сломать, удержать." },
    agility = { name = "Ловкость", start = 2, order = 2, text = "Прыгнуть, увернуться, стащить." },
    wits = { name = "Смекалка", start = 2, order = 3, text = "Заметить, понять, придумать." },
    charm = { name = "Обаяние", start = 1, order = 4, text = "Уговорить, рассмешить, подружиться." },
}
