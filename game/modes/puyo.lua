-- Puyo Puyo: pairs of slime blobs fall, 4 of one color touching pop, the ones above
-- fall down and can pop again - a chain ("Puyo Puyo Blobs" by marie_iskandar, CC0).
--
--   game.stage "slime_well" { kind = "puyo", goal = 3000 }
--   local r = s:play("puyo", { chain = 3 })     -- r.win, r.score, r.chain (the longest)
--
--   goal     points to win (default 2000)
--   chain    win by making a chain this long instead (2 = two pops in a row)
--   colors   how many colors fall (3..5, default 4)
-- Keys: [←][→] move, [↑]/[X] rotate, [Z] rotate back, [↓] faster, [Space] drop.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Puyo = class(Arcade)
Puyo.keymap = "puzzle"
Puyo.info = {
    title = "Слизни-хлопушки",
    rules = "Четыре слизня одного цвета рядом — хлоп! Те, что сверху, упадут и могут хлопнуть снова: "
        .. "это цепочка, она даёт много очков.",
    keys = { { "left", "двигать", "[←][→]" }, { "rotateCW", "повернуть" }, { "drop", "бросить" } },
    background = "forest",
    dim = 0.5,
}
Puyo.defaultLives = 1

local COLS, ROWS = 6, 12
local CELL = 34
local FX, FY = math.floor((960 - COLS * CELL) / 2), 74
local CHAIN_POWER = { 0, 8, 16, 32, 64, 96, 128, 160, 192, 224, 256 }
local ROT = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } -- where the second blob is
local TINTS = { { 0.95, 0.4, 0.5 }, { 0.6, 0.85, 0.2 }, { 0.3, 0.6, 1 }, { 1, 0.7, 0.1 }, { 0.6, 0.4, 1 } }

function Puyo:setup()
    self.sheet = assets.image("assets/sprites/arcade/puyo.png")
    self.q = {}
    for c = 1, 5 do
        self.q[c] = {}
        for f = 0, 18 do
            self.q[c][f] = assets.quad(self.sheet, f * 18, (c - 1) * 18, 16, 16)
        end
    end
    self.dotQ = {}
    for c = 1, 5 do self.dotQ[c] = assets.quad(self.sheet, 54 + (c - 1) * 18, 90, 16, 16) end
    self.colors = math.max(3, math.min(5, self.def.colors or (self.level >= 4 and 5 or 4)))
    self.goal = self.def.goal or (not self.def.chain and 2000 or nil)
    self.chainGoal = self.def.chain
    self.grid = {}
    for r = 1, ROWS do self.grid[r] = {} end
    self.anim = {}       -- r..":"..c -> squash timer
    self.queue = { self:newPair(), self:newPair() }
    self.bestChain = 0
    self.fallTime = 0
    self.state = "spawn"
    self.wait = 0.3
end

function Puyo:goalText()
    if self.chainGoal then return "Сделай цепочку из " .. self.chainGoal end
    return "Набери " .. self.goal .. " очков"
end

function Puyo:progress()
    if self.chainGoal then return "Лучшая цепочка: " .. self.bestChain .. "/" .. self.chainGoal end
    return "Цель: " .. self.goal
end

function Puyo:results()
    self.extraResult = { chain = self.bestChain }
    return { "Самая длинная цепочка: " .. self.bestChain }
end

function Puyo:newPair()
    return { love.math.random(self.colors), love.math.random(self.colors) }
end

function Puyo:cell(r, c)
    if c < 1 or c > COLS or r > ROWS then return -1 end
    if r < 1 then return nil end
    return self.grid[r][c]
end

function Puyo:fits(r, c, rot)
    local d = ROT[rot]
    local a, b = self:cell(r, c), self:cell(r + d[2], c + d[1])
    return a == nil and b == nil
end

function Puyo:spawn()
    local colors = table.remove(self.queue, 1)
    table.insert(self.queue, self:newPair())
    self.piece = { r = 1, c = 3, rot = 1, colors = colors, y = 1, lockT = 0 }
    if not self:fits(1, 3, 1) then
        self.piece = nil
        self:lose()
        return
    end
    self.state = "fall"
end

function Puyo:step(dt)
    for k, t in pairs(self.anim) do
        self.anim[k] = t - dt
        if self.anim[k] <= 0 then self.anim[k] = nil end
    end
    if self.state == "spawn" then
        self.wait = self.wait - dt
        if self.wait <= 0 then self:spawn() end
        return
    elseif self.state == "pop" then
        self.popT = self.popT + dt
        if self.popT >= 0.45 then self:finishPop() end
        return
    elseif self.state == "drop" then
        self:stepDrop(dt)
        return
    end
    local p = self.piece
    if not p then return end
    if input.pressed("left", true) and self:fits(p.r, p.c - 1, p.rot) then p.c = p.c - 1; audio.play("t_move") end
    if input.pressed("right", true) and self:fits(p.r, p.c + 1, p.rot) then p.c = p.c + 1; audio.play("t_move") end
    local turn = (input.pressed("rotateCW") and 1 or 0) - (input.pressed("rotateCCW") and 1 or 0)
    if turn ~= 0 then
        local rot = (p.rot - 1 + turn) % 4 + 1
        -- kicks: push away from the wall / the floor
        for _, k in ipairs({ { 0, 0 }, { -ROT[rot][1], 0 }, { 0, -1 } }) do
            if self:fits(p.r + k[2], p.c + k[1], rot) then
                p.rot, p.c, p.r = rot, p.c + k[1], p.r + k[2]
                audio.play("t_rotate")
                break
            end
        end
    end
    if input.pressed("drop") then
        while self:fits(p.r + 1, p.c, p.rot) do p.r = p.r + 1 end
        audio.play("t_drop")
        self:shake(3, 0.12)
        return self:lock()
    end
    local speed = (0.9 + self.level * 0.25) * (input.down("down") and 12 or 1)
    self.fallTime = self.fallTime + dt * speed
    while self.fallTime >= 1 do
        self.fallTime = self.fallTime - 1
        if self:fits(p.r + 1, p.c, p.rot) then
            p.r = p.r + 1
            p.lockT = 0
        else
            p.lockT = p.lockT + 1
            if p.lockT >= 1 or input.down("down") then return self:lock() end
        end
    end
end

function Puyo:lock()
    local p = self.piece
    local d = ROT[p.rot]
    local cells = { { p.r, p.c, p.colors[1] }, { p.r + d[2], p.c + d[1], p.colors[2] } }
    for _, x in ipairs(cells) do
        if x[1] >= 1 then self.grid[x[1]][x[2]] = x[3] end
    end
    self.piece = nil
    audio.play("t_lock")
    self.chain = 0
    self:startDrop()
end

-- blobs with nothing below fall down, smoothly
function Puyo:startDrop()
    self.falling = {}
    for c = 1, COLS do
        local write = ROWS
        for r = ROWS, 1, -1 do
            local v = self.grid[r][c]
            if v then
                if write ~= r then
                    self.grid[write][c] = v
                    self.grid[r][c] = nil
                    table.insert(self.falling, { r = write, c = c, y = r, v = 0 })
                end
                write = write - 1
            end
        end
    end
    self.state = "drop"
end

function Puyo:stepDrop(dt)
    local moving = false
    for _, f in ipairs(self.falling) do
        if f.y < f.r then
            f.v = f.v + 60 * dt
            f.y = math.min(f.r, f.y + f.v * dt)
            moving = true
            if f.y >= f.r then self.anim[f.r .. ":" .. f.c] = 0.18 end
        end
    end
    if not moving then
        self.falling = {}
        self:findPops()
    end
end

function Puyo:findPops()
    local seen, groups = {}, {}
    for r = 1, ROWS do
        for c = 1, COLS do
            local v = self.grid[r][c]
            local key = r * 10 + c
            if v and not seen[key] then
                local group, stack = {}, { { r, c } }
                seen[key] = true
                while #stack > 0 do
                    local cur = table.remove(stack)
                    table.insert(group, cur)
                    for _, d in ipairs(ROT) do
                        local nr, nc = cur[1] + d[2], cur[2] + d[1]
                        local k2 = nr * 10 + nc
                        if nr >= 1 and nr <= ROWS and nc >= 1 and nc <= COLS and not seen[k2] and self.grid[nr][nc] == v then
                            seen[k2] = true
                            table.insert(stack, { nr, nc })
                        end
                    end
                end
                if #group >= 4 then table.insert(groups, { color = v, cells = group }) end
            end
        end
    end
    if #groups == 0 then
        self.state, self.wait = "spawn", 0.12
        return
    end
    self.chain = self.chain + 1
    self.bestChain = math.max(self.bestChain, self.chain)
    local popped, colorSet, groupBonus = 0, {}, 0
    self.popping = {}
    for _, g in ipairs(groups) do
        popped = popped + #g.cells
        colorSet[g.color] = true
        groupBonus = groupBonus + math.min(10, #g.cells - 4)
        for _, cell in ipairs(g.cells) do
            table.insert(self.popping, { cell[1], cell[2], g.color })
        end
    end
    local colorsUsed = 0
    for _ in pairs(colorSet) do colorsUsed = colorsUsed + 1 end
    local colorBonus = ({ 0, 3, 6, 12, 24 })[colorsUsed]
    local power = (CHAIN_POWER[self.chain] or 300) + colorBonus + groupBonus
    local pts = 10 * popped * math.max(1, power)
    local cx, cy = 0, 0
    for _, p in ipairs(self.popping) do
        cx, cy = cx + p[2], cy + p[1]
    end
    cx, cy = FX + (cx / #self.popping - 0.5) * CELL, FY + (cy / #self.popping - 0.5) * CELL
    self:addScore(pts, cx, cy)
    if self.chain >= 2 then
        self:banner(self.chain .. " ЦЕПОЧКА!", self.chain >= 4 and "red" or "gold", 1)
        self:shake(2 + self.chain, 0.2)
    end
    audio.play(self.chain >= 2 and "chain" or "puyo_pop", { pitch = 1 + (self.chain - 1) * 0.12 })
    self.state, self.popT = "pop", 0
end

function Puyo:finishPop()
    for _, p in ipairs(self.popping) do
        self.grid[p[1]][p[2]] = nil
        self:burst(FX + (p[2] - 0.5) * CELL, FY + (p[1] - 0.5) * CELL, TINTS[p[3]], 8, 150)
    end
    self.popping = nil
    if self.chainGoal and self.chain >= self.chainGoal then
        return self:win()
    end
    if self.goal and self.score >= self.goal then
        return self:win()
    end
    self:startDrop()
end

function Puyo:drawBlob(color, x, y, frame, sx, sy, alpha)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(self.sheet, self.q[color][frame or 0], x, y + CELL - 1, 0, sx or 2, sy or 2, 8, 16)
end

function Puyo:drawGame()
    local lg = love.graphics
    lg.setColor(0.03, 0.04, 0.12, 0.85)
    lg.rectangle("fill", FX - 6, FY - 6, COLS * CELL + 12, ROWS * CELL + 12, 8)
    lg.setColor(0.5, 0.6, 1, 0.7)
    lg.setLineWidth(3)
    lg.rectangle("line", FX - 6, FY - 6, COLS * CELL + 12, ROWS * CELL + 12, 8)
    -- the cross where the new pair comes: losing if it is filled
    lg.setColor(1, 0.3, 0.3, 0.25 + 0.15 * math.sin(self.time * 4))
    lg.setLineWidth(3)
    local xx, xy = FX + 2.5 * CELL, FY + 0.5 * CELL
    lg.line(xx - 8, xy - 8, xx + 8, xy + 8)
    lg.line(xx + 8, xy - 8, xx - 8, xy + 8)
    local hide = {}
    for _, f in ipairs(self.falling or {}) do hide[f.r * 10 + f.c] = f end
    local popping = {}
    for _, p in ipairs(self.popping or {}) do popping[p[1] * 10 + p[2]] = true end
    -- links between neighbors of one color (a soft bridge under the blobs)
    for r = 1, ROWS do
        for c = 1, COLS do
            local v = self.grid[r][c]
            if v and not hide[r * 10 + c] then
                local t = TINTS[v]
                lg.setColor(t[1] * 0.85, t[2] * 0.85, t[3] * 0.85, 1)
                if c < COLS and self.grid[r][c + 1] == v and not hide[r * 10 + c + 1] then
                    lg.rectangle("fill", FX + (c - 0.5) * CELL, FY + (r - 0.5) * CELL - 7, CELL, 14, 6)
                end
                if r < ROWS and self.grid[r + 1][c] == v and not hide[(r + 1) * 10 + c] then
                    lg.rectangle("fill", FX + (c - 0.5) * CELL - 7, FY + (r - 0.5) * CELL, 14, CELL, 6)
                end
            end
        end
    end
    for r = 1, ROWS do
        for c = 1, COLS do
            local v = self.grid[r][c]
            local f = hide[r * 10 + c]
            if v then
                local y = FY + ((f and f.y or r) - 1) * CELL
                local x = FX + (c - 0.5) * CELL
                if popping[r * 10 + c] then
                    local k = self.popT / 0.45
                    local blink = math.floor(self.popT * 20) % 2 == 0
                    self:drawBlob(v, x, y, blink and 2 or 0, 2 + k * 0.8, 2 + k * 0.8, 1 - k * 0.6)
                else
                    local squash = self.anim[r .. ":" .. c]
                    if squash then
                        self:drawBlob(v, x, y, 1, 2.3, 1.7)
                    else
                        local wob = 1 + 0.04 * math.sin(self.time * 5 + r + c)
                        self:drawBlob(v, x, y, 0, 2 * wob, 2 / wob)
                    end
                end
            end
        end
    end
    -- the falling pair and its shadow at the bottom
    local p = self.piece
    if p then
        local d = ROT[p.rot]
        local gr = p.r
        while self:fits(gr + 1, p.c, p.rot) do gr = gr + 1 end
        for i, off in ipairs({ { 0, 0 }, d }) do
            local color = p.colors[i]
            local x = FX + (p.c + off[1] - 0.5) * CELL
            local sy = FY + (gr + off[2] - 1) * CELL
            lg.setColor(1, 1, 1, 0.8)
            lg.draw(self.sheet, self.dotQ[color], x, sy + CELL / 2, 0, 2, 2, 8, 8)
            local y = FY + (p.r + off[2] - 1) * CELL
            if p.r + off[2] >= 1 then
                self:drawBlob(color, x, y, 0)
            end
        end
        -- the pivot blinks a little
        lg.setBlendMode("add")
        lg.setColor(1, 1, 1, 0.12 + 0.12 * math.sin(self.time * 10))
        lg.draw(self.sheet, self.q[p.colors[1]][2], FX + (p.c - 0.5) * CELL, FY + p.r * CELL - 1, 0, 2, 2, 8, 16)
        lg.setBlendMode("alpha")
    end
    -- next pairs
    local nx = FX + COLS * CELL + 40
    ui.print("Дальше", nx, FY, { font = "small", color = "light" })
    for i, pair in ipairs(self.queue) do
        local y = FY + 30 + (i - 1) * 90
        local s = i == 1 and 2 or 1.5
        self:drawBlob(pair[2], nx + 20, y, 0, s, s)
        self:drawBlob(pair[1], nx + 20, y + 16 * s, 0, s, s)
    end
end

return Puyo
