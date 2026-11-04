-- The dialogue window: window, name plate, portrait, typewriter text with
-- effects, a synthesized voice, the "next" marker and answer choices.
-- Used by in-game dialogues and the visual novel.
--
--   box:say(speaker, { "page 1", "page 2" })   -- speaker = { id, name, color, voice, portrait }
--   box:ask(speaker, "Вопрос?", { "Да", "Нет" })
--   box:ask(speaker, "Вопрос?", { "Да", { label = "Нет", disabled = true } }, { time = 6, default = 1 })
--   local event, value, timeout = box:update(dt) -- "done" | "choice", index (timeout = the time ran out)
--   box:draw()
--   box.onEvent = function(speaker, name, value) end   -- {@hop}, {@emote=...} in the text

local audio = require("engine.audio")
local class = require("engine.class")
local input = require("engine.input")
local screen = require("engine.screen")
local voice = require("engine.voice")
local Menu = require("engine.ui.menu")
local panel = require("engine.ui.panel")
local Text = require("engine.ui.text")
local theme = require("engine.ui.theme")

local DialogBox = class()

-- opts: x, y, w, h, choiceStyle ("panel" / "buttons" / "window"), position ("bottom" / "top")
function DialogBox:init(opts)
    opts = opts or {}
    self.w = opts.w or (screen.width - 80)
    self.h = opts.h or (theme.textShadow and 176 or 150)
    self.x = opts.x or math.floor((screen.width - self.w) / 2)
    self.position = opts.position or "bottom"
    self.y = opts.y or (screen.height - self.h - 20)
    self.choiceStyle = opts.choiceStyle or "panel"
    if theme.choiceStyle == "window" then
        self.choiceStyle = "window"
    end
    self.state = "hidden"
    self.time = 0
    self.appear = 0
    self.fast = false -- novel "skip" mode: instant text
    self.auto = false -- novel "auto" mode: a finished page turns by itself after a pause
    self.autoTime = 0
end

local function blip(speaker)
    local count = 0
    local v = speaker and speaker.voice or theme.narratorVoice
    return function(c)
        count = count + 1
        if type(v) == "string" or type(v) == "table" then
            voice.say(v, c, count)
        elseif count % 2 == 1 and theme.sounds.text then
            audio.play(theme.sounds.text, { pitch = v or 1, volume = 0.35 })
        end
    end
end

function DialogBox:textLeft()
    return (self.speaker and self.speaker.portrait) and 162 or 34
end

function DialogBox:makeText(str)
    local left = self:textLeft()
    return Text(str, {
        font = theme.font("dialog"),
        width = self.w - left - 50,
        speed = self.fast and 0 or (self.speaker and self.speaker.speed or theme.textSpeed),
        onChar = blip(self.speaker),
        onEvent = function(name, value)
            if self.onEvent then
                self.onEvent(self.speaker, name, value)
            end
        end,
    })
end

function DialogBox:open()
    if self.state == "hidden" then
        self.appear = 0
    end
end

function DialogBox:say(speaker, pages)
    self:open()
    self.speaker = speaker
    self.pages = type(pages) == "table" and pages or { pages }
    self.page = 1
    self.text = self:makeText(self.pages[1])
    self.menu = nil
    self.state = "text"
end

-- options: strings or { label = "...", disabled = true }
-- opts.time: seconds to answer (a bar runs out under the text), then opts.default is chosen
function DialogBox:ask(speaker, prompt, options, opts)
    opts = opts or {}
    self:open()
    self.speaker = speaker
    self.text = prompt and self:makeText(prompt) or nil
    local items = {}
    for i, option in ipairs(options) do
        if type(option) == "table" then
            items[i] = { label = option.label or option[1], disabled = option.disabled }
        else
            items[i] = { label = option }
        end
    end
    self.menu = Menu(items, {
        style = self.choiceStyle == "buttons" and "buttons" or "plain",
        width = self.choiceStyle == "buttons" and 340 or nil,
        font = theme.font("dialog"),
    })
    self.timeMax = opts.time
    self.timeLeft = opts.time
    self.timeDefault = opts.default or #items
    self.state = "choice"
end

function DialogBox:hide()
    self.state = "hidden"
end

local function confirmPressed()
    if input.pressed("interact") then
        input.consume("interact")
        return true
    end
    return input.pressed("confirm") or input.mouse.pressed[1]
end

function DialogBox:update(dt)
    self.time = self.time + dt
    self.appear = math.min(1, self.appear + dt * 7)
    if self.appear < 1 then
        return nil
    end
    if self.state == "text" then
        self.text:update(dt)
        local turn = false
        if self.auto and self.text:isDone() then
            self.autoTime = self.autoTime + dt
            turn = self.autoTime > 1.2 + (self.text.total or 0) * 0.025
        else
            self.autoTime = 0
        end
        if confirmPressed() or (self.fast and self.text:isDone()) or turn then
            self.autoTime = 0
            input.consume("confirm")
            input.mouse.pressed[1] = nil
            if not self.text:isDone() then
                self.text:skip()
            elseif self.page < #self.pages then
                self.page = self.page + 1
                self.text = self:makeText(self.pages[self.page])
            else
                self.state = "idle"
                return "done"
            end
        end
    elseif self.state == "choice" then
        if self.text and not self.text:isDone() then
            self.text:update(dt)
            if confirmPressed() then
                input.consume("confirm")
                input.mouse.pressed[1] = nil
                self.text:skip()
            end
            return nil
        end
        local chosen = self.menu:update(dt)
        if chosen then
            self.state = "idle"
            self.timeLeft = nil
            return "choice", chosen
        end
        if self.timeLeft then
            local before = self.timeLeft
            self.timeLeft = self.timeLeft - dt
            if math.ceil(self.timeLeft) < math.ceil(before) and before <= 3 and theme.sounds.move then
                audio.play(theme.sounds.move, { pitch = 1.5 })
            end
            if self.timeLeft <= 0 then
                self.timeLeft = nil
                self.state = "idle"
                return "choice", self.timeDefault, true
            end
        end
    end
    return nil
end

-- height of the window: grows when answers are inside it
function DialogBox:boxHeight()
    if self.state == "choice" and self.choiceStyle == "window" and self.menu then
        local textH = self.text and self.text:getHeight() or 0
        return math.max(self.h, 28 + textH + self.menu:getHeight() + 22)
    end
    return self.h
end

function DialogBox:drawChoices(x, y, h)
    local menu = self.menu
    if self.choiceStyle == "window" then
        local textH = self.text and self.text:getHeight() or 0
        menu:draw(x + self:textLeft() + 44, y + 24 + textH + 4)
        return
    end
    if self.choiceStyle == "buttons" then
        local w = menu:getWidth()
        local mx = math.floor((screen.width - w) / 2)
        local my = math.floor(y - 30 - menu:getHeight())
        menu:draw(mx, my)
        return
    end
    local w = menu:getWidth() + 76
    local mh = menu:getHeight() + 26
    local mx = self.x + self.w - w - 24
    local my = y - mh - 8
    panel.draw(mx, my, w, mh)
    menu:draw(mx + 46, my + 16)
end

-- the time to answer: a bar along the bottom of the window, it turns red at the end
function DialogBox:drawTimer(x, y, w, h)
    local lg = love.graphics
    local k = math.max(0, math.min(1, self.timeLeft / self.timeMax))
    local left = self:textLeft()
    local bx, by, bw, bh = x + left, y + h - 18, w - left - 34, 6
    lg.setColor(theme.color("barFrame"))
    lg.rectangle("fill", bx - 2, by - 2, bw + 4, bh + 4)
    lg.setColor(theme.color("barBack"))
    lg.rectangle("fill", bx, by, bw, bh)
    local c = theme.color(k > 0.3 and "accent" or "red")
    local blink = k <= 0.3 and (math.floor(self.time * 8) % 2 == 0) and 0.6 or 1
    lg.setColor(c[1], c[2], c[3], blink)
    lg.rectangle("fill", bx, by, math.floor(bw * k + 0.5), bh)
    lg.setColor(1, 1, 1, 1)
end

function DialogBox:draw()
    if self.state == "hidden" then
        return
    end
    local lg = love.graphics
    local w, h = self.w, self:boxHeight()
    local x = self.x
    local y = self.position == "top" and 20 or (screen.height - h - 20)
    if self.appear < 1 then
        -- the window opens from its middle line, like in old RPGs
        local k = 0.15 + 0.85 * self.appear
        local hh = math.floor(h * k)
        lg.setColor(1, 1, 1, 0.6 + 0.4 * self.appear)
        panel.draw(x, y + (h - hh) / 2, w, hh)
        lg.setColor(1, 1, 1, 1)
        return
    end
    lg.setColor(1, 1, 1, 1)
    panel.draw(x, y, w, h)
    local sp = self.speaker
    if sp and sp.portrait then
        local p = sp.portrait
        panel.draw(x + 18, y + 18, 124, h - 36, "small")
        local image = p.image
        local _, _, qw, qh = p.quad:getViewport()
        local s = p.scale or math.min(104 / qw, (h - 50) / qh)
        lg.setColor(1, 1, 1, 1)
        lg.draw(image, p.quad, math.floor(x + 18 + 62 - qw * s / 2), math.floor(y + h - 24 - qh * s), 0, s, s)
    end
    if sp and sp.name then
        local font = theme.font("small")
        local tw = font:getWidth(sp.name)
        local nh = font:getHeight() + 14
        panel.draw(x + 24, y - nh + 6, tw + 36, nh, "small")
        local c = theme.nameColor(sp.color)
        local px = theme.pixelOf(font)
        lg.setFont(font)
        if theme.textShadow then
            lg.setColor(theme.colors.shadow)
            lg.print(sp.name, x + 42 + px, y - nh + 13 + px)
        end
        lg.setColor(c)
        lg.print(sp.name, x + 42, y - nh + 13)
    end
    if self.text then
        self.text:draw(x + self:textLeft(), y + 24)
    end
    if self.state == "text" and self.text:isDone() then
        local arrow = theme.image("next")
        lg.setColor(1, 1, 1, 1)
        local bob = math.floor(math.sin(self.time * 6) * 3 + 0.5)
        if arrow then
            lg.draw(arrow, x + w - 48, y + h - 42 + bob, 0, 0.85, 0.85)
        else
            panel.arrow(x + w - 34, y + h - 26 + bob, self.page < #self.pages and "down" or "down", 14)
        end
    end
    if self.state == "choice" and (not self.text or self.text:isDone()) then
        self:drawChoices(x, y, h)
        if self.timeLeft and self.timeMax then
            self:drawTimer(x, y, w, h)
        end
    end
    lg.setColor(1, 1, 1, 1)
end

return DialogBox
