-- Xonix: cut pieces off the sea to uncover a picture.
-- Picture: Hendrik Voogd "Italian landscape with Umbrella Pines" (1807) from the Public Domain Pack
-- by Drummyfish (CC0); slimes: "Puyo Puyo Blobs" by marie_iskandar (CC0); the ball: "Breakout set" by Buch (CC0).
--
--   game.stage "painting" { kind = "xonix", goal = 75, picture = "assets/sprites/arcade/picture_pines.jpg" }
--   local r = s:play("xonix", { goal = 60, enemies = 2 })     -- r.win, r.score, r.percent
--
--   goal      percent of the field to take (default 70)
--   picture   the image that is uncovered (800 x 448 fits exactly)
--   enemies   slimes in the sea (default 1 + level)
--   hunters   slimes that walk on the land (default 0, 1 from level 3)
-- Keys: arrows. On the land you can stop, in the sea you can't: get back to the land
-- before a slime touches your trail.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Xonix = class(Arcade)
Xonix.info = {
    title = "Картина",
    rules = "Под морем спрятана картина. Плыви по морю и возвращайся на берег — отрезанный кусок станет землёй. "
        .. "Слизни не должны коснуться твоего следа.",
    keys = { { "up", "плыть", "[←↑→↓]" } },
    background = "black",
    dim = 0,
}

local W, H, CELL = 100, 56, 8
local FX, FY = 80, 68
local SEA, LAND, TRAIL = 0, 1, 2
local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

function Xonix:setup()
    self.picture = assets.image(self.def.picture or "assets/sprites/arcade/picture_pines.jpg")
    self.puyo = assets.image("assets/sprites/arcade/puyo.png")
    self.breakout = assets.image("assets/sprites/arcade/breakout.png")
    self.ballQ = assets.quad(self.breakout, 84, 136, 8, 8)
    self.seaQ, self.landQ = {}, {}
    for f = 0, 1 do
        self.seaQ[f] = assets.quad(self.puyo, f * 18, 2 * 18, 16, 16)
        self.landQ[f] = assets.quad(self.puyo, f * 18, 0, 16, 16)
    end
    self.goal = self.def.goal or 70
    self.grid = {}
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            local border = x < 2 or y < 2 or x >= W - 2 or y >= H - 2
            self.grid[y * W + x] = border and LAND or SEA
        end
    end
    self.interior = (W - 4) * (H - 4)
    self.mask = love.image.newImageData(W, H)
    self.maskImage = nil
    self.player = { x = math.floor(W / 2), y = 0, dir = nil, clock = 0 }
    self.trail = {}
    self.enemies = {}
    for _ = 1, self.def.enemies or (1 + self.level) do
        local a = love.math.random() * math.pi * 2
        table.insert(self.enemies, { x = love.math.random(10, W - 10) + 0.5, y = love.math.random(10, H - 10) + 0.5,
            vx = (love.math.random() < 0.5 and -1 or 1), vy = (love.math.random() < 0.5 and -1 or 1),
            speed = 14 + self.level * 3, land = false, t = a })
    end
    local hunters = self.def.hunters or (self.level >= 3 and 1 or 0)
    for i = 1, hunters do
        table.insert(self.enemies, { x = i * 20 + 0.5, y = H - 1.5, vx = 1, vy = -1, speed = 10 + self.level * 2,
            land = true, t = 0 })
    end
    self.percent = 0
    self:refreshMask()
end

function Xonix:goalText() return "Открой " .. self.goal .. "% картины" end
function Xonix:progress() return "Открыто " .. math.floor(self.percent) .. "% / " .. self.goal .. "%" end
function Xonix:results()
    self.extraResult = { percent = math.floor(self.percent) }
    return { "Картина открыта на " .. math.floor(self.percent) .. "%" }
end

function Xonix:at(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return nil end
    return self.grid[y * W + x]
end

-- sea = dark water over the picture, the land is the picture itself
function Xonix:refreshMask()
    local m = self.mask
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            local v = self.grid[y * W + x]
            if v == SEA then
                local wave = ((x + y) % 2 == 0) and 0.02 or 0
                m:setPixel(x, y, 0.04 + wave, 0.1 + wave, 0.24 + wave, 0.94)
            elseif v == TRAIL then
                m:setPixel(x, y, 1, 0.85, 0.3, 1)
            else
                m:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
    if self.maskImage then
        self.maskImage:replacePixels(m)
    else
        self.maskImage = love.graphics.newImage(m)
        self.maskImage:setFilter("nearest", "nearest")
    end
end

function Xonix:step(dt)
    local p = self.player
    for name, d in pairs(DIRS) do
        if input.down(name) then
            -- in the sea you cannot turn back onto your own trail
            if not (#self.trail > 0 and p.dir and d[1] == -p.dir[1] and d[2] == -p.dir[2]) then
                p.want = d
            end
        end
    end
    local onLand = self:at(p.x, p.y) == LAND
    local anyKey = input.down("up") or input.down("down") or input.down("left") or input.down("right")
    if onLand and not anyKey then
        p.want, p.dir = nil, nil
    end
    p.clock = p.clock + dt * 28
    while p.clock >= 1 do
        p.clock = p.clock - 1
        if p.want then p.dir = p.want end
        if p.dir then self:movePlayer() end
        if self.dead then break end
    end
    if self.dead then
        self.dead = nil
        return
    end
    for _, e in ipairs(self.enemies) do
        self:moveEnemy(e, dt)
    end
end

function Xonix:movePlayer()
    local p = self.player
    local nx, ny = p.x + p.dir[1], p.y + p.dir[2]
    local v = self:at(nx, ny)
    if v == nil then
        p.dir = nil
        return
    end
    if v == TRAIL then return self:die() end
    local wasSea = self:at(p.x, p.y) ~= LAND
    p.x, p.y = nx, ny
    if v == SEA then
        self.grid[ny * W + nx] = TRAIL
        table.insert(self.trail, { nx, ny })
        self.mask:setPixel(nx, ny, 1, 0.85, 0.3, 1)
        self.maskImage:replacePixels(self.mask)
        if #self.trail % 6 == 1 then audio.play("t_move") end
    elseif v == LAND and wasSea and #self.trail > 0 then
        self:claim()
        p.dir, p.want = nil, nil
    end
end

-- the trail becomes land, and so does every part of the sea without a slime in it
function Xonix:claim()
    for _, t in ipairs(self.trail) do self.grid[t[2] * W + t[1]] = LAND end
    self.trail = {}
    local reach = {}
    local stack = {}
    for _, e in ipairs(self.enemies) do
        if not e.land then
            local ex, ey = math.floor(e.x), math.floor(e.y)
            if self:at(ex, ey) == SEA then table.insert(stack, ey * W + ex) end
        end
    end
    while #stack > 0 do
        local i = table.remove(stack)
        if not reach[i] and self.grid[i] == SEA then
            reach[i] = true
            local x, y = i % W, math.floor(i / W)
            if x > 0 then table.insert(stack, i - 1) end
            if x < W - 1 then table.insert(stack, i + 1) end
            if y > 0 then table.insert(stack, i - W) end
            if y < H - 1 then table.insert(stack, i + W) end
        end
    end
    local gained, sea = 0, 0
    for i = 0, W * H - 1 do
        if self.grid[i] == SEA then
            if not reach[i] then
                self.grid[i] = LAND
                gained = gained + 1
            else
                sea = sea + 1
            end
        end
    end
    local before = self.percent
    self.percent = 100 * (1 - sea / self.interior)
    local p = self.player
    local pts = math.floor(gained / 4) + (gained > 600 and 200 or 0)
    self:addScore(pts, FX + p.x * CELL, FY + p.y * CELL - 10)
    if gained > 600 then self:banner("БОЛЬШОЙ КУСОК!") end
    audio.play("capture", { pitch = 1 + math.min(0.5, gained / 3000) })
    self:flash({ 1, 1, 0.8 }, 0.15)
    self:refreshMask()
    if self.percent >= self.goal then
        self:addScore(math.floor((self.percent - self.goal) * 20) + 300)
        self:win()
    elseif math.floor(before / 10) < math.floor(self.percent / 10) then
        self:popup(screen.width / 2, 90, math.floor(self.percent) .. "%", { 0.6, 0.9, 1 })
    end
end

function Xonix:die()
    local p = self.player
    self:burst(FX + (p.x + 0.5) * CELL, FY + (p.y + 0.5) * CELL, { 1, 0.85, 0.3 }, 20, 180)
    for _, t in ipairs(self.trail) do self.grid[t[2] * W + t[1]] = SEA end
    local start = self.trail[1]
    self.trail = {}
    if start then
        -- back to the shore where the trail began
        local sx, sy = start[1], start[2]
        for _, d in pairs(DIRS) do
            if self:at(sx + d[1], sy + d[2]) == LAND then sx, sy = sx + d[1], sy + d[2]; break end
        end
        p.x, p.y = sx, sy
    end
    p.dir, p.want = nil, nil
    self.dead = true
    self:refreshMask()
    self:loseLife()
end

function Xonix:moveEnemy(e, dt)
    e.t = e.t + dt
    local own = e.land and LAND or SEA
    local steps = math.ceil(e.speed * dt / 0.5)
    local sdt = dt / steps
    for _ = 1, steps do
        local nx = e.x + e.vx * e.speed * sdt
        local ny = e.y + e.vy * e.speed * sdt
        local cx, cy = math.floor(nx), math.floor(e.y)
        local vx = self:at(cx, cy)
        if vx == TRAIL and not e.land then return self:hitTrail(e) end
        if vx ~= own then e.vx = -e.vx; nx = e.x end
        local vy = self:at(math.floor(nx), math.floor(ny))
        if vy == TRAIL and not e.land then return self:hitTrail(e) end
        if vy ~= own then e.vy = -e.vy; ny = e.y end
        e.x, e.y = nx, ny
        local p = self.player
        if math.abs(e.x - (p.x + 0.5)) < 1.6 and math.abs(e.y - (p.y + 0.5)) < 1.6 then
            if e.land or self:at(p.x, p.y) ~= LAND then return self:die() end
        end
    end
end

function Xonix:hitTrail(e)
    e.bump = 0.3
    self:die()
end

function Xonix:drawGame()
    local lg = love.graphics
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.picture, FX, FY, 0, (W * CELL) / self.picture:getWidth(), (H * CELL) / self.picture:getHeight())
    lg.draw(self.maskImage, FX, FY, 0, CELL, CELL)
    -- a soft shine on the sea
    lg.setBlendMode("add")
    lg.setColor(0.2, 0.4, 0.8, 0.06 + 0.04 * math.sin(self.time * 2))
    lg.rectangle("fill", FX, FY, W * CELL, H * CELL)
    lg.setBlendMode("alpha")
    lg.setColor(0.8, 0.7, 0.5, 1)
    lg.setLineWidth(4)
    lg.rectangle("line", FX - 3, FY - 3, W * CELL + 6, H * CELL + 6)
    for _, e in ipairs(self.enemies) do
        local q = e.land and self.landQ or self.seaQ
        local f = math.floor(e.t * 4) % 2
        local s = 1.5 * (1 + 0.08 * math.sin(e.t * 9))
        lg.setColor(1, 1, 1, 1)
        lg.draw(self.puyo, q[f], FX + e.x * CELL, FY + e.y * CELL + 8, 0, s, 3 / s, 8, 16)
    end
    local p = self.player
    local blink = (#self.trail > 0 and math.floor(self.time * 10) % 2 == 0) and 0.6 or 1
    lg.setColor(1, 1, 1, blink)
    lg.draw(self.breakout, self.ballQ, FX + (p.x + 0.5) * CELL, FY + (p.y + 0.5) * CELL, 0, 2.2, 2.2, 4, 4)
    lg.setColor(1, 1, 1, 1)
end

return Xonix
