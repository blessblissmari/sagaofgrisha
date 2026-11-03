-- Visual novel: backgrounds, character figures with emotions, the dialogue box, choices.
--
--   game.stage "prologue" {
--       kind = "novel", music = "calm", next = "island",
--       background = "forest", weather = "leaves", daytime = "evening",
--       script = function(s)
--           s:bg("forest")                       -- name from game.backgrounds or an image path
--           s:title("Глава 1", "Остров")         -- chapter banner
--           s:show("bunny", { at = "right" })    -- left / center / right or 0..1
--           s:say("bunny", "Привет! {@hop}Как я рада!")   -- {@...} = emotion at this letter
--           s:emotion("grisha", "anger")         -- joy anger fear surprise sad love think sleepy
--           local a = s:ask("bunny", "Пойдёшь со мной?", { "Да", "Нет" })
--           s:hide("bunny")
--       end,
--   }
-- Emotions (who = character id):
--   s:emote(who, "heart")   bubble: ! ? heart anger sweat sad music dots sleep idea star
--   s:hop(who, times)       s:shake(who) (or s:shake() = the screen)   s:tremble(who, seconds)
--   s:bounce(who)           s:zoom(who, 1.3)   s:tint(who, "red" | {r,g,b} | nil)
--   s:look(who, "left")     s:move(who, "left")  s:faint(who)  s:closeup(who | nil)
--   s:flash(color)          s:weather("rain")  s:daytime("night")  s:letterbox(true)
-- The stage ends with the script and goes to `next`.
-- Hold [Ctrl] to skip text, [Esc] opens the pause menu.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local emote = engine.emote
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui
local util = engine.util
local Background = engine.Background
local Weather = engine.Weather
local Mode = require("game.modes.base")

local function G()
    return require("game")
end

local Novel = class(Mode)
Novel.liveScripts = true

local POSITIONS = { left = 0.22, center = 0.5, right = 0.78, farleft = 0.1, farright = 0.9 }

-- emotions = several effects at once
Novel.emotions = {
    joy = { emote = "music", hop = 2 },
    happy = { emote = "music", bounce = true },
    anger = { emote = "anger", shake = true, tint = { 1, 0.6, 0.55 } },
    fear = { emote = "sweat", tremble = 1.2, tint = { 0.75, 0.8, 1 } },
    surprise = { emote = "!", hop = 1 },
    sad = { emote = "sad", sink = true, tint = { 0.75, 0.78, 0.95 } },
    love = { emote = "heart", bounce = true, tint = { 1, 0.88, 0.9 } },
    think = { emote = "dots" },
    question = { emote = "?" },
    idea = { emote = "idea", hop = 1 },
    sleepy = { emote = "sleep" },
    calm = { tint = false },
}

function Novel:init(def)
    Mode.init(self, def)
    self.dialogBox = { choiceStyle = "buttons" }
    self.figures = {}
    self.fade = 0
    self.flashAlpha = 0
    self.emotes = emote.List()
    self.view = { zoom = 1, x = 0.5, y = 0.6 } -- scene camera for close-ups
    self.bars = 0                                 -- cinematic black bars 0..1
    self.weather = Weather(def.weather, { daytime = def.daytime })
    self:setBackground(def.background or "black")
end

local imageBackgrounds = {}
function Novel:setBackground(name)
    local g = G()
    local def = type(name) == "table" and name or g.backgrounds[name]
    if not def and type(name) == "string" then
        -- a single image: stretched to cover the screen
        def = imageBackgrounds[name]
        if not def then
            local image = assets.image(name)
            local s = math.max(screen.width / image:getWidth(), screen.height / image:getHeight())
            def = { color = { 0, 0, 0 }, layers = { { image = name, scale = s } } }
            imageBackgrounds[name] = def
        end
    end
    self.background = Background(def or g.backgrounds.black)
    self.backgroundName = name
end

function Novel:start()
    self:fire("enter")
    if self.def.script then
        self:run(self.def.script, {}, function()
            self:finish({ win = true })
        end)
    else
        self:finish({ win = true })
    end
end

-- figures ---------------------------------------------------------------------------

local function figureOf(who)
    local sp = G().speaker(who)
    return sp and sp.figure
end

local function newFigure(who, picture, x, opts)
    return {
        who = who, picture = picture, x = x, alpha = 0, offset = 40 * (x < 0.5 and -1 or 1),
        flip = opts.flip or false, scale = opts.scale, order = util.ulen(tostring(who)) + love.math.random(),
        dx = 0, dy = 0, sx = 1, sy = 1, rot = 0, zoom = 1, shakeT = 0, trembleT = 0,
        tint = { 1, 1, 1 },
    }
end

function Novel:figure(who)
    return self.figures[who]
end

-- script commands -------------------------------------------------------------------

function Novel:cmd_bg(s, name, transition, opts)
    if transition == false or transition == "none" or not self.background then
        self:setBackground(name)
        return nil
    end
    -- any screen transition: s:bg("castle", "page"), s:bg("night", "starwars", { direction = { 0, 1 } })
    if type(transition) == "string" and transition ~= "fade" and scene.transitions[transition] then
        local info = scene.transitions[transition]
        scene.transition(function() self:setBackground(name) end, transition, opts)
        return ((opts and opts.duration) or info.duration or 1) + 0.05
    end
    -- fade through black
    self.timer:tween(0.35, self, { fade = 1 }, "quadIn", function()
        self:setBackground(name)
        self.timer:tween(0.35, self, { fade = 0 }, "quadOut")
    end)
    return 0.75
end

function Novel:cmd_show(s, who, opts)
    opts = opts or {}
    local at = opts.at or "center"
    local x = type(at) == "number" and at or POSITIONS[at] or 0.5
    local f = self.figures[who]
    if f then
        self.timer:tween(0.4, f, { x = x, alpha = 1 }, "quadOut")
        f.flip = opts.flip ~= nil and opts.flip or f.flip
        return nil
    end
    local picture = opts.picture and G().resolvePicture(opts.picture) or figureOf(who)
    if not picture then
        return nil
    end
    f = newFigure(who, picture, x, opts)
    self.figures[who] = f
    self.timer:tween(0.45, f, { alpha = 1, offset = 0 }, "cubicOut")
    return opts.wait and 0.45 or nil
end

function Novel:cmd_hide(s, who)
    local f = self.figures[who]
    if not f then
        return nil
    end
    self.emotes:remove(f)
    self.timer:tween(0.3, f, { alpha = 0 }, "quadIn", function()
        if self.figures[who] == f then
            self.figures[who] = nil
        end
    end)
    return nil
end

function Novel:cmd_hideAll(s)
    for who in pairs(self.figures) do
        self:cmd_hide(s, who)
    end
end

function Novel:cmd_move(s, who, at, time)
    local f = self.figures[who]
    if f then
        local x = type(at) == "number" and at or POSITIONS[at] or 0.5
        self.timer:tween(time or 0.6, f, { x = x }, "quadInOut")
    end
end

function Novel:cmd_look(s, who, dir)
    local f = self.figures[who]
    if f then
        -- figures look right by default
        f.flip = dir == "left"
    end
end

function Novel:cmd_emote(s, who, kind, duration)
    local f = self.figures[who]
    if f then
        self.emotes:add(f, kind, duration)
        audio.play("blip", { volume = 0.5, pitch = kind == "!" and 1.4 or 1 })
    end
end

function Novel:cmd_hop(s, who, times, height)
    local f = self.figures[who]
    if not f then
        return
    end
    times, height = times or 1, height or 34
    local function hop(n)
        if n <= 0 then
            return
        end
        f.sx, f.sy = 1.12, 0.88
        self.timer:tween(0.12, f, { sx = 1, sy = 1 }, "quadOut")
        self.timer:tween(0.16, f, { dy = -height }, "quadOut", function()
            self.timer:tween(0.16, f, { dy = 0 }, "quadIn", function()
                f.sx, f.sy = 1.1, 0.9
                self.timer:tween(0.1, f, { sx = 1, sy = 1 }, "quadOut")
                hop(n - 1)
            end)
        end)
    end
    hop(times)
    audio.play("jump", { volume = 0.4 })
end

function Novel:cmd_bounce(s, who)
    local f = self.figures[who]
    if f then
        f.sx, f.sy = 0.86, 1.14
        self.timer:tween(0.45, f, { sx = 1, sy = 1 }, "elasticOut")
    end
end

function Novel:cmd_shake(s, who, power, duration)
    if type(who) ~= "string" then
        return Mode.cmd_shake(self, s, who, power)
    end
    local f = self.figures[who]
    if f then
        f.shakeT = duration or 0.5
        f.shakePower = power or 10
    end
end

function Novel:cmd_quake(s, power, duration)
    return Mode.cmd_shake(self, s, power or 10, duration or 0.6)
end

function Novel:cmd_tremble(s, who, seconds)
    local f = self.figures[who]
    if f then
        f.trembleT = seconds or 1.5
    end
end

function Novel:cmd_zoom(s, who, scale, time)
    local f = self.figures[who]
    if f then
        self.timer:tween(time or 0.4, f, { zoom = scale or 1.25 }, "quadOut")
    end
end

local NAMED_TINTS = { red = { 1, 0.55, 0.5 }, blue = { 0.6, 0.7, 1 }, green = { 0.7, 1, 0.7 },
    dark = { 0.45, 0.45, 0.55 }, gold = { 1, 0.9, 0.6 }, pink = { 1, 0.8, 0.88 } }

function Novel:cmd_tint(s, who, color, time)
    local f = self.figures[who]
    if not f then
        return
    end
    local c = color and (NAMED_TINTS[color] or color) or { 1, 1, 1 }
    self.timer:tween(time or 0.3, f.tint, { c[1], c[2], c[3] }, "linear")
end

function Novel:cmd_faint(s, who)
    local f = self.figures[who]
    if f then
        self.timer:tween(0.6, f, { rot = (f.flip and -1 or 1) * math.pi / 2 * 0.9, dy = 30 }, "bounceOut")
        audio.play("fall", { volume = 0.5 })
    end
end

function Novel:cmd_recover(s, who)
    local f = self.figures[who]
    if f then
        self.timer:tween(0.4, f, { rot = 0, dy = 0, zoom = 1 }, "backOut")
        self:cmd_tint(s, who, nil)
    end
end

-- close-up on a character (nil = whole scene)
function Novel:cmd_closeup(s, who, zoom)
    local f = who and self.figures[who]
    if f then
        self.timer:tween(0.6, self.view, { zoom = zoom or 1.35, x = f.x, y = 0.55 }, "quadInOut")
    else
        self.timer:tween(0.6, self.view, { zoom = 1, x = 0.5, y = 0.6 }, "quadInOut")
    end
    return 0.3
end

function Novel:cmd_emotion(s, who, name)
    local e = Novel.emotions[name]
    if not e then
        return self:cmd_emote(s, who, name)
    end
    if e.emote then
        self:cmd_emote(s, who, e.emote)
    end
    if e.hop then
        self:cmd_hop(s, who, e.hop)
    end
    if e.bounce then
        self:cmd_bounce(s, who)
    end
    if e.shake then
        self:cmd_shake(s, who)
    end
    if e.tremble then
        self:cmd_tremble(s, who, e.tremble)
    end
    if e.sink then
        local f = self.figures[who]
        if f then
            self.timer:tween(0.5, f, { dy = 14 }, "quadOut")
        end
    elseif self.figures[who] and self.figures[who].dy > 0 then
        self.timer:tween(0.3, self.figures[who], { dy = 0 }, "quadOut")
    end
    if e.tint ~= nil then
        self:cmd_tint(s, who, e.tint or nil)
    end
end

function Novel:cmd_flash(s, color)
    self.flashColor = color or { 1, 1, 1 }
    self.flashAlpha = 1
    self.timer:tween(0.5, self, { flashAlpha = 0 }, "quadOut")
    return nil
end

function Novel:cmd_weather(s, kind)
    self.weather:set(kind)
end

function Novel:cmd_daytime(s, name)
    self.weather:setTime(name)
end

function Novel:cmd_letterbox(s, on)
    self.timer:tween(0.5, self, { bars = on == false and 0 or 1 }, "quadInOut")
end

function Novel:cmd_title(s, text, sub)
    audio.play("bell")
    self.banner = { text = text, sub = sub, alpha = 0 }
    local b = self.banner
    self.timer:tween(0.5, b, { alpha = 1 }, "quadOut", function()
        self.timer:after(1.6, function()
            self.timer:tween(0.5, b, { alpha = 0 }, "quadIn")
        end)
    end)
    return 2.8
end

-- {@hop}, {@emote=heart}, {@emotion=anger}, {@shake}, {@quake}, {@flash}, {@sound=coin} in the text:
-- the speaking character reacts at this letter
function Novel:textEvent(speaker, name, value)
    local who = speaker and speaker.id
    local fn = self["cmd_" .. name]
    if name == "sound" then
        audio.play(value)
    elseif name == "music" then
        audio.music(value)
    elseif name == "quake" or name == "flash" or name == "weather" or name == "daytime" then
        fn(self, nil, value ~= "" and value or nil)
    elseif fn and who then
        if value and value ~= "" then
            fn(self, nil, who, tonumber(value) or value)
        else
            fn(self, nil, who)
        end
    end
end

-- callbacks -------------------------------------------------------------------------

function Novel:update(dt, fromScript)
    Mode.update(self, dt)
    self.background:update(dt)
    self.weather:update(dt)
    self.emotes:update(dt)
    for _, f in pairs(self.figures) do
        f.shakeT = math.max(0, f.shakeT - dt)
        f.trembleT = math.max(0, f.trembleT - dt)
    end
    local top = scene.top()
    if top and top.box then
        top.box.fast = input.down("skip")
        self.speaking = top.box.state ~= "hidden" and top.box.speaker and top.box.speaker.id
    end
    if self:pausePressed() then
        input.consume("pause")
        self:openPause()
    end
end

local function figureTop(self, f)
    local p = f.picture
    local _, _, qw, qh = p.quad:getViewport()
    local s = (f.scale or p.scale or math.min(420 / qh, 360 / qw)) * f.zoom
    return f.x * screen.width + f.offset + f.dx, screen.height - 120 + f.dy - qh * s * f.sy
end

function Novel:draw()
    local lg = love.graphics
    local ox, oy = self:shakeOffset(love.timer.getDelta())
    lg.push()
    lg.translate(ox, oy)
    -- scene camera (close-ups)
    local v = self.view
    if v.zoom ~= 1 then
        -- zoom around the focus point: it stays in place, everything grows
        local fx, fy = v.x * screen.width, v.y * screen.height
        lg.translate(fx, fy)
        lg.scale(v.zoom)
        lg.translate(-fx, -fy)
    end
    self.background:draw(self.time * 10, 0)
    local list = {}
    for _, f in pairs(self.figures) do
        table.insert(list, f)
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    for _, f in ipairs(list) do
        local p = f.picture
        local _, _, qw, qh = p.quad:getViewport()
        local s = (f.scale or p.scale or math.min(420 / qh, 360 / qw)) * f.zoom
        local x = f.x * screen.width + f.offset + f.dx
        local y = screen.height - 120 + f.dy
        if f.shakeT > 0 then
            x = x + (love.math.random() * 2 - 1) * (f.shakePower or 10) * math.min(1, f.shakeT * 3)
        end
        if f.trembleT > 0 then
            x = x + math.sin(self.time * 60) * 2.5
        end
        local dimmed = self.speaking and self.speaking ~= f.who
        local k = dimmed and 0.6 or 1
        local breathe = (not dimmed and self.speaking == f.who) and math.abs(math.sin(self.time * 3)) * 3 or 0
        local t = f.tint
        lg.setColor(k * t[1], k * t[2], k * t[3], f.alpha)
        lg.draw(p.image, p.quad, math.floor(x), math.floor(y - breathe), f.rot,
            (f.flip and -s or s) * f.sx, s * f.sy, qw / 2, qh)
    end
    lg.setColor(1, 1, 1, 1)
    self.emotes:draw(function(f)
        local x, y = figureTop(self, f)
        return x + 30, math.max(y - 4, 70)
    end, 1.4)
    lg.pop()
    self.weather:draw(screen.width, screen.height, self.time * 10, 0)
    -- cinematic bars
    if self.bars > 0 then
        local bh = math.floor(60 * self.bars)
        lg.setColor(0, 0, 0, 1)
        lg.rectangle("fill", 0, 0, screen.width, bh)
        lg.rectangle("fill", 0, screen.height - bh, screen.width, bh)
    end
    lg.setColor(1, 1, 1, 1)
    if self.banner and self.banner.alpha > 0 then
        local b = self.banner
        lg.setColor(1, 1, 1, b.alpha)
        ui.banner(b.text, screen.width / 2, 150, 560, { font = "title" })
        if b.sub then
            ui.print(b.sub, screen.width / 2, 232, { font = "body", align = "center", color = "light", shadow = true, alpha = b.alpha })
        end
        lg.setColor(1, 1, 1, 1)
    end
    if self.flashAlpha > 0 then
        local c = self.flashColor
        lg.setColor(c[1], c[2], c[3], self.flashAlpha)
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    if self.fade > 0 then
        lg.setColor(0, 0, 0, self.fade)
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    lg.setColor(1, 1, 1, 1)
    ui.print("[Ctrl] перемотка   [Esc] пауза", screen.width - 12, 8,
        { font = "small", align = "right", color = "light", shadow = true, alpha = 0.6 })
end

return Novel
