-- Small math and table helpers used everywhere.

local utf8 = require("utf8")

local util = {}

function util.clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function util.lerp(a, b, t)
    return a + (b - a) * t
end

function util.round(v)
    return math.floor(v + 0.5)
end

function util.sign(v)
    return v > 0 and 1 or (v < 0 and -1 or 0)
end

-- Moves value towards target by at most step.
function util.approach(value, target, step)
    if value < target then
        return math.min(value + step, target)
    end
    return math.max(value - step, target)
end

function util.distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Unit vector (0, 0 stays 0, 0) and the original length.
function util.normalize(x, y)
    local length = math.sqrt(x * x + y * y)
    if length == 0 then
        return 0, 0, 0
    end
    return x / length, y / length, length
end

-- Angle difference in -pi..pi, so turning always takes the short way.
function util.angleDelta(from, to)
    local d = (to - from) % (2 * math.pi)
    if d > math.pi then
        d = d - 2 * math.pi
    end
    return d
end

function util.lerpAngle(a, b, t)
    return a + util.angleDelta(a, b) * t
end

-- Exponential smoothing that does not depend on the frame rate.
-- speed ~ 10 is snappy, ~ 2 is lazy.
function util.damp(current, target, speed, dt)
    return util.lerp(current, target, 1 - math.exp(-speed * dt))
end

function util.overlaps(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

function util.pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function util.shuffle(t)
    for i = #t, 2, -1 do
        local j = love.math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function util.pick(t)
    return t[love.math.random(#t)]
end

function util.copy(t)
    local result = {}
    for k, v in pairs(t) do
        result[k] = v
    end
    return result
end

function util.deepCopy(t)
    if type(t) ~= "table" then
        return t
    end
    local result = {}
    for k, v in pairs(t) do
        result[k] = util.deepCopy(v)
    end
    return result
end

-- Copies missing keys from defaults into t (one level deep).
function util.defaults(t, defaults)
    t = t or {}
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = v
        end
    end
    return t
end

function util.find(t, value)
    for i, v in ipairs(t) do
        if v == value then
            return i
        end
    end
end

function util.removeValue(t, value)
    local i = util.find(t, value)
    if i then
        table.remove(t, i)
    end
end

-- UTF-8 aware string helpers (Russian letters are 2 bytes each).
function util.ulen(s)
    return utf8.len(s) or #s
end

function util.usub(s, i, j)
    local length = util.ulen(s)
    j = j or length
    if i < 1 then i = 1 end
    if j > length then j = length end
    if i > j then
        return ""
    end
    local startByte = utf8.offset(s, i)
    local endByte = utf8.offset(s, j + 1)
    return s:sub(startByte, endByte and endByte - 1 or #s)
end

-- "#ff8800" -> { 1, 0.53, 0 }
function util.hexColor(hex)
    hex = hex:gsub("#", "")
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    local a = #hex >= 8 and tonumber(hex:sub(7, 8), 16) or 255
    return { r / 255, g / 255, b / 255, a / 255 }
end

return util
