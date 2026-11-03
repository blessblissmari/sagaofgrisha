-- Scene stack: title, world, battle, dialogue overlay, pause menu...
--
-- A scene is any table with optional methods:
--   scene:load()            once, before the first enter
--   scene:enter(...)        when it becomes active (switch / push)
--   scene:leave()           when it is removed
--   scene:pause()           another scene was pushed on top of it
--   scene:resume(...)       the scene on top was popped (gets pop's arguments)
--   scene:update(dt), scene:draw()
--   scene:keypressed(key), scene:textinput(text), scene:mousepressed(x, y, button)
-- and optional fields:
--   scene.transparent = true   scenes below are drawn too (overlays)
--   scene.effects = { "crt" }  post effect shaders while this scene is shown
--
--   scene.switch(s, ...)  replace the top scene
--   scene.push(s, ...)    open s on top (the old one is paused)
--   scene.pop(...)        close the top scene, the one below resumes with ...
--   scene.clear(s, ...)   remove everything and start s
--   scene.transition(fn, kind, opts)  cover the screen (fade, swirl...), call fn, uncover
--   scene.fadeSwitch / fadePush / fadePop - the same with a plain fade

local input = require("engine.input")
local shaders = require("engine.shaders")
local screen = require("engine.screen")

local scene = { stack = {} }

local stack = scene.stack
local loaded = setmetatable({}, { __mode = "k" })
local transition = nil
local snapshot = nil -- the old screen of a reveal transition

local function call(s, name, ...)
    if s and s[name] then
        return s[name](s, ...)
    end
end

local function activate(s, ...)
    assert(type(s) == "table", "scene: a scene must be a table")
    if not loaded[s] then
        loaded[s] = true
        call(s, "load")
    end
    table.insert(stack, s)
    call(s, "enter", ...)
end

function scene.top()
    return stack[#stack]
end

function scene.has(s)
    for _, v in ipairs(stack) do
        if v == s then
            return true
        end
    end
    return false
end

function scene.switch(s, ...)
    local old = table.remove(stack)
    call(old, "leave")
    activate(s, ...)
end

function scene.push(s, ...)
    call(scene.top(), "pause")
    activate(s, ...)
end

function scene.pop(...)
    local old = table.remove(stack)
    call(old, "leave")
    call(scene.top(), "resume", ...)
end

function scene.clear(s, ...)
    while #stack > 0 do
        call(table.remove(stack), "leave")
    end
    activate(s, ...)
end

-- transitions ---------------------------------------------------------------
--
--   scene.transition(fn, "swirl")         cover the screen, call fn, uncover
--   scene.transition(fn, "circle", { duration = 1, center = { x, y }, color = { 1, 1, 1 } })
--
-- Cover kinds (the screen is covered, the scene changes, the screen opens):
--   fade (default), pixel, swirl, wipe, circle, dissolve, blinds, wave, diamond,
--   battle, flash. Each kind except "fade" is a shader in
--   assets/shaders/transitions/<kind>.glsl that gets
--     progress  0 (scene visible) .. 1 (screen covered)
--     phase     0 while covering, 1 while uncovering
--     color, center (0..1), screenSize, time
-- Reveal kinds (the old picture is kept and the new scene appears through it):
--   page (book page turn), starwars (soft line wipe), clock, iris, crossfade, slide.
--   Their shaders get progress 0 (old) .. 1 (new), `previous` (the old screen),
--   direction, center, softness:
--   scene.transition(fn, "starwars", { direction = { 0, 1 }, softness = 0.2 })
-- A new transition is just a new .glsl file plus a line in scene.transitions.

scene.transitions = {
    fade = { duration = 0.6 },
    pixel = { duration = 0.9 },
    swirl = { duration = 1.3 },
    wipe = { duration = 0.8 },
    circle = { duration = 1.0 },
    dissolve = { duration = 1.0 },
    blinds = { duration = 0.9 },
    wave = { duration = 1.1 },
    diamond = { duration = 1.0 },
    battle = { duration = 1.4 },
    flash = { duration = 0.6, color = { 1, 1, 1 } },
    -- reveal transitions
    page = { duration = 1.4, reveal = true },
    starwars = { duration = 1.0, reveal = true },
    clock = { duration = 1.1, reveal = true },
    iris = { duration = 1.0, reveal = true },
    crossfade = { duration = 0.9, reveal = true },
    slide = { duration = 0.8, reveal = true },
}
scene.defaultTransition = "fade"

local function transitionShader(kind)
    if kind == "fade" or kind == "flash" then
        return nil
    end
    return shaders.get("transitions/" .. kind)
end

function scene.transition(fn, kind, opts)
    opts = opts or {}
    kind = kind or scene.defaultTransition
    if kind == "none" or kind == false then
        fn()
        return
    end
    if transition then
        -- already in a transition: just do the change, never lose it
        fn()
        return
    end
    local info = scene.transitions[kind] or {}
    if info.reveal then
        local shader = transitionShader(kind)
        if shader then
            transition = {
                fn = fn, time = 0, kind = kind, shader = shader, reveal = true, done = false,
                duration = opts.duration or info.duration or 1,
                direction = opts.direction or info.direction, center = opts.center,
                softness = opts.softness or info.softness,
            }
            input.lock(true)
            return
        end
        kind, info = "fade", scene.transitions.fade -- no shaders on this GPU
    end
    transition = {
        fn = fn,
        time = 0,
        half = (opts.duration or info.duration or 0.6) / 2,
        kind = kind,
        shader = transitionShader(kind),
        color = opts.color or info.color or { 0, 0, 0 },
        center = opts.center,
        done = false,
    }
    input.lock(true)
end

-- old name, opts.kind selects the transition
function scene.fade(fn, opts)
    opts = opts or {}
    scene.transition(fn, opts.kind or "fade", opts)
end

local function packed(...)
    return { n = select("#", ...), ... }
end

function scene.fadeSwitch(s, ...)
    local args = packed(...)
    scene.transition(function() scene.switch(s, unpack(args, 1, args.n)) end, "fade")
end

function scene.fadePush(s, ...)
    local args = packed(...)
    scene.transition(function() scene.push(s, unpack(args, 1, args.n)) end, "fade")
end

function scene.fadePop(...)
    local args = packed(...)
    scene.transition(function() scene.pop(unpack(args, 1, args.n)) end, "fade")
end

function scene.pixelPush(s, ...)
    local args = packed(...)
    scene.transition(function() scene.push(s, unpack(args, 1, args.n)) end, "pixel")
end

function scene.isTransitioning()
    return transition ~= nil
end

-- 0 = fully visible, 1 = fully covered
local function coverage()
    if not transition or transition.reveal then
        return 0
    end
    local t = transition.time / transition.half
    if t <= 1 then
        return t
    end
    return math.max(0, 2 - t)
end

-- callbacks -----------------------------------------------------------------

function scene.update(dt)
    if transition and transition.reveal then
        -- the old picture was saved by the last draw: change the scene now
        if transition.snapshot and not transition.done then
            transition.done = true
            transition.fn()
        elseif transition.done then
            transition.time = transition.time + dt
            if transition.time >= transition.duration then
                transition = nil
                input.lock(false)
            end
        end
    elseif transition then
        transition.time = transition.time + dt
        if not transition.done and transition.time >= transition.half then
            transition.done = true
            transition.fn()
        end
        if transition.time >= transition.half * 2 then
            transition = nil
            input.lock(false)
        end
    end
    -- the keymap of the scene on top: modes set scene.keymap = their kind,
    -- menus and overlays without one use the "menu" keys
    local top = scene.top()
    if top then
        input.use(top.keymap or "menu", top.controls)
    end
    call(top, "update", dt)
end

function scene.draw()
    -- find the lowest scene that has to be drawn
    local first = #stack
    while first > 1 and stack[first].transparent do
        first = first - 1
    end
    for i = first, #stack do
        love.graphics.origin()
        love.graphics.setColor(1, 1, 1, 1)
        call(stack[i], "draw")
    end
    love.graphics.origin()

    if transition and transition.reveal and not transition.snapshot then
        -- keep the old picture for a reveal transition
        local source = screen.getCanvas()
        if source then
            if not snapshot or snapshot:getWidth() ~= screen.width or snapshot:getHeight() ~= screen.height then
                snapshot = love.graphics.newCanvas(screen.width, screen.height)
            end
            love.graphics.push("all")
            love.graphics.setCanvas(snapshot)
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.origin()
            love.graphics.setShader()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(source, 0, 0)
            love.graphics.pop()
        end
        transition.snapshot = true
    end
    local c = coverage()
    if c > 0 and not transition.shader then
        -- plain fade (also the fallback when a shader could not be compiled)
        local col = transition.color
        love.graphics.setColor(col[1], col[2], col[3], c)
        love.graphics.rectangle("fill", 0, 0, screen.width, screen.height)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- Post effects of the top-most scene that defines them, plus the shader of
-- the running transition (always last, so it covers everything).
function scene.effects()
    local list = {}
    for i = #stack, 1, -1 do
        if stack[i].effects then
            for _, name in ipairs(stack[i].effects) do
                table.insert(list, name)
            end
            break
        end
    end
    if transition and transition.reveal and transition.done then
        local name = "transitions/" .. transition.kind
        local center = transition.center or { screen.width / 2, screen.height / 2 }
        shaders.send(name, "progress", math.min(1, transition.time / transition.duration))
        shaders.send(name, "previous", snapshot)
        shaders.send(name, "center", { center[1] / screen.width, center[2] / screen.height })
        shaders.send(name, "direction", transition.direction or { 0, 0 })
        shaders.send(name, "softness", transition.softness or 0)
        table.insert(list, name)
        return list
    end
    local c = coverage()
    if c > 0 and transition.shader then
        local name = "transitions/" .. transition.kind
        local center = transition.center or { screen.width / 2, screen.height / 2 }
        shaders.send(name, "progress", c)
        shaders.send(name, "phase", transition.done and 1 or 0)
        shaders.send(name, "color", transition.color)
        shaders.send(name, "center", { center[1] / screen.width, center[2] / screen.height })
        table.insert(list, name)
    end
    return list
end

-- Forward any other LOVE callback to the top scene.
function scene.forward(name, ...)
    if transition then
        return
    end
    return call(scene.top(), name, ...)
end

return scene
