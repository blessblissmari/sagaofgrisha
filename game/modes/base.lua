-- Base of every stage kind (topdown, novel, tetris...). A mode gets the stage
-- description from story.lua (def) and adds the gameplay.
--
-- Common stage fields (story.lua):
--   music        name from game/data/sounds.lua, false = silence
--   script       function(s) run when the stage starts (s = director, see game/director.lua)
--   on           { event = function(s, ...) } reactions to events of the mode
--                (win, lose, enter, pickup, kill... see each mode)
--   next         stage after this one: "name" or { win = "a", lose = "b" }
--   done         function(s, result) run when the stage is over, before next
--   transition   how to enter the stage: "fade", "swirl", "pixel" ... (see engine/scene.lua)
--
-- A mode can add script commands: function Mode:cmd_shake(s, power) ... end
-- makes s:shake(power) available in story scripts of this stage.

local engine = require("engine")
local audio = engine.audio
local class = engine.class
local fx = engine.fx
local input = engine.input
local scene = engine.scene
local timer = engine.timer

local function G()
    return require("game")
end

local Mode = class()

function Mode:init(def)
    self.def = def
    self.name = def.name or def.kind
    self.timer = timer.new()
    self.fx = fx.Layer()
    self.time = 0
    self.started = false
end

function Mode:enter()
    local m = self.def.music
    if m == false then
        audio.stopMusic(0.5)
    elseif m then
        audio.music(m)
    end
end

-- first update: run the stage script, if any
function Mode:start()
    if self.def.script then
        self:run(self.def.script)
    end
    self:fire("enter")
end

-- Runs a story script on top of this mode: script(s, ...).
function Mode:run(script, args, onDone)
    return G().run(script, self, args, onDone)
end

-- Story reaction to an event: def.on[name](s, ...). Returns true if there is one.
function Mode:fire(name, ...)
    local handler = self.def.on and self.def.on[name]
    if handler then
        self:run(handler, { ... })
        return true
    end
    return false
end

-- The stage is over: result = { win = true, score = 100 }.
function Mode:finish(result)
    G().finish(self, result)
end

function Mode:update(dt)
    if not self.started then
        self.started = true
        self:start()
        if scene.top() ~= self then
            return
        end
    end
    self.time = self.time + dt
    self.timer:update(dt)
    self.fx:update(dt)
end

-- Opens the pause menu. extra: more menu items { label = ..., action = fn }.
function Mode:openPause(extra)
    local Pause = require("game.ui.pause")
    scene.push(Pause(self, extra))
end

function Mode:pausePressed()
    return input.pressed("pause") and not scene.isTransitioning()
end

-- common script commands ----------------------------------------------------------

function Mode:cmd_shake(s, power, duration)
    if self.camera then
        self.camera:shake(power or 6, duration or 0.4)
    else
        self.shakeTime, self.shakePower = duration or 0.4, power or 6
    end
end

function Mode:cmd_win(s, extra)
    local r = { win = true }
    for k, v in pairs(extra or {}) do r[k] = v end
    self:finish(r)
    return "wait"
end

function Mode:cmd_lose(s, extra)
    local r = { win = false }
    for k, v in pairs(extra or {}) do r[k] = v end
    self:finish(r)
    return "wait"
end

-- screen shake offset for modes without a camera
function Mode:shakeOffset(dt)
    if self.shakeTime and self.shakeTime > 0 then
        self.shakeTime = self.shakeTime - (dt or 0)
        local p = self.shakePower * math.max(0, self.shakeTime)
        return (love.math.random() * 2 - 1) * p, (love.math.random() * 2 - 1) * p
    end
    return 0, 0
end

return Mode
