# Сага о Грише

Пиксельная RPG на [LÖVE 11](https://love2d.org): визуальная новелла, остров с видом сверху,
подземелье в духе Daggerfall (псевдо-3D), бои с небесной сферой, платформер и мини-игры.

**Играть в браузере:** https://blessblissmari.github.io/sagaofgrisha/
(первая загрузка ~20 МБ; нажмите на экран, чтобы включился звук)

## Запуск на компьютере

1. Установите LÖVE 11.4 или 11.5 — https://love2d.org
2. В папке проекта: `love .` (или перетащите папку на `love.exe`)

## Управление

| Где | Клавиши |
| --- | --- |
| Везде | стрелки / WASD — ходить и выбирать, Enter / Пробел — ОК, Esc / X — назад, F11 — весь экран |
| Остров | E / F — говорить и подбирать, Пробел / J — удар, K — бросить камень, I / Tab — сумка |
| Подземелье | ↑↓ — вперёд/назад, ← → / Q E — поворот, A D — шаг вбок, F / Enter — открыть дверь, Пробел или протянуть мышью — удар, Shift / правая кнопка мыши — блок, M — карта |
| Бой | V — вид сверху / изометрия, Q E — вращать камеру |
| Пещера | Пробел / Z — прыжок, Shift / C — рывок, J — удар, K — камень |

## Где что лежит

- `story.lua` — весь сюжет: этапы (`game.stage`), диалоги, выборы, бои, голоса героев, фоны и небо.
  Чтобы менять игру, обычно достаточно этого файла — подробные подсказки прямо в нём.
- `game/` — режимы (`modes/`: novel, topdown, raycaster, battle, platformer, tetris, title) и данные
  (`data/`: персонажи, предметы, фоны, небо, монстры).
- `engine/` — движок: сцены и переходы, UI в стиле Final Fantasy, ввод, звук, сохранения, небесная сфера.
- `assets/` — графика, звук, шрифты и шейдеры (`shaders/transitions/` — переходы между сценами).

## Карты в Tiled

Карты — обычные файлы [Tiled](https://www.mapeditor.org) (1.10 и новее), игра читает `.tmx` напрямую.

1. Откройте проект `assets/maps/SagaOfGrisha.tiled-project` (File → Open File or Project).
2. Возьмите заготовку из `assets/maps/templates/` и сохраните её под новым именем (File → Save As):

   | Заготовка | Режим (`kind`) | Тайлы | Слои |
   | --- | --- | --- | --- |
   | `topdown.tmx` | `topdown` — вид сверху, как остров | 32×32 | Ground, Buildings, Above (поверх героя) + Triggers, Spawns, Items, Mobs, NPCs |
   | `platformer.tmx` | `platformer` — как пещера | 16×16 | Back, Ground + Triggers, Spawns, Items, Mobs, Gates |
   | `dungeon.tmx` | `raycaster` — подземелье от первого лица | 64×64 | Walls (тайл = текстура стены, пусто = пол) + Spawns, Items, Mobs, Triggers |
   | `iso.tmx` | `iso` — изометрия с высотами, как луг | 32×16 | floor, level1, level2… (Vertical offset = −16 × уровень) + Spawns, Mobs, Items, NPC, Triggers |

3. Объекты ставьте **шаблонами** (панель Project → `templates/`, перетащить на карту):
   `items/` — предметы, `mobs/` — монстры, `npcs/` — персонажи (в Tiled видна их картинка),
   `objects/` — появление героя (`spawn_player`), выход (`exit`), зоны с текстом (`look`, `dialogue_once`), ворота (`gate`).
4. У объектов, тайлов и карт есть классы со свойствами и выпадающими списками:
   `Trigger` (dialogue, go, spawn, transition, interact, prompt, once, requires, sound, finish), `Item`, `Mob`
   (group — монстры одной группы дерутся вместе), `NPC`, `Spawn`, `Gate`; тайлы — `Tile`, `Wall`, `IsoTile`;
   класс карты (Map → Map Properties → Class) — это режим игры.
   Текст диалога пишется прямо в свойстве: `Гриша: Привет! | Кашка: Мяу` (реплики через `|`).
5. **F5** в Tiled (команда «Играть карту (LÖVE)», нужен `love` в PATH; путь меняется в File → Commands)
   или `love . --map=assets/maps/templates/topdown.tmx` — сразу сыграть карту.
6. Подключите карту к сюжету в `story.lua`: `game.stage "my_level" { kind = "topdown", map = "assets/maps/my_level.tmx" }`.
7. Добавили предметы, монстров, спрайты или этапы — обновите списки и шаблоны: `love . --tiled`.

## Веб-версия

После каждого пуша в `main` GitHub Actions (`.github/workflows/pages.yml`) собирает игру через
[love.js](https://github.com/Davidobot/love.js) и выкладывает на GitHub Pages. Страница-обёртка — `web/index.html`.

## Авторы графики и звука

Все ассеты — с [OpenGameArt.org](https://opengameart.org) и других свободных источников;
полный список авторов и лицензий будет в `CREDITS.md`.
