-- Look of the whole UI in one place: fonts, colors, images and UI sounds.
-- The game can change anything here at start-up (see game/config.lua).

local assets = require("engine.assets")

local theme = {
    fonts = {
        -- pixel fonts are crisp only at multiples of their pixel grid:
        -- Tiny5 (8, 16, 24...), Press Start 2P (8, 16, 24...)
        body = { "assets/fonts/Tiny5.ttf", 24 },
        small = { "assets/fonts/Tiny5.ttf", 16 },
        title = { "assets/fonts/PressStart2P.ttf", 24 },
        pixel = { "assets/fonts/PressStart2P.ttf", 16 },
        tiny = { "assets/fonts/PressStart2P.ttf", 8 },
    },
    colors = {
        ink = { 0.23, 0.15, 0.08 },       -- text on parchment
        faded = { 0.47, 0.38, 0.25 },     -- disabled items, hints on parchment
        accent = { 0.62, 0.17, 0.11 },    -- names, the selected item
        light = { 1, 0.96, 0.86 },        -- text on dark backgrounds
        gold = { 1, 0.83, 0.33 },
        red = { 0.85, 0.22, 0.2 },
        green = { 0.35, 0.68, 0.3 },
        blue = { 0.32, 0.55, 0.92 },
        shadow = { 0, 0, 0, 0.55 },
        dim = { 0, 0, 0, 0.55 },          -- darkens the game behind menus
    },
    -- 9-slice panel: the border is stretched, the middle is tiled
    panel = { image = "assets/sprites/dilaoguebox.png", border = 3, scale = 2 },
    smallPanel = { image = "assets/sprites/dilaoguebox.png", border = 3, scale = 1 },
    images = {
        cursor = "assets/sprites/ui/arrow_right.png",
        cursorLeft = "assets/sprites/ui/arrow_left.png",
        next = "assets/sprites/ui/arrow_down.png",
        up = "assets/sprites/ui/arrow_up.png",
        scroll = "assets/sprites/ui/scroll.png",
        roll = "assets/sprites/ui/roll.png",
        button = "assets/sprites/ui/choice_idle.png",
        buttonActive = "assets/sprites/ui/choice_active.png",
        slot = "assets/sprites/ui/slot.png",
        slotSelected = "assets/sprites/ui/slot_selected.png",
        hearts = "assets/sprites/ui/hearts.png",
    },
    icons = "assets/sprites/icons/", -- ui.icon("carrot") -> icons/carrot.png
    -- names from game/data/sounds.lua
    sounds = {
        move = "ui_move", select = "ui_select", back = "ui_back",
        error = "ui_error", text = "ui_text", open = "ui_pause",
    },
    textSpeed = 45, -- letters per second in dialogues
}

function theme.font(name)
    local f = theme.fonts[name] or theme.fonts.body
    return assets.font(f[1], f[2])
end

function theme.image(name)
    return assets.image(theme.images[name] or name)
end

function theme.color(name)
    return theme.colors[name] or name
end

return theme
