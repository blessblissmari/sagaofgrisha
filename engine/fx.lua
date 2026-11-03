-- Visual effects: particles, floating numbers and sprite sheet effects.
-- A Layer is drawn in whatever space is active (world camera or screen).
--
--   fx.define("hit", { image = "assets/sprites/fx/weaponhit.png", frame = 100, columns = 6, count = 30 })
--   local effects = fx.Layer()
--   effects:play("hit", x, y, { scale = 0.5 })
--   effects:burst(x, y, { count = 10, color = { 1, 0.8, 0.2 }, speed = 90 })
--   effects:popup(x, y, "-12", { color = { 1, 0.3, 0.3 } })
--   effects:update(dt); effects:draw()

local assets = require("engine.assets")
local class = require("engine.class")

local fx = { effects = {}, font = nil }

-- def: image, frame (size, square) or frameWidth/frameHeight, columns,
--      count (frames), fps, blend ("add" for glowing effects),
--      x, y (where the frames start in the image, default 0, 0)
function fx.define(name, def)
    fx.effects[name] = def
end

local sheets = {}
local function sheetOf(def)
    local sheet = sheets[def]
    if sheet then
        return sheet
    end
    local image = assets.image(def.image)
    local fw, fh = def.frameWidth or def.frame, def.frameHeight or def.frame
    local quads = {}
    for i = 0, def.count - 1 do
        local cx, cy = i % def.columns, math.floor(i / def.columns)
        quads[i + 1] = love.graphics.newQuad((def.x or 0) + cx * fw, (def.y or 0) + cy * fh, fw, fh, image:getDimensions())
    end
    sheet = { image = image, quads = quads, fw = fw, fh = fh }
    sheets[def] = sheet
    return sheet
end

local Layer = class()
fx.Layer = Layer

function Layer:init()
    self.particles, self.popups, self.sprites = {}, {}, {}
end

function Layer:clear()
    self.particles, self.popups, self.sprites = {}, {}, {}
end

-- opts: count, color, speed, angle + spread (radians), life, size, gravity, drag, up
function Layer:burst(x, y, opts)
    opts = opts or {}
    local speed = opts.speed or 80
    for _ = 1, opts.count or 8 do
        local a = (opts.angle or 0) + (love.math.random() * 2 - 1) * (opts.spread or math.pi)
        local s = speed * (0.35 + 0.65 * love.math.random())
        local life = (opts.life or 0.5) * (0.6 + 0.4 * love.math.random())
        table.insert(self.particles, {
            x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s - (opts.up or 0),
            life = life, maxLife = life, size = opts.size or 2,
            color = opts.color or { 1, 1, 1 }, gravity = opts.gravity or 0, drag = opts.drag or 2,
        })
    end
end

-- Floating text that jumps up and fades (damage numbers, "+1 морковь").
-- The font: opts.font, else layer.font (set it for zoomed worlds), else fx.font.
function Layer:popup(x, y, text, opts)
    opts = opts or {}
    table.insert(self.popups, {
        x = x, y = y, text = tostring(text), t = 0, life = opts.life or 0.9,
        vy = opts.vy or -70, color = opts.color or { 1, 1, 1 },
        font = opts.font or self.font or fx.font, scale = opts.scale or 1,
    })
end

-- opts: scale, color, rotation, speed (fps multiplier), follow (entity)
function Layer:play(name, x, y, opts)
    local def = fx.effects[name]
    if not def then
        print("[fx] unknown effect: " .. tostring(name))
        return
    end
    opts = opts or {}
    local item = {
        def = def, sheet = sheetOf(def), x = x, y = y, t = 0,
        scale = opts.scale or 1, color = opts.color, rotation = opts.rotation or 0,
        fps = (def.fps or 40) * (opts.speed or 1), follow = opts.follow,
    }
    table.insert(self.sprites, item)
    return item
end

function Layer:update(dt)
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(self.particles, i)
        else
            local k = math.exp(-p.drag * dt)
            p.vx, p.vy = p.vx * k, p.vy * k + p.gravity * dt
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        end
    end
    for i = #self.popups, 1, -1 do
        local p = self.popups[i]
        p.t = p.t + dt
        p.vy = p.vy + 160 * dt
        p.y = p.y + p.vy * dt
        if p.t >= p.life then
            table.remove(self.popups, i)
        end
    end
    for i = #self.sprites, 1, -1 do
        local s = self.sprites[i]
        s.t = s.t + dt
        if s.follow then
            s.x, s.y = s.follow.x, s.follow.y - (s.follow.height or 16) / 2
        end
        if s.t * s.fps >= #s.sheet.quads then
            table.remove(self.sprites, i)
        end
    end
end

function Layer:isEmpty()
    return #self.particles == 0 and #self.popups == 0 and #self.sprites == 0
end

function Layer:draw()
    for _, p in ipairs(self.particles) do
        local c = p.color
        love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * math.min(1, p.life / p.maxLife * 2))
        local s = p.size
        love.graphics.rectangle("fill", math.floor(p.x - s / 2), math.floor(p.y - s / 2), s, s)
    end
    for _, s in ipairs(self.sprites) do
        local frame = math.min(#s.sheet.quads, math.floor(s.t * s.fps) + 1)
        if s.def.blend == "add" then
            love.graphics.setBlendMode("add")
        end
        love.graphics.setColor(s.color or { 1, 1, 1, 1 })
        love.graphics.draw(s.sheet.image, s.sheet.quads[frame], math.floor(s.x), math.floor(s.y),
            s.rotation, s.scale, s.scale, s.sheet.fw / 2, s.sheet.fh / 2)
        love.graphics.setBlendMode("alpha")
    end
    for _, p in ipairs(self.popups) do
        local font = p.font or love.graphics.getFont()
        local alpha = math.min(1, (p.life - p.t) / 0.3)
        local w = font:getWidth(p.text) * p.scale
        local x, y = math.floor(p.x - w / 2), math.floor(p.y)
        love.graphics.setFont(font)
        love.graphics.setColor(0.08, 0.05, 0.05, alpha)
        for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 1 } }) do
            love.graphics.print(p.text, x + o[1], y + o[2], 0, p.scale)
        end
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
        love.graphics.print(p.text, x, y, 0, p.scale)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return fx
