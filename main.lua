-- Сага о Грише
--
-- The game is described in story.lua (stages, dialogues, items, mobs...).
-- The engine lives in engine/, the gameplay of every stage kind in game/modes/.
-- See README.md.

local engine = require("engine")
local game = require("game")

require("story")

function love.load()
    game.boot(require("game.config"))
end

engine.hook()
