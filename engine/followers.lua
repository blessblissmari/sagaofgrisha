-- Breadcrumb trail for followers (pets, party members): the leader leaves
-- points behind while it moves, follower number i walks to the point that
-- is i * spacing pixels behind along the path. Followers therefore go
-- exactly where the leader went (around corners, over platforms and jumps).
--
--   local trail = Trail(18)
--   trail:push(player.x, player.y, { facing = "left" })     -- every frame
--   local x, y, data = trail:at(18 * i)                      -- for follower i

local class = require("engine.class")

local Trail = class()

function Trail:init(spacing, maxLength)
    self.spacing = spacing or 20
    self.maxLength = maxLength or 400
    self.points = {} -- newest first: { x, y, d (distance to the previous point), data }
end

function Trail:reset(x, y, data)
    self.points = { { x = x, y = y, d = 0, data = data } }
end

function Trail:push(x, y, data)
    local first = self.points[1]
    if not first then
        self:reset(x, y, data)
        return
    end
    local d = math.sqrt((x - first.x) ^ 2 + (y - first.y) ^ 2)
    if d < 2 then
        first.data = data or first.data
        return
    end
    table.insert(self.points, 1, { x = x, y = y, d = 0, data = data })
    self.points[2].d = d
    -- forget the end of the trail
    local total = 0
    for i = 1, #self.points do
        total = total + self.points[i].d
        if total > self.maxLength then
            for j = #self.points, i + 1, -1 do
                self.points[j] = nil
            end
            break
        end
    end
end

-- Point `distance` pixels behind the newest one; nil if the trail is shorter.
function Trail:at(distance)
    local p = self.points
    if #p == 0 then
        return nil
    end
    local walked = 0
    for i = 1, #p - 1 do
        local seg = p[i].d
        if walked + seg >= distance then
            local t = seg > 0 and (distance - walked) / seg or 0
            local a, b = p[i], p[i + 1]
            return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, b.data
        end
        walked = walked + seg
    end
    local last = p[#p]
    return last.x, last.y, last.data, true
end

function Trail:length()
    local total = 0
    for i = 1, #self.points do
        total = total + self.points[i].d
    end
    return total
end

return Trail
