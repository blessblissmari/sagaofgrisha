-- Runs one story script as a coroutine on top of a mode ("host").
-- Shows the dialogue box, waits, opens mini-games and battles; the host is
-- paused meanwhile (modes with liveScripts = true keep animating).
-- The commands available in scripts are in game/director.lua.

local class = require("engine.class")
local scene = require("engine.scene")
local DialogBox = require("engine.ui.dialogbox")
local Director = require("game.director")

local Runner = class()
Runner.transparent = true

function Runner:init(script, host, args, onDone)
    self.host = host
    self.args = args or {}
    self.onDone = onDone
    self.box = DialogBox(host and host.dialogBox or nil)
    -- {@hop}, {@emote=heart} ... in the text: the host makes the speaker react
    self.box.onEvent = function(speaker, name, value)
        if self.host and self.host.textEvent then
            self.host:textEvent(speaker, name, value)
        end
    end
    self.director = Director(script, host, self)
    self.name = "script"
    -- the keys of the stage below work in its dialogues too ([A] auto, [L] history in the novel)
    self.keymap = host and host.keymap or nil
    self.controls = host and host.controls or nil
end

function Runner:enter()
    if not self.started then
        self.started = true
        self:continue(unpack(self.args))
    end
end

-- the scene on top of the runner closed (a mini-game, a menu): nothing to do here, the
-- director continues the script itself (Director:play passes the result). The name must
-- not be used for the coroutine: scene.pop calls :resume() without arguments.
function Runner:resume() end

-- go on with the script; the arguments are what the waiting command returns
function Runner:continue(...)
    if self.dead then
        return
    end
    self.waitTime, self.waitFn = nil, nil
    local co = self.director.co
    local ok, result = coroutine.resume(co, ...)
    if not ok then
        error("story script error: " .. tostring(result) .. "\n" .. debug.traceback(co), 0)
    end
    if coroutine.status(co) == "dead" then
        self:finish(result)
    end
end

function Runner:finish(result)
    self.dead = true
    self.box:hide()
    for i = #scene.stack, 1, -1 do
        if scene.stack[i] == self then
            if i == #scene.stack then
                scene.pop()
            else
                table.remove(scene.stack, i)
            end
            break
        end
    end
    if self.onDone then
        self.onDone(result)
    end
end

-- requests from the director ---------------------------------------------------

function Runner:say(speaker, text)
    self.box:say(speaker, text)
    require("game").remember(speaker, text)
end

function Runner:ask(speaker, prompt, options, opts)
    self.box:ask(speaker, prompt, options, opts)
end

function Runner:wait(seconds)
    self.box:hide()
    self.waitTime = seconds
end

function Runner:waitUntil(fn)
    self.waitFn = fn
end

function Runner:hideBox()
    self.box:hide()
end

-- scene callbacks ------------------------------------------------------------------

function Runner:update(dt)
    if self.host and self.host.liveScripts and self.host.update then
        self.host:update(dt, true)
    end
    if self.waitTime then
        self.waitTime = self.waitTime - dt
        if self.waitTime <= 0 then
            self.waitTime = nil
            self:continue()
        end
        return
    end
    if self.waitFn then
        if self.waitFn(dt) then
            self.waitFn = nil
            self:continue()
        end
        return
    end
    if self.box.state ~= "hidden" and self.box.state ~= "idle" then
        local event, value, timeout = self.box:update(dt)
        if event == "done" then
            self:continue()
        elseif event == "choice" then
            self:continue(value, timeout)
        end
    end
end

function Runner:draw()
    if self.host and self.host.drawScriptOverlay then
        self.host:drawScriptOverlay()
    end
    self.box:draw()
end

return Runner
