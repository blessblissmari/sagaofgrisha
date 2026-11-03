-- Side view physics (platformers): moving a box through solid tiles,
-- one-way platforms and extra solid rectangles of a World.
--
--   e.x, e.y   point between the feet, e.w x e.h box above it (like Entity)
--   local hitWall = physics.moveX(world, e, e.vx * dt)
--   local landed, hitCeiling = physics.moveY(world, e, e.vy * dt, dropThrough)
--
-- One-way platforms (tile property oneway = true) only stop a box that
-- falls on them from above; dropThrough = true lets it fall through.

local util = require("engine.util")

local physics = {}

local function blocked(world, e, x, y)
    return world:isBlocked(x - e.w / 2, y - e.h, e.w, e.h)
end

-- Is there a one-way platform top between the feet heights y0 and y1 (y0 < y1)?
-- Returns the top of the platform.
function physics.onewayBelow(world, e, y0, y1)
    local th = world.tileHeight
    local top = math.floor(y1 / th) * th
    if top < y0 - 0.01 or top >= y1 then
        return nil
    end
    local row = math.floor(top / th) + 1
    local c1 = math.floor((e.x - e.w / 2) / world.tileWidth) + 1
    local c2 = math.floor((e.x + e.w / 2 - 0.01) / world.tileWidth) + 1
    for col = c1, c2 do
        if world:isOnewayTile(col, row) then
            return top
        end
    end
    return nil
end

-- Moves along one axis in 1 pixel steps, stops at walls (with sub-pixel precision).
local function sweep(world, e, dx, dy, dropThrough)
    local total = math.abs(dx + dy)
    local sx, sy = util.sign(dx), util.sign(dy)
    local moved = 0
    while moved < total do
        local step = math.min(1, total - moved)
        local nx, ny = e.x + sx * step, e.y + sy * step
        if blocked(world, e, nx, ny) then
            -- get as close as possible
            local lo, hi = 0, step
            for _ = 1, 5 do
                local mid = (lo + hi) / 2
                if blocked(world, e, e.x + sx * mid, e.y + sy * mid) then
                    hi = mid
                else
                    lo = mid
                end
            end
            e.x, e.y = e.x + sx * lo, e.y + sy * lo
            return true
        end
        if sy > 0 and not dropThrough then
            local top = physics.onewayBelow(world, e, e.y, ny)
            if top then
                e.y = top
                return true, true
            end
        end
        e.x, e.y = nx, ny
        moved = moved + step
    end
    return false
end

-- Returns true when a wall stopped the box.
function physics.moveX(world, e, dx)
    if dx == 0 then
        return false
    end
    if blocked(world, e, e.x, e.y) then
        e.x = e.x + dx -- stuck inside a wall: let it out
        return false
    end
    return (sweep(world, e, dx, 0))
end

-- Returns landed (moving down and stopped), hitCeiling (moving up and stopped),
-- onOneway (landed on a one-way platform).
function physics.moveY(world, e, dy, dropThrough)
    if dy == 0 then
        return false, false
    end
    if blocked(world, e, e.x, e.y) then
        e.y = e.y + dy
        return false, false
    end
    local hit, oneway = sweep(world, e, 0, dy, dropThrough)
    if dy > 0 then
        return hit, false, oneway
    end
    return false, hit
end

-- Is the box standing on something (solid or one-way)?
function physics.onGround(world, e)
    if blocked(world, e, e.x, e.y + 0.5) then
        return true
    end
    return physics.onewayBelow(world, e, e.y, e.y + 0.5) ~= nil
end

-- Is there a wall right next to the box? side = -1 (left) or 1 (right)
function physics.touchingWall(world, e, side)
    return blocked(world, e, e.x + side * 1, e.y - 1)
end

-- Is there ground in front of the feet (for walkers that turn at ledges)?
function physics.groundAhead(world, e, side)
    local x = e.x + side * (e.w / 2 + 2)
    local col, row = world:tileAt(x, e.y + 2)
    return world:isSolidTile(col, row) or world:isOnewayTile(col, row)
end

return physics
