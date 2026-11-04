-- Sky sphere around a turning camera (like a 3D engine sky: Godot, WorldBox...).
-- The battle draws it behind the field: turning the camera turns the sky, a view
-- from above tilts it down to the ground, a view from behind shows the horizon.
--
--   local sky = Sky(def)            -- def from game/data/skies.lua or a table
--   sky:update(dt)
--   sky:draw(yaw, pitch, fov)       -- radians; pitch < 0 looks down
--   sky:draw(yaw, pitch, fov, w, h, flip)  -- into a canvas of w x h; flip = mirrored
--
-- def fields (colors are { r, g, b } or "#rrggbb"):
--   top, horizon            sky gradient            ground, groundHorizon   the ground
--   sun = { yaw, pitch, color, size }  (pitch < 0 hides it)
--   clouds 0..1, cloudColor, stars 0..1 (night), grid 0..1 (ground pattern)
--   band = "mountains"      a background from game/data/backgrounds.lua wrapped
--                           around the horizon as a panorama (opaque sky layers
--                           are skipped, so the real sky stays visible)
--   bandRepeat = 5          how many times the art repeats in a full turn
--   bandDrop = 0.03         how deep the band sinks below the horizon (radians)
--   panorama = "path.png"   or a ready equirectangular panorama for the band:
--                           bandLat = { bottom, top } latitudes in radians
-- Shader: assets/shaders/sky.glsl. Without shaders the gradient is drawn by hand.

local assets = require("engine.assets")
local class = require("engine.class")
local screen = require("engine.screen")
local shaders = require("engine.shaders")
local util = require("engine.util")

local Sky = class()

local function color(c, default)
    if type(c) == "string" then
        return util.hexColor(c)
    end
    return c or default
end

function Sky:init(def, backgrounds)
    def = def or {}
    self.def = def
    self.top = color(def.top, { 0.22, 0.42, 0.78 })
    self.horizon = color(def.horizon, { 0.72, 0.86, 0.96 })
    self.ground = color(def.ground, { 0.2, 0.3, 0.16 })
    self.groundHorizon = color(def.groundHorizon, { 0.45, 0.55, 0.42 })
    self.cloudColor = color(def.cloudColor, { 1, 1, 1 })
    local sun = def.sun or {}
    local sy, sp = sun.yaw or 0.7, sun.pitch or 0.35
    self.sunDir = { math.sin(sy) * math.cos(sp), math.sin(sp), math.cos(sy) * math.cos(sp) }
    self.sunColor = color(sun.color, { 1, 0.95, 0.8 })
    self.sunSize = sun.size or 0.035
    if def.sun == false then
        self.sunColor = { 0, 0, 0 }
        self.sunSize = 0
    end
    self.clouds, self.stars, self.grid = def.clouds or 0, def.stars or 0, def.grid or 0.35
    self.white = love.graphics.newImage(love.image.newImageData(1, 1, "rgba8", string.char(255, 255, 255, 255)))
    -- the panorama band
    if def.panorama then
        self.band = assets.image(def.panorama)
        self.band:setWrap("repeat", "clamp")
        self.bandLat = def.bandLat or { -0.05, 0.6 }
    elseif def.band and backgrounds and backgrounds[def.band] then
        self:buildBand(backgrounds[def.band], def.bandRepeat or 5, def.bandDrop or 0.03)
    end
end

-- glue the transparent layers of a parallax background into one wide strip
function Sky:buildBand(bg, repeats, drop)
    local layers = {}
    local height = 0
    for _, l in ipairs(bg.layers or {}) do
        local image = assets.image(l.image)
        local data = love.image.newImageData(l.image)
        local _, _, _, a = data:getPixel(0, 0)
        -- skip layers that are opaque at the top-left corner (a painted sky)
        if a < 0.5 and l.blend ~= "add" then
            table.insert(layers, { image = image, def = l })
            height = math.max(height, image:getHeight())
        end
    end
    if #layers == 0 then
        return
    end
    local width = 0
    for _, l in ipairs(layers) do
        width = math.max(width, l.image:getWidth())
    end
    local W = width * repeats
    local canvas = love.graphics.newCanvas(W, height)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    for _, l in ipairs(layers) do
        local iw, ih = l.image:getDimensions()
        -- a whole number of copies, slightly stretched, so the strip wraps without a seam
        local n = math.max(1, math.floor(W / iw + 0.5))
        local sx = W / (n * iw)
        for i = 0, n - 1 do
            love.graphics.draw(l.image, i * iw * sx, height - ih, 0, sx, 1)
        end
    end
    love.graphics.pop()
    canvas:setFilter("nearest", "nearest")
    canvas:setWrap("repeat", "clamp")
    self.band = canvas
    -- square art pixels: the strip covers a full turn horizontally
    local h = (2 * math.pi / W) * height
    self.bandLat = { -drop, h - drop }
end

function Sky:update(dt)
end

-- vertical field of view -> focal length in pixels (to move flat things with the sky)
function Sky.focal(fov)
    return (screen.height / 2) / math.tan((fov or 1.05) / 2)
end

function Sky:draw(yaw, pitch, fov, w, h, flip)
    local lg = love.graphics
    fov = fov or 1.05
    w, h = w or screen.width, h or screen.height
    local sh = shaders.get("sky")
    if not sh then
        -- no shaders: a plain gradient with the horizon at the right height
        local f = (h / 2) / math.tan(fov / 2)
        local hy = h / 2 + math.tan(pitch) * f
        local band = h / 9
        lg.setColor(self.top)
        lg.rectangle("fill", 0, 0, w, h)
        lg.setColor(self.horizon)
        lg.rectangle("fill", 0, hy - band, w, band)
        lg.setColor(self.groundHorizon)
        lg.rectangle("fill", 0, hy, w, h)
        lg.setColor(1, 1, 1, 1)
        return
    end
    shaders.send(sh, "screenSize", { w, h })
    shaders.send(sh, "flipX", flip and 1 or 0)
    shaders.send(sh, "yaw", yaw)
    shaders.send(sh, "pitch", pitch)
    shaders.send(sh, "fov", fov)
    shaders.send(sh, "topColor", self.top)
    shaders.send(sh, "horizonColor", self.horizon)
    shaders.send(sh, "groundColor", self.ground)
    shaders.send(sh, "groundHorizon", self.groundHorizon)
    shaders.send(sh, "sunDir", self.sunDir)
    shaders.send(sh, "sunColor", self.sunColor)
    shaders.send(sh, "sunSize", self.sunSize)
    shaders.send(sh, "clouds", self.clouds)
    shaders.send(sh, "cloudColor", self.cloudColor)
    shaders.send(sh, "stars", self.stars)
    shaders.send(sh, "grid", self.grid)
    shaders.send(sh, "useBand", self.band and 1 or 0)
    if self.band then
        shaders.send(sh, "band", self.band)
        shaders.send(sh, "bandLat", self.bandLat)
    end
    lg.setShader(sh)
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.white, 0, 0, 0, w, h)
    lg.setShader()
end

return Sky
