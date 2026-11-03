-- Windows (panels) of any size.
--   * "window" style: drawn by code - a gradient with 4 corner colors,
--     rounded corners, a light frame and a dark edge (Final Fantasy-like)
--   * image style: 9-slice - corners as is, borders stretched, middle tiled
--
--   panel.draw(x, y, w, h)                       -- theme.window
--   panel.draw(x, y, w, h, "small")              -- theme.smallWindow ("active" = highlighted)
--   panel.draw(x, y, w, h, { image = "...", border = 4, scale = 2, shadow = true })

local assets = require("engine.assets")
local theme = require("engine.ui.theme")
local util = require("engine.util")

local panel = {}

local function toColor(c)
    if type(c) == "string" then
        return util.hexColor(c)
    end
    return c
end

-- image 9-slice ---------------------------------------------------------------

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

local function drawImage(x, y, w, h, style)
    local d = build(style)
    local s = style.scale or 1
    local b = d.b * s
    w, h = math.max(w, b * 2), math.max(h, b * 2)
    local lg = love.graphics
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

-- code-drawn window -----------------------------------------------------------

local meshes, meshCount = {}, 0

-- a rounded rectangle as a triangle fan, the color of every vertex is mixed
-- from the 4 corner colors
local function windowMesh(w, h, r, colors)
    local key = w .. "x" .. h .. "r" .. r .. tostring(colors)
    local mesh = meshes[key]
    if mesh then
        return mesh
    end
    if meshCount > 300 then
        meshes, meshCount = {}, 0
    end
    local tl, tr, bl, br = toColor(colors[1]), toColor(colors[2]), toColor(colors[3]), toColor(colors[4] or colors[3])
    local function vertex(px, py)
        local u, v = px / w, py / h
        local c = {}
        for i = 1, 3 do
            local top = tl[i] + (tr[i] - tl[i]) * u
            local bottom = bl[i] + (br[i] - bl[i]) * u
            c[i] = top + (bottom - top) * v
        end
        return { px, py, 0, 0, c[1], c[2], c[3], 1 }
    end
    local verts = { vertex(w / 2, h / 2) }
    local corners = { { w - r, r, -90 }, { w - r, h - r, 0 }, { r, h - r, 90 }, { r, r, 180 } }
    local steps = r > 0 and 4 or 1
    for _, c in ipairs(corners) do
        for i = 0, steps do
            local a = math.rad(c[3] + 90 * i / steps)
            table.insert(verts, vertex(c[1] + math.cos(a) * r, c[2] + math.sin(a) * r))
        end
    end
    table.insert(verts, verts[2])
    mesh = love.graphics.newMesh(verts, "fan", "static")
    meshes[key] = mesh
    meshCount = meshCount + 1
    return mesh
end

local function drawWindow(x, y, w, h, style)
    local lg = love.graphics
    local r, g, b, a = lg.getColor()
    local alpha = a * (style.alpha or 1)
    local radius = math.min(style.radius or 6, math.floor(math.min(w, h) / 2))
    lg.setColor(r, g, b, alpha)
    lg.draw(windowMesh(w, h, radius, style.colors), x, y)
    local oldWidth, oldStyle = lg.getLineWidth(), lg.getLineStyle()
    lg.setLineStyle("rough")
    if style.edge then
        local e = toColor(style.edge)
        lg.setColor(e[1], e[2], e[3], a)
        lg.setLineWidth(2)
        lg.rectangle("line", x - 1, y - 1, w + 2, h + 2, radius + 1, radius + 1, 6)
    end
    local c = toColor(style.border or { 1, 1, 1 })
    lg.setColor(c[1], c[2], c[3], a)
    lg.setLineWidth(style.borderWidth or 2)
    lg.rectangle("line", x + 1, y + 1, w - 2, h - 2, math.max(radius - 1, 0), math.max(radius - 1, 0), 6)
    -- soft inner line under the frame
    lg.setColor(0, 0, 0, a * 0.25)
    lg.setLineWidth(1)
    lg.rectangle("line", x + 3.5, y + 3.5, w - 7, h - 7, math.max(radius - 3, 0), math.max(radius - 3, 0), 6)
    lg.setLineWidth(oldWidth)
    lg.setLineStyle(oldStyle)
    lg.setColor(r, g, b, a)
end

-- style: nil (theme.window), "small", "active", or a style table
function panel.style(style)
    if style == nil or style == "window" then
        return theme.window
    elseif style == "small" then
        return theme.smallWindow
    elseif style == "active" then
        return theme.activeWindow
    end
    return style
end

function panel.draw(x, y, w, h, style)
    style = panel.style(style)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    w, h = math.max(math.floor(w + 0.5), 8), math.max(math.floor(h + 0.5), 8)
    local lg = love.graphics
    local r, g, b, a = lg.getColor()
    if style.shadow ~= false then
        lg.setColor(0, 0, 0, 0.3 * a)
        lg.rectangle("fill", x + 4, y + 5, w, h, style.radius or 0)
        lg.setColor(r, g, b, a)
    end
    if style.image then
        drawImage(x, y, w, h, style)
    else
        drawWindow(x, y, w, h, style)
    end
end

-- Image stretched to a width keeping its proportions (scrolls, buttons).
-- Without the image (FF style) a window is drawn: height = opts.h or 56.
function panel.image(name, x, y, w, color, h)
    local image = theme.image(name)
    if not image then
        h = h or 56
        if color then
            love.graphics.setColor(color)
        end
        panel.draw(x, y, w, h, name == "buttonActive" and "active" or "small")
        love.graphics.setColor(1, 1, 1, 1)
        return h
    end
    local s = w / image:getWidth()
    if color then
        love.graphics.setColor(color)
    end
    love.graphics.draw(image, math.floor(x), math.floor(y), 0, s, s)
    love.graphics.setColor(1, 1, 1, 1)
    return image:getHeight() * s
end

-- small triangle "more text" / scroll markers, drawn by code
function panel.arrow(x, y, dir, size, color)
    local lg = love.graphics
    size = size or 10
    local pts
    if dir == "up" then
        pts = { x, y - size / 2, x + size / 2, y + size / 2, x - size / 2, y + size / 2 }
    elseif dir == "left" then
        pts = { x - size / 2, y, x + size / 2, y - size / 2, x + size / 2, y + size / 2 }
    elseif dir == "right" then
        pts = { x + size / 2, y, x - size / 2, y - size / 2, x - size / 2, y + size / 2 }
    else
        pts = { x - size / 2, y - size / 2, x + size / 2, y - size / 2, x, y + size / 2 }
    end
    local r, g, b, a = lg.getColor()
    lg.setColor(0, 0, 0, 0.7 * a)
    lg.push()
    lg.translate(2, 2)
    lg.polygon("fill", pts)
    lg.pop()
    local c = color or { 1, 1, 1 }
    lg.setColor(c[1], c[2], c[3], (c[4] or 1) * a)
    lg.polygon("fill", pts)
    lg.setColor(r, g, b, a)
end

-- the menu cursor: the hand (FF) or the arrow image; x, y = where it points
function panel.cursor(x, y, scale)
    local image = theme.image("cursor")
    if not image then
        panel.arrow(x - 8, y, "right", 14)
        return
    end
    scale = scale or 1
    local w, h = image:getDimensions()
    love.graphics.draw(image, math.floor(x - w * scale), math.floor(y - h * scale / 2), 0, scale, scale)
end

return panel
