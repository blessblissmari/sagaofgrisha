local game = require("game")
game.title = "Сага о Грише"
game.start = "island"
game.player.party = { "bunny" }
game.player.items = { stone = 3 }
game.stage "menu" { kind = "title", background = "mountains", music = "calm", subtitle = "тест", newGame = "island" }
game.stage "island" { kind = "topdown", map = "assets/maps/island.tmx",
    triggers = {
        test_trigger = function(s)
            local a = s:ask("Вы согласны или нет?", { "Да", "Нет" })
            s:say("grisha", a == 1 and "Да!" or "Нет!")
        end,
    } }
game.stage "fight" { kind = "battle", enemies = { "blob_blue", "slime", "frog" }, next = "island" }
game.stage "tetris_test" { kind = "tetris", goal = 3, next = "island" }
game.stage "cave" { kind = "platformer", map = "assets/maps/cave.tmx",
    triggers = { exit = { "island", spawn = "from_cave" } } }
