-- HUD of the real-time stages: hearts, coins, keys and the action hint.

local engine = require("engine")
local input = engine.input
local screen = engine.screen
local ui = engine.ui

local function G()
    return require("game")
end

local hud = {}

-- the key hints are shown only for a few seconds after a stage starts (and while
-- the game stands still for a long time), so they don't hang on the screen forever
local hint = { text = nil, owner = nil, since = 0, idle = 0 }
hud.HINT_TIME = 7

-- alpha of a hint line: 1 in the first seconds, then it fades out
function hud.hintAlpha(text, owner)
    local now = love.timer.getTime()
    if hint.text ~= text or hint.owner ~= owner then
        hint.text, hint.owner, hint.since = text, owner, now
    end
    local age = now - hint.since
    return math.max(0, math.min(1, hud.HINT_TIME - age))
end

-- show the hints again (after the pause menu, for example)
function hud.showHints()
    hint.since = love.timer.getTime()
end

-- opts: prompt (text for the interact key), hint (bottom line), coins (default true)
function hud.draw(opts)
    opts = opts or {}
    local st = G().state
    ui.hearts(16, 14, st.hp, st.maxHp, 0.75)
    local y = 46
    local coins = st.inventory:count("coin")
    if coins > 0 or opts.coins then
        ui.icon("coin", 14, y - 4, 0.75)
        ui.print(coins, 46, y, { font = "small", color = "light", shadow = true })
        y = y + 28
    end
    local keys = st.inventory:count("key")
    if keys > 0 then
        ui.icon("key", 14, y - 4, 0.75)
        ui.print(keys, 46, y, { font = "small", color = "light", shadow = true })
    end
    if opts.prompt then
        ui.keyHint(screen.width / 2, screen.height - 46, opts.promptAction or "interact", opts.prompt)
    end
    if opts.hint then
        local a = hud.hintAlpha(opts.hint, opts.owner)
        if a > 0 then
            ui.print(opts.hint, screen.width - 14, screen.height - 26,
                { font = "small", align = "right", color = "light", shadow = true, alpha = 0.8 * a })
        end
    end
end

-- "[Esc] пауза  [I] сумка" in the corner
function hud.keys(list)
    local parts = {}
    for _, pair in ipairs(list) do
        table.insert(parts, "[" .. input.keyName(pair[1]) .. "] " .. pair[2])
    end
    return table.concat(parts, "   ")
end

return hud
