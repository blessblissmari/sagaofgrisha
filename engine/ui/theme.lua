-- Look of the whole UI in one place: fonts, colors, windows, images, sounds.
-- Two ready styles ("presets"):
--   "ff"        Final Fantasy-like: blue gradient windows with a light frame,
--               white text with a shadow, a hand cursor (default)
--   "parchment" paper windows from the Pixel Parchment UI kit
-- In story.lua:  game.ui = "parchment"   or tweak single fields:
--   game.ui = { preset = "ff", window = { colors = { "#305090", "#203070", "#101850", "#080830" } } }

local assets = require("engine.assets")

local ARK = "assets/fonts/ArkPixel10.ttf"     -- 10 px grid: crisp at 10, 20, 30, 40
local TINY5 = "assets/fonts/Tiny5.ttf"        -- 8 px grid
local PRESS = "assets/fonts/PressStart2P.ttf" -- 8 px grid

local theme = {}

theme.presets = {
    ff = {
        fonts = {
            body = { ARK, 30 },    -- dialogues, menus
            small = { ARK, 20 },   -- hints, HUD, descriptions
            title = { PRESS, 32 }, -- big titles
            pixel = { PRESS, 16 },
            tiny = { PRESS, 8 },   -- numbers flying in the world
            dialog = { ARK, 30 },
        },
        colors = {
            ink = { 1, 1, 1 },                -- text in windows
            faded = { 0.58, 0.62, 0.78 },     -- disabled items, hints
            accent = { 1, 0.88, 0.45 },       -- names, the selected item
            light = { 1, 1, 1 },              -- text over the game
            gold = { 1, 0.84, 0.34 },
            red = { 1, 0.42, 0.38 },
            green = { 0.5, 0.92, 0.45 },
            blue = { 0.5, 0.75, 1 },
            shadow = { 0.02, 0.02, 0.1, 0.85 },
            dim = { 0, 0, 0.05, 0.55 },
            barFrame = { 0.02, 0.03, 0.12, 0.95 },
            barBack = { 0.1, 0.12, 0.3, 1 },
        },
        textShadow = true, -- every text gets a 1-pixel shadow (like in FF)
        -- windows are drawn by code: 4 corner colors (top-left, top-right,
        -- bottom-left, bottom-right) like the window color setting in FF7
        window = {
            kind = "window", radius = 6,
            colors = { { 0.24, 0.33, 0.78 }, { 0.17, 0.24, 0.66 }, { 0.07, 0.09, 0.36 }, { 0.03, 0.04, 0.22 } },
            border = { 0.93, 0.94, 1 }, edge = { 0.02, 0.02, 0.08 }, alpha = 0.95,
        },
        smallWindow = {
            kind = "window", radius = 4,
            colors = { { 0.24, 0.33, 0.78 }, { 0.17, 0.24, 0.66 }, { 0.07, 0.09, 0.36 }, { 0.03, 0.04, 0.22 } },
            border = { 0.85, 0.87, 0.95 }, edge = { 0.02, 0.02, 0.08 }, alpha = 0.92,
        },
        -- highlighted window (the chosen answer, the selected slot)
        activeWindow = {
            kind = "window", radius = 4,
            colors = { { 0.38, 0.5, 0.95 }, { 0.3, 0.42, 0.88 }, { 0.12, 0.16, 0.52 }, { 0.08, 0.1, 0.4 } },
            border = { 1, 0.95, 0.7 }, edge = { 0.02, 0.02, 0.08 }, alpha = 0.97,
        },
        images = {
            cursor = "assets/sprites/ui/hand.png", -- "Hand cursor" by andreyin (CC0)
            hearts = "assets/sprites/ui/hearts.png",
        },
        choiceStyle = "window", -- answers inside the dialogue window, with the hand cursor
        nameTint = 0.6,         -- character name colors are mixed with white
        menuSpacing = 1.12,     -- line height of menus (x font height)
        cursorScale = 1,
    },
    parchment = {
        fonts = {
            body = { TINY5, 24 },
            small = { TINY5, 16 },
            title = { PRESS, 24 },
            pixel = { PRESS, 16 },
            tiny = { PRESS, 8 },
            dialog = { TINY5, 24 },
        },
        colors = {
            ink = { 0.23, 0.15, 0.08 },
            faded = { 0.47, 0.38, 0.25 },
            accent = { 0.62, 0.17, 0.11 },
            light = { 1, 0.96, 0.86 },
            gold = { 1, 0.83, 0.33 },
            red = { 0.85, 0.22, 0.2 },
            green = { 0.35, 0.68, 0.3 },
            blue = { 0.32, 0.55, 0.92 },
            shadow = { 0, 0, 0, 0.55 },
            dim = { 0, 0, 0, 0.55 },
            barFrame = { 0.1, 0.07, 0.05, 0.9 },
            barBack = { 0.3, 0.22, 0.15, 1 },
        },
        textShadow = false,
        -- 9-slice image: the border is stretched, the middle is tiled
        window = { image = "assets/sprites/dilaoguebox.png", border = 3, scale = 2 },
        smallWindow = { image = "assets/sprites/dilaoguebox.png", border = 3, scale = 1 },
        activeWindow = { image = "assets/sprites/dilaoguebox.png", border = 3, scale = 1 },
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
        choiceStyle = "buttons",
        nameTint = 0,
        menuSpacing = 1.4,
        cursorScale = 0.75,
    },
}

theme.icons = "assets/sprites/icons/" -- ui.icon("carrot") -> icons/carrot.png
-- names from game/data/sounds.lua
theme.sounds = {
    move = "ui_move", select = "ui_select", back = "ui_back",
    error = "ui_error", text = "ui_text", open = "ui_pause",
}
theme.textSpeed = 45 -- letters per second in dialogues
theme.narratorVoice = "narrator" -- voice of text without a speaker (engine/voice.lua), false = silent

local function copy(t)
    if type(t) ~= "table" then
        return t
    end
    local r = {}
    for k, v in pairs(t) do
        r[k] = copy(v)
    end
    return r
end

local function merge(into, from)
    for k, v in pairs(from) do
        if type(v) == "table" and type(into[k]) == "table" and not v[1] then
            merge(into[k], v)
        else
            into[k] = copy(v)
        end
    end
end

-- theme.use("ff") / theme.use("parchment") / theme.use({ preset = "ff", colors = { ... } })
function theme.use(style)
    if type(style) == "string" then
        style = { preset = style }
    end
    style = style or {}
    local preset = theme.presets[style.preset or "ff"] or theme.presets.ff
    for k in pairs(theme.presets.ff) do
        theme[k] = nil
    end
    merge(theme, copy(preset))
    local extra = copy(style)
    extra.preset = nil
    merge(theme, extra)
    -- old names
    theme.panel = theme.window
    theme.smallPanel = theme.smallWindow
    theme.name = style.preset or "ff"
end

function theme.font(name)
    local f = theme.fonts[name] or theme.fonts.body
    return assets.font(f[1], f[2])
end

function theme.image(name)
    local path = theme.images[name]
    if not path then
        return nil
    end
    return assets.image(path)
end

function theme.color(name)
    return theme.colors[name] or name
end

-- color of a character's name on the name plate
function theme.nameColor(color)
    local c = color or theme.colors.accent
    local k = theme.nameTint or 0
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k, 1 }
end

-- 1 font pixel: shadows and outlines of pixel fonts
function theme.pixelOf(font)
    return math.max(1, math.floor(font:getHeight() / 14))
end

theme.use("ff")

return theme
