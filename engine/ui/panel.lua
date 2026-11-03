-- 9-slice panels: corners are drawn as is, borders are stretched and the
-- middle is tiled, so a small image makes a box of any size.
--
--   panel.draw(x, y, w, h)                          -- default style (theme.panel)
--   panel.draw(x, y, w, h, { image = "...", border = 4, scale = 2, shadow = true })

local assets = require("engine.assets")
local theme = require("engine.ui.theme")

local panel = {}

local built = {}

local function build(style)
    local data = built[style.image .. "#" .. style.border]
    if data then
        return data
    end
    local image = assets.image(style.image)
    local iw, ih = image:getDimensions()
    local b = style.border
    local function q(x, y, w, h)
        return love.graphics.newQuad(x, y, w, h, iw, ih)
    end
    data = {
        image = image, b = b, iw = iw, ih = ih,
        tl = q(0, 0, b, b), tr = q(iw - b, 0, b, b),
        bl = q(0, ih - b, b, b), br = q(iw - b, ih - b, b, b),
        top = q(b, 0, iw - 2 * b, b), bottom = q(b, ih - b, iw - 2 * b, b),
        left = q(0, b, b, ih - 2 * b), right = q(iw - b, b, b, ih - 2 * b),
        center = assets.tiled(style.image, b, b, iw - 2 * b, ih - 2 * b),
        quads = {},
    }
    built[style.image .. "#" .. style.border] = data
    return data
end

local function centerQuad(d, w, h)
    local key = w .. "x" .. h
    local quad = d.quads[key]
    if not quad then
        quad = love.graphics.newQuad(0, 0, w, h, d.center:getDimensions())
        d.quads[key] = quad
    end
    return quad
end

function panel.draw(x, y, w, h, style)
    style = style or theme.panel
    local d = build(style)
    local s = style.scale or 1
    local b = d.b * s
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    w, h = math.max(math.floor(w + 0.5), b * 2), math.max(math.floor(h + 0.5), b * 2)
    local lg = love.graphics
    local r, g, bl, a = lg.getColor()
    if style.shadow ~= false then
        lg.setColor(0, 0, 0, 0.35 * a)
        lg.rectangle("fill", x + 4, y + 4, w, h)
        lg.setColor(r, g, bl, a)
    end
    local cw, ch = w - 2 * b, h - 2 * b
    if cw > 0 and ch > 0 then
        lg.draw(d.center, centerQuad(d, math.ceil(cw / s), math.ceil(ch / s)), x + b, y + b, 0, s, s)
    end
    local ew, eh = d.iw - 2 * d.b, d.ih - 2 * d.b
    lg.draw(d.image, d.top, x + b, y, 0, cw / ew, s)
    lg.draw(d.image, d.bottom, x + b, y + h - b, 0, cw / ew, s)
    lg.draw(d.image, d.left, x, y + b, 0, s, ch / eh)
    lg.draw(d.image, d.right, x + w - b, y + b, 0, s, ch / eh)
    lg.draw(d.image, d.tl, x, y, 0, s, s)
    lg.draw(d.image, d.tr, x + w - b, y, 0, s, s)
    lg.draw(d.image, d.bl, x, y + h - b, 0, s, s)
    lg.draw(d.image, d.br, x + w - b, y + h - b, 0, s, s)
end

-- Image stretched to a width keeping its proportions (scrolls, buttons).
function panel.image(name, x, y, w, color)
    local image = theme.image(name)
    local s = w / image:getWidth()
    if color then
        love.graphics.setColor(color)
    end
    love.graphics.draw(image, math.floor(x), math.floor(y), 0, s, s)
    love.graphics.setColor(1, 1, 1, 1)
    return image:getHeight() * s
end

return panel
