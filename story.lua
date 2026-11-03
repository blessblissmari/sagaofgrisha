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
            { "Бой: день", play = "fight_day" },
            { "Бой: закат", play = "fight_sunset" },
            { "Бой: ночь", play = "fight_night" },
            { "Тетрис", play = "tetris" },
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
        s:title("Глава 1", "Лес у моря")
        s:show("grisha", { at = "left" })
        s:show("bunny", { at = "right" })
        s:say("grisha", "Привет, {accent}Кашка{/}! {wave}Смотри, какой лес!{/} Тут {shake}страшновато{/}...")
        s:emotion("bunny", "joy")
        s:say("bunny", "Ура!{@hop} Я так рада!{p} {rainbow}Пойдём искать морковку!{/}")
        s:emotion("grisha", "anger")
        s:say("grisha", "{@shake}Что?! Опять морковка?!")
        s:emote("bunny", "sweat")
        local a = s:ask("bunny", "Ну пожалуйста... Пойдём?", { "Да, пойдём", "Нет", "Может быть" })
        if a == 1 then
            s:closeup("bunny")
            s:emotion("bunny", "love")
            s:say("bunny", "Спасибо!{@hop} Ты лучший!")
            s:closeup()
        elseif a == 2 then
            s:emotion("bunny", "sad")
            s:say("bunny", "{slow}Ну и ладно...{/}")
            s:emotion("grisha", "sweat")
            s:say("grisha", "Ладно-ладно, пойдём!")
        else
            s:emotion("grisha", "think")
            s:say("grisha", "Хм... {p=1}Ну, может быть.")
        end
        s:bg("cliffs", "starwars")
        s:say(nil, "{slow}Тем временем у моря...{/}")
        s:emotion("grisha", "surprise")
        s:quake()
        s:say("grisha", "{@shake}Земля трясётся!")
        s:emotion("bunny", "fear")
        s:say("bunny", "Бежим на остров!")
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
    triggers = {
        cave = { "cave" },
        dungeon = { "dungeon", transition = "iris" },
        sacks = function(s)
            s:say("grisha", "Мешки с мукой. {p}И... {accent}морковка{/}!")
            if s:once("sacks_carrot") then
                s:give("carrot", 1)
            end
        end,
        -- конец моста: «вход платный — одна партия в тетрис» (см. табличку sign в Tiled)
        test_trigger = function(s)
            if s:flag("bridge_paid") then
                s:say("grisha", "За мостом только море... {p}Пока что.")
                return
            end
            s:emote("grisha", "?")
            local a = s:ask("Сторож моста: «Хочешь пройти — сыграй партию в тетрис!»", { "Играть", "Не сейчас" })
            if a == 1 then
                local r = s:play("tetris")
                if r.win then
                    s:flag("bridge_paid", true)
                    s:say("grisha", "{wave}Есть!{/} Три линии — и мост мой.")
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
    triggers = { exit = { "menu", transition = "iris" } },
}

-- =====================================================================================
--  Пошаговые бои. sky = небо-сфера вокруг поля (day, meadow, sunset, night, forest,
--  snow, dungeon или своя таблица). [V] вид, [Q/E] поворот камеры.
-- =====================================================================================
game.stage "fight_day" { kind = "battle", enemies = { "blob_blue", "slime", "frog" }, sky = "day" }
game.stage "fight_sunset" { kind = "battle", enemies = { "slime", "frog" }, sky = "sunset" }
game.stage "fight_night" { kind = "battle", enemies = { "blob_red", "blob_blue" }, sky = "night" }
game.stage "fight_dungeon" { kind = "battle", enemies = { "blob_blue", "slime" }, sky = "dungeon" }

-- Мини-игра
game.stage "tetris" { kind = "tetris", goal = 3 }
