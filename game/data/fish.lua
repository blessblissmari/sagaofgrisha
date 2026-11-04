-- Fish for the fishing mini-game (game/modes/fishing.lua). Pictures: pixel fish of "Sea World Pack"
-- by avodhel (CC0), 32x32 cells of assets/sprites/arcade/fish.png (5 in a row, all look right).
--   cell        number of the picture (1..17)
--   difficulty  how fast it moves in the bar (0..100)
--   behavior    "mixed", "smooth", "dart" (sudden jumps), "sinker" (likes the bottom), "floater" (the top)
--   rarity      chance weight (bigger = more often)
--   size        { min, max } in cm
--   points      score for a catch
return {
    silverfin = { cell = 1, name = "Серебрянка", difficulty = 15, behavior = "smooth", rarity = 30, size = { 12, 25 }, points = 40 },
    lionfish = { cell = 2, name = "Крылатка", difficulty = 70, behavior = "dart", rarity = 4, size = { 20, 38 }, points = 250 },
    perch = { cell = 3, name = "Морской окунь", difficulty = 30, behavior = "mixed", rarity = 22, size = { 18, 45 }, points = 70 },
    crucian = { cell = 4, name = "Карась", difficulty = 10, behavior = "smooth", rarity = 30, size = { 10, 30 }, points = 30 },
    parrot = { cell = 5, name = "Рыба-попугай", difficulty = 45, behavior = "floater", rarity = 12, size = { 25, 60 }, points = 120 },
    wrasse = { cell = 6, name = "Губан", difficulty = 35, behavior = "mixed", rarity = 18, size = { 15, 40 }, points = 80 },
    angel = { cell = 7, name = "Рыба-ангел", difficulty = 50, behavior = "smooth", rarity = 10, size = { 12, 30 }, points = 140 },
    butterfly = { cell = 8, name = "Рыба-бабочка", difficulty = 40, behavior = "dart", rarity = 12, size = { 10, 22 }, points = 110 },
    idol = { cell = 9, name = "Мавританский идол", difficulty = 75, behavior = "floater", rarity = 3, size = { 15, 25 }, points = 300 },
    scorpion = { cell = 10, name = "Скорпена", difficulty = 60, behavior = "sinker", rarity = 6, size = { 20, 50 }, points = 200 },
    swallow = { cell = 11, name = "Рыба-ласточка", difficulty = 25, behavior = "mixed", rarity = 20, size = { 10, 20 }, points = 60 },
    wrasse_pink = { cell = 12, name = "Розовый губан", difficulty = 30, behavior = "smooth", rarity = 16, size = { 12, 28 }, points = 70 },
    goby = { cell = 13, name = "Бычок", difficulty = 20, behavior = "sinker", rarity = 25, size = { 8, 20 }, points = 45 },
    emperor = { cell = 14, name = "Императорский ангел", difficulty = 85, behavior = "dart", rarity = 2, size = { 25, 40 }, points = 400 },
    porcupine = { cell = 15, name = "Иглобрюх", difficulty = 55, behavior = "sinker", rarity = 7, size = { 20, 50 }, points = 180 },
    puffer = { cell = 16, name = "Рыба-шар", difficulty = 45, behavior = "floater", rarity = 9, size = { 15, 35 }, points = 150 },
    fugu = { cell = 17, name = "Фугу", difficulty = 95, behavior = "mixed", rarity = 1, size = { 30, 60 }, points = 600 },
}
