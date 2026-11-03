-- Vertical menu for keyboard, gamepad and mouse.
--
--   local menu = Menu({
--       { label = "Новая игра", action = function() ... end },
--       { label = "Громкость", value = function() return "80%" end,
--         change = function(delta) ... end },            -- changed with left / right
--       { label = "Секрет", disabled = true },
--       { label = "Выход", action = love.event.quit },
--   }, { cancel = function() ... end })
--
--   local chosen = menu:update(dt)  -- index, when an item WITHOUT action is chosen
--   menu:draw(x, y)
--
-- opts: font, align ("left" / "center"), spacing, width, style ("plain" / "buttons"),
--       color, selectedColor, disabledColor, shadow, cancel, onMove(index), index

local audio = require("engine.audio")
local class = require("engine.class")
local input = require("engine.input")
local panel = require("engine.ui.panel")
local theme = require("engine.ui.theme")
local util = require("engine.util")

local Menu = class()

local function isEnabled(item)
    local d = item.disabled
    if type(d) == "function" then
        d = d()
    end
    return not d
end

local function sound(name)
    local s = theme.sounds[name]
    if s then
        audio.play(s)
    end
end

function Menu:init(items, opts)
    opts = opts or {}
    self.font = opts.font or theme.font("body")
    self.align = opts.align or "left"
    self.style = opts.style or "plain"
    self.spacing = opts.spacing or (self.style == "buttons" and math.max(54, self.font:getHeight() + 22)
        or math.floor(self.font:getHeight() * (theme.menuSpacing or 1.15)))
    self.width = opts.width
    self.color = opts.color or theme.colors.ink
    self.selectedColor = opts.selectedColor or theme.colors.accent
    self.disabledColor = opts.disabledColor or theme.colors.faded
    self.shadow = opts.shadow
    if self.shadow == nil and theme.textShadow then
        self.shadow = true
    end
    self.cancel = opts.cancel
    self.onMove = opts.onMove
    self.time = 0
    self.rects = {}
    self.active = true
    self:setItems(items, opts.index)
end

function Menu:setItems(items, index)
    self.items = items
    self.index = index or 1
    if self.items[self.index] and not isEnabled(self.items[self.index]) then
        self:move(1, true)
    end
end

function Menu:selected()
    return self.items[self.index]
end

function Menu:move(delta, silent)
    local n = #self.items
    if n == 0 then
        return
    end
    for _ = 1, n do
        self.index = (self.index - 1 + delta) % n + 1
        if isEnabled(self.items[self.index]) then
            break
        end
    end
    if not silent then
        sound("move")
        if self.onMove then
            self.onMove(self.index)
        end
    end
end

local function labelOf(item)
    local label = item.label
    if type(label) == "function" then
        label = label()
    end
    if item.value then
        label = label .. ":  < " .. tostring(item.value()) .. " >"
    end
    return label
end

function Menu:getWidth()
    if self.width then
        return self.width
    end
    local w = 0
    for _, item in ipairs(self.items) do
        w = math.max(w, self.font:getWidth(labelOf(item)))
    end
    return w
end

function Menu:getHeight()
    return #self.items * self.spacing
end

function Menu:choose()
    local item = self.items[self.index]
    if not item then
        return nil
    end
    if not isEnabled(item) then
        sound("error")
        return nil
    end
    sound("select")
    input.consume("confirm")
    if item.action then
        item.action(item, self)
        return nil
    end
    return self.index
end

function Menu:update(dt)
    self.time = self.time + dt
    if not self.active or #self.items == 0 then
        return nil
    end
    if input.pressed("up", true) then
        self:move(-1)
    elseif input.pressed("down", true) then
        self:move(1)
    end
    local item = self.items[self.index]
    if item and item.change and isEnabled(item) then
        if input.pressed("left", true) then
            item.change(-1)
            sound("move")
        elseif input.pressed("right", true) then
            item.change(1)
            sound("move")
        end
    end
    -- mouse: hover selects, click chooses
    local m = input.mouse
    local clicked = false
    for i, r in pairs(self.rects) do
        if util.pointInRect(m.x, m.y, r[1], r[2], r[3], r[4]) and isEnabled(self.items[i]) then
            if m.moved and i ~= self.index then
                self.index = i
                sound("move")
            end
            if m.pressed[1] then
                self.index = i
                clicked = true
            end
        end
    end
    if input.pressed("confirm") or clicked then
        return self:choose()
    elseif input.pressed("cancel") and self.cancel then
        sound("back")
        input.consume("cancel")
        self.cancel()
    end
    return nil
end

function Menu:draw(x, y)
    local lg = love.graphics
    local font = self.font
    lg.setFont(font)
    local width = self:getWidth()
    local bob = math.floor(math.abs(math.sin(self.time * 5)) * 4 + 0.5)
    local px = theme.pixelOf(font)
    local shadowColor = theme.colors.shadow
    self.rects = {}
    local function text(label, tx, ty, color)
        if self.shadow then
            lg.setColor(shadowColor)
            lg.print(label, tx + px, ty + px)
        end
        lg.setColor(color)
        lg.print(label, tx, ty)
    end
    for i, item in ipairs(self.items) do
        local label = labelOf(item)
        local selected = i == self.index and self.active
        local enabled = isEnabled(item)
        local iy = y + (i - 1) * self.spacing
        local color = not enabled and self.disabledColor or (selected and self.selectedColor or self.color)
        if self.style == "buttons" then
            local image = theme.image(selected and "buttonActive" or "button")
            local bh
            if image then
                local s = width / image:getWidth()
                bh = image:getHeight() * s
                lg.setColor(1, 1, 1, enabled and 1 or 0.6)
                lg.draw(image, math.floor(x), math.floor(iy), 0, s, s)
            else
                bh = self.spacing - 8
                lg.setColor(1, 1, 1, enabled and 1 or 0.7)
                panel.draw(x, iy, width, bh, selected and "active" or "small")
            end
            local tw = font:getWidth(label)
            text(label, math.floor(x + (width - tw) / 2), math.floor(iy + (bh - font:getHeight()) / 2 + 1), color)
            if selected then
                lg.setColor(1, 1, 1, 1)
                panel.cursor(x - 4 + bob, iy + bh / 2, theme.cursorScale)
            end
            self.rects[i] = { x, iy, width, bh }
        else
            local tw = font:getWidth(label)
            local tx = self.align == "center" and math.floor(x + (width - tw) / 2) or x
            text(label, tx, iy, color)
            if selected then
                lg.setColor(1, 1, 1, 1)
                panel.cursor(tx - 6 + bob, iy + font:getHeight() / 2, theme.cursorScale)
            end
            self.rects[i] = { x - 30, iy - 4, width + 30, self.spacing }
        end
    end
    lg.setColor(1, 1, 1, 1)
end

return Menu
