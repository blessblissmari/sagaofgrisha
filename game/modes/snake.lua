-- Snake: a worm of slime blobs eats carrots ("Puyo Puyo Blobs" by marie_iskandar, CC0;
-- icons from "496 pixel art icons", CC0).
--
--   game.stage "garden" { kind = "snake", goal = 15, wrap = true }
--   local r = s:play("snake", { goal = 20, time = 90 })     -- r.win, r.score, r.length
--
--   goal    carrots to eat (default 12)
--   wrap    true: the field is round, leaving it on one side brings you back on the other
--   rocks   how many stones lie on the field (default 2 + level)
--   speed   moves per second at the start (default 6 + level)
-- A golden coin shows up now and then: +5 points, but it runs away in a few seconds.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Snake = class(Arcade)
Snake.info = {
    title = "Слизняк",
    rules = "Слизняк любит морковку: каждая делает его длиннее. Не врежься в себя, в камни и в стены.",
    keys = { { "up", "поворот", "[←↑→↓]" } },
    background = "hills",
    dim = 0.35,
}
Snake.defaultLives = 1

local CELL = 32
local COLS, ROWS = 24, 14
local OX, OY = math.floor((960 - COLS * CELL) / 2), 56
local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

function Snake:setup()
    self.sheet = assets.image("assets/sprites/arcade/puyo.png")
    self.q = {}
    for color = 0, 4 do
        self.q[color] = {}
        for f = 0, 18 do
            self.q[color][f] = assets.quad(self.sheet, f * 18, color * 18, 16, 16)
        end
    end
    self.stoneQ = assets.quad(self.sheet, 18, 90, 16, 16)
    self.goal = self.def.goal or 12
    self.wrap = self.def.wrap
    self.rate = self.def.speed or (6 + self.level)
    local cx, cy = math.floor(COLS / 2), math.floor(ROWS / 2)
    self.body = { { cx, cy, c = 0 }, { cx - 1, cy, c = 1 }, { cx - 2, cy, c = 2 } }
    self.dir, self.queue = { 1, 0 }, {}
    self.clock, self.eaten, self.colorNext = 0, 0, 3
    self.grow, self.chew = 0, 0
    self.rocks = {}
    for _ = 1, self.def.rocks or (2 + self.level) do
        local x, y = self:freeCell(3)
        if x then self.rocks[#self.rocks + 1] = { x, y } end
    end
    self:placeFood()
    self.coinTimer = 8
end

function Snake:goalText() return "Съешь " .. self.goal .. " морковок" end
function Snake:progress() return "Морковки " .. self.eaten .. "/" .. self.goal end
function Snake:results()
    self.extraResult = { length = #self.body }
    return { "Длина слизняка: " .. #self.body }
end

function Snake:occupied(x, y)
    for _, s in ipairs(self.body) do
        if s[1] == x and s[2] == y then return true end
    end
    for _, r in ipairs(self.rocks or {}) do
        if r[1] == x and r[2] == y then return true end
    end
    if self.food and self.food[1] == x and self.food[2] == y then return true end
    return false
end

-- a random empty cell, not too close to the head
function Snake:freeCell(margin)
    local head = self.body[1]
    for _ = 1, 400 do
        local x, y = love.math.random(1, COLS - 2), love.math.random(1, ROWS - 2)
        if not self:occupied(x, y) and (math.abs(x - head[1]) + math.abs(y - head[2]) > (margin or 2)) then
            return x, y
        end
    end
end

function Snake:placeFood()
    local x, y = self:freeCell(3)
    self.food = { x, y, t = 0 }
end

function Snake:step(dt)
    for name, d in pairs(DIRS) do
        if input.pressed(name) then
            local last = self.queue[#self.queue] or self.dir
            if (d[1] ~= -last[1] or d[2] ~= -last[2]) and (d[1] ~= last[1] or d[2] ~= last[2]) and #self.queue < 3 then
                table.insert(self.queue, d)
            end
        end
    end
    self.chew = math.max(0, self.chew - dt * 4)
    self.food.t = self.food.t + dt
    if self.coin then
        self.coin.t = self.coin.t - dt
        if self.coin.t <= 0 then self.coin = nil end
    else
        self.coinTimer = self.coinTimer - dt
        if self.coinTimer <= 0 then
            local x, y = self:freeCell(4)
            if x then self.coin = { x, y, t = 6 } end
            self.coinTimer = 10 + love.math.random() * 8
        end
    end
    local rate = self.rate + self.eaten * 0.25
    self.clock = self.clock + dt * rate
    while self.clock >= 1 and self.phase == "play" do
        self.clock = self.clock - 1
        self:move()
    end
end

function Snake:move()
    if #self.queue > 0 then
        self.dir = table.remove(self.queue, 1)
    end
    local head = self.body[1]
    local nx, ny = head[1] + self.dir[1], head[2] + self.dir[2]
    if self.wrap then
        nx, ny = (nx % COLS), (ny % ROWS)
    elseif nx < 0 or ny < 0 or nx >= COLS or ny >= ROWS then
        return self:crash(head[1], head[2])
    end
    -- the tail moves away this turn, so the head may take its place
    local last = #self.body - (self.grow > 0 and 0 or 1)
    for i = 1, last do
        local s = self.body[i]
        if s[1] == nx and s[2] == ny then return self:crash(nx, ny) end
    end
    for _, r in ipairs(self.rocks) do
        if r[1] == nx and r[2] == ny then return self:crash(nx, ny) end
    end
    -- every segment takes the place (and the look) of the one before it
    table.insert(self.body, 1, { nx, ny, c = head.c })
    for i = 2, #self.body - 1 do
        self.body[i].c = self.body[i + 1].c
    end
    if self.grow > 0 then
        self.grow = self.grow - 1
        self.body[#self.body].c = self.colorNext
        self.colorNext = (self.colorNext + 1) % 5
    else
        table.remove(self.body)
    end
    local px, py = OX + nx * CELL + CELL / 2, OY + ny * CELL + CELL / 2
    if nx == self.food[1] and ny == self.food[2] then
        self.eaten = self.eaten + 1
        self.grow = self.grow + 1
        self.chew = 1
        self:addScore(10 + self.eaten, px, py - 10)
        self:burst(px, py, { 1, 0.6, 0.2 }, 10, 120)
        audio.play("puyo_pop", { pitch = 1 + self.eaten * 0.02 })
        if self.eaten >= self.goal then
            self:addScore(100)
            return self:win()
        end
        self:placeFood()
    elseif self.coin and nx == self.coin[1] and ny == self.coin[2] then
        self.coin = nil
        self:addScore(50, px, py - 10, { 1, 0.85, 0.2 })
        self:burst(px, py, { 1, 0.85, 0.2 }, 14, 150)
        audio.play("coin")
    end
end

function Snake:crash(x, y)
    self:burst(OX + x * CELL + CELL / 2, OY + y * CELL + CELL / 2, { 0.9, 0.3, 0.4 }, 24, 200)
    audio.play("hurt")
    self.dead = true
    if not self:loseLife() then
        -- more lives: start again with a short worm
        self.dead = false
        local keep = math.max(3, math.floor(#self.body / 2))
        local cx, cy = math.floor(COLS / 2), math.floor(ROWS / 2)
        local body = {}
        for i = 1, keep do body[i] = { cx - i + 1, cy, c = self.body[i].c } end
        self.body, self.dir, self.queue = body, { 1, 0 }, {}
    end
end

function Snake:cellPos(x, y)
    return OX + x * CELL, OY + y * CELL
end

function Snake:drawGame()
    local lg = love.graphics
    -- a checkered lawn
    for y = 0, ROWS - 1 do
        for x = 0, COLS - 1 do
            if (x + y) % 2 == 0 then lg.setColor(0.32, 0.55, 0.28, 0.92) else lg.setColor(0.28, 0.5, 0.25, 0.92) end
            lg.rectangle("fill", OX + x * CELL, OY + y * CELL, CELL, CELL)
        end
    end
    lg.setColor(0.1, 0.2, 0.08, 1)
    lg.setLineWidth(4)
    lg.rectangle("line", OX - 2, OY - 2, COLS * CELL + 4, ROWS * CELL + 4)
    if self.wrap then
        lg.setColor(0.6, 0.9, 1, 0.3 + 0.2 * math.sin(self.time * 3))
        lg.setLineWidth(2)
        lg.rectangle("line", OX - 2, OY - 2, COLS * CELL + 4, ROWS * CELL + 4)
    end
    lg.setColor(1, 1, 1, 1)
    for _, r in ipairs(self.rocks) do
        local x, y = self:cellPos(r[1], r[2])
        ui.icon("stone", x - 1, y - 1, CELL / 34)
    end
    -- carrot: bobs up and down
    local fx, fy = self:cellPos(self.food[1], self.food[2])
    local bob = math.sin(self.food.t * 5) * 3
    lg.setColor(0, 0, 0, 0.25)
    lg.ellipse("fill", fx + CELL / 2, fy + CELL - 4, 10, 4)
    ui.icon("carrot", fx - 1, fy - 4 + bob, CELL / 34)
    if self.coin then
        local cx, cy = self:cellPos(self.coin[1], self.coin[2])
        local a = self.coin.t < 2 and (math.floor(self.coin.t * 8) % 2 == 0 and 0.3 or 1) or 1
        ui.icon("coin", cx - 1, cy + math.sin(self.time * 6) * 2, CELL / 34, a)
    end
    -- the worm: from the tail to the head, every blob a little bigger
    local n = #self.body
    local move = self.phase == "play" and self.clock or 0
    for i = n, 1, -1 do
        local s = self.body[i]
        local x, y = self:cellPos(s[1], s[2])
        local frame = 2
        local scale = 2 * (0.8 + 0.2 * (1 - (i - 1) / math.max(1, n)))
        local sy = scale
        if i == 1 then
            frame = self.chew > 0 and 1 or 0
            if self.dead then frame = 5 end
        else
            sy = scale * (1 + 0.08 * math.sin(self.time * 10 - i * 0.7))
        end
        lg.setColor(1, 1, 1, 1)
        lg.draw(self.sheet, self.q[s.c][frame], x + CELL / 2, y + CELL - 1, 0, scale, sy, 8, 16)
    end
end

return Snake
