-- Parallax backgrounds made of repeating image layers.
--
--   local bg = Background(def)        -- def from game/data/backgrounds.lua
--   bg:update(dt)
--   bg:draw(cameraX, cameraY)         -- camera position in world pixels (0, 0 = still)
--
-- def = { color = { r, g, b }, layers = { layer, ... } }, layer fields:
--   image      path
--   scale      size of one art pixel on the screen (default 4)
--   x, y       position of the layer on the screen (y = top)
--   speed      automatic scrolling in screen pixels per second
--   parallax   how much the layer follows the camera (0 = sky, 1 = foreground)
--   parallaxY  the same vertically (default 0)
--   tileY      repeat downwards too
--   fill       color drawn below the layer (to cover the screen bottom)
--   shader     "water" (animated waves) or "sway" (trees in the wind)
--   sway       sway amount in art pixels
--   blend      "add" for light rays, alpha = transparency, color = tint

local assets = require("engine.assets")
local class = require("engine.class")
local screen = require("engine.screen")
local shaders = require("engine.shaders")

local Background = class()

local emptyImage

function Background:init(def)
    self.def = def or { color = { 0, 0, 0 }, layers = {} }
    self.time = 0
    self.layers = {}
    for _, l in ipairs(self.def.layers or {}) do
        local image = assets.image(l.image)
        image:setWrap("repeat", l.tileY and "repeat" or "clampzero")
        table.insert(self.layers, { def = l, image = image, scroll = 0 })
    end
end

function Background:update(dt)
    self.time = self.time + dt
    for _, layer in ipairs(self.layers) do
        layer.scroll = layer.scroll + (layer.def.speed or 0) * dt
    end
end

local function applyShader(layer, s, ox)
    local l = layer.def
    if l.shader == "sway" then
        local sh = shaders.get("sway")
        if sh then
            shaders.send(sh, "textureSize", { layer.image:getWidth(), layer.image:getHeight() })
            shaders.send(sh, "amount", l.sway or 1)
            love.graphics.setShader(sh)
        end
    elseif l.shader == "water" then
        local sh = shaders.get("water")
        if sh then
            if not emptyImage then
                emptyImage = love.graphics.newImage(love.image.newImageData(1, 1))
            end
            shaders.send(sh, "canvasSize", { layer.image:getWidth(), layer.image:getHeight() })
            shaders.send(sh, "worldOffset", { 0, 0 })
            shaders.send(sh, "zoom", 1)
            shaders.send(sh, "maskMode", 0)
            shaders.send(sh, "waveHeight", l.waves or 1)
            shaders.send(sh, "reflectionStrength", 0)
            shaders.send(sh, "reflection", emptyImage)
            love.graphics.setShader(sh)
        end
    end
end

function Background:draw(cameraX, cameraY)
    local lg = love.graphics
    cameraX, cameraY = cameraX or 0, cameraY or 0
    local c = self.def.color or { 0, 0, 0 }
    lg.clear(c[1], c[2], c[3], 1)
    local W, H = screen.width, screen.height
    for _, layer in ipairs(self.layers) do
        local l = layer.def
        local s = l.scale or 4
        local iw, ih = layer.image:getDimensions()
        local ox = layer.scroll + cameraX * (l.parallax or 0) - (l.x or 0)
        local y = (l.y or 0) - cameraY * (l.parallaxY or 0)
        if l.fill then
            lg.setColor(l.fill)
            lg.rectangle("fill", 0, y + ih * s, W, H)
        end
        local qw = math.ceil(W / s) + 2
        local qh = l.tileY and math.ceil((H - y) / s) + 2 or ih
        local quad = layer.quad
        local qx = math.floor(ox / s) % iw
        if not quad then
            quad = lg.newQuad(0, 0, qw, qh, iw, ih)
            layer.quad = quad
        end
        quad:setViewport(qx, 0, qw, qh, iw, ih)
        local col = l.color or { 1, 1, 1 }
        lg.setColor(col[1], col[2], col[3], l.alpha or 1)
        if l.blend == "add" then
            lg.setBlendMode("add")
        end
        applyShader(layer, s, ox)
        lg.draw(layer.image, quad, -(ox % s), math.floor(y), 0, s, s)
        lg.setShader()
        lg.setBlendMode("alpha")
    end
    lg.setColor(1, 1, 1, 1)
end

return Background
