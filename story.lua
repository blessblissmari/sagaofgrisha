-- =====================================================================================
--  Сага о Грише — тестовая сборка (витрина движка)
--  Весь сюжет описывается здесь: этапы (stage), персонажи, сцены, фоны, небо, голоса.
--  Подробности по каждому режиму — в комментариях в начале game/modes/<режим>.lua
-- =====================================================================================
local game = require("game")

game.title = "Сага о Грише"
game.start = "menu"

-- Оформление: "ff" (окна в стиле Final Fantasy, по умолчанию) или "parchment" (пергамент).
-- Можно переопределить цвета: game.ui = { preset = "ff", colors = { accent = "#ffd34a" } }
game.ui = "ff"

-- Герой и стартовый инвентарь (оружие и броня надеваются в сумке [I])
game.player.party = { "bunny" }
game.player.items = { stone = 3, carrot = 2, potion = 2, sword = 1, axe = 1, spear = 1,
    leather = 1, helmet = 1, letter = 1 }
game.player.equipment = { weapon = "sword", body = "leather" }

-- Голоса: у каждого персонажа свой синтезированный «голос» (male, female, kid, old,
-- monster, alien, robot, ghost, animal, narrator, beep). Можно поменять прямо тут:
--   game.characters.bunny.voice = { "kid", 520 }   -- тип и высота тона в Гц
game.characters.bunny.voice = "animal"

-- Управление: у каждого вида геймплея своя раскладка (все раскладки — в game/config.lua):
--   game.controls.common      — везде (меню, диалоги, пауза, сумка)
--   game.controls.topdown, .platformer, .raycaster, .battle, .novel, .tetris, .arcade, .puzzle...
-- Например:
--   game.controls.topdown.attack = { "space", "j" }
--   game.controls.raycaster.map = { "m", "tab" }
-- Или только в одном этапе: game.stage "boss" { kind = "battle", controls = { parry = { "f" } } }
-- Подсказки на экране ([Пробел] удар...) сами берут клавиши из раскладки.

-- Предметы на земле поднимаются двумя способами (game/data/items.lua, поле pickup):
--   "auto"  — просто пройти по нему (монеты, еда, камни; подлетают к герою сами)
--   "press" — подойти и нажать [E] (оружие, броня, ключи, письма)
-- В Tiled у предмета можно задать свойство pickup = auto/press.

-- Тексты писем/записок (предмет letter открывается в сумке)
game.notes.letter = "Гриша!\n\nЕсли читаешь это — значит, ты всё-таки открыл сумку. "
    .. "Загляни в подземелье к северу от острова. Там темно, сыро и полно слизней.\n\n— Кашка"

-- Свои фоны и небо можно описать тут же (как в game/data/backgrounds.lua и skies.lua):
--   game.backgrounds.castle = { color = { 0.1, 0.1, 0.2 }, layers = { { image = "...", scale = 4 } } }
--   game.skies.storm = { top = "#202838", horizon = "#606878", clouds = 0.9, band = "mountains" }

-- =====================================================================================
--  Инструменты рассказчика (все команды — в начале game/director.lua). Итог виден в
--  дневнике [N] (или «Дневник» в паузе): задания, решения, отношения, таланты, энциклопедия.
--    s:think("...")                          мысли героя: имя «Гриша (про себя)», приглушённый цвет
--    s:ask(вопрос, ответы, кто, { id = "quake", time = 6, default = 3 })
--        id   — решение попадёт в дневник и в итоги главы, позже s:choice("quake") вернёт номер
--        time — выбор на время (полоска тает), не успел — выбран ответ default
--    ответ может быть таблицей (номер всё равно — место в списке):
--        { "Отдать морковку", requires = "carrot", take = true }  серый «(нужно: Морковь)», если нет
--        { "Выбить дверь", check = { "strength", 9 } }            «[Сила] Выбить дверь 42%» + бросок
--        { "Соврать", flag = "lied", like = { "bunny", -1 }, remember = { "bunny", "lie", "ты соврал" } }
--        { "Секрет", hidden = not s:flag("knows") }                 ответа просто нет
--        local i, ok, late = s:ask(...)   -- ok = результат проверки, late = время вышло
--    s:check("wits", 8, "Найти тайник")       бросок 2d6 + талант против сложности -> true/false
--    s:talent("charm", 1)                     талант растёт (таланты: game/data/talents.lua)
--    s:remember("bunny", "id", "что было")    в углу «Кашка запомнит это.»; s:remembers("bunny", "id")
--    s:like("bunny", 1) / s:affinity("bunny") отношения: «Кашка одобряет» / «не одобряет»
--    s:journal("id", "Задание") / s:journalDone("id")      задания
--    s:learn("people", "id", "Имя", "Описание")             энциклопедия: people, places, monsters, things
--    s:chapter("Глава 2") / s:recap("Итоги главы")          глава (s:title в новелле ставит её сам)
-- =====================================================================================

-- =====================================================================================
--  Главное меню
-- =====================================================================================
game.stage "menu" {
    kind = "title", background = "mountains", music = "calm",
    subtitle = "тестовая сборка",
    newGame = "prologue", newGameTransition = "page",
    menu = {
        { "Демо-режимы", list = {
            { "Визуальная новелла", go = "prologue" },
            { "Переходы между сценами", go = "transitions" },
            { "Остров (вид сверху)", go = "island" },
            { "Подземелье (псевдо-3D)", go = "dungeon", transition = "iris" },
            { "Пещера (платформер)", go = "cave" },
            { "Луг (изометрия)", go = "meadow" },
            { "Карта мира (3D)", go = "world" },
            { "Бой: день", play = "fight_day" },
            { "Бой: закат", play = "fight_sunset" },
            { "Бой: ночь", play = "fight_night" },
            { "Тетрис", play = "tetris" },
        } },
        -- все мини-игры: play = имя режима (game/modes/...) или этапа
        { "Мини-игры", list = {
            { "Тактика (как в «Героях»)", play = "tactics" },
            { "Тетрис", play = "tetris" },
            { "Слизняк", play = "snake" },
            { "Кирпичики", play = "breakout" },
            { "Самоцветы", play = "match3" },
            { "Слизни-хлопушки", play = "puyo" },
            { "Картина", play = "xonix" },
            { "Парочки", play = "memory" },
            { "Покер Кашки", play = "cards" },
            { "Кости", play = "dice" },
            { "Рыбалка", play = "fishing" },
            { "Пляска", play = "rhythm" },
            { "Звёздный патруль", play = "shmup" },
            { "Взлом", play = "lockpick" },
            { "Гонка", play = "racing" },
        } },
    },
}

-- =====================================================================================
--  Пролог: визуальная новелла
--  Эффекты в тексте: {wave}волна{/} {shake}дрожь{/} {rainbow}радуга{/} {accent}цвет{/}
--  {#ff8080}любой цвет{/} {slow}медленно{/} {p} пауза, {@hop} — эмоция в момент буквы.
-- =====================================================================================
game.stage "prologue" {
    kind = "novel", background = "forest", weather = "leaves", music = "calm",
    script = function(s)
        s:title("Глава 1", "Лес у моря")      -- заодно это глава дневника: «Глава 1. Лес у моря»
        s:show("grisha", { at = "left" })
        s:show("bunny", { at = "right" })
        s:say("grisha", "Привет, {accent}Кашка{/}! {wave}Смотри, какой лес!{/} Тут {shake}страшновато{/}...")
        s:emotion("bunny", "joy")
        s:say("bunny", "Ура!{@hop} Я так рада!{p} {rainbow}Пойдём искать морковку!{/}")
        s:emotion("grisha", "anger")
        s:say("grisha", "{@shake}Что?! Опять морковка?!")
        s:emote("bunny", "sweat")
        -- id: решение попадёт в дневник ([N] -> «Решения») и в итоги главы (s:recap)
        local a = s:ask("bunny", "Ну пожалуйста... Пойдём?", { "Да, пойдём", "Нет", "Может быть" }, { id = "carrot_walk" })
        if a == 1 then
            s:closeup("bunny")
            s:emotion("bunny", "love")
            s:say("bunny", "Спасибо!{@hop} Ты лучший!")
            s:like("bunny", 1)                 -- отношения: в углу «Кашка одобряет»
            s:closeup()
        elseif a == 2 then
            s:emotion("bunny", "sad")
            s:say("bunny", "{slow}Ну и ладно...{/}")
            s:like("bunny", -1)
            s:emotion("grisha", "sweat")
            s:say("grisha", "Ладно-ладно, пойдём!")
        else
            s:emotion("grisha", "think")
            s:think("Морковка, морковка... {p}Хоть бы раз грибы.")   -- мысли героя
            s:say("grisha", "Хм... {p=1}Ну, может быть.")
        end
        s:journal("carrot", "Найти морковку для Кашки")       -- задание в дневнике
        s:learn("people", "bunny", "Кашка", "Серая вислоухая крольчиха. Любит морковку, покер и приключения — именно в таком порядке.")
        s:bg("cliffs", "starwars")
        s:say(nil, "{slow}Тем временем у моря...{/}")
        s:emotion("grisha", "surprise")
        s:quake()
        s:say("grisha", "{@shake}Земля трясётся!")
        s:emotion("bunny", "fear")
        -- выбор на время: полоска под ответами тает, не успел — берётся default
        local b = s:ask("bunny", "{shake}Гриша!{/} Что делать?!", { "Схватить Кашку и бежать", "Бежать первым", "Замереть" },
            { time = 6, default = 3, id = "quake" })
        if b == 1 then
            s:emotion("bunny", "love")
            s:say("bunny", "{wave}Ой!{/} Ты меня несёшь?! {p}Мой герой!")
            s:remember("bunny", "quake_saved", "в землетрясение Гриша вынес её на руках")  -- «Кашка запомнит это.»
            s:like("bunny", 1)
        elseif b == 2 then
            s:emotion("bunny", "anger")
            s:say("bunny", "Эй! {shake}Подожди меня!{/}")
            s:remember("bunny", "quake_left", "в землетрясение Гриша убежал первым")
            s:like("bunny", -1)
        else
            s:think("Ноги не слушаются... {p}Кашка тянет меня за штанину.")
            s:say("bunny", "{shake}Очнись!{/} Бежим на остров!")
        end
        s:journal("island", "Переждать землетрясение на острове")
        s:recap("Итоги главы")                   -- решения главы на одном экране
        s:go("island", "page")
    end,
}

-- =====================================================================================
--  Витрина переходов: s:bg("фон", "переход")
--  Закрывающие: fade, pixel, swirl, wipe, circle, dissolve, blinds, wave, diamond, battle
--  Раскрывающие (старая картинка уходит, новая появляется): page, starwars, clock, iris,
--  crossfade, slide. Опции: { direction = { 0, 1 }, softness = 0.2, duration = 2 }
-- =====================================================================================
game.stage "transitions" {
    kind = "novel", background = "mountains", music = "calm",
    script = function(s)
        s:show("grisha", { at = "center" })
        s:say("grisha", "Покажу переходы. {accent}Листаем страницу{/}...")
        s:bg("forest", "page")
        s:say("grisha", "А это — {accent}шторка из «Звёздных войн»{/}: мягкая невидимая полоса.")
        s:bg("cliffs", "starwars")
        s:say("grisha", "Та же шторка сверху вниз.")
        s:bg("hills", "starwars", { direction = { 0, 1 }, softness = 0.25 })
        s:say("grisha", "{accent}Часы{/} — тоже из «Звёздных войн».")
        s:bg("snowy", "clock")
        s:say("grisha", "{accent}Диафрагма{/}.")
        s:bg("mountains", "iris")
        s:say("grisha", "{accent}Сдвиг{/}.")
        s:bg("forest", "slide")
        s:say("grisha", "{accent}Наплыв{/}.")
        s:bg("cliffs", "crossfade")
        s:say("grisha", "И закрывающие: {accent}вихрь{/}...")
        s:bg("hills", "swirl")
        s:say("grisha", "...{accent}пиксели{/}...")
        s:bg("snowy", "pixel")
        s:say("grisha", "...и {accent}жалюзи{/}.")
        s:bg("mountains", "blinds")
        s:say("grisha", "Всё! Обратно в меню.")
        s:go("menu", "page")
    end,
}

-- =====================================================================================
--  Карты рисуются в Tiled: откройте проект assets/maps/SagaOfGrisha.tiled-project.
--  Заготовки для каждого режима — assets/maps/templates/ (topdown, platformer, dungeon,
--  iso), объекты ставятся шаблонами из templates/items, mobs, npcs, objects.
--  Своя карта = свой этап:  game.stage "my_level" { kind = "topdown", map = "assets/maps/my_level.tmx" }
--  Сыграть карту сразу: love . --map=assets/maps/my_level.tmx (в Tiled — клавиша F5).
--  Добавили предмет, монстра, спрайт или этап — обновите списки Tiled: love . --tiled
-- =====================================================================================

-- =====================================================================================
--  Остров: вид сверху. Зоны (Triggers) из Tiled -> что происходит.
--  [F]/[Enter] — действие, [Пробел] — удар оружием, [I] — сумка, [Esc] — пауза.
-- =====================================================================================
game.stage "island" {
    kind = "topdown", map = "assets/maps/island.tmx", music = "calm",
    battle = "fight_day",
    -- при входе на остров: задания дневника (без диалога — сразу можно бегать)
    script = function(s)
        if s:once("island_tasks") then
            s:chapter("Глава 2. Остров")
            s:journalDone("island")
            s:journal("dungeon", "Заглянуть в подземелье на севере острова")
        end
    end,
    triggers = {
        cave = { "cave" },
        -- лодка у южного берега: в большой мир (карта мира 3D, stage "world")
        boat = function(s)
            local a = s:ask("bunny", "Лодка! {p}Поплывём в большой мир?", { "Плывём!", "Не сейчас" })
            if a == 1 then
                s:go("world", { spawn = "boat", transition = "iris" })
            end
        end,
        -- дверь подземелья заперта: мини-игра «Взлом» (game/modes/lockpick.lua)
        -- ответ с проверкой таланта: «[Сила] Выбить дверь плечом 42%» — бросок 2d6 + Сила >= 9
        dungeon = function(s)
            if not s:flag("dungeon_open") then
                s:learn("places", "dungeon", "Подземелье", "Старая дверь на севере острова. Внутри темно, сыро и полно слизней.")
                local a, ok = s:ask("grisha", "Заперто. {p}Замок старый, ржавый...",
                    { "Вскрыть отмычкой", { "Выбить дверь плечом", check = { "strength", 9 } }, "Уйти" })
                if a == 3 then return end
                if a == 2 then
                    if not ok then
                        s:hurt(1)
                        s:say("grisha", "{shake}Ай!{/} Дверь крепче плеча. {p}Лучше отмычкой.")
                        return
                    end
                    s:say("grisha", "{shake}Бам!{/} {p}Петли не выдержали.")
                else
                    local r = s:play("lockpick", { goal = 1, lives = 3, level = 1 })
                    if not r.win then
                        s:say("grisha", "{shake}Хрусь!{/} Отмычки кончились. {p}Потом ещё попробую.")
                        return
                    end
                    s:say("grisha", "{wave}Щёлк!{/} Открыто.")
                end
                s:flag("dungeon_open", true)
                s:journalDone("dungeon")
            end
            s:go("dungeon", "iris")
        end,
        -- табличка у моста: проверка Смекалки по желанию игрока
        sign = function(s)
            s:say("sign", "«Мост в никуда. Вход платный: одна партия в тетрис.»")
            s:journal("bridge", "Пройти по мосту: сторож просит партию в тетрис")
            if s:once("sign_small_print") then
                local a, ok = s:ask("grisha", "Внизу что-то мелко нацарапано...",
                    { { "Разобрать надпись", check = { "wits", 8 } }, "Пройти мимо" })
                if a == 1 and ok then
                    s:say("grisha", "{accent}«С края моста клюёт лучше всего»{/}. {p}Запомню.")
                    s:learn("places", "bridge", "Мост в никуда", "Ведёт прямо в море. Сторож пускает за партию в тетрис, а с края отлично клюёт.")
                elseif a == 1 then
                    s:think("Буквы пляшут... {p}Ладно, не очень-то и хотелось.")
                end
            end
        end,
        -- ответ, для которого нужен предмет: без морковки он серый «(нужно: Морковь)»
        sacks = function(s)
            local offer = "Сыграем в мой покер? {p}На морковку!"
            if s:once("sacks_carrot") then
                s:say("grisha", "Мешки с мукой. {p}И... {accent}морковка{/}!")
                s:give("carrot", 1)
                local c = s:ask("bunny", "{wave}Морковка!{/} {p}Это мне?", {
                    { "Отдать Кашке", requires = "carrot", take = true, like = { "bunny", 1 },
                        remember = { "bunny", "carrot_gift", "Гриша отдал ей морковку из мешка" } },
                    "Оставлю себе",
                }, { id = "sacks_carrot" })
                if c == 1 then
                    s:say("bunny", "{rainbow}Хрум-хрум!{/} {p}Самая вкусная!")
                    s:journalDone("carrot")
                    offer = "А теперь... {p}сыграем в мой покер? На морковку!"
                else
                    s:like("bunny", -1)
                    offer = "{slow}Жадина.{/} {p}Тогда отыграю её в покер!"
                end
            else
                s:say("grisha", "Мешки с мукой.")
            end
            -- Кашка зовёт в свой покер (game/modes/cards.lua); prize — что дают за победу
            local a = s:ask("bunny", offer, { "Сыграем", "Потом" })
            if a == 1 then
                local r = s:play("cards", { level = 1, prize = { carrot = 2 } })
                if r.win then
                    s:say("bunny", "{wave}Ты выиграл!{/} Ладно, держи морковку...")
                else
                    s:say("bunny", "{rainbow}Ха-ха!{/} Морковка моя!")
                end
            end
        end,
        -- конец моста: «вход платный — одна партия в тетрис» (см. табличку sign в Tiled)
        test_trigger = function(s)
            if s:flag("bridge_paid") then
                -- с края моста клюёт: мини-игра «Рыбалка» (game/modes/fishing.lua), рыба идёт в сумку
                local a = s:ask("grisha", "За мостом только море... {p}Зато какой клёв! Порыбачить?",
                    { "Закинуть удочку", "Не сейчас" })
                if a == 1 then
                    local r = s:play("fishing", { goal = 2, level = 1 })
                    if r.win then
                        s:journalDone("fish")
                        -- последствия: Кашка помнит, как было в землетрясение
                        if s:remembers("bunny", "quake_left") then
                            s:say("bunny", "{wave}Рыбка!{/} {p}Хвостик мой. {p}Ты мне должен — за землетрясение.")
                        elseif s:affinity("bunny") >= 2 then
                            s:say("bunny", "{wave}Рыбка!{/} {p}Давай пополам — как друзья.")
                        else
                            s:say("bunny", "{wave}Рыбка!{/} {p}Чур, мне хвостик.")
                        end
                    else
                        s:say("grisha", "Сорвалась... {p}В другой раз.")
                    end
                end
                return
            end
            s:emote("grisha", "?")
            local a = s:ask("Сторож моста: «Хочешь пройти — сыграй партию в тетрис!»", { "Играть", "Не сейчас" })
            if a == 1 then
                local r = s:play("tetris")
                if r.win then
                    s:flag("bridge_paid", true)
                    s:journalDone("bridge")
                    s:journal("fish", "Порыбачить с края моста")
                    s:learn("people", "keeper", "Сторож моста", "Пускает на мост только тех, кто сыграет с ним в тетрис. Сам играет так себе.")
                    s:say("grisha", "{wave}Есть!{/} Три линии — и мост мой. {p}С края, наверное, отлично клюёт.")
                    s:give("coin", 5)
                else
                    s:say("grisha", "Эх... {shake}ещё разок{/} потом попробую.")
                end
            end
        end,
    },
}

-- Пещера: платформер
game.stage "cave" {
    kind = "platformer", map = "assets/maps/cave.tmx",
    triggers = { exit = { "island", spawn = "from_cave" } },
}

-- =====================================================================================
--  Подземелье: псевдо-3D (raycaster), бой от первого лица как в Daggerfall.
--  [W/S] шаг, [A/D] вбок, [Q/E] поворот, [F] дверь/действие, [Пробел] или тянуть мышью — удар,
--  [Shift]/правая кнопка — блок, [M] карта, [I] сумка (оружие из сумки видно в руке).
-- =====================================================================================
game.stage "dungeon" {
    kind = "raycaster", map = "assets/maps/dungeon.tmx", music = "calm",
    battle = "fight_dungeon",
    triggers = { exit = { "island", spawn = "from_dungeon", transition = "iris" } },
}

-- =====================================================================================
--  Луг: изометрическая карта с высотами (Tiled, isometric 32x16). Бои — прямо на карте,
--  как в Chrono Trigger: подойди к врагам — они окружат Гришу, заиграет боевая музыка.
--  [WASD]/стрелки — ходить, [Пробел] — удар (до 3 подряд), [Shift] — рывок,
--  [K] — бросить камень, [Q] — совместный приём с Кашкой, [E] — говорить/поднять.
--  Враг светится красным — сейчас ударит: ударь его в этот момент, чтобы отбить (парирование).
-- =====================================================================================
game.stage "meadow" {
    kind = "iso", map = "assets/maps/iso_meadow.tmx", music = "calm",
    battleMusic = "arcade",
    triggers = { exit = { "world", spawn = "meadow", transition = "iris" } },
}

-- бой из сценария на карте мира: проиграл или сбежал — Гриша приходит в себя на месте
local function worldFight(s, enemies)
    local r = s:battle(enemies)
    if r and r.win then
        return true
    end
    s:heal()
    if not (r and r.fled) then
        s:think("Уф... {p}Еле ноги унесли.")
    end
    return false
end

-- =====================================================================================
--  Карта мира в 3D (как в Final Fantasy VII-IX): маленькая круглая планета — уйдёшь за
--  восточный край, придёшь с западного. Карта рисуется в Tiled (assets/maps/world.tmx,
--  плитки assets/maps/world.tsx = земли из game/data/grounds.lua), здания — из
--  game/data/prefabs.lua. [WASD] идти, [Shift] бежать, [Q/E] камера, [V] вид, [M] карта,
--  [F] войти / сесть в лодку / сойти на берег. На опасных землях — случайные бои.
-- =====================================================================================
game.stage "world" {
    kind = "world", map = "assets/maps/world.tmx", music = "calm",
    battle = "fight_world",
    -- земля (encounter в grounds.lua) -> кто там водится
    encounters = {
        plains = { "blob_blue", "slime" },
        forest = { "frog", "beetle", "slime" },
        hills = { "blob_red", "beetle" },
        desert = { "crab", "beetle" },
        snow = { "ghost", "blob_blue" },
    },
    -- первый раз в большом мире
    script = function(s)
        if s:once("world_intro") then
            s:chapter("Глава 3. Большой мир")
            s:think("Горы, леса, дым из труб... {p}Мир куда больше нашего острова.")
            s:say("bunny", "Говорят, он {accent}круглый{/}! {p}Уйдёшь на восток — придёшь с запада.")
            s:learn("places", "world", "Большой мир",
                "Маленькая круглая планета: уйдёшь за край — придёшь с другой стороны. [M] — карта, [Q/E] — повернуть камеру.")
            s:journal("village", "Найти деревню Морковкино на южном берегу")
        end
    end,
    -- места на карте (Places в Tiled): имя -> что будет по [F]
    triggers = {
        island = { "island", spawn = "from_world" },
        meadow = { "meadow", spawn = "from_world", transition = "iris" },

        -- деревня: староста, задания и кости (game/modes/dice.lua)
        village = function(s)
            s:learn("places", "village", "Морковкино",
                "Деревня огородников на южном берегу. Староста — Дед Архип, лучший игрок в кости в округе.")
            s:journalDone("village")
            if s:once("village_hello") then
                s:say("elder", "Ишь ты, гости! {p}С острова, что ли? {p}Я Архип, староста Морковкина.")
                s:learn("people", "elder", "Дед Архип", "Староста Морковкина. Ворчит, но добрый. Обожает кости.")
                local a = s:ask("elder", "Слизни совсем распоясались: их король засел в замке на севере. {p}Поможешь старику?", {
                    { "Помогу!", like = { "bunny", 1 } },
                    "А что мне за это?",
                    "Мне бы морковки...",
                }, { id = "elder_help" })
                if a == 1 then
                    s:say("elder", "{wave}Вот молодец!{/} {p}Сходи на маяк, к Нилу: сверху он всё видит.")
                elseif a == 2 then
                    s:say("elder", "Хе! Деловой. {p}Обыграешь меня в кости — будут тебе монеты.")
                else
                    s:say("bunny", "{wave}Морковки!{/} {p}Да-да, морковки!")
                    s:say("elder", "Морковки у нас полдеревни. {p}Обыграешь в кости — получишь.")
                end
                s:journal("castle", "Разузнать, как попасть в Замок Короля Слизней")
                s:journal("lighthouse", "Поговорить со смотрителем маяка на северо-востоке")
            end
            local a = s:ask("elder", "Ну что, сыграем в кости? {p}До 1500 очков.",
                { "Сыграть в кости", "Расспросить о мире", "Уйти" })
            if a == 1 then
                local r = s:play("dice", { goal = 1500, opponent = "old", prize = { coin = 10, carrot = 1 } })
                if r.win then
                    s:say("elder", "Ну уважил старика! {p}Держи монеты. И морковку — для ушастой.")
                else
                    s:say("elder", "Хе-хе! Молод ещё. {p}Приходи отыгрываться.")
                end
            elseif a == 2 then
                s:say("elder", "На севере — замок Короля Слизней. {p}На западе — старая башня, там отшельник звёзды считает.")
                s:say("elder", "В горах — заброшенная шахта, на востоке — руины. {p}А на маяке живёт Нил, рыбак знатный.")
            end
        end,

        -- замок: ворота закрыты; проверки талантов и предмет в ответах
        castle = function(s)
            s:learn("places", "castle", "Замок Короля Слизней", "Серые стены на севере. Ворота заперты, на стене — стражник.")
            if s:once("castle_hello") then
                s:say("guard", "Стой! Кто идёт? {p}Король Слизней никого не принимает!")
                s:learn("people", "guard", "Стражник", "Охраняет ворота замка. Служит Королю Слизней за жалованье и очень любит морковку.")
            end
            local a, ok = s:ask("guard", "Чего надо?", {
                { "Уговорить открыть ворота", check = { "charm", 10 } },
                { "Выбить ворота", check = { "strength", 11 } },
                { "Угостить морковкой", requires = "carrot", take = true, hidden = s:flag("mine_tunnel") },
                "Уйти",
            })
            if a == 1 then
                if ok then
                    s:say("guard", "Эх... ладно, по секрету: {p}король {accent}боится воды{/}. {p}Но ворота не открою — приказ!")
                    s:flag("king_fears_water", true)
                    s:learn("monsters", "slime_king", "Король Слизней", "Засел в замке на севере. Стражник проболтался: боится воды.")
                else
                    s:say("guard", "Ишь, болтун! {p}Проваливай, пока цел.")
                end
            elseif a == 2 then
                if ok then
                    s:say("grisha", "{shake}БУМ!{/} {p}Ворота дрогнули...")
                    s:say("guard", "Тревога! {p}Слизни, к воротам!")
                    if worldFight(s, { "blob_red", "slime", "blob_red" }) then
                        s:think("Ворота держатся. {p}Силой их не взять — нужен другой путь.")
                    end
                else
                    s:hurt(1)
                    s:say("grisha", "{shake}Ай!{/} {p}Ворота крепче плеча.")
                end
            elseif a == 3 then
                s:say("guard", "Морковка? {p}{slow}Хрум.{/} {p}Слушай: в старой шахте есть ход прямо под замок.")
                s:flag("mine_tunnel", true)
                s:journalDone("castle")
                s:journal("mine", "Найти в заброшенной шахте ход под замок")
            end
        end,

        -- башня: отшельник и загадка (проверка Смекалки)
        tower = function(s)
            s:learn("places", "tower", "Старая башня", "Башня на западе, вся в плюще. Наверху живёт отшельник Фома и считает звёзды.")
            if s:flag("tower_riddle") then
                s:say("hermit", "Восемьсот сорок одна... восемьсот сорок две... {p}Не мешай, юноша.")
                return
            end
            if s:once("tower_hello") then
                s:say("hermit", "Тише, тише... {p}Я считаю звёзды. {p}Сбился. Опять сначала.")
                s:learn("people", "hermit", "Отшельник Фома", "Живёт в старой башне и третий год считает звёзды. Любит загадки.")
            end
            local a, ok = s:ask("hermit", "Отгадаешь загадку — дам кое-что. {p}Что круглое, а края у него нет?", {
                { "Подумать как следует", check = { "wits", 8 } },
                "Тарелка!",
                "Не знаю",
            })
            if a == 1 and ok then
                s:say("grisha", "Наш мир! {p}Уходишь за край — приходишь с другой стороны.")
                s:say("hermit", "{wave}Верно!{/} {p}Держи старую карту. Только не потеряй.")
                s:give("map", 1)
                s:talent("wits", 1)
                s:flag("tower_riddle", true)
            elseif a == 1 then
                s:think("Круглое без края... {p}Голова кругом.")
            elseif a == 2 then
                s:say("hermit", "У тарелки есть край, юноша. {p}Приходи, когда подумаешь.")
            end
        end,

        -- шахта: замок на двери («Взлом»), внутри — «Самоцветы»
        mine = function(s)
            s:learn("places", "mine", "Заброшенная шахта", "В горах. Вход заколочен, на двери — ржавый замок. Внутри, говорят, полно самоцветов.")
            if not s:flag("mine_open") then
                local a = s:ask("grisha", "Вход заколочен, на двери — ржавый замок.", { "Вскрыть замок", "Уйти" })
                if a ~= 1 then return end
                local r = s:play("lockpick", { goal = 1, lives = 3, level = 2 })
                if not r.win then
                    s:say("grisha", "{shake}Хрусь!{/} Не поддаётся. {p}Потом ещё попробую.")
                    return
                end
                s:flag("mine_open", true)
                s:say("grisha", "{wave}Щёлк!{/} {p}Темно... и что-то блестит.")
            end
            local a = s:ask("bunny", "Смотри, {rainbow}самоцветы{/}! {p}Накопаем?", { "Копать самоцветы", "Уйти" })
            if a == 1 then
                local r = s:play("match3", { goal = 1200, moves = 20, prize = { coin = 8 } })
                if r.win then
                    s:say("bunny", "{rainbow}Сколько блеска!{/} {p}Купим целый воз морковки!")
                    if s:flag("mine_tunnel") and s:once("mine_tunnel_found") then
                        s:say("grisha", "А вот и ход под замок... {p}{shake}завален{/}. Нужна кирка.")
                        s:journalDone("mine")
                        s:journal("pickaxe", "Раздобыть кирку и расчистить ход под замок")
                    end
                else
                    s:say("grisha", "Камни, камни... {p}Одни камни.")
                end
            end
        end,

        -- руины: призрак — уговорить (Обаяние) или драться
        ruins = function(s)
            s:learn("places", "ruins", "Древние руины", "Колонны и камни на востоке. Говорят, там бродит призрак.")
            if s:flag("ruins_clear") then
                local a, ok = s:ask("grisha", "На колонне — старые знаки.", { { "Разобрать знаки", check = { "wits", 9 } }, "Уйти" })
                if a == 1 and ok then
                    s:say("grisha", "{accent}«Кто уплывёт на восток, вернётся с запада»{/}. {p}Даже древние знали.")
                    s:learn("things", "runes", "Знаки на колонне", "«Кто уплывёт на восток, вернётся с запада». Древние знали, что мир круглый.")
                elseif a == 1 then
                    s:think("Закорючки... {p}Похоже на следы Кашки.")
                end
                return
            end
            s:say("ghost", "{wave}Уууу...{/} {p}Кто топчет мои камни?")
            local a, ok = s:ask("grisha", "Призрак! {p}Что делать?", {
                { "Заговорить с ним", check = { "charm", 9 } },
                "Драться!",
                "Уйти потихоньку",
            }, { id = "ruins_ghost" })
            if a == 3 then return end
            if a == 1 and ok then
                s:say("ghost", "Со мной... говорят? {p}Триста лет никто не говорил. {p}Возьми, это было моё.")
                s:give("ring", 1)
                s:like("bunny", 1)
            else
                if a == 1 then
                    s:say("ghost", "{shake}Уууу!{/} Не заговаривай мне зубы!")
                end
                if not worldFight(s, { "ghost", "ghost" }) then return end
                s:say("grisha", "Растаял... {p}А под камнем — монеты.")
                s:give("coin", 12)
            end
            s:flag("ruins_clear", true)
        end,

        -- маяк: смотритель, подсказки и «Рыбалка»
        lighthouse = function(s)
            s:learn("places", "lighthouse", "Маяк", "Белая башня на северо-восточном мысу. Светит кораблям — и лодке Гриши.")
            if s:once("lighthouse_hello") then
                s:say("keeper", "Открыто! {p}Заходи, не стой на ветру.")
                s:learn("people", "keeper", "Смотритель Нил", "Живёт на маяке, знает все течения и всех рыб. Сверху видит весь мир.")
                s:say("keeper", "Сверху видать: слизни ползут от замка во все стороны. {p}Король что-то затевает.")
                s:journalDone("lighthouse")
            end
            local a = s:ask("keeper", "Порыбачим с причала? {p}Поймаешь трёх — с меня награда.",
                { "Порыбачить", "Спросить про замок", "Уйти" })
            if a == 1 then
                local r = s:play("fishing", { goal = 3, level = 2, prize = { coin = 6 } })
                if r.win then
                    s:say("keeper", "Знатный улов! {p}Держи монеты. И заходи ещё.")
                else
                    s:say("keeper", "Ушла рыбка... {p}Тут терпение нужно.")
                end
            elseif a == 2 then
                if s:flag("king_fears_water") then
                    s:say("keeper", "Боится воды, говоришь? {p}Хе... Тогда лодка — твой лучший друг.")
                elseif s:flag("mine_tunnel") then
                    s:say("keeper", "Ход под замок? {p}Кирку спроси в Морковкине — там всё есть.")
                else
                    s:say("keeper", "Ворота там крепкие. {p}А у стражника, говорят, слабость — {accent}морковка{/}.")
                end
            end
        end,
    },
}

-- =====================================================================================
--  Пошаговые бои. sky = небо-сфера вокруг поля (day, meadow, sunset, night, forest,
--  snow, dungeon или своя таблица). [V] вид, [Q/E] поворот камеры.
-- =====================================================================================
game.stage "fight_day" { kind = "battle", enemies = { "blob_blue", "slime", "frog" }, sky = "day" }
game.stage "fight_sunset" { kind = "battle", enemies = { "slime", "frog" }, sky = "sunset" }
game.stage "fight_night" { kind = "battle", enemies = { "blob_red", "blob_blue" }, sky = "night" }
game.stage "fight_dungeon" { kind = "battle", enemies = { "blob_blue", "slime" }, sky = "dungeon" }
game.stage "fight_world" { kind = "battle", enemies = { "slime" }, sky = "day" } -- враги и небо — от земли

-- Мини-игра
game.stage "tetris" { kind = "tetris", goal = 3 }
