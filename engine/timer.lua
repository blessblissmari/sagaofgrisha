-- Timers, tweens and scripts.
--
--   local t = timer.new()            -- or use the global one: timer.after(...)
--   t:after(1, function() print("1 second later") end)
--   t:every(0.5, function() print("tick") end, 3)        -- 3 times
--   t:tween(0.3, obj, { x = 100, alpha = 0 }, "quadOut", onDone)
--   t:script(function(wait)
--       print("a"); wait(1); print("b, 1 second later")
--   end)
--   t:update(dt)                     -- call every frame
--
-- Every function returns a handle, t:cancel(handle) stops it.

local Timer = {}
Timer.__index = Timer

local easing = {}

function easing.linear(t) return t end
function easing.quadIn(t) return t * t end
function easing.quadOut(t) return 1 - (1 - t) * (1 - t) end
function easing.quadInOut(t)
    if t < 0.5 then return 2 * t * t end
    return 1 - (-2 * t + 2) ^ 2 / 2
end
function easing.cubicOut(t) return 1 - (1 - t) ^ 3 end
function easing.cubicInOut(t)
    if t < 0.5 then return 4 * t * t * t end
    return 1 - (-2 * t + 2) ^ 3 / 2
end
function easing.sineInOut(t) return -(math.cos(math.pi * t) - 1) / 2 end
function easing.backOut(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
function easing.elasticOut(t)
    if t == 0 or t == 1 then return t end
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
end
function easing.bounceOut(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    end
    t = t - 2.625 / d1
    return n1 * t * t + 0.984375
end

function Timer.new()
    return setmetatable({ items = {} }, Timer)
end

local function add(self, item)
    item.time = 0
    table.insert(self.items, item)
    return item
end

function Timer:after(delay, fn)
    return add(self, { kind = "after", delay = delay, fn = fn })
end

-- count = nil repeats forever
function Timer:every(interval, fn, count)
    return add(self, { kind = "every", delay = interval, fn = fn, count = count })
end

-- fn(dt, progress) every frame for duration seconds, then onDone()
function Timer:during(duration, fn, onDone)
    return add(self, { kind = "during", delay = duration, fn = fn, onDone = onDone })
end

-- Animates numeric fields of subject to the values in target.
function Timer:tween(duration, subject, target, ease, onDone)
    if type(ease) ~= "function" then
        ease = easing[ease or "quadOut"] or easing.linear
    end
    return add(self, {
        kind = "tween", delay = math.max(duration, 1e-6),
        subject = subject, target = target, ease = ease, onDone = onDone,
    })
end

-- Runs fn as a coroutine; fn receives wait(seconds).
function Timer:script(fn)
    local item = { kind = "script" }
    local function wait(seconds)
        item.delay = item.time + (seconds or 0)
        coroutine.yield()
    end
    item.co = coroutine.create(function() fn(wait) end)
    item.delay = 0
    return add(self, item)
end

function Timer:cancel(item)
    if item then
        item.dead = true
    end
end

function Timer:clear()
    self.items = {}
end

local function step(item, dt)
    item.time = item.time + dt
    local kind = item.kind

    if kind == "after" then
        if item.time >= item.delay then
            item.dead = true
            item.fn()
        end
    elseif kind == "every" then
        while item.time >= item.delay and not item.dead do
            item.time = item.time - item.delay
            if item.fn() == false then
                item.dead = true -- returning false from fn stops it
            end
            if item.count then
                item.count = item.count - 1
                if item.count <= 0 then
                    item.dead = true
                end
            end
        end
    elseif kind == "during" then
        local progress = math.min(item.time / item.delay, 1)
        item.fn(dt, progress)
        if progress >= 1 then
            item.dead = true
            if item.onDone then item.onDone() end
        end
    elseif kind == "tween" then
        if not item.from then
            item.from = {}
            for k in pairs(item.target) do
                item.from[k] = item.subject[k] or 0
            end
        end
        local progress = math.min(item.time / item.delay, 1)
        local e = item.ease(progress)
        for k, to in pairs(item.target) do
            item.subject[k] = item.from[k] + (to - item.from[k]) * e
        end
        if progress >= 1 then
            item.dead = true
            if item.onDone then item.onDone() end
        end
    elseif kind == "script" then
        if item.time >= item.delay then
            local ok, err = coroutine.resume(item.co)
            if not ok then
                error("timer script: " .. tostring(err) .. "\n" .. debug.traceback(item.co), 0)
            end
            if coroutine.status(item.co) == "dead" then
                item.dead = true
            end
        end
    end
end

function Timer:update(dt)
    local items = self.items
    local count = #items -- items added during this update start next frame
    for i = 1, count do
        local item = items[i]
        if not item.dead then
            step(item, dt)
        end
    end
    -- remove finished items
    local j = 0
    for i = 1, #items do
        if not items[i].dead then
            j = j + 1
            items[j] = items[i]
        end
    end
    for i = #items, j + 1, -1 do
        items[i] = nil
    end
end

function Timer:isActive(item)
    return item ~= nil and not item.dead and self ~= nil
end

-- module: timer.new(), timer.easing and a global timer
local timer = { new = Timer.new, easing = easing, Timer = Timer }
local global = Timer.new()
timer.global = global
for _, name in ipairs({ "after", "every", "during", "tween", "script", "cancel", "clear", "update" }) do
    timer[name] = function(...) return global[name](global, ...) end
end

return timer
