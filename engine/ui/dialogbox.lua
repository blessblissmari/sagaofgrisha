-- The dialogue window: parchment box, name plate, portrait, typewriter text,
-- "next" arrow and answer choices. Used by in-game dialogues and the novel.
--
--   box:say(speaker, { "page 1", "page 2" })   -- speaker = { name, color, voice, portrait }
--   box:ask(speaker, "Вопрос?", { "Да", "Нет" })
--   local event, value = box:update(dt)       -- "done" | "choice", index
--   box:draw()

local audio = require("engine.audio")
local class = require("engine.class")
local input = require("engine.input")
local screen = require("engine.screen")
local Menu = require("engine.ui.menu")
local panel = require("engine.ui.panel")
local Text = require("engine.ui.text")
local theme = require("engine.ui.theme")

local DialogBox = class()

-- opts: x, y, w, h, choiceStyle ("panel" / "buttons")
function DialogBox:init(opts)
    opts = opts or {}
    self.w = opts.w or (screen.width - 80)
    self.h = opts.h or 150
    self.x = opts.x or math.floor((screen.width - self.w) / 2)
    self.y = opts.y or (screen.height - self.h - 20)
    self.choiceStyle = opts.choiceStyle or "panel"
    self.state = "hidden"
    self.time = 0
    self.appear = 0
    self.fast = false -- novel "skip" mode: instant text
end

local function blip(speaker)
    local count = 0
    return function(c)
        count = count + 1
        if count % 2 == 1 and theme.sounds.text then
            audio.play(theme.sounds.text, { pitch = speaker and speaker.voice or 1, volume = 0.35 })
        end
    end
end

function DialogBox:textLeft()
    return (self.speaker and self.speaker.portrait) and 156 or 30
end

function DialogBox:makeText(str)
    local left = self:textLeft()
    return Text(str, {
        width = self.w - left - 50,
        speed = self.fast and 0 or theme.textSpeed,
        onChar = blip(self.speaker),
    })
end

function DialogBox:say(speaker, pages)
    self.speaker = speaker
    self.pages = type(pages) == "table" and pages or { pages }
    self.page = 1
    self.text = self:makeText(self.pages[1])
    self.menu = nil
    self.state = "text"
end

function DialogBox:ask(speaker, prompt, options)
    self.speaker = speaker
    self.text = prompt and self:makeText(prompt) or nil
    local items = {}
    for i, option in ipairs(options) do
        items[i] = { label = option }
    end
    self.menu = Menu(items, {
        style = self.choiceStyle == "buttons" and "buttons" or "plain",
        width = self.choiceStyle == "buttons" and 340 or nil,
    })
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
    self.appear = math.min(1, self.appear + dt * 6)
    if self.state == "text" then
        self.text:update(dt)
        if confirmPressed() or (self.fast and self.text:isDone()) then
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
            return "choice", chosen
        end
    end
    return nil
end

function DialogBox:drawChoices()
    local menu = self.menu
    if self.choiceStyle == "buttons" then
        local w = menu:getWidth()
        local x = math.floor((screen.width - w) / 2)
        local y = math.floor(self.y - 30 - menu:getHeight())
        menu:draw(x, y)
        return
    end
    local w = menu:getWidth() + 76
    local h = menu:getHeight() + 26
    local x = self.x + self.w - w - 24
    local y = self.y - h - 8
    panel.draw(x, y, w, h)
    menu:draw(x + 46, y + 16)
end

function DialogBox:draw()
    if self.state == "hidden" then
        return
    end
    local lg = love.graphics
    local x, y, w, h = self.x, self.y + math.floor((1 - self.appear) * 20), self.w, self.h
    lg.setColor(1, 1, 1, 1)
    panel.draw(x, y, w, h)
    local sp = self.speaker
    if sp and sp.portrait then
        local p = sp.portrait
        panel.draw(x + 18, y + 18, 118, h - 36, theme.smallPanel)
        local image = p.image
        local _, _, qw, qh = p.quad:getViewport()
        local s = p.scale or math.min(100 / qw, (h - 50) / qh)
        lg.setColor(1, 1, 1, 1)
        lg.draw(image, p.quad, math.floor(x + 18 + 59 - qw * s / 2), math.floor(y + h - 22 - qh * s), 0, s, s)
    end
    if sp and sp.name then
        local font = theme.font("body")
        local tw = font:getWidth(sp.name)
        panel.draw(x + 26, y - 30, tw + 40, 42)
        lg.setFont(font)
        lg.setColor(sp.color or theme.colors.accent)
        lg.print(sp.name, x + 46, y - 21)
    end
    if self.text then
        self.text:draw(x + self:textLeft(), y + 26)
    end
    if self.state == "text" and self.text:isDone() then
        local arrow = theme.image("next")
        lg.setColor(1, 1, 1, 1)
        lg.draw(arrow, x + w - 48, math.floor(y + h - 42 + math.sin(self.time * 6) * 3), 0, 0.85, 0.85)
    end
    if self.state == "choice" and (not self.text or self.text:isDone()) then
        self:drawChoices()
    end
    lg.setColor(1, 1, 1, 1)
end

return DialogBox
