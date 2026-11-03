-- Emotion bubbles over characters (drawn by code, no images):
--   "!" surprise   "?" question   "heart" love   "anger" angry vein
--   "sweat" drop    "music" happy   "dots" silence   "sleep" Zzz   "idea" light bulb
--   "sad" tear      "star" excited
--
--   emote.draw("heart", x, y, t, scale)   -- x, y = bottom of the bubble tail, t = seconds shown
-- Modes keep a list: self.emotes = emote.List(); list:add(target, "heart"); list:update(dt);
-- list:draw(function(target) return x, y end)

local emote = {}

local lg = love.graphics

local function bubble(w, h, alpha)
    lg.setColor(0.05, 0.05, 0.12, alpha)
    lg.rectangle("fill", -w / 2 - 2, -h - 12, w + 4, h + 4, 8)
    lg.polygon("fill", -7, -10, 7, -10, 0, 2)
    lg.setColor(1, 1, 1, alpha)
    lg.rectangle("fill", -w / 2, -h - 10, w, h, 7)
    lg.polygon("fill", -5, -10, 5, -10, 0, -1)
end

local function heart(cx, cy, r)
    lg.circle("fill", cx - r * 0.5, cy - r * 0.2, r * 0.55)
    lg.circle("fill", cx + r * 0.5, cy - r * 0.2, r * 0.55)
    lg.polygon("fill", cx - r * 1.02, cy, cx + r * 1.02, cy, cx, cy + r * 1.05)
end

local function drop(cx, cy, r)
    lg.circle("fill", cx, cy + r * 0.3, r * 0.6)
    lg.polygon("fill", cx - r * 0.58, cy + r * 0.2, cx + r * 0.58, cy + r * 0.2, cx, cy - r)
end

local SYMBOLS = {}

SYMBOLS["!"] = function(a, t)
    lg.setColor(0.9, 0.15, 0.1, a)
    lg.rectangle("fill", -3, -40, 6, 16, 2)
    lg.rectangle("fill", -3, -21, 6, 5, 2)
end

SYMBOLS["?"] = function(a, t)
    lg.setColor(0.15, 0.35, 0.85, a)
    lg.setLineWidth(4)
    lg.arc("line", "open", 0, -33, 6, math.pi * 1.05, math.pi * 2.35, 8)
    lg.line(1, -27, 0, -23)
    lg.setLineWidth(1)
    lg.rectangle("fill", -2, -20, 5, 5, 2)
end

SYMBOLS.heart = function(a, t)
    local s = 1 + math.sin(t * 9) * 0.12
    lg.setColor(0.92, 0.2, 0.35, a)
    heart(0, -30, 9 * s)
end

SYMBOLS.anger = function(a, t)
    -- the "angry vein": 4 curves bent towards the middle
    local s = 1 + math.abs(math.sin(t * 10)) * 0.18
    lg.setColor(0.88, 0.1, 0.08, a)
    lg.setLineWidth(3.5)
    for i = 0, 3 do
        local ang = i * math.pi / 2 + math.pi / 4
        local cx, cy = math.cos(ang) * 8 * s, -27 + math.sin(ang) * 8 * s
        local toCenter = ang + math.pi
        lg.arc("line", "open", cx, cy, 6 * s, toCenter - 0.9, toCenter + 0.9, 6)
    end
    lg.setLineWidth(1)
end

SYMBOLS.sweat = function(a, t)
    lg.setColor(0.3, 0.6, 0.95, a)
    drop(6, -32 + (t * 10 % 6), 7)
end

SYMBOLS.sad = function(a, t)
    lg.setColor(0.3, 0.55, 0.95, a)
    drop(-6, -34 + (t * 14 % 10), 5)
    drop(6, -30 + ((t * 14 + 5) % 10), 5)
end

SYMBOLS.music = function(a, t)
    lg.setColor(0.2, 0.2, 0.3, a)
    local y = math.sin(t * 6) * 2
    lg.ellipse("fill", -5, -21 + y, 5, 4)
    lg.rectangle("fill", -1, -40 + y, 3, 19)
    lg.polygon("fill", 2, -40 + y, 10, -35 + y, 10, -31 + y, 2, -35 + y)
end

SYMBOLS.dots = function(a, t)
    lg.setColor(0.2, 0.2, 0.3, a)
    for i = 0, 2 do
        if t * 3 % 4 > i then
            lg.circle("fill", -10 + i * 10, -26, 3)
        end
    end
end

SYMBOLS.sleep = function(a, t)
    lg.setColor(0.25, 0.3, 0.6, a)
    lg.setLineWidth(3)
    local function z(x, y, s)
        lg.line(x - s, y - s, x + s, y - s, x - s, y + s, x + s, y + s)
    end
    z(-6, -24, 5)
    if t % 1.2 > 0.4 then
        z(6, -34, 4)
    end
    lg.setLineWidth(1)
end

SYMBOLS.idea = function(a, t)
    local glow = 0.75 + math.sin(t * 8) * 0.25
    lg.setColor(1, 0.85 * glow + 0.1, 0.2, a)
    lg.circle("fill", 0, -33, 8)
    lg.setColor(0.45, 0.45, 0.5, a)
    lg.rectangle("fill", -4, -26, 8, 6, 2)
end

SYMBOLS.star = function(a, t)
    lg.setColor(1, 0.8, 0.15, a)
    local pts = {}
    local rot = t * 2
    for i = 0, 9 do
        local r = i % 2 == 0 and 10 or 4.5
        local ang = rot + i * math.pi / 5 - math.pi / 2
        table.insert(pts, math.cos(ang) * r)
        table.insert(pts, -30 + math.sin(ang) * r)
    end
    lg.polygon("fill", pts)
end

emote.kinds = SYMBOLS
emote.aliases = { surprise = "!", question = "?", love = "heart", angry = "anger", happy = "music",
    silence = "dots", ["..."] = "dots", zzz = "sleep", fear = "sweat", cry = "sad", tear = "sad" }

function emote.draw(kind, x, y, t, scale)
    kind = emote.aliases[kind] or kind
    local symbol = SYMBOLS[kind]
    if not symbol then
        return
    end
    t = t or 1
    scale = scale or 1
    -- pops in with a small bounce
    local k = math.min(1, t * 6)
    local pop = k < 1 and (0.4 + k * 0.8) or 1
    local alpha = 1
    local r, g, b, a = lg.getColor()
    alpha = alpha * a
    lg.push()
    lg.translate(math.floor(x), math.floor(y))
    lg.scale(scale * pop, scale * pop)
    bubble(34, 30, alpha)
    symbol(alpha, t)
    lg.pop()
    lg.setColor(r, g, b, a)
end

-- a list of bubbles over targets ---------------------------------------------------

local List = {}
List.__index = List

function emote.List()
    return setmetatable({ items = {} }, List)
end

-- duration: seconds (default 1.6), 0 = until removed
function List:add(target, kind, duration)
    for i = #self.items, 1, -1 do
        if self.items[i].target == target then
            table.remove(self.items, i)
        end
    end
    table.insert(self.items, { target = target, kind = kind, t = 0, duration = duration or 1.6 })
end

function List:remove(target)
    for i = #self.items, 1, -1 do
        if self.items[i].target == target then
            table.remove(self.items, i)
        end
    end
end

function List:update(dt)
    for i = #self.items, 1, -1 do
        local e = self.items[i]
        e.t = e.t + dt
        if e.duration > 0 and e.t >= e.duration then
            table.remove(self.items, i)
        end
    end
end

-- position(target) -> x, y on the screen (or in the world, inside the camera)
function List:draw(position, scale)
    for _, e in ipairs(self.items) do
        local x, y = position(e.target)
        if x then
            local fade = e.duration > 0 and math.min(1, (e.duration - e.t) * 4) or 1
            lg.setColor(1, 1, 1, fade)
            emote.draw(e.kind, x, y, e.t, scale)
        end
    end
    lg.setColor(1, 1, 1, 1)
end

return emote
