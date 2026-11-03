-- Sprite animations described as data and played with anim8.
--
--   local HERO = {
--       image = "assets/sprites/td_hero.png",
--       frame = { 16, 16 },            -- frame size in the sheet
--       origin = { 8, 16 },            -- the point between the feet (default)
--       scale = 2,
--       animations = {
--           --         columns  row  seconds per frame  [on end]
--           idle = { down = { 5, 1, 0.2 }, up = { 1, 1, 0.2 } },
--           walk = { down = { "5-8", 1, 0.15 } },
--           die  = { "1-4", 5, 0.1, "pauseAtEnd" },
--       },
--   }
--   local sprite = anim.new(HERO)    -- every entity gets its own copy
--   sprite:play("walk", "down")      -- same as sprite:play("walk.down")
--   sprite:update(dt)
--   sprite:draw(x, y, { flip = true, color = { 1, 1, 1, 0.5 } })

local anim8 = require("libs.anim8.anim8")
local assets = require("engine.assets")
local class = require("engine.class")

local anim = {}

local built = setmetatable({}, { __mode = "k" }) -- def -> shared data

local function isFrames(v)
    return type(v[1]) == "number" or type(v[1]) == "string" or v.frames ~= nil
end

local function build(def)
    local b = built[def]
    if b then
        return b
    end
    local image = assets.image(def.image, def.colorKey and { colorKey = def.colorKey })
    local fw, fh = def.frame[1], def.frame[2]
    local grid = anim8.newGrid(fw, fh, image:getWidth(), image:getHeight(),
        def.left or 0, def.top or 0, def.border or 0)
    local templates = {}
    local function walk(group, prefix)
        for name, v in pairs(group) do
            local key = prefix and (prefix .. "." .. name) or name
            if isFrames(v) then
                local frames = v.frames and grid(unpack(v.frames)) or grid(v[1], v[2])
                templates[key] = anim8.newAnimation(frames, v.duration or v[3] or 0.1, v.onLoop or v[4])
            else
                walk(v, key)
            end
        end
    end
    walk(def.animations, nil)
    b = { image = image, templates = templates, fw = fw, fh = fh }
    built[def] = b
    return b
end

local Sprite = class()
anim.Sprite = Sprite

function Sprite:init(def)
    local b = build(def)
    self.def = def
    self.image = b.image
    self.templates = b.templates
    self.frameWidth, self.frameHeight = b.fw, b.fh
    self.ox = def.origin and def.origin[1] or b.fw / 2
    self.oy = def.origin and def.origin[2] or b.fh
    self.scale = def.scale or 1
    self.speed = 1
    self.instances = {}
    self.name, self.current = nil, nil
    self:play(def.default or next(b.templates))
end

function Sprite:has(name, sub)
    return self.templates[sub and (name .. "." .. sub) or name] ~= nil
end

-- Unknown names are ignored, so the current animation keeps playing.
-- play("walk", "left") falls back to "walk" when there is no "walk.left".
function Sprite:play(name, sub, restart)
    if sub then
        if self.templates[name .. "." .. sub] then
            name = name .. "." .. sub
        elseif not self.templates[name] then
            return self
        end
    end
    if self.name == name and not restart then
        return self
    end
    local a = self.instances[name]
    if not a then
        local template = self.templates[name]
        if not template then
            return self
        end
        a = template:clone()
        self.instances[name] = a
    end
    a:gotoFrame(1)
    a:resume()
    self.name, self.current = name, a
    return self
end

function Sprite:update(dt)
    if self.current then
        self.current:update(dt * self.speed)
    end
end

function Sprite:isFinished()
    return self.current ~= nil and self.current.status == "paused"
end

function Sprite:getFrame()
    return self.current and self.current.position or 1
end

function Sprite:getQuad()
    return self.current.frames[self.current.position]
end

-- opts: scale, flip (mirror horizontally), flipY, rotation, color, ox, oy
function Sprite:draw(x, y, opts)
    if not self.current then
        return
    end
    opts = opts or {}
    local s = opts.scale or self.scale
    local sx, sy = s, s
    if opts.flip then sx = -sx end
    if opts.flipY then sy = -sy end
    if opts.color then
        love.graphics.setColor(opts.color)
    end
    love.graphics.draw(self.image, self:getQuad(), math.floor(x + 0.5), math.floor(y + 0.5),
        opts.rotation or 0, sx, sy, opts.ox or self.ox, opts.oy or self.oy)
    if opts.color then
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function anim.new(def)
    return Sprite(def)
end

return anim
