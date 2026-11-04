-- Game settings: screen, keys, sounds. Change keys here, not in the code:
-- the game asks for ACTIONS (input.pressed("attack")), never for keys.

local web = love.system and love.system.getOS() == "Web"

return {
    -- the window title comes from story.lua (game.title)
    width = 960,          -- virtual resolution, scaled to the window
    height = 540,
    pixelPerfect = false, -- true: only integer scaling

    -- Keys that work everywhere: menus, dialogues, the system.
    -- Every kind of gameplay has its own keymap below (keymaps.topdown, keymaps.battle...),
    -- story.lua can change any of them: game.controls.raycaster.map = { "m", "tab" }
    -- or one stage only: game.stage "boss" { kind = "battle", controls = { parry = { "f" } } }
    keys = {
        up = { "up", "w" },
        down = { "down", "s" },
        left = { "left", "a" },
        right = { "right", "d" },
        confirm = { "return", "space", "kpenter" },
        cancel = { "escape", "backspace", "x" },
        -- in the browser [Esc] also leaves the full screen, so [P] comes first there
        pause = web and { "p", "escape" } or { "escape", "p" },
        inventory = { "i", "tab" },
        journal = { "n" },              -- tasks, decisions, relations, the encyclopedia
        skip = { "lctrl", "rctrl" },    -- hold to fast-forward dialogues
        debug = { "f1" },
        fullscreen = { "f11" },
    },

    -- Default keymap of every kind of gameplay (the stage kind). Actions missing here
    -- come from `keys` above.
    keymaps = {
        -- menus, the bag, the pause screen (everything without its own keymap)
        menu = {
            tabLeft = { "q", "pageup" },    -- tabs of the bag
            tabRight = { "e", "pagedown" },
            interact = { "f" },
        },
        -- the world from above
        topdown = {
            interact = { "e", "f" },        -- talk, pick up, use
            attack = { "space", "j" },
            throw = { "k" },                -- throw a stone
            run = { "lshift", "rshift" },
        },
        -- the side view
        iso = {                             -- isometric field with real-time fights
            interact = { "e", "f" },
            attack = { "space", "j" },
            dash = { "lshift", "rshift", "l" }, -- quick dodge (no damage while dashing)
            throw = { "k" },
            tech = { "q" },                 -- the duo tech with the pet (the bar is full)
        },
        platformer = {
            jump = { "space", "z", "w", "up" },
            dash = { "lshift", "rshift", "c" },
            punch = { "j", "x" },
            throw = { "k" },
            interact = { "e", "f" },
        },
        -- the first-person dungeon (Daggerfall style)
        raycaster = {
            forward = { "up", "w" },
            back = { "down", "s" },
            turnLeft = { "left", "q" },
            turnRight = { "right", "e" },
            strafeLeft = { "a" },
            strafeRight = { "d" },
            use = { "f", "return" },        -- open doors, talk, pick up
            attack = { "space" },           -- or drag the mouse
            block = { "lshift", "rshift" }, -- hold (or the right mouse button)
            map = { "m" },
        },
        -- turn-based battles
        battle = {
            attack = { "space", "return" }, -- timed hits: press when the ring closes
            parry = { "space", "return" },  -- when an enemy hits: press right before the blow
            dodge = { "lshift", "rshift" }, -- jump away from a blow
            view = { "v" },                 -- top-down <-> isometric
            camLeft = { "q" },
            camRight = { "e" },
            fast = { "lctrl", "rctrl" },    -- hold: everything twice as fast
        },
        -- visual novel
        novel = {
            skip = { "lctrl", "rctrl" },
            log = { "l" },                  -- what was said before
            auto = { "a" },                 -- turn the pages by itself
        },
        -- mini-games
        tetris = {
            rotateCW = { "up", "w", "x" },
            rotateCCW = { "z", "q" },
            hardDrop = { "space" },
            hold = { "c", "lshift" },
        },
        arcade = {                          -- breakout, snake, xonix, shooter...
            fire = { "space", "z", "j" },
            action = { "x", "k" },
            focus = { "lshift", "rshift" },  -- the shooter: slow and precise flight
        },
        puzzle = {                          -- puyo, match-3, memory, cards...
            rotateCW = { "x", "up", "w" },
            rotateCCW = { "z", "q" },
            drop = { "space" },
            select = { "space", "return" },
        },
        cards = {                           -- the card game (Balatro style)
            select = { "space", "up", "w" },  -- take / put back the card under the cursor
            play = { "return" },
            discard = { "x", "backspace" },
            sort = { "c", "tab" },          -- by rank / by suit
        },
        dice = {                            -- the dice game (Farkle, Kingdom Come style)
            pick = { "space", "up", "w" },  -- take / put back the die under the cursor
            roll = { "return", "r" },       -- throw the other dice
            bank = { "x", "b" },            -- write the points down and pass the turn
        },
        fishing = {
            reel = { "space", "j", "return" }, -- hold to raise the bar
        },
        tactics = {                         -- the hex battle (Heroes of Might and Magic style)
            wait = { "q" },                 -- move at the end of the round
            defend = { "e" },
            spell = { "c", "b" },           -- Гриша's spell book
            cycle = { "tab" },              -- another side of the enemy to attack from
        },
        rhythm = {
            laneLeft = { "left", "a" },
            laneDown = { "down", "s" },
            laneUp = { "up", "w" },
            laneRight = { "right", "d" },
        },
    },

    pad = {
        up = { "dpup" }, down = { "dpdown" }, left = { "dpleft" }, right = { "dpright" },
        confirm = { "a" }, cancel = { "b" }, interact = { "a" }, attack = { "x" },
        throw = { "y" }, dash = { "leftshoulder" }, tech = { "rightshoulder" }, pause = { "start" }, inventory = { "back" }, view = { "rightstick" },
        camLeft = { "leftshoulder" }, camRight = { "rightshoulder" },
        rotateCW = { "a" }, rotateCCW = { "b" }, hardDrop = { "dpup" }, hold = { "rightshoulder" },
        jump = { "a" }, dash = { "rightshoulder" }, punch = { "x" },
        turnLeft = { "leftshoulder" }, turnRight = { "rightshoulder" },
        use = { "a" }, block = { "y" }, map = { "leftstick" },
        skip = { "leftshoulder" },
        fire = { "a", "rightshoulder" }, action = { "x" }, focus = { "leftshoulder" }, reel = { "a" },
        select = { "a" }, play = { "x" }, discard = { "y" }, sort = { "back" },
        pick = { "a" }, roll = { "x" }, bank = { "y" },
        wait = { "x" }, defend = { "y" }, spell = { "rightshoulder" }, cycle = { "leftshoulder" },
        laneLeft = { "dpleft", "x" }, laneDown = { "dpdown", "a" }, laneUp = { "dpup", "y" }, laneRight = { "dpright", "b" },
    },

    musicVolume = 0.7,
    sfxVolume = 1,
    storyFolder = "game.story.",
}
