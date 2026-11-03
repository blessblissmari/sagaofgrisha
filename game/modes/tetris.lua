-- Tetris on the NES art of "Tetromix" (devurandom, CC0) with the music beat
-- driving the effects (BPM and the first beat are in game/data/sounds.lua).
--
--   game.stage "bridge_tetris" { kind = "tetris", goal = 10, lives = 3, music = "arcade" }
--   local r = s:play("tetris", { goal = 5 })    -- r.win, r.score, r.lines
--
--   goal    lines to win (nil = endless, the game ends when the lives are over)
--   lives   hearts: filling the well up costs one heart and starts a new round
--   level   starting speed (1..20)
--   record  name for the high score table (default: the stage name)
--
-- Keys: arrows move, [Up]/[X] rotate, [Z] rotate back, [Down] soft drop,
-- [Space] hard drop, [Esc] pause.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Mode = require("game.modes.base")

local function G()
    return require("game")
end

local Tetris = class(Mode)

local COLS, ROWS, HIDDEN = 10, 20, 2
local CELL = 16
local OX, OY = 224, 30                 -- where the 256x240 NES screen goes (x2)
local WELL_X, WELL_Y = OX + 88 * 2, OY + 56 * 2

-- pieces: cells of rotation state 0 in an n x n box, tile in tetromix_tiles.png
local PIECES = {
    { name = "I", n = 4, cells = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } } },
    { name = "O", n = 4, cells = { { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } }, tile = 0, noRotate = true },
    { name = "T", n = 3, cells = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, tile = 1 },
    { name = "S", n = 3, cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } }, tile = 2 },
    { name = "Z", n = 3, cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } }, tile = 3 },
    { name = "J", n = 3, cells = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, tile = 4 },
    { name = "L", n = 3, cells = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, tile = 5 },
}
local KICKS = { { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { -2, 0 }, { 2, 0 }, { 0, 1 } }
local LINE_SCORES = { 100, 300, 500, 800 }

local function rotateCells(cells, n, times)
    local result = {}
    for i, c in ipairs(cells) do
        local x, y = c[1], c[2]
        for _ = 1, times % 4 do
            x, y = n - 1 - y, x
        end
        result[i] = { x, y }
    end
    return result
end

function Tetris:init(def)
    Mode.init(self, def)
    self.screenImage = assets.image("assets/sprites/arcade/tetromix_game.png")
    self.titleImage = assets.image("assets/sprites/arcade/tetromix_title.png")
    self.tiles = assets.image("assets/sprites/arcade/tetromix_tiles.png")
    self.quads = {}
    for i = 0, 22 do
        self.quads[i] = assets.quad(self.tiles, i * 8, 0, 8, 8)
    end
    self.goal = def.goal
    self.maxLives = def.lives or 3
    self.recordName = def.record or def.name or "tetris"
    self.phase = "title"
    self:reset()
end

function Tetris:reset()
    self.grid = {}
    for r = 1, ROWS + HIDDEN do
        self.grid[r] = {}
    end
    self.score, self.lines = 0, 0
    self.level = self.def.level or 1
    self.lives = self.maxLives
    self.round = 1
    self.combo, self.backToBack = -1, false
    self.bag, self.queue = {}, {}
    self.pieceId = 0
    self.clearing = nil
    self.flash = 0
    self:fillQueue()
end

function Tetris:enter()
    local m = self.def.music
    if m == nil then
        m = "arcade"
    end
    if m then
        audio.music(m)
    end
    audio.play("lag")
end

-- 7-bag randomizer: every piece once per 7
function Tetris:fillQueue()
    while #self.queue < 3 do
        if #self.bag == 0 then
            self.bag = { 1, 2, 3, 4, 5, 6, 7 }
            for i = #self.bag, 2, -1 do
                local j = love.math.random(i)
                self.bag[i], self.bag[j] = self.bag[j], self.bag[i]
            end
        end
        table.insert(self.queue, table.remove(self.bag))
    end
end

function Tetris:cellsOf(p, rot, x, y)
    local def = PIECES[p.kind]
    local cells = def.noRotate and def.cells or rotateCells(def.cells, def.n, rot or p.rot)
    local result = {}
    for i, c in ipairs(cells) do
        result[i] = { (x or p.x) + c[1], (y or p.y) + c[2] }
    end
    return result
end

function Tetris:fits(p, rot, x, y)
    for _, c in ipairs(self:cellsOf(p, rot, x, y)) do
        local cx, cy = c[1], c[2]
        if cx < 1 or cx > COLS or cy > ROWS + HIDDEN then
            return false
        end
        if cy >= 1 and self.grid[cy][cx] then
            return false
        end
    end
    return true
end

function Tetris:spawn()
    self:fillQueue()
    local kind = table.remove(self.queue, 1)
    self:fillQueue()
    self.pieceId = self.pieceId + 1
    local def = PIECES[kind]
    self.piece = { kind = kind, rot = 0, x = def.n == 4 and 4 or 4, y = 1, id = self.pieceId }
    self.lockTime, self.lockResets = 0, 0
    self.fallTime = 0
    if not self:fits(self.piece) then
        self.piece = nil
        self:topOut()
    end
end

function Tetris:gravity()
    local l = math.min(self.level, 20)
    return (0.8 - (l - 1) * 0.007) ^ (l - 1)
end

function Tetris:move(dx)
    local p = self.piece
    if p and self:fits(p, p.rot, p.x + dx, p.y) then
        p.x = p.x + dx
        self:touched()
        audio.play("t_move")
        return true
    end
    return false
end

function Tetris:rotate(dir)
    local p = self.piece
    if not p or PIECES[p.kind].noRotate then
        return
    end
    local rot = (p.rot + dir) % 4
    for _, k in ipairs(KICKS) do
        if self:fits(p, rot, p.x + k[1], p.y + k[2]) then
            p.rot, p.x, p.y = rot, p.x + k[1], p.y + k[2]
            self:touched()
            audio.play("t_rotate")
            return
        end
    end
end

-- moving on the ground restarts the lock timer (a few times)
function Tetris:touched()
    if self.lockTime > 0 and self.lockResets < 15 then
        self.lockTime = 0
        self.lockResets = self.lockResets + 1
    end
end

function Tetris:landed()
    local p = self.piece
    return not self:fits(p, p.rot, p.x, p.y + 1)
end

function Tetris:ghostY()
    local p = self.piece
    local y = p.y
    while self:fits(p, p.rot, p.x, y + 1) do
        y = y + 1
    end
    return y
end

function Tetris:hardDrop()
    local p = self.piece
    local y = self:ghostY()
    self.score = self.score + (y - p.y) * 2
    p.y = y
    audio.play("t_drop")
    self.dropFlash = 0.15
    self:lock()
end

function Tetris:lock()
    local p = self.piece
    local cells = self:cellsOf(p)
    local horizontal = true
    for _, c in ipairs(cells) do
        if c[2] ~= cells[1][2] then
            horizontal = false
        end
    end
    table.sort(cells, function(a, b) return a[1] + a[2] * 100 < b[1] + b[2] * 100 end)
    local above = true
    for i, c in ipairs(cells) do
        if c[2] >= 1 then
            self.grid[c[2]][c[1]] = { kind = p.kind, id = p.id, index = i, horizontal = horizontal, t = 0 }
        end
        if c[2] > HIDDEN then
            above = false
        end
    end
    self.piece = nil
    audio.play("t_lock")
    if above then
        self:topOut()
        return
    end
    -- full rows?
    local full = {}
    for r = 1, ROWS + HIDDEN do
        local count = 0
        for c = 1, COLS do
            if self.grid[r][c] then
                count = count + 1
            end
        end
        if count == COLS then
            table.insert(full, r)
        end
    end
    if #full > 0 then
        self:clearRows(full)
    else
        self.combo = -1
        self.spawnDelay = 0.1
    end
end

function Tetris:clearRows(rows)
    local n = #rows
    self.combo = self.combo + 1
    local points = LINE_SCORES[n] * self.level
    if n == 4 then
        if self.backToBack then
            points = math.floor(points * 1.5)
        end
        self.backToBack = true
        audio.play("horn")
        self.flash = 1
        self:cmd_shake(nil, 8, 0.4)
        self.message = { text = "TETRIS!", t = 0 }
    else
        self.backToBack = false
        audio.play("t_line")
    end
    if self.combo > 0 then
        points = points + 50 * self.combo * self.level
        if self.combo >= 2 then
            audio.play("rizz")
            self.message = { text = "КОМБО x" .. (self.combo + 1), t = 0 }
        end
    end
    self.score = self.score + points
    self.clearing = { rows = rows, t = 0 }
    for _, r in ipairs(rows) do
        for c = 1, COLS do
            self.fx:burst(WELL_X + (c - 0.5) * CELL, WELL_Y + (r - HIDDEN - 0.5) * CELL, {
                count = 3, color = { 1, 0.95, 0.7 }, speed = 120, life = 0.5, size = 3, gravity = 300,
            })
        end
    end
end

function Tetris:finishClear()
    local rows = self.clearing.rows
    table.sort(rows)
    for _, r in ipairs(rows) do
        table.remove(self.grid, r)
        table.insert(self.grid, 1, {})
    end
    local before = self.lines
    self.lines = self.lines + #rows
    self.clearing = nil
    local newLevel = (self.def.level or 1) + math.floor(self.lines / 10)
    if newLevel > self.level then
        self.level = newLevel
        audio.play("t_level")
        self.message = { text = "УРОВЕНЬ " .. self.level, t = 0 }
    end
    if self.goal and self.lines >= self.goal and before < self.goal then
        self:gameOver(true)
        return
    end
    self.spawnDelay = 0.15
end

-- the well is full: one heart less and a new round
function Tetris:topOut()
    self.lives = self.lives - 1
    self.combo, self.backToBack = -1, false
    if self.lives <= 0 then
        self:gameOver(false)
        return
    end
    audio.play("what")
    self.round = self.round + 1
    self.wipe = { t = 0 }
    self.message = { text = "РАУНД " .. self.round, t = 0 }
end

function Tetris:gameOver(win)
    self.phase = "over"
    self.win = win
    self.piece = nil
    self.overTime = 0
    self.newRecord = G().record(self.recordName, self.score)
    if win then
        audio.play("fanfare")
    else
        audio.stopMusic(1)
        audio.play("longsad")
    end
    if self.newRecord then
        self.timer:after(1.2, function() audio.play("cool") end)
    end
end

function Tetris:giveUp()
    self:gameOver(false)
end

-- beat of the music: 0 right on the beat .. 1 just before the next one
function Tetris:beat()
    local info = audio.musicInfo()
    local bpm = info.bpm or 120
    local t = audio.musicTime() - (info.beatOffset or 0)
    local beats = t * bpm / 60
    return beats - math.floor(beats), math.floor(beats)
end

-- callbacks ----------------------------------------------------------------------

function Tetris:update(dt)
    Mode.update(self, dt)
    if self.flash > 0 then
        self.flash = math.max(0, self.flash - dt * 2)
    end
    if self.dropFlash then
        self.dropFlash = self.dropFlash - dt
        if self.dropFlash <= 0 then self.dropFlash = nil end
    end
    if self.message then
        self.message.t = self.message.t + dt
        if self.message.t > 1.4 then self.message = nil end
    end
    if self:pausePressed() and self.phase ~= "over" then
        input.consume("pause")
        self:openPause({ { label = "Сдаться", action = function()
            engine.scene.pop()
            self:giveUp()
        end } })
        return
    end
    if self.phase == "title" then
        if input.pressed("confirm") or input.pressed("hardDrop") then
            input.consume("confirm")
            audio.play("ui_select")
            self.phase = "play"
            self.spawnDelay = 0.4
        end
        return
    elseif self.phase == "over" then
        self.overTime = self.overTime + dt
        if self.overTime > 1.5 and (input.pressed("confirm") or input.pressed("hardDrop")) then
            input.consume("confirm")
            self:finish({ win = self.win, score = self.score, lines = self.lines })
        end
        return
    end

    if self.clearing then
        self.clearing.t = self.clearing.t + dt
        if self.clearing.t >= 0.35 then
            self:finishClear()
        end
        return
    end
    if self.wipe then
        self.wipe.t = self.wipe.t + dt
        if self.wipe.t >= 0.8 and not self.wipe.cleared then
            self.wipe.cleared = true
            for r = 1, ROWS + HIDDEN do
                self.grid[r] = {}
            end
        end
        if self.wipe.t >= 1.4 then
            self.wipe = nil
            self.spawnDelay = 0.2
        end
        return
    end
    if not self.piece then
        self.spawnDelay = (self.spawnDelay or 0) - dt
        if self.spawnDelay <= 0 then
            self.spawnDelay = nil
            self:spawn()
        end
        return
    end

    -- input: auto repeat for left / right (DAS)
    local dir = (input.down("left") and -1 or 0) + (input.down("right") and 1 or 0)
    if dir ~= 0 then
        if dir ~= self.dasDir then
            self.dasDir, self.dasTime = dir, 0
            self:move(dir)
        else
            self.dasTime = self.dasTime + dt
            while self.dasTime > 0.17 do
                self.dasTime = self.dasTime - 0.05
                if not self:move(dir) then
                    break
                end
            end
        end
    else
        self.dasDir = nil
    end
    if input.pressed("rotateCW") then
        self:rotate(1)
    elseif input.pressed("rotateCCW") then
        self:rotate(-1)
    end
    if not self.piece then
        return
    end
    if input.pressed("hardDrop") then
        self:hardDrop()
        return
    end
    local speed = self:gravity()
    if input.down("down") then
        speed = math.min(speed, 0.04)
    end
    local p = self.piece
    if self:landed() then
        self.lockTime = self.lockTime + dt
        if self.lockTime >= 0.5 then
            self:lock()
        end
    else
        self.fallTime = self.fallTime + dt
        while self.fallTime >= speed and not self:landed() do
            self.fallTime = self.fallTime - speed
            p.y = p.y + 1
            if input.down("down") then
                self.score = self.score + 1
            end
        end
        if self:landed() then
            self.fallTime = 0
        end
    end
end

-- drawing -----------------------------------------------------------------------

function Tetris:tileFor(cell, r, c, grid)
    if cell.kind ~= 1 then
        return PIECES[cell.kind].tile
    end
    -- the I piece is drawn as one bar: find its ends among its own cells
    local function same(rr, cc)
        local o = grid[rr] and grid[rr][cc]
        return o and o.id == cell.id
    end
    if cell.horizontal then
        local left, right = same(r, c - 1), same(r, c + 1)
        if not left and right then return 9 end
        if left and not right then return 11 end
        return 10
    end
    local up, down = same(r - 1, c), same(r + 1, c)
    if not up and down then return 6 end
    if up and not down then return 8 end
    return 7
end

function Tetris:drawCell(tile, c, r, alpha, pulse)
    local x = WELL_X + (c - 1) * CELL
    local y = WELL_Y + (r - HIDDEN - 1) * CELL
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(self.tiles, self.quads[tile], x, y, 0, 2, 2)
    if pulse and pulse > 0 then
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 1, 1, pulse)
        love.graphics.draw(self.tiles, self.quads[tile], x, y, 0, 2, 2)
        love.graphics.setBlendMode("alpha")
    end
end

function Tetris:drawNumber(value, x, y, digits)
    local s = tostring(math.floor(value))
    if digits then
        s = string.rep("0", digits - #s) .. s
        if #s > digits then s = s:sub(-digits) end
    end
    love.graphics.setColor(1, 1, 1, 1)
    for i = 1, #s do
        local d = tonumber(s:sub(i, i))
        love.graphics.draw(self.tiles, self.quads[12 + d], OX + (x + (i - 1) * 8) * 2, OY + y * 2, 0, 2, 2)
    end
end

function Tetris:drawPiece(p, x, y, cellSize, alpha)
    local cells = self:cellsOf(p, p.rot, 0, 0)
    local grid = {}
    local minx, maxx, miny, maxy = 9, -9, 9, -9
    for i, c in ipairs(cells) do
        grid[c[2]] = grid[c[2]] or {}
        grid[c[2]][c[1]] = { kind = p.kind, id = 0, horizontal = cells[1][2] == cells[4][2] }
        minx, maxx = math.min(minx, c[1]), math.max(maxx, c[1])
        miny, maxy = math.min(miny, c[2]), math.max(maxy, c[2])
    end
    local w, h = (maxx - minx + 1) * cellSize, (maxy - miny + 1) * cellSize
    for _, c in ipairs(cells) do
        local tile = self:tileFor(grid[c[2]][c[1]], c[2], c[1], grid)
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(self.tiles, self.quads[tile], x - w / 2 + (c[1] - minx) * cellSize,
            y - h / 2 + (c[2] - miny) * cellSize, 0, cellSize / 8, cellSize / 8)
    end
end

function Tetris:draw()
    local lg = love.graphics
    lg.clear(0, 0, 0, 1)
    local phase, beatIndex = self:beat()
    local pulse = (1 - phase) ^ 4
    local ox, oy = self:shakeOffset(love.timer.getDelta())
    lg.push()
    lg.translate(ox, oy)
    if self.phase == "title" then
        lg.setColor(1, 1, 1, 1)
        lg.draw(self.titleImage, OX, OY, 0, 2, 2)
        local blink = math.floor(self.time * 2) % 2 == 0
        if not blink then
            lg.setColor(0, 0, 0, 1)
            lg.rectangle("fill", OX + 12 * 8 * 2, OY + 14 * 8 * 2, 9 * 8 * 2, 2 * 8 * 2)
        end
        local rec = G().records[self.recordName]
        ui.print(self.goal and ("Цель: " .. self.goal .. " линий") or "Бесконечная игра", screen.width / 2, OY + 154 * 2,
            { font = "pixel", align = "center", color = "gold" })
        ui.print("Рекорд: " .. (rec or 0), screen.width / 2, OY + 154 * 2 + 30,
            { font = "pixel", align = "center", color = { 0.4, 0.6, 1 } })
        ui.print("[Enter] старт", screen.width / 2, OY + 154 * 2 + 60, { font = "pixel", align = "center", color = "light" })
        lg.pop()
        return
    end

    lg.setColor(1, 1, 1, 1)
    lg.draw(self.screenImage, OX, OY, 0, 2, 2)
    -- the stars twinkle on the beat
    lg.setBlendMode("add")
    love.math.setRandomSeed(7)
    for i = 1, 14 do
        local sx, sy = love.math.random(4, 252), love.math.random(2, 40)
        local on = (beatIndex + i) % 4 == 0
        lg.setColor(1, 1, 0.8, on and pulse * 0.9 or 0.08)
        lg.rectangle("fill", OX + sx * 2, OY + sy * 2, 2, 2)
    end
    love.math.setRandomSeed(os.time())
    lg.setBlendMode("alpha")

    -- the well
    lg.setScissor(WELL_X, WELL_Y, COLS * CELL, ROWS * CELL)
    for r = HIDDEN + 1, ROWS + HIDDEN do
        for c = 1, COLS do
            local cell = self.grid[r][c]
            if cell then
                self:drawCell(self:tileFor(cell, r, c, self.grid), c, r, 1, pulse * 0.12)
            end
        end
    end
    if self.piece then
        local p = self.piece
        local gy = self:ghostY()
        for _, c in ipairs(self:cellsOf(p, p.rot, p.x, gy)) do
            if c[2] > HIDDEN then
                lg.setColor(1, 1, 1, 0.18)
                lg.rectangle("fill", WELL_X + (c[1] - 1) * CELL + 1, WELL_Y + (c[2] - HIDDEN - 1) * CELL + 1, CELL - 2, CELL - 2)
                lg.setColor(1, 1, 1, 0.45)
                lg.rectangle("line", WELL_X + (c[1] - 1) * CELL + 1.5, WELL_Y + (c[2] - HIDDEN - 1) * CELL + 1.5, CELL - 3, CELL - 3)
            end
        end
        local cells = self:cellsOf(p)
        local grid = {}
        for _, c in ipairs(cells) do
            grid[c[2]] = grid[c[2]] or {}
            grid[c[2]][c[1]] = { kind = p.kind, id = -1, horizontal = cells[1][2] == cells[4][2] }
        end
        for _, c in ipairs(cells) do
            if c[2] > HIDDEN then
                self:drawCell(self:tileFor(grid[c[2]][c[1]], c[2], c[1], grid), c[1], c[2], 1, 0)
            end
        end
    end
    if self.clearing then
        local on = math.floor(self.clearing.t * 20) % 2 == 0
        for _, r in ipairs(self.clearing.rows) do
            lg.setColor(1, 1, 1, on and 0.9 or 0.3)
            lg.rectangle("fill", WELL_X, WELL_Y + (r - HIDDEN - 1) * CELL, COLS * CELL, CELL)
        end
    end
    if self.wipe then
        local k = math.min(1, self.wipe.t / 0.8)
        local rows = math.floor(k * ROWS)
        if self.wipe.cleared then
            rows = math.floor((1 - (self.wipe.t - 0.8) / 0.6) * ROWS)
        end
        lg.setColor(0.75, 0.2, 0.05, 1)
        lg.rectangle("fill", WELL_X, WELL_Y + (ROWS - rows) * CELL, COLS * CELL, rows * CELL)
    end
    lg.setScissor()
    -- beat glow around the well
    lg.setBlendMode("add")
    lg.setColor(1, 0.8, 0.4, pulse * 0.35 + self.flash * 0.6)
    lg.setLineWidth(4)
    lg.rectangle("line", WELL_X - 6, WELL_Y - 6, COLS * CELL + 12, ROWS * CELL + 12)
    lg.setLineWidth(1)
    lg.setBlendMode("alpha")

    -- numbers on the NES screen
    self:drawNumber(self.score, 64, 24, 6)
    self:drawNumber(self.level, 48, 56, 2)
    self:drawNumber(self.round, 224, 56, 2)
    local left = self.goal and math.max(0, self.goal - self.lines) or (10 - self.lines % 10)
    self:drawNumber(left, 32, 168, 2)
    lg.setColor(1, 1, 1, 1)
    for i = 1, self.lives do
        lg.draw(self.tiles, self.quads[22], OX + (216 + (i - 1) * 8) * 2, OY + 24 * 2, 0, 2, 2)
    end
    if self.queue[1] then
        self:drawPiece({ kind = self.queue[1], rot = 0 }, OX + 212 * 2, OY + 184 * 2, 14)
    end
    if not self.goal then
        ui.print("ДО УРОВНЯ", OX + 32 * 2 - 40, OY + 154 * 2, { font = "tiny", color = { 0.3, 0.45, 0.9 } })
    end

    self.fx:draw()
    if self.flash > 0 then
        lg.setColor(1, 1, 1, self.flash * 0.5)
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    if self.message then
        local m = self.message
        local a = math.min(1, (1.4 - m.t) * 3)
        ui.print(m.text, WELL_X + COLS * CELL / 2, WELL_Y + 120 - m.t * 30,
            { font = "pixel", align = "center", color = { 1, 0.9, 0.4, a }, outline = { 0, 0, 0, a } })
    end
    if self.phase == "over" then
        lg.setColor(0, 0, 0, 0.75)
        lg.rectangle("fill", WELL_X, WELL_Y + 110, COLS * CELL, 110)
        ui.print(self.win and "ПОБЕДА!" or "GAME OVER", WELL_X + COLS * CELL / 2, WELL_Y + 124,
            { font = "pixel", align = "center", color = self.win and "gold" or "red" })
        ui.print("Очки: " .. self.score, WELL_X + COLS * CELL / 2, WELL_Y + 154, { font = "small", align = "center", color = "light" })
        if self.newRecord then
            ui.print("НОВЫЙ РЕКОРД!", WELL_X + COLS * CELL / 2, WELL_Y + 176, { font = "small", align = "center", color = "gold" })
        end
        if self.overTime > 1.5 then
            ui.print("[Enter]", WELL_X + COLS * CELL / 2, WELL_Y + 198, { font = "small", align = "center", color = "light" })
        end
    end
    lg.pop()
    lg.setColor(1, 1, 1, 1)
    ui.print("←→ двигать   ↑/X поворот   ↓ вниз   Пробел — сброс   Esc — пауза", screen.width / 2, screen.height - 20,
        { font = "small", align = "center", color = "light", alpha = 0.6 })
end

return Tetris
