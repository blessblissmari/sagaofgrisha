-- Visual novel: backgrounds, character figures, the dialogue box, choices.
--
--   game.stage "prologue" {
--       kind = "novel", music = "calm", next = "island",
--       script = function(s)
--           s:bg("forest")                       -- name from game.backgrounds or an image path
--           s:title("Глава 1", "Остров")         -- chapter banner
--           s:show("bunny", { at = "right" })    -- left / center / right or 0..1
--           s:say("bunny", "Привет!")
--           local a = s:ask("bunny", "Пойдёшь со мной?", { "Да", "Нет" })
--           if a == 2 then s:say("bunny", "Жаль...") end
--           s:hide("bunny")
--           s:shake(); s:flash()
--       end,
--   }
-- The stage ends with the script and goes to `next`.
-- Hold [Ctrl] to skip text, [Esc] opens the pause menu.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui
local util = engine.util
local Background = engine.Background
local Mode = require("game.modes.base")

local function G()
    return require("game")
end

local Novel = class(Mode)
Novel.liveScripts = true

local POSITIONS = { left = 0.22, center = 0.5, right = 0.78, farleft = 0.1, farright = 0.9 }

function Novel:init(def)
    Mode.init(self, def)
    self.dialogBox = { choiceStyle = "buttons" }
    self.figures = {}
    self.fade = 0
    self.flashAlpha = 0
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

-- script commands -------------------------------------------------------------------

function Novel:cmd_bg(s, name, transition)
    if transition == false or transition == "none" or not self.background then
        self:setBackground(name)
        return nil
    end
    -- fade through black
    self.timer:tween(0.35, self, { fade = 1 }, "quadIn", function()
        self:setBackground(name)
        self.timer:tween(0.35, self, { fade = 0 }, "quadOut")
    end)
    return 0.75
end

local function figureOf(who)
    local sp = G().speaker(who)
    return sp and sp.figure
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
    f = { who = who, picture = picture, x = x, alpha = 0, offset = 40 * (x < 0.5 and -1 or 1),
        flip = opts.flip or false, scale = opts.scale, order = util.ulen(tostring(who)) + love.math.random() }
    self.figures[who] = f
    self.timer:tween(0.45, f, { alpha = 1, offset = 0 }, "cubicOut")
    return opts.wait and 0.45 or nil
end

function Novel:cmd_hide(s, who)
    local f = self.figures[who]
    if not f then
        return nil
    end
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

function Novel:cmd_flash(s, color)
    self.flashColor = color or { 1, 1, 1 }
    self.flashAlpha = 1
    self.timer:tween(0.5, self, { flashAlpha = 0 }, "quadOut")
    return nil
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

-- callbacks -------------------------------------------------------------------------

function Novel:update(dt, fromScript)
    Mode.update(self, dt)
    self.background:update(dt)
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

function Novel:draw()
    local ox, oy = self:shakeOffset(love.timer.getDelta())
    love.graphics.push()
    love.graphics.translate(ox, oy)
    self.background:draw(self.time * 10, 0)
    local list = {}
    for _, f in pairs(self.figures) do
        table.insert(list, f)
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    for _, f in ipairs(list) do
        local p = f.picture
        local _, _, qw, qh = p.quad:getViewport()
        local s = f.scale or p.scale or math.min(420 / qh, 360 / qw)
        local x = f.x * screen.width + f.offset
        local y = screen.height - 120
        local dimmed = self.speaking and self.speaking ~= f.who
        local k = dimmed and 0.6 or 1
        local bounce = (not dimmed and self.speaking == f.who) and math.abs(math.sin(self.time * 3)) * 3 or 0
        love.graphics.setColor(k, k, k, f.alpha)
        love.graphics.draw(p.image, p.quad, math.floor(x), math.floor(y - bounce), 0,
            f.flip and -s or s, s, qw / 2, qh)
    end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
    if self.banner and self.banner.alpha > 0 then
        local b = self.banner
        love.graphics.setColor(1, 1, 1, b.alpha)
        ui.banner(b.text, screen.width / 2, 150, 520, { font = "title" })
        if b.sub then
            ui.print(b.sub, screen.width / 2, 216, { font = "body", align = "center", color = "light", shadow = true, alpha = b.alpha })
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
    if self.flashAlpha > 0 then
        local c = self.flashColor
        love.graphics.setColor(c[1], c[2], c[3], self.flashAlpha)
        love.graphics.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    if self.fade > 0 then
        love.graphics.setColor(0, 0, 0, self.fade)
        love.graphics.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    love.graphics.setColor(1, 1, 1, 1)
    ui.print("[Ctrl] перемотка   [Esc] пауза", screen.width - 12, 8,
        { font = "small", align = "right", color = "light", shadow = true, alpha = 0.6 })
end

return Novel
