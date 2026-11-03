-- UI toolkit: panels, text, menus, the dialogue box, HUD helpers and toasts.
--
--   ui.say("bunny", "Привет!")                      -- quick dialogue (see engine/dialogue.lua)
--   ui.ask("Вы согласны или нет?", { "Да", "Нет" }, function(i) ... end)
--   ui.toast("Подобрано: морковь", { icon = "carrot" })
--   ui.panel.draw(x, y, w, h)
--   ui.print("Текст", x, y, { font = "small", color = "accent", align = "center", width = 200 })
--   ui.hearts(x, y, hp, maxHp)
--   ui.keyHint(x, y, "interact", "Поднять")

local assets = require("engine.assets")
local input = require("engine.input")
local screen = require("engine.screen")

local ui = {
    theme = require("engine.ui.theme"),
    panel = require("engine.ui.panel"),
    Text = require("engine.ui.text"),
    Menu = require("engine.ui.menu"),
    DialogBox = require("engine.ui.dialogbox"),
}

local theme = ui.theme

function ui.font(name)
    return theme.font(name)
end

-- opts: font (name or Font), color (name or table), align, width, shadow (true / color)
function ui.print(text, x, y, opts)
    opts = opts or {}
    local font = type(opts.font) == "string" and theme.font(opts.font) or opts.font or theme.font("body")
    local color = theme.color(opts.color or "ink")
    love.graphics.setFont(font)
    text = tostring(text)
    local width = opts.width
    local tx = x
    if opts.align == "center" then
        tx = width and x + math.floor((width - font:getWidth(text)) / 2) or x - math.floor(font:getWidth(text) / 2)
    elseif opts.align == "right" then
        tx = width and x + width - font:getWidth(text) or x - font:getWidth(text)
    end
    tx, y = math.floor(tx), math.floor(y)
    if opts.shadow then
        local s = opts.shadow == true and theme.colors.shadow or opts.shadow
        love.graphics.setColor(s)
        love.graphics.print(text, tx + 2, y + 2)
    end
    if opts.outline then
        love.graphics.setColor(theme.color(opts.outline))
        for _, o in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }) do
            love.graphics.print(text, tx + o[1], y + o[2])
        end
    end
    love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * (opts.alpha or 1))
    love.graphics.print(text, tx, y)
    love.graphics.setColor(1, 1, 1, 1)
    return font:getWidth(text)
end

function ui.icon(name, x, y, scale, alpha)
    local image = assets.image(theme.icons .. name .. ".png")
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(image, math.floor(x), math.floor(y), 0, scale or 1, scale or 1)
    love.graphics.setColor(1, 1, 1, 1)
    return image:getWidth() * (scale or 1)
end

function ui.dim(alpha)
    local c = theme.colors.dim
    love.graphics.setColor(c[1], c[2], c[3], alpha or c[4])
    love.graphics.rectangle("fill", 0, 0, screen.width, screen.height)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Hearts HUD: every heart is 2 hp (full / half / empty).
local heartQuads
function ui.hearts(x, y, hp, maxHp, scale)
    local image = theme.image("hearts")
    if not heartQuads then
        heartQuads = {
            full = assets.quad(image, 0, 0, 36, 32),
            half = assets.quad(image, 38, 0, 36, 32),
            empty = assets.quad(image, 76, 0, 36, 32),
        }
    end
    scale = scale or 0.75
    local count = math.ceil(maxHp / 2)
    for i = 1, count do
        local value = hp - (i - 1) * 2
        local quad = value >= 2 and heartQuads.full or (value == 1 and heartQuads.half or heartQuads.empty)
        love.graphics.draw(image, quad, math.floor(x + (i - 1) * 38 * scale), math.floor(y), 0, scale, scale)
    end
end

-- Simple bar (hp, timing): a dark frame and a colored fill.
function ui.bar(x, y, w, h, value, max, color, back)
    local k = math.max(0, math.min(1, value / math.max(max, 1e-6)))
    love.graphics.setColor(0.1, 0.07, 0.05, 0.9)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
    love.graphics.setColor(back or { 0.3, 0.22, 0.15, 1 })
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(theme.color(color or "red"))
    love.graphics.rectangle("fill", x, y, math.floor(w * k + 0.5), h)
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.rectangle("fill", x, y, math.floor(w * k + 0.5), math.max(1, math.floor(h / 3)))
    love.graphics.setColor(1, 1, 1, 1)
end

-- "[E] Поднять" centered on x: a small parchment key cap and a label.
function ui.keyHint(x, y, action, label, opts)
    opts = opts or {}
    local font = theme.font("small")
    local key = input.keyName(action)
    local kw = math.max(font:getWidth(key) + 12, 22)
    local lw = label and font:getWidth(label) + 8 or 0
    local total = kw + lw
    local left = math.floor(x - total / 2)
    ui.panel.draw(left, y, kw, 22, theme.smallPanel)
    ui.print(key, left + kw / 2, y + 3, { font = font, align = "center" })
    if label then
        ui.print(label, left + kw + 6, y + 3, { font = font, color = opts.color or "light", shadow = true })
    end
end

-- Scroll banner with a centered title (chapter names, results).
function ui.banner(text, cx, y, w, opts)
    opts = opts or {}
    local h = ui.panel.image("scroll", cx - w / 2, y, w)
    local font = theme.font(opts.font or "body")
    ui.print(text, cx, y + (h - font:getHeight()) / 2 + 1, { font = font, align = "center", color = opts.color or "ink" })
    return h
end

-- toasts ----------------------------------------------------------------------

local toasts = {}

-- opts: icon (name in assets/sprites/icons), time, color
function ui.toast(text, opts)
    opts = opts or {}
    table.insert(toasts, { text = text, icon = opts.icon, time = opts.time or 2.2, t = 0, color = opts.color })
    while #toasts > 4 do
        table.remove(toasts, 1)
    end
end

function ui.update(dt)
    for i = #toasts, 1, -1 do
        local t = toasts[i]
        t.t = t.t + dt
        if t.t >= t.time then
            table.remove(toasts, i)
        end
    end
end

function ui.drawToasts()
    local font = theme.font("small")
    local y = 16
    for _, t in ipairs(toasts) do
        local alpha = math.min(1, t.t * 6, (t.time - t.t) * 3)
        local iconW = t.icon and 30 or 0
        local w = font:getWidth(t.text) + 32 + iconW
        local x = math.floor((screen.width - w) / 2)
        local slide = math.floor((1 - math.min(1, t.t * 6)) * -12)
        love.graphics.setColor(1, 1, 1, alpha)
        ui.panel.draw(x, y + slide, w, 34)
        if t.icon then
            ui.icon(t.icon, x + 12, y + slide + 4, 0.75, alpha)
        end
        ui.print(t.text, x + 16 + iconW, y + slide + 9, { font = font, color = t.color or "ink", alpha = alpha })
        y = y + 40
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function ui.clearToasts()
    toasts = {}
end

-- dialogue shortcuts ------------------------------------------------------------

function ui.say(who, text, onDone)
    local dialogue = require("engine.dialogue")
    return dialogue.run(function(d) d:say(who, text) end, { onDone = onDone })
end

function ui.ask(question, options, onDone, who)
    local dialogue = require("engine.dialogue")
    return dialogue.run(function(d) return d:choice(question, options, who) end, { onDone = onDone })
end

return ui
