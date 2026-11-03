-- Dialogues and visual-novel scripts are plain Lua functions:
--
--   -- game/story/bunny.lua
--   return function(d)
--       d:say("bunny", "Привет, Гриша!")
--       local answer = d:choice("Хочешь морковку?", { "Да", "Нет" })
--       if answer == 1 then
--           d:give("carrot")
--           d:say("bunny", { "Держи!", "Только не ешь сразу." })   -- two pages
--       end
--       d:flag("talkedToBunny", true)
--   end
--
--   dialogue.run("bunny")                          -- name of a file in game/story
--   dialogue.run(scriptFunction, { onDone = function(result) end })
--
-- Commands (d:...):
--   say(who, text)          who: id from game/data/characters.lua, any name or nil
--   choice(prompt, options) returns the number of the chosen option
--   wait(seconds), sound(name), music(name), stopMusic()
--   flag(name) / flag(name, value)      story flags, saved with the game
--   give(item, n), take(item, n), has(item, n)
--   call(fn, ...)           run any code
--   run(name)               run another script inside this one
-- Novel only (ignored in in-game dialogues):
--   bg(name), show(who, { at = "left" | "center" | "right" }), hide(who),
--   shake(power), flash(color), title(text)
--
-- The script's return value is passed to onDone.

local class = require("engine.class")
local DialogBox = require("engine.ui.dialogbox")
local scene = require("engine.scene")
local audio = require("engine.audio")

local dialogue = {
    folder = "game.story.",
    characters = {}, -- id -> { name, color, voice, portrait = { image, quad, scale } }
    context = {},    -- flags = {}, inventory = Inventory (set by the game)
}

function dialogue.speaker(who)
    if who == nil then
        return nil
    end
    return dialogue.characters[who] or { name = tostring(who) }
end

function dialogue.load(name)
    if type(name) == "function" then
        return name
    end
    local ok, script = pcall(require, dialogue.folder .. name)
    if not ok then
        error("dialogue '" .. tostring(name) .. "': " .. tostring(script), 0)
    end
    return script
end

-- Director: runs a script as a coroutine and talks to a host
-- (the in-game overlay below or the novel scene).
local Director = class()
dialogue.Director = Director

function Director:init(script, host)
    self.host = host
    self.done = false
    self.co = coroutine.create(function() return script(self) end)
end

function Director:resume(...)
    if self.done then
        return
    end
    local ok, result = coroutine.resume(self.co, ...)
    if not ok then
        error("dialogue script error: " .. tostring(result) .. "\n" .. debug.traceback(self.co), 0)
    end
    if coroutine.status(self.co) == "dead" then
        self.done = true
        self.host:dialogueFinished(result)
    end
end

function Director:say(who, text)
    self.host:dialogueSay(dialogue.speaker(who), text)
    return coroutine.yield()
end

function Director:narrate(text)
    return self:say(nil, text)
end

function Director:choice(prompt, options, who)
    self.host:dialogueChoice(dialogue.speaker(who), prompt, options)
    return coroutine.yield()
end

function Director:wait(seconds)
    self.host:dialogueWait(seconds)
    return coroutine.yield()
end

function Director:sound(name, opts)
    return audio.play(name, opts)
end

function Director:music(name, opts)
    return audio.music(name, opts)
end

function Director:stopMusic(fade)
    audio.stopMusic(fade or 1)
end

function Director:flag(name, value)
    local flags = dialogue.context.flags or {}
    dialogue.context.flags = flags
    if value == nil then
        return flags[name]
    end
    flags[name] = value
    return value
end

function Director:give(item, count)
    local inv = dialogue.context.inventory
    if inv then
        inv:add(item, count or 1)
        if dialogue.context.onGive then
            dialogue.context.onGive(item, count or 1)
        end
    end
end

function Director:take(item, count)
    local inv = dialogue.context.inventory
    return inv and inv:remove(item, count or 1) or false
end

function Director:has(item, count)
    local inv = dialogue.context.inventory
    return inv and inv:has(item, count or 1) or false
end

function Director:call(fn, ...)
    return fn(...)
end

function Director:run(name)
    return dialogue.load(name)(self)
end

-- novel commands: forwarded if the host knows them
for _, name in ipairs({ "bg", "show", "hide", "shake", "flash", "title", "clear" }) do
    Director[name] = function(self, ...)
        local fn = self.host["novel_" .. name]
        if fn then
            local waits = fn(self.host, ...)
            if waits then
                return coroutine.yield()
            end
        end
    end
end

-- In-game dialogue: a transparent scene on top of the current one --------------

local Overlay = class()
Overlay.transparent = true

function Overlay:init(script, opts)
    self.opts = opts or {}
    self.box = DialogBox()
    self.director = Director(script, self)
    self.waitTime = nil
    self.started = false
end

function Overlay:enter()
    if not self.started then
        self.started = true
        self.director:resume()
    end
end

function Overlay:dialogueSay(speaker, text)
    self.box:say(speaker, text)
end

function Overlay:dialogueChoice(speaker, prompt, options)
    self.box:ask(speaker, prompt, options)
end

function Overlay:dialogueWait(seconds)
    self.box:hide()
    self.waitTime = seconds
end

function Overlay:dialogueFinished(result)
    self.finished = true
    if scene.top() == self then
        scene.pop()
    end
    if self.opts.onDone then
        self.opts.onDone(result)
    end
end

function Overlay:update(dt)
    if self.waitTime then
        self.waitTime = self.waitTime - dt
        if self.waitTime <= 0 then
            self.waitTime = nil
            self.director:resume()
        end
        return
    end
    local event, value = self.box:update(dt)
    if event == "done" then
        self.director:resume()
    elseif event == "choice" then
        self.director:resume(value)
    end
end

function Overlay:draw()
    self.box:draw()
end

-- opts: onDone(result)
function dialogue.run(name, opts)
    local overlay = Overlay(dialogue.load(name), opts)
    scene.push(overlay)
    return overlay
end

return dialogue
