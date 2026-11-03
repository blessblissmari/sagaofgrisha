-- Match-3 ("Retro Color Puzzle Assets" by Haley Wakamatsu, CC-BY 4.0): swap two
-- neighbors to line up three or more of a kind.
--
--   game.stage "gems" { kind = "match3", goal = 1500, time = 90 }
--   local r = s:play("match3", { moves = 20, goal = 1000 })   -- r.win, r.score
--
--   goal    points to win (default 1200)
--   time    seconds (default 90); moves = limit the swaps instead of the time
--   kinds   how many kinds of blocks (4..5, default 5)
-- Four in a row make a striped block (clears its line), five - a star (clears a color).
-- Keys: arrows move the frame, [Space] take a block and an arrow to swap. Or the mouse.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Match3 = class(Arcade)
Match3.keymap = "puzzle"
Match3.info = {
    title = "Самоцветы",
    rules = "Меняй местами соседние камни, чтобы собрать три в ряд. Четыре дают полосатый камень, "
        .. "пять — звезду, которая уберёт весь цвет.",
    keys = { { "up", "рамка", "[←↑→↓]" }, { "select", "взять и поменять" } },
    background = "cliffs",
    dim = 0.55,
    time = 90,
}
Match3.defaultLives = 0

local N, CELL = 8, 50
local BX, BY = math.floor((960 - N * CELL) / 2), 80
local COLORS = { { 1, 0.35, 0.45 }, { 1, 0.85, 0.3 }, { 0.4, 0.9, 0.4 }, { 0.4, 0.7, 1 }, { 0.7, 0.45, 1 } }

function Match3:setup()
    self.sheet = assets.image("assets/sprites/arcade/retroblocks.png")
    self.q = {}
    for i = 1, 5 do
        self.q[i] = assets.quad(self.sheet, 32 + (i - 1) * 16, 112, 16, 16)
    end
    self.starQ = assets.quad(self.sheet, 112, 96, 16, 16)
    self.kinds = math.max(4, math.min(5, self.def.kinds or 5))
    self.goal = self.def.goal or 1200
    self.movesLeft = self.def.moves
    if self.movesLeft then self.timeLeft = nil end
    self.cursor = { 4, 4 }
    self.state = "idle"
    self.idleT = 0
    self:fill()
end

function Match3:goalText()
    if self.movesLeft then return "Набери " .. self.goal .. " очков за " .. self.movesLeft .. " ходов" end
    return "Набери " .. self.goal .. " очков за " .. math.floor(self.timeLimit) .. " секунд"
end

function Match3:progress()
    if self.movesLeft then return "Ходов: " .. self.movesLeft .. "   Цель: " .. self.goal end
    return "Цель: " .. self.goal
end

function Match3:newTile(r, c, kind)
    return { k = kind or love.math.random(self.kinds), y = r, x = c, s = 1 }
end

-- a board with no lines and at least one possible move
function Match3:fill()
    repeat
        self.grid = {}
        for r = 1, N do
            self.grid[r] = {}
            for c = 1, N do
                local k
                repeat
                    k = love.math.random(self.kinds)
                until not ((c > 2 and self.grid[r][c - 1].k == k and self.grid[r][c - 2].k == k)
                    or (r > 2 and self.grid[r - 1][c].k == k and self.grid[r - 2][c].k == k))
                self.grid[r][c] = self:newTile(r - N - 1 + (N - r) * 0.0, c, k)
                self.grid[r][c].y = r - N - 2
            end
        end
    until self:findMove()
    self.state = "fall"
end

function Match3:kindAt(r, c)
    local t = self.grid[r] and self.grid[r][c]
    return t and t.k
end

-- all lines of 3+: returns a set of cells and the lines
function Match3:findLines()
    local marked, lines = {}, {}
    for r = 1, N do
        local c = 1
        while c <= N do
            local k, len = self:kindAt(r, c), 1
            while k and c + len <= N and self:kindAt(r, c + len) == k do len = len + 1 end
            if k and len >= 3 then
                local line = { dir = "row", cells = {} }
                for i = 0, len - 1 do marked[r * 16 + c + i] = true; table.insert(line.cells, { r, c + i }) end
                table.insert(lines, line)
            end
            c = c + len
        end
    end
    for c = 1, N do
        local r = 1
        while r <= N do
            local k, len = self:kindAt(r, c), 1
            while k and r + len <= N and self:kindAt(r + len, c) == k do len = len + 1 end
            if k and len >= 3 then
                local line = { dir = "col", cells = {} }
                for i = 0, len - 1 do marked[(r + i) * 16 + c] = true; table.insert(line.cells, { r + i, c }) end
                table.insert(lines, line)
            end
            r = r + len
        end
    end
    return marked, lines
end

function Match3:swapCells(a, b)
    local g = self.grid
    g[a[1]][a[2]], g[b[1]][b[2]] = g[b[1]][b[2]], g[a[1]][a[2]]
end

function Match3:findMove()
    for r = 1, N do
        for c = 1, N do
            for _, d in ipairs({ { 0, 1 }, { 1, 0 } }) do
                local r2, c2 = r + d[1], c + d[2]
                if r2 <= N and c2 <= N then
                    self:swapCells({ r, c }, { r2, c2 })
                    local _, lines = self:findLines()
                    self:swapCells({ r, c }, { r2, c2 })
                    if #lines > 0 then return { { r, c }, { r2, c2 } } end
                end
            end
        end
    end
end

function Match3:trySwap(a, b)
    if b[1] < 1 or b[1] > N or b[2] < 1 or b[2] > N then return end
    local ta, tb = self.grid[a[1]][a[2]], self.grid[b[1]][b[2]]
    self.selected = nil
    self.idleT = 0
    self.hint = nil
    -- a star swapped with anything clears all blocks of that kind
    if ta.special == "star" or tb.special == "star" then
        local star, other = ta.special == "star" and a or b, ta.special == "star" and b or a
        local kind = self.grid[other[1]][other[2]].k
        local cells = { star }
        for r = 1, N do
            for c = 1, N do
                if self.grid[r][c].k == kind then table.insert(cells, { r, c }) end
            end
        end
        self:useMove()
        audio.play("powerup")
        self:flash({ 1, 1, 0.8 }, 0.3)
        self.combo = 1
        return self:clear(cells)
    end
    self:swapCells(a, b)
    local _, lines = self:findLines()
    self.swap = { a = a, b = b, t = 0, back = #lines == 0 }
    self.state = "swap"
    audio.play("card_slide")
end

function Match3:useMove()
    if self.movesLeft then self.movesLeft = self.movesLeft - 1 end
end

function Match3:step(dt)
    self.idleT = self.idleT + dt
    for r = 1, N do
        for c = 1, N do
            local t = self.grid[r][c]
            if t.pop then t.pop = t.pop + dt end
        end
    end
    if self.state == "idle" then
        self:control()
        if self.idleT > 6 and not self.hint then self.hint = self:findMove() end
    elseif self.state == "swap" then
        local s = self.swap
        s.t = s.t + dt / 0.16
        if s.t >= 1 then
            if s.back and not s.returning then
                self:swapCells(s.a, s.b)
                s.t, s.returning = 0, true
                audio.play("ui_error")
            elseif s.returning then
                self.swap, self.state = nil, "idle"
            else
                self.swap = nil
                self:useMove()
                self.combo = 0
                self:resolve(s.b)
            end
        end
    elseif self.state == "clear" then
        self.clearT = self.clearT + dt
        if self.clearT >= 0.25 then self:collapse() end
    elseif self.state == "fall" then
        local moving = false
        for r = 1, N do
            for c = 1, N do
                local t = self.grid[r][c]
                if t.y < r then
                    t.vy = (t.vy or 0) + 40 * dt
                    t.y = math.min(r, t.y + t.vy * dt)
                    moving = true
                    if t.y >= r then t.vy = 0; t.land = 0.15 end
                end
                if t.land then t.land = t.land - dt; if t.land <= 0 then t.land = nil end end
            end
        end
        if not moving then self:resolve() end
    end
end

function Match3:control()
    local cur = self.cursor
    local dirs = { up = { -1, 0 }, down = { 1, 0 }, left = { 0, -1 }, right = { 0, 1 } }
    for name, d in pairs(dirs) do
        if input.pressed(name, true) then
            if self.selected then
                return self:trySwap(self.selected, { self.selected[1] + d[1], self.selected[2] + d[2] })
            end
            cur[1] = math.max(1, math.min(N, cur[1] + d[1]))
            cur[2] = math.max(1, math.min(N, cur[2] + d[2]))
            audio.play("ui_move")
        end
    end
    if input.pressed("select") then
        if self.selected and (self.selected[1] ~= cur[1] or self.selected[2] ~= cur[2]) then
            local s = self.selected
            if math.abs(s[1] - cur[1]) + math.abs(s[2] - cur[2]) == 1 then return self:trySwap(s, { cur[1], cur[2] }) end
        end
        self.selected = not self.selected and { cur[1], cur[2] } or nil
        audio.play("ui_select")
    end
    -- the mouse: click a block, then a neighbor (or drag)
    local m = input.mouse
    local mc, mr = math.floor((m.x - BX) / CELL) + 1, math.floor((m.y - BY) / CELL) + 1
    local inside = mr >= 1 and mr <= N and mc >= 1 and mc <= N
    if inside and m.moved then cur[1], cur[2] = mr, mc end
    if inside and m.pressed[1] then
        local s = self.selected
        if s and math.abs(s[1] - mr) + math.abs(s[2] - mc) == 1 then return self:trySwap(s, { mr, mc }) end
        self.selected = { mr, mc }
        self.dragFrom = { mr, mc }
    end
    if self.dragFrom and inside and (mr ~= self.dragFrom[1] or mc ~= self.dragFrom[2]) and love.mouse.isDown(1) then
        local a = self.dragFrom
        self.dragFrom = nil
        if math.abs(a[1] - mr) + math.abs(a[2] - mc) == 1 then return self:trySwap(a, { mr, mc }) end
    end
    if not love.mouse.isDown(1) then self.dragFrom = nil end
end

-- after a swap or a fall: clear the lines (or go back to waiting)
function Match3:resolve(swapped)
    local marked, lines = self:findLines()
    if #lines == 0 then
        self.state = "idle"
        if self.score >= self.goal then return self:win() end
        if self.movesLeft and self.movesLeft <= 0 then return self:gameOver(self.score >= self.goal) end
        if not self:findMove() then
            self:banner("НЕТ ХОДОВ — ПЕРЕМЕШАЮ")
            self:fill()
        end
        return
    end
    local cells, special = {}, nil
    for key in pairs(marked) do
        table.insert(cells, { math.floor(key / 16), key % 16 })
    end
    -- the longest line leaves a special block where the swap happened
    for _, line in ipairs(lines) do
        if #line.cells >= 4 then
            local at = line.cells[2]
            for _, cell in ipairs(line.cells) do
                if swapped and cell[1] == swapped[1] and cell[2] == swapped[2] then at = swapped end
            end
            local kind = self.grid[line.cells[1][1]][line.cells[1][2]].k
            special = { at = at, kind = kind, what = #line.cells >= 5 and "star" or (line.dir == "row" and "row" or "col") }
        end
    end
    self.combo = (self.combo or 0) + 1
    self:clear(cells, special)
end

function Match3:clear(cells, special)
    local set, list = {}, {}
    local function add(r, c)
        local key = r * 16 + c
        if r >= 1 and r <= N and c >= 1 and c <= N and not set[key] then
            set[key] = true
            table.insert(list, { r, c })
            local t = self.grid[r][c]
            -- striped blocks clear their whole line
            if t.special == "row" then for i = 1, N do add(r, i) end end
            if t.special == "col" then for i = 1, N do add(i, c) end end
        end
    end
    for _, cell in ipairs(cells) do add(cell[1], cell[2]) end
    if special then
        local key = special.at[1] * 16 + special.at[2]
        if set[key] then
            set[key] = nil
            for i, cell in ipairs(list) do
                if cell[1] == special.at[1] and cell[2] == special.at[2] then table.remove(list, i); break end
            end
            local t = self.grid[special.at[1]][special.at[2]]
            t.k, t.special, t.pop = special.kind, special.what, nil
            t.born = 0.3
            audio.play("bonus")
        end
    end
    local mult = math.min(8, self.combo or 1)
    local cx, cy = 0, 0
    for _, cell in ipairs(list) do
        local t = self.grid[cell[1]][cell[2]]
        t.pop = 0
        t.dead = true
        cx, cy = cx + cell[2], cy + cell[1]
        self:burst(BX + (cell[2] - 0.5) * CELL, BY + (cell[1] - 0.5) * CELL, COLORS[t.k], 6, 120)
    end
    local pts = #list * 10 * mult
    if #list > 0 then
        self:addScore(pts, BX + (cx / #list - 0.5) * CELL, BY + (cy / #list - 0.5) * CELL)
    end
    if mult >= 2 then self:popup(screen.width / 2, BY - 20, "КАСКАД x" .. mult, { 0.6, 0.9, 1 }) end
    if #list >= 10 then self:shake(5, 0.25) end
    audio.play("brick_break", { pitch = 0.9 + mult * 0.1 })
    self.state, self.clearT = "clear", 0
end

-- the cleared blocks disappear, the ones above fall, new ones come from the top
function Match3:collapse()
    for c = 1, N do
        local column = {}
        for r = N, 1, -1 do
            local t = self.grid[r][c]
            if not t.dead then table.insert(column, t) end
        end
        local missing = N - #column
        for i = 1, missing do
            local t = self:newTile(0, c)
            t.y = 1 - i - 0.5
            table.insert(column, t)
        end
        for i, t in ipairs(column) do
            self.grid[N - i + 1][c] = t
        end
    end
    self.state = "fall"
end

function Match3:drawGame()
    local lg = love.graphics
    lg.setColor(0.03, 0.04, 0.14, 0.85)
    lg.rectangle("fill", BX - 8, BY - 8, N * CELL + 16, N * CELL + 16, 10)
    for r = 1, N do
        for c = 1, N do
            if (r + c) % 2 == 0 then
                lg.setColor(1, 1, 1, 0.05)
                lg.rectangle("fill", BX + (c - 1) * CELL, BY + (r - 1) * CELL, CELL, CELL)
            end
        end
    end
    lg.setScissor(BX - 8, BY - 8, N * CELL + 16, N * CELL + 16)
    local s = self.swap
    for r = 1, N do
        for c = 1, N do
            local t = self.grid[r][c]
            local x, y = BX + (c - 0.5) * CELL, BY + (t.y - 0.5) * CELL
            if s then
                local k = s.t
                k = k * k * (3 - 2 * k)
                local from
                if s.returning then
                    from = (r == s.a[1] and c == s.a[2]) and s.b or ((r == s.b[1] and c == s.b[2]) and s.a or nil)
                else
                    from = (r == s.a[1] and c == s.a[2]) and s.b or ((r == s.b[1] and c == s.b[2]) and s.a or nil)
                end
                if from then
                    x = BX + ((from[2] + (c - from[2]) * k) - 0.5) * CELL
                    y = BY + ((from[1] + (r - from[1]) * k) - 0.5) * CELL
                end
            end
            local scale = 3
            if t.pop then scale = 3 * math.max(0, 1 - t.pop / 0.25) end
            if t.born then t.born = t.born - love.timer.getDelta(); scale = 3 * (1 + 0.4 * math.max(0, t.born)); if t.born <= 0 then t.born = nil end end
            local sx, sy = scale, scale
            if t.land then sx, sy = scale * 1.12, scale * 0.88 end
            if self.hint and ((self.hint[1][1] == r and self.hint[1][2] == c) or (self.hint[2][1] == r and self.hint[2][2] == c)) then
                x = x + math.sin(self.time * 18) * 2
            end
            if self.selected and self.selected[1] == r and self.selected[2] == c then
                sy = sy * (1 + 0.08 * math.sin(self.time * 12))
            end
            lg.setColor(1, 1, 1, 1)
            if t.special == "star" then
                lg.draw(self.sheet, self.starQ, x, y, self.time * 2, scale, scale, 8, 8)
            else
                lg.draw(self.sheet, self.q[t.k], x, y + (sy - scale) * -8, 0, sx, sy, 8, 8)
                if t.special == "row" or t.special == "col" then
                    lg.setBlendMode("add")
                    lg.setColor(1, 1, 1, 0.35 + 0.25 * math.sin(self.time * 8))
                    if t.special == "row" then
                        lg.rectangle("fill", x - 22, y - 4, 44, 8)
                    else
                        lg.rectangle("fill", x - 4, y - 22, 8, 44)
                    end
                    lg.setBlendMode("alpha")
                end
            end
        end
    end
    lg.setScissor()
    -- the frame (cursor)
    local cur = self.selected or self.cursor
    local pulse = 2 + math.sin(self.time * 8) * 2
    lg.setColor(1, 1, 1, self.selected and 1 or 0.8)
    lg.setLineWidth(3)
    lg.rectangle("line", BX + (cur[2] - 1) * CELL + 2 - pulse / 2, BY + (cur[1] - 1) * CELL + 2 - pulse / 2,
        CELL - 4 + pulse, CELL - 4 + pulse, 6)
    if self.selected then
        lg.setColor(1, 0.9, 0.4, 0.9)
        lg.rectangle("line", BX + (self.cursor[2] - 1) * CELL + 6, BY + (self.cursor[1] - 1) * CELL + 6, CELL - 12, CELL - 12, 4)
    end
    lg.setColor(1, 1, 1, 1)
end

return Match3
