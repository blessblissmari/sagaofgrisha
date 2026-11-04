-- Top-down racing (Micro Machines style): three laps against three rivals. Drifting fills the
-- nitro bar, nitro gives a short boost. Grass slows you down, trees and rocks stop you.
-- Pixel art: cars "Cars Top Down View" by Ian Peter (CC0, recolored); the road, the grass, trees, rocks,
-- barrels, benches and houses: "isaiah658's Pixel Pack #1" by isaiah658 (CC0). Everything is drawn 2x.
--
--   game.stage "rally" { kind = "racing", laps = 3, goal = 1, level = 3, prize = { coin = 15 } }
--   local r = s:play("racing", { laps = 2, goal = 3 })     -- r.win, r.place, r.time
--
--   laps     laps of the race (default 3)
--   goal     the place you need: 1 = only the win (default 3 on level 1, 2 on level 2, else 1)
--   track    list of points { {x, y}, ... } of your own closed track (default: the island ring)
--   rivals   number of rivals 0..4 (default 3)
-- Keys: [↑] gas, [↓] brake / back, [←][→] steer, [Space] hand brake (drift), [X] nitro.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Racing = class(Arcade)
Racing.info = {
    title = "Гонка",
    rules = "Три круга против соперников. Ручник — занос, занос копит нитро. Трава тормозит, деревья и шины — стоп. "
        .. "Приди к финишу в числе первых.",
    keys = { { "up", "газ", "[↑]" }, { "left", "руль", "[←][→]" }, { "fire", "ручник" }, { "action", "нитро" } },
    background = "black",
    dim = 0,
    lives = false,
}
Racing.defaultLives = 0

local DIR = "assets/sprites/racing/"
local HW = 88        -- half width of the road
local CURB = 26
local STEP = 12      -- distance between samples of the center line
local TRACK = {
    { 400, 300 }, { 1100, 250 }, { 1700, 320 }, { 2200, 430 }, { 2380, 800 }, { 2120, 1110 },
    { 1650, 1010 }, { 1330, 1160 }, { 1500, 1460 }, { 1100, 1580 }, { 600, 1470 }, { 330, 1120 },
    { 520, 760 }, { 280, 540 },
}
local CARS = { "car_blue", "car_red", "car_green", "car_yellow", "car_black" }
local PX = 2          -- every picture is drawn 2x (the cars a bit less: they turn anyway)
local CAR_SCALE = 1.35
local NAMES = { "Гриша", "Рыжий", "Зелёный", "Жёлтый", "Чёрный" }
local COLORS = { { 0.3, 0.6, 1 }, { 1, 0.35, 0.3 }, { 0.3, 0.85, 0.4 }, { 1, 0.85, 0.2 }, { 0.3, 0.3, 0.3 } }

-- a closed Catmull-Rom spline through the points, sampled every STEP pixels
local function buildLine(points)
    local dense = {}
    local n = #points
    for i = 1, n do
        local p0, p1 = points[(i - 2) % n + 1], points[i]
        local p2, p3 = points[i % n + 1], points[(i + 1) % n + 1]
        for k = 0, 39 do
            local t = k / 40
            local t2, t3 = t * t, t * t * t
            local x = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            local y = 0.5 * ((2 * p1[2]) + (-p0[2] + p2[2]) * t + (2 * p0[2] - 5 * p1[2] + 4 * p2[2] - p3[2]) * t2
                + (-p0[2] + 3 * p1[2] - 3 * p2[2] + p3[2]) * t3)
            table.insert(dense, { x, y })
        end
    end
    -- resample by length
    local line = {}
    local acc, total = 0, 0
    table.insert(line, { x = dense[1][1], y = dense[1][2] })
    for i = 2, #dense + 1 do
        local a, b = dense[i - 1], dense[(i - 1) % #dense + 1]
        local seg = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        while acc + seg >= STEP do
            local k = (STEP - acc) / seg
            a = { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k }
            seg = seg - (STEP - acc)
            acc = 0
            total = total + STEP
            table.insert(line, { x = a[1], y = a[2] })
        end
        acc = acc + seg
    end
    if #line > 2 then
        local f, l = line[1], line[#line]
        if (f.x - l.x) ^ 2 + (f.y - l.y) ^ 2 < (STEP * 0.5) ^ 2 then table.remove(line) end
    end
    local m = #line
    for i, p in ipairs(line) do
        local a, b = line[(i - 2) % m + 1], line[i % m + 1]
        local tx, ty = b.x - a.x, b.y - a.y
        local len = math.sqrt(tx * tx + ty * ty)
        p.tx, p.ty = tx / len, ty / len
        p.nx, p.ny = -p.ty, p.tx
        p.dist = (i - 1) * STEP
        p.angle = math.atan2(p.ty, p.tx)
    end
    return line
end

local function strip(line, image, fromOff, toOff, uScale)
    local verts = {}
    for i = 1, #line + 1 do
        local p = line[(i - 1) % #line + 1]
        local v = (i - 1) * STEP / 128
        table.insert(verts, { p.x + p.nx * fromOff, p.y + p.ny * fromOff, 0, v })
        table.insert(verts, { p.x + p.nx * toOff, p.y + p.ny * toOff, uScale, v })
    end
    local mesh = love.graphics.newMesh(verts, "strip", "static")
    mesh:setTexture(image)
    return mesh
end

function Racing:setup()
    self.img = {}
    for _, n in ipairs({ "road", "shoulder", "grass", "tall_grass", "flowers", "flowers2", "tree1", "tree2", "pine", "bush",
        "rocks", "barrel", "bench", "streetlight", "house1", "house3" }) do
        self.img[n] = assets.image(DIR .. n .. ".png")
    end
    for _, c in ipairs(CARS) do self.img[c] = assets.image(DIR .. c .. ".png") end
    for _, n in ipairs({ "road", "shoulder", "grass" }) do self.img[n]:setWrap("repeat", "repeat") end
    self.line = buildLine(self.def.track or TRACK)
    local L = self.line
    self.N = #L
    -- bounds of the world
    local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9
    for _, p in ipairs(L) do
        x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
    end
    self.bounds = { x0 - 500, y0 - 400, x1 + 500, y1 + 400 }
    local b = self.bounds
    -- the grass goes a screen further than the world, so the camera never sees its end
    self.grassQuad = love.graphics.newQuad(0, 0, (b[3] - b[1] + 1000) / PX, (b[4] - b[2] + 600) / PX, 16, 16)
    self.roadMesh = strip(L, self.img.road, HW, -HW, 1)
    self.curbL = strip(L, self.img.shoulder, HW + CURB, HW - 6, 1)
    self.curbR = strip(L, self.img.shoulder, -HW - CURB, -HW + 6, 1)
    self:decorate()
    self.laps = self.def.laps or 3
    self.goal = self.def.goal or (self.level <= 1 and 3 or (self.level == 2 and 2 or 1))
    self.cars = {}
    local rivals = math.max(0, math.min(4, self.def.rivals or 3))
    for i = 1, rivals + 1 do
        local row, col = math.floor((i - 1) / 2), (i - 1) % 2
        local idx = (self.N - 4 - row * 7) % self.N + 1
        local p = L[idx]
        local off = (col == 0 and 1 or -1) * HW * 0.45
        local car = { x = p.x + p.nx * off, y = p.y + p.ny * off, a = p.angle, vx = 0, vy = 0, sprite = CARS[i],
            name = NAMES[i], color = COLORS[i], idx = idx, lap = -1, armed = true, player = i == 1, nitro = 0,
            boost = 0, skidT = 0, place = i, finishT = nil, offset = off, wantOffset = off }
        if not car.player then
            car.skill = 0.84 + self.level * 0.035 + (i - 2) * 0.02 + love.math.random() * 0.03
        end
        table.insert(self.cars, car)
    end
    self.player = self.cars[1]
    self.skids = {}
    self.countdown = 3.2
    self.raceT = 0
    self.cam = { x = self.player.x, y = self.player.y }
end

-- trees, rocks, benches and houses around the road (never on it). The pictures are drawn from the
-- side (3/4 view), so they stand on their lowest point: x, y is the foot, r the solid part.
function Racing:decorate()
    local rng = love.math.newRandomGenerator(7)
    self.props = {}
    self.deco = {}
    local function far(x, y, d)
        for i = 1, self.N, 3 do
            local p = self.line[i]
            if (p.x - x) ^ 2 + (p.y - y) ^ 2 < d * d then return false end
        end
        return true
    end
    local b = self.bounds
    -- grass tufts and flowers: only pictures on the ground
    for _ = 1, 160 do
        local x, y = rng:random(b[1], b[3]), rng:random(b[2], b[4])
        if far(x, y, HW + CURB + 20) then
            local k = rng:random(3)
            table.insert(self.deco, { img = k == 1 and "tall_grass" or (k == 2 and "flowers" or "flowers2"),
                x = math.floor(x / PX) * PX, y = math.floor(y / PX) * PX })
        end
    end
    for _ = 1, 110 do
        local x, y = rng:random(b[1], b[3]), rng:random(b[2], b[4])
        local k = rng:random(4)
        local big = k <= 2
        if far(x, y, HW + 70) and far(x, y - (big and 110 or 50), HW + (big and 90 or 60)) then
            local img = k == 1 and "tree1" or (k == 2 and "tree2" or (k == 3 and "pine" or "bush"))
            table.insert(self.props, { img = img, x = x, y = y, r = big and 20 or (k == 3 and 16 or 24),
                solid = true, top = true, foot = k ~= 4 })
        end
    end
    -- rocks and barrels on the outside of the sharp bends
    for i = 1, self.N, 6 do
        local a, c = self.line[i], self.line[(i + 9) % self.N + 1]
        local turn = math.atan2(math.sin(c.angle - a.angle), math.cos(c.angle - a.angle))
        if math.abs(turn) > 0.5 then
            local side = turn > 0 and -1 or 1
            local d = HW + CURB + 34
            local barrel = i % 24 == 1
            table.insert(self.props, { img = barrel and "barrel" or "rocks", x = a.x + a.nx * d * side,
                y = a.y + a.ny * d * side, r = barrel and 14 or 20, solid = true, foot = barrel })
        end
    end
    -- the benches for the fans and two houses by the start, wherever there is room
    local placed = 0
    for _, side in ipairs({ -1, 1 }) do
        for k = 0, 40, 4 do
            local p = self.line[(k - 1) % self.N + 1]
            local d = side * (HW + 180)
            local x, y = p.x + p.nx * d, p.y + p.ny * d
            local roomy = true
            for _, q in ipairs(self.props) do
                if q.big and (q.x - x) ^ 2 + (q.y - y) ^ 2 < 300 ^ 2 then roomy = false end
            end
            if roomy and far(x, y, HW + 150) and far(x, y - 120, HW + 120) then
                if placed == 0 then
                    -- a stand: three benches and two lamps
                    for j = -1, 1 do
                        table.insert(self.props, { img = "bench", x = x + j * 70, y = y, r = 0, big = j == 0 })
                    end
                    table.insert(self.props, { img = "streetlight", x = x - 120, y = y + 10, r = 8, solid = true, foot = true })
                    table.insert(self.props, { img = "streetlight", x = x + 120, y = y + 10, r = 8, solid = true, foot = true })
                else
                    table.insert(self.props, { img = placed == 1 and "house1" or "house3", x = x, y = y + 100, r = 80,
                        solid = true, foot = true, top = true, big = true })
                end
                placed = placed + 1
                if placed > 2 then break end
            end
        end
        if placed > 2 then break end
    end
    -- the far ones are drawn first
    table.sort(self.props, function(p, q) return p.y < q.y end)
end

function Racing:goalText()
    return self.goal == 1 and ("Выиграй гонку: " .. self.laps .. " круга") or ("Финишируй в первой " .. self.goal ..
        "-ке: " .. self.laps .. " круга")
end

function Racing:progress()
    local p = self.player
    return "Круг " .. math.max(1, math.min(self.laps, p.lap + 1)) .. "/" .. self.laps .. "    Место " .. p.place .. "/" ..
        #self.cars
end

function Racing:results()
    self.extraResult = { place = self.player.place, time = self.player.finishT }
    local t = self.player.finishT
    return { "Место: " .. self.player.place .. " из " .. #self.cars ..
        (t and string.format("   Время %d:%05.2f", math.floor(t / 60), t % 60) or "") }
end

-- the nearest sample of the center line around the last known one
function Racing:track(car)
    local best, bd = car.idx, 1e18
    for d = -30, 30 do
        local i = (car.idx - 1 + d) % self.N + 1
        local p = self.line[i]
        local dd = (p.x - car.x) ^ 2 + (p.y - car.y) ^ 2
        if dd < bd then best, bd = i, dd end
    end
    local old = car.idx
    car.idx = best
    local p = self.line[best]
    car.side = (car.x - p.x) * p.nx + (car.y - p.y) * p.ny
    car.off = math.abs(car.side) > HW + 6
    -- laps: crossing the start line forwards
    if old > self.N * 0.85 and best < self.N * 0.15 then
        if car.armed then
            car.lap = car.lap + 1
            car.armed = false
            if car.lap >= 1 and car.lap < self.laps and car.player then
                self:banner(car.lap == self.laps - 1 and "ПОСЛЕДНИЙ КРУГ!" or ("Круг " .. (car.lap + 1)), "gold", 1.2)
                audio.play("bell")
            end
            if car.lap >= self.laps and not car.finishT then
                car.finishT = self.raceT
                self.finished = (self.finished or 0) + 1
                car.finalPlace = self.finished
            end
        end
    elseif old < self.N * 0.15 and best > self.N * 0.85 then
        car.lap = car.lap - 1
        car.armed = true
    end
    if best > self.N * 0.4 and best < self.N * 0.6 then car.armed = true end
    car.progress = car.lap * self.N + best
end

function Racing:drive(car, dt, gas, brake, steer, hand, nitro)
    local fx, fy = math.cos(car.a), math.sin(car.a)
    local fs = car.vx * fx + car.vy * fy
    local ls = car.vx * -fy + car.vy * fx
    local maxSpeed = (car.player and 520 or 520 * car.skill) * (car.off and 0.5 or 1) * (car.boost > 0 and 1.35 or 1)
    if gas then fs = fs + (car.boost > 0 and 700 or 430) * dt end
    if brake then fs = fs - (fs > 0 and 700 or 260) * dt end
    if not gas and not brake then fs = fs * (1 - math.min(1, dt * (car.stopping and 1.6 or 0.6))) end
    if car.off then fs = fs * (1 - math.min(1, dt * 1.8)) end
    fs = math.max(-160, math.min(maxSpeed, fs))
    local turn = steer * 2.8 * math.max(-1, math.min(1, fs / 160)) * (hand and 1.25 or 1)
    car.a = car.a + turn * dt
    local grip = hand and 1.6 or (car.off and 5 or 9)
    ls = ls * math.exp(-grip * dt)
    -- drifting: skid marks and nitro
    local drifting = math.abs(ls) > 110 and math.abs(fs) > 150
    if drifting then
        car.nitro = math.min(1, car.nitro + dt * 0.35)
        car.skidT = car.skidT - dt
        if car.skidT <= 0 then
            car.skidT = 0.03
            for s = -1, 1, 2 do
                table.insert(self.skids, { x = car.x - fx * 20 + -fy * 12 * s, y = car.y - fy * 20 + fx * 12 * s, a = car.a })
            end
            if #self.skids > 500 then for _ = 1, 20 do table.remove(self.skids, 1) end end
        end
    end
    if nitro and car.nitro >= 0.34 and car.boost <= 0 then
        car.nitro = car.nitro - 0.34
        car.boost = 1.1
        if car.player then audio.play("dash"); self:shake(3, 0.2) end
    end
    car.boost = math.max(0, car.boost - dt)
    fx, fy = math.cos(car.a), math.sin(car.a)
    car.vx, car.vy = fx * fs + -fy * ls, fy * fs + fx * ls
    car.x, car.y = car.x + car.vx * dt, car.y + car.vy * dt
    car.speed = fs
    if car.off and math.abs(fs) > 120 and love.math.random() < dt * 20 then
        self.fx:burst(car.x - fx * 20, car.y - fy * 20, { color = { 0.55, 0.45, 0.3, 0.7 }, count = 2, speed = 40, life = 0.5,
            size = 4 })
    end
end

function Racing:thinkAI(car, dt)
    local L = self.line
    local speed = math.sqrt(car.vx ^ 2 + car.vy ^ 2)
    local look = 6 + math.floor(speed / 28)
    local tp = L[(car.idx - 1 + look) % self.N + 1]
    -- keep away from the car in front
    car.offT = (car.offT or 0) - dt
    if car.offT <= 0 then
        car.offT = 1 + love.math.random() * 2
        car.wantOffset = (love.math.random() - 0.5) * HW * 0.9
    end
    for _, o in ipairs(self.cars) do
        if o ~= car then
            local dx, dy = o.x - car.x, o.y - car.y
            local ahead = dx * math.cos(car.a) + dy * math.sin(car.a)
            if ahead > 0 and ahead < 110 and math.abs(-dx * math.sin(car.a) + dy * math.cos(car.a)) < 40 then
                car.wantOffset = (o.side or 0) > 0 and -HW * 0.5 or HW * 0.5
            end
        end
    end
    car.offset = car.offset + (car.wantOffset - car.offset) * math.min(1, dt * 1.5)
    local tx, ty = tp.x + tp.nx * car.offset, tp.y + tp.ny * car.offset
    local want = math.atan2(ty - car.y, tx - car.x)
    local diff = math.atan2(math.sin(want - car.a), math.cos(want - car.a))
    local steer = math.max(-1, math.min(1, diff * 2.5))
    -- slow down before bends
    local a0, a1 = L[car.idx], L[(car.idx - 1 + 22) % self.N + 1]
    local bend = math.abs(math.atan2(math.sin(a1.angle - a0.angle), math.cos(a1.angle - a0.angle)))
    local target = 520 * car.skill * (1 - math.min(0.5, bend * 0.45))
    -- a little rubber band: the rivals wait when the hero is far behind
    local gap = (car.progress or 0) - (self.player.progress or 0)
    if gap > self.N * 0.3 then target = target * 0.88 elseif gap < -self.N * 0.2 then target = target * 1.08 end
    local fs = car.speed or 0
    local nitro = car.nitro >= 0.34 and bend < 0.2 and love.math.random() < dt * 0.5
    if car.finishT then target = 200 end
    self:drive(car, dt, fs < target, fs > target + 40, steer, false, nitro)
    car.nitro = math.min(1, car.nitro + dt * 0.03)
end

function Racing:collide()
    local cars = self.cars
    for i = 1, #cars do
        local a = cars[i]
        for j = i + 1, #cars do
            local b = cars[j]
            local dx, dy = b.x - a.x, b.y - a.y
            local d2 = dx * dx + dy * dy
            if d2 < 40 * 40 and d2 > 0.01 then
                local d = math.sqrt(d2)
                local nx, ny = dx / d, dy / d
                local push = (40 - d) / 2
                a.x, a.y = a.x - nx * push, a.y - ny * push
                b.x, b.y = b.x + nx * push, b.y + ny * push
                local rel = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
                if rel < 0 then
                    local imp = -rel * 0.8
                    a.vx, a.vy = a.vx - nx * imp * 0.5, a.vy - ny * imp * 0.5
                    b.vx, b.vy = b.vx + nx * imp * 0.5, b.vy + ny * imp * 0.5
                    if (a.player or b.player) and imp > 60 then
                        audio.play("punch", { volume = 0.4 })
                        self:shake(3, 0.15)
                    end
                end
            end
        end
        for _, p in ipairs(self.props) do
            if p.solid then
                local dx, dy = a.x - p.x, a.y - p.y
                local r = p.r + 16
                local d2 = dx * dx + dy * dy
                if d2 < r * r and d2 > 0.01 then
                    local d = math.sqrt(d2)
                    local nx, ny = dx / d, dy / d
                    a.x, a.y = p.x + nx * r, p.y + ny * r
                    local vn = a.vx * nx + a.vy * ny
                    if vn < 0 then
                        a.vx, a.vy = (a.vx - nx * vn * 1.5) * 0.5, (a.vy - ny * vn * 1.5) * 0.5
                        if a.player and vn < -80 then
                            audio.play("stomp")
                            self:shake(5, 0.2)
                        end
                    end
                end
            end
        end
        local b = self.bounds
        a.x = math.max(b[1] + 40, math.min(b[3] - 40, a.x))
        a.y = math.max(b[2] + 40, math.min(b[4] - 40, a.y))
    end
end

function Racing:step(dt)
    if self.countdown > 0 then
        local before = math.ceil(self.countdown)
        self.countdown = self.countdown - dt
        local now = math.ceil(self.countdown)
        if now ~= before and now >= 1 and now <= 3 then
            self:banner(tostring(now), "light", 0.8)
            audio.play("blip")
        end
        if self.countdown <= 0 then
            self:banner("СТАРТ!", "green", 1)
            audio.play("bell")
        end
        for _, c in ipairs(self.cars) do self:track(c) end
        self:updateCamera(dt)
        return
    end
    self.raceT = self.raceT + dt
    local p = self.player
    if not p.finishT then
        local steer = (input.down("right") and 1 or 0) - (input.down("left") and 1 or 0)
        self:drive(p, dt, input.down("up"), input.down("down"), steer, input.down("fire"), input.pressed("action"))
    else
        p.stopping = true
        self:drive(p, dt, false, false, 0, false, false)
    end
    for _, c in ipairs(self.cars) do
        if not c.player then self:thinkAI(c, dt) end
    end
    self:collide()
    for _, c in ipairs(self.cars) do self:track(c) end
    -- places: finished cars by their order, the others by how far they are
    local order = {}
    for _, c in ipairs(self.cars) do table.insert(order, c) end
    table.sort(order, function(a, b)
        if a.finalPlace or b.finalPlace then
            return (a.finalPlace or 99) < (b.finalPlace or 99)
        end
        return a.progress > b.progress
    end)
    for i, c in ipairs(order) do c.place = i end
    self:updateCamera(dt)
    if p.finishT and not self.overDone then
        self.overDone = true
        local place = p.finalPlace or p.place
        p.place = place
        self:addScore(math.max(0, (#self.cars + 1 - place)) * 1000 + math.max(0, math.floor(3000 - p.finishT * 10)))
        self:banner(place == 1 and "ПЕРВОЕ МЕСТО!" or ("Место: " .. place), place <= self.goal and "gold" or "red", 1.6)
        self.timer:after(1.8, function() self:gameOver(place <= self.goal) end)
    end
    -- everybody else finished long ago
    if not p.finishT and (self.finished or 0) >= #self.cars - 1 then
        self.waitT = (self.waitT or 0) + dt
        if self.waitT > 15 then self:gameOver(false) end
    end
end

function Racing:updateCamera(dt)
    local p = self.player
    local tx, ty = p.x + p.vx * 0.35, p.y + p.vy * 0.35
    self.cam.x = self.cam.x + (tx - self.cam.x) * math.min(1, dt * 4)
    self.cam.y = self.cam.y + (ty - self.cam.y) * math.min(1, dt * 4)
end

function Racing:idle(dt)
    for _, c in ipairs(self.cars) do
        if c.player then
            c.stopping = true
            self:drive(c, dt, false, false, 0, false, false)
        else
            self:thinkAI(c, dt)
        end
    end
    self:collide()
    for _, c in ipairs(self.cars) do self:track(c) end
    self:updateCamera(dt)
end

local function drawC(img, x, y, rot, s, alpha)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, x, y, rot or 0, s, s, img:getWidth() / 2, img:getHeight() / 2)
end

-- a side-view picture standing on its foot (or lying around its center), on whole pixels
local function drawProp(img, p)
    local w, h = img:getDimensions()
    love.graphics.draw(img, math.floor(p.x), math.floor(p.y), 0, PX, PX, math.floor(w / 2), p.foot and h - 3 or h / 2)
end

function Racing:drawGame()
    local lg = love.graphics
    local W, H = screen.width, screen.height
    lg.push()
    lg.translate(math.floor(W / 2 - self.cam.x), math.floor(H / 2 - self.cam.y))
    local b = self.bounds
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.img.grass, self.grassQuad, b[1] - 500, b[2] - 300, 0, PX, PX)
    for _, d in ipairs(self.deco) do lg.draw(self.img[d.img], d.x, d.y, 0, PX, PX, 8, 8) end
    lg.draw(self.curbL)
    lg.draw(self.curbR)
    lg.draw(self.roadMesh)
    -- the start line: a checkered band across the road
    local s = self.line[1]
    for k = -7, 6 do
        for r = 0, 1 do
            if (k + r) % 2 == 0 then lg.setColor(0.95, 0.95, 0.95, 1) else lg.setColor(0.15, 0.15, 0.18, 1) end
            local o = k * (HW / 7) + HW / 14
            local cx, cy = s.x + s.nx * o + s.tx * (r * 12 - 6), s.y + s.ny * o + s.ty * (r * 12 - 6)
            lg.push()
            lg.translate(cx, cy)
            lg.rotate(s.angle)
            lg.rectangle("fill", -6, -HW / 14, 12, HW / 7)
            lg.pop()
        end
    end
    -- skid marks: short dark strokes
    lg.setColor(0.05, 0.05, 0.06, 0.35)
    for _, k in ipairs(self.skids) do
        lg.push()
        lg.translate(k.x, k.y)
        lg.rotate(k.a)
        lg.rectangle("fill", -6, -2, 12, 4)
        lg.pop()
    end
    lg.setColor(1, 1, 1, 1)
    for _, p in ipairs(self.props) do
        if not p.top then drawProp(self.img[p.img], p) end
    end
    -- cars with a soft shadow
    for _, c in ipairs(self.cars) do
        local img = self.img[c.sprite]
        lg.setColor(0, 0, 0, 0.3)
        lg.draw(img, c.x + 4, c.y + 5, c.a + math.pi / 2, CAR_SCALE, CAR_SCALE, img:getWidth() / 2, img:getHeight() / 2)
        drawC(img, c.x, c.y, c.a + math.pi / 2, CAR_SCALE)
        if c.boost > 0 then
            local fx, fy = math.cos(c.a), math.sin(c.a)
            lg.setColor(1, 0.7, 0.2, 0.7)
            lg.circle("fill", c.x - fx * 30, c.y - fy * 30, 6 + math.sin(self.time * 40) * 2)
        end
    end
    lg.setColor(1, 1, 1, 1)
    for _, p in ipairs(self.props) do
        if p.top then drawProp(self.img[p.img], p) end
    end
    lg.pop()
    lg.setColor(1, 1, 1, 1)
    self:drawMinimap()
    -- speed and nitro
    local p = self.player
    ui.print(math.floor(math.abs(p.speed or 0) / 4) .. " км/ч", 24, H - 56, { font = "pixel", color = "light",
        outline = { 0, 0, 0, 0.8 } })
    ui.bar(24, H - 30, 160, 8, p.nitro, 1, p.nitro >= 0.34 and "gold" or "blue")
    ui.print("нитро", 192, H - 36, { font = "small", color = "faded" })
    if self.countdown > 0 then
        -- the start lights: three lamps in a dark box
        lg.setColor(0.06, 0.06, 0.08, 0.92)
        lg.rectangle("fill", W / 2 - 84, 62, 168, 56, 6)
        lg.setColor(0.35, 0.35, 0.4, 1)
        lg.setLineWidth(2)
        lg.rectangle("line", W / 2 - 84, 62, 168, 56, 6)
        lg.setLineWidth(1)
        local lit = 3 - math.ceil(self.countdown)
        for i = 0, 2 do
            if i <= lit then
                lg.setColor(i == 2 and 0.3 or 1, i == 2 and 1 or 0.25, 0.2, 1)
            else
                lg.setColor(0.2, 0.2, 0.22, 1)
            end
            lg.circle("fill", W / 2 - 50 + i * 50, 90, 14)
        end
        lg.setColor(1, 1, 1, 1)
    end
end

function Racing:drawMinimap()
    local lg = love.graphics
    local b = self.bounds
    local mw, mh = 170, 110
    local x0, y0 = screen.width - mw - 16, 40
    local sx = math.min(mw / (b[3] - b[1]), mh / (b[4] - b[2]))
    lg.setColor(0, 0, 0, 0.45)
    lg.rectangle("fill", x0 - 6, y0 - 6, mw + 12, mh + 12, 6)
    local pts = {}
    for i = 1, self.N, 4 do
        local p = self.line[i]
        table.insert(pts, x0 + (p.x - b[1]) * sx)
        table.insert(pts, y0 + (p.y - b[2]) * sx)
    end
    table.insert(pts, pts[1]); table.insert(pts, pts[2])
    lg.setColor(0.85, 0.9, 0.95, 0.8)
    lg.setLineWidth(3)
    lg.line(pts)
    lg.setLineWidth(1)
    for i = #self.cars, 1, -1 do
        local c = self.cars[i]
        lg.setColor(c.color[1], c.color[2], c.color[3], 1)
        lg.circle("fill", x0 + (c.x - b[1]) * sx, y0 + (c.y - b[2]) * sx, c.player and 5 or 3.5)
    end
    lg.setColor(1, 1, 1, 1)
end

return Racing
