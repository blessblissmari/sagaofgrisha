-- F1 debug overlay: FPS, scene stack and any values a scene wants to show.
--
--   local dbg = require("engine.debug")
--   dbg.watch("player", string.format("%d, %d", player.x, player.y))  -- every frame
--   if dbg.enabled then world:drawDebug(camera) end

local dbg = { enabled = false }

local lines = {}

function dbg.toggle()
    dbg.enabled = not dbg.enabled
end

function dbg.watch(label, value)
    if dbg.enabled then
        table.insert(lines, label .. ": " .. tostring(value))
    end
end

function dbg.draw(sceneStack)
    if not dbg.enabled then
        lines = {}
        return
    end
    local lg = love.graphics
    local font = lg.getFont()
    local names = {}
    for _, s in ipairs(sceneStack or {}) do
        table.insert(names, s.name or "?")
    end
    local all = {
        string.format("FPS %d   %.1f MB", love.timer.getFPS(), collectgarbage("count") / 1024),
        "scenes: " .. table.concat(names, " > "),
    }
    for _, l in ipairs(lines) do
        table.insert(all, l)
    end
    local w = 0
    for _, l in ipairs(all) do
        w = math.max(w, font:getWidth(l))
    end
    lg.setColor(0, 0, 0, 0.65)
    lg.rectangle("fill", 4, 4, w + 12, #all * (font:getHeight() + 2) + 8)
    lg.setColor(0.6, 1, 0.6, 1)
    for i, l in ipairs(all) do
        lg.print(l, 10, 8 + (i - 1) * (font:getHeight() + 2))
    end
    lg.setColor(1, 1, 1, 1)
    lines = {}
end

return dbg
