-- Game settings: screen, keys, sounds. Change keys here, not in the code:
-- the game asks for ACTIONS (input.pressed("attack")), never for keys.

return {
    -- the window title comes from story.lua (game.title)
    width = 960,          -- virtual resolution, scaled to the window
    height = 540,
    pixelPerfect = false, -- true: only integer scaling

    keys = {
        up = { "up", "w" },
        down = { "down", "s" },
        left = { "left", "a" },
        right = { "right", "d" },
        confirm = { "return", "space", "kpenter" },
        cancel = { "escape", "backspace", "x" },
        interact = { "e", "f" },        -- talk, pick up (also turns dialogue pages)
        attack = { "space", "j" },
        throw = { "k" },                -- throw a stone in the world
        pause = { "escape", "p" },
        inventory = { "i", "tab" },
        -- platformer
        jump = { "space", "z", "w", "up" },
        dash = { "lshift", "rshift", "c" },
        punch = { "j", "x" },
        -- raycaster (forward / back are up / down)
        turnLeft = { "left", "q" },
        turnRight = { "right" },
        strafeLeft = { "a" },
        strafeRight = { "d" },
        -- battle camera
        view = { "v" },                 -- top-down <-> isometric
        camLeft = { "q" },
        camRight = { "e" },
        -- tetris
        rotateCW = { "up", "w", "x" },
        rotateCCW = { "z", "q" },
        hardDrop = { "space" },
        hold = { "c", "lshift" },
        -- novel
        skip = { "lctrl", "rctrl" },    -- hold to fast-forward
        -- system
        debug = { "f1" },
        fullscreen = { "f11" },
    },

    pad = {
        up = { "dpup" }, down = { "dpdown" }, left = { "dpleft" }, right = { "dpright" },
        confirm = { "a" }, cancel = { "b" }, interact = { "a" }, attack = { "x" },
        throw = { "y" }, pause = { "start" }, inventory = { "back" }, view = { "rightstick" },
        camLeft = { "leftshoulder" }, camRight = { "rightshoulder" },
        rotateCW = { "a" }, rotateCCW = { "b" }, hardDrop = { "dpup" }, hold = { "rightshoulder" },
        jump = { "a" }, dash = { "rightshoulder" }, punch = { "x" },
        turnLeft = { "leftshoulder" }, turnRight = { "rightshoulder" },
        skip = { "leftshoulder" },
    },

    musicVolume = 0.7,
    sfxVolume = 1,
    storyFolder = "game.story.",
}
