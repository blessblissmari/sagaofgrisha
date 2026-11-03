-- Breakout / Arkanoid on the art of "Breakout set" by Buch (CC0).
--
--   game.stage "wall" { kind = "breakout", rounds = 2, lives = 3 }
--   local r = s:play("breakout", { layouts = { "rrrrrrrrrrrr", "b*bb*bb*bb*b" } })
--
--   rounds    how many walls to break to win (default 2); the walls come from `layouts`
--   layouts   your own walls: a list of walls, a wall is a list of rows of 12 letters:
--             b g r p o (colors, 1 hit)  s (steel, 2 hits)  n (bronze, 3 hits)
--             * (a surprise: drops a bonus)  . (empty)
--   speed     ball speed (default 330 + 30 per level)
-- Bonuses: wide paddle, three balls, slow ball, fire ball (goes through), +1 heart.
-- Keys: [←][→] or the mouse move, [Space] launch.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Breakout = class(Arcade)
Breakout.info = {
    title = "Кирпичики",
    rules = "Отбивай шарик и разбей все кирпичи. Полосатые прячут бонусы. Чем дальше от центра "
        .. "ракетки ударил — тем круче отскок.",
    keys = { { "left", "двигать", "[←][→]" }, { "fire", "запустить" } },
    background = "mountains",
    dim = 0.6,
}

local S = 2                                  -- art pixel -> screen pixels
local COLS, BW, BH = 12, 32 * S, 16 * S
local FX0 = math.floor((960 - COLS * BW) / 2)
local FY0 = 56
local FIELD = { x = FX0 - 8, y = 40, w = COLS * BW + 16, h = 500 }
local PADDLE_Y = 488

local COLORS = { -- brick letter -> sheet position and particle color
    b = { 8, 8, { 0.35, 0.55, 1 } }, g = { 8, 28, { 0.4, 0.8, 0.3 } }, r = { 8, 48, { 0.9, 0.3, 0.3 } },
    p = { 8, 68, { 0.7, 0.4, 0.9 } }, o = { 8, 88, { 1, 0.65, 0.2 } }, s = { 8, 108, { 0.6, 0.6, 0.6 } },
    n = { 8, 128, { 0.65, 0.4, 0.25 } },
}
local HITS = { s = 2, n = 3 }
local BALL_COLORS = { b = 1, g = 2, r = 3, p = 4, o = 5, s = 6, n = 7 }

local LAYOUTS = {
    { "............", "rrrrrrrrrrrr", "oooo*oo*oooo", "gggggggggggg", "bbb*bbbb*bbb", "pppppppppppp" },
    { "s..........s", "sr.r*rr*r.rs", "so.oooooo.os", "sg.g*gg*g.gs", "sb.bbbbbb.bs", "snnnnnnnnnns" },
    { "....*..*....", "...rrrrrr...", "..oo*oo*oo..", ".gggggggggg.", "bbbb*bb*bbbb", "pppppppppppp", "nn..nnnn..nn" },
    { "*b*b*b*b*b*b", "gggggggggggg", "ssssssssssss", "rrrrrrrrrrrr", "oo*oo**oo*oo", "nnnnnnnnnnnn" },
}

local BONUSES = {
    { id = "wide", text = "ШИРЕ!", color = "b", stripe = 48 },
    { id = "multi", text = "ТРИ ШАРА!", color = "g", stripe = 120 },
    { id = "slow", text = "МЕДЛЕННЕЕ", color = "p", stripe = 192 },
    { id = "fire", text = "ОГНЕННЫЙ ШАР!", color = "r", stripe = 228 },
    { id = "life", text = "+1 ЖИЗНЬ", color = "o", stripe = 264 },
}

function Breakout:setup()
    self.sheet = assets.image("assets/sprites/arcade/breakout.png")
    self.q = {}
    for k, c in pairs(COLORS) do
        self.q[k] = assets.quad(self.sheet, c[1], c[2], 32, 16)
    end
    self.stripeQ = {}
    for i = 0, 6 do
        for j, y in ipairs({ 8, 28, 48 }) do
            self.stripeQ[#self.stripeQ + 1] = assets.quad(self.sheet, 48 + i * 36, y, 32, 16)
        end
    end
    self.ballQ = {}
    for i = 0, 6 do
        self.ballQ[i + 1] = assets.quad(self.sheet, 48 + i * 9, 136, 8, 8)
    end
    self.paddleQ = assets.quad(self.sheet, 8, 151, 64, 20)
    self.paddleFireQ = assets.quad(self.sheet, 76, 151, 64, 20)
    self.heartQ = assets.quad(self.sheet, 120, 135, 10, 9)
    self.layouts = self.def.layouts or LAYOUTS
    self.rounds = self.def.rounds or math.min(2, #self.layouts)
    self.round = 1
    self.baseSpeed = self.def.speed or (300 + 30 * self.level)
    self.paddle = { x = 480, w = 64 * S, wide = 0, squash = 0 }
    self.combo = 0
    self:buildWall()
    self:resetBalls()
end

function Breakout:goalText()
    return "Разбей " .. self.rounds .. (self.rounds == 1 and " стену" or " стены")
end

function Breakout:progress()
    return "Стена " .. self.round .. "/" .. self.rounds
end

function Breakout:results()
    return { "Разбито кирпичей: " .. (self.broken or 0) }
end

function Breakout:buildWall()
    local layout = self.layouts[(self.round - 1) % #self.layouts + 1]
    self.bricks, self.left = {}, 0
    for r, row in ipairs(layout) do
        for c = 1, math.min(COLS, #row) do
            local ch = row:sub(c, c)
            if ch ~= "." and ch ~= " " then
                local special = ch == "*"
                local color = special and ({ "b", "g", "r", "p", "o" })[love.math.random(5)] or ch
                local b = {
                    x = FX0 + (c - 1) * BW, y = FY0 + (r - 1) * BH, color = color, special = special,
                    hits = HITS[ch] or 1, stripe = special and love.math.random(#self.stripeQ) or nil,
                    t = -((r + c) * 0.03), hit = 0,
                }
                table.insert(self.bricks, b)
                self.left = self.left + 1
            end
        end
    end
    self.capsules = {}
end

function Breakout:resetBalls()
    self.balls = { { x = self.paddle.x, y = PADDLE_Y - 10, vx = 0, vy = 0, stuck = true, trail = {} } }
    self.fireT = 0
    self.slow = 0
end

function Breakout:launch(ball)
    ball.stuck = false
    local a = -math.pi / 2 + (love.math.random() - 0.5) * 0.6
    ball.vx, ball.vy = math.cos(a) * self.baseSpeed, math.sin(a) * self.baseSpeed
    audio.play("blip")
end

function Breakout:speed()
    local s = self.baseSpeed * (1 + math.min(0.45, (self.playTime or 0) / 240))
    if self.slow > 0 then s = s * 0.7 end
    return s
end

function Breakout:paddleWidth()
    return self.paddle.w * (self.paddle.wide > 0 and 1.5 or 1)
end

function Breakout:step(dt)
    local p = self.paddle
    local dir = 0
    if input.down("left") then dir = dir - 1 end
    if input.down("right") then dir = dir + 1 end
    if dir ~= 0 then
        p.x = p.x + dir * 620 * dt
    elseif input.mouse.moved then
        p.x = input.mouse.x
    end
    local half = self:paddleWidth() / 2
    p.x = math.max(FIELD.x + half, math.min(FIELD.x + FIELD.w - half, p.x))
    p.wide = math.max(0, p.wide - dt)
    p.squash = math.max(0, p.squash - dt * 4)
    self.fireT = math.max(0, self.fireT - dt)
    self.slow = math.max(0, self.slow - dt)
    for _, b in ipairs(self.bricks) do
        b.t = b.t + dt
        b.hit = math.max(0, b.hit - dt * 5)
    end

    local launch = input.pressed("fire") or input.pressed("confirm") or input.mouse.pressed[1]
    for i = #self.balls, 1, -1 do
        local ball = self.balls[i]
        if ball.stuck then
            ball.x, ball.y = p.x, PADDLE_Y - 10
            if launch then self:launch(ball) end
        else
            self:moveBall(ball, dt)
            if ball.y > screen.height + 20 then
                table.remove(self.balls, i)
            end
        end
    end
    if #self.balls == 0 then
        self.combo = 0
        if not self:loseLife() then
            self:resetBalls()
        end
        return
    end
    for i = #self.capsules, 1, -1 do
        local c = self.capsules[i]
        c.y = c.y + 150 * dt
        c.t = c.t + dt
        if c.y > PADDLE_Y - 12 and c.y < PADDLE_Y + 20 and math.abs(c.x - p.x) < half + 24 then
            self:takeBonus(c.bonus, c.x)
            table.remove(self.capsules, i)
        elseif c.y > screen.height then
            table.remove(self.capsules, i)
        end
    end
end

function Breakout:moveBall(ball, dt)
    local speed = self:speed()
    local len = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    ball.vx, ball.vy = ball.vx / len * speed, ball.vy / len * speed
    -- small steps: the ball never skips a brick
    local steps = math.ceil(speed * dt / 6)
    local sdt = dt / steps
    for _ = 1, steps do
        ball.x = ball.x + ball.vx * sdt
        ball.y = ball.y + ball.vy * sdt
        local r = 8
        if ball.x < FIELD.x + r then ball.x, ball.vx = FIELD.x + r, math.abs(ball.vx); audio.play("blip") end
        if ball.x > FIELD.x + FIELD.w - r then ball.x, ball.vx = FIELD.x + FIELD.w - r, -math.abs(ball.vx); audio.play("blip") end
        if ball.y < FIELD.y + r then ball.y, ball.vy = FIELD.y + r, math.abs(ball.vy); audio.play("blip") end
        -- paddle: the angle depends on where the ball hits it
        local p = self.paddle
        local half = self:paddleWidth() / 2
        if ball.vy > 0 and ball.y + r >= PADDLE_Y and ball.y < PADDLE_Y + 20 and math.abs(ball.x - p.x) < half + r then
            local k = math.max(-1, math.min(1, (ball.x - p.x) / half))
            local a = -math.pi / 2 + k * 1.1
            ball.vx, ball.vy = math.cos(a) * speed, math.sin(a) * speed
            ball.y = PADDLE_Y - r
            p.squash = 1
            self.combo = 0
            audio.play("blip", { pitch = 0.8 })
        end
        -- bricks
        for i = #self.bricks, 1, -1 do
            local b = self.bricks[i]
            if ball.x + r > b.x and ball.x - r < b.x + BW and ball.y + r > b.y and ball.y - r < b.y + BH then
                if self.fireT <= 0 then
                    -- bounce off the side that is the closest
                    local ox = math.min(ball.x + r - b.x, b.x + BW - (ball.x - r))
                    local oy = math.min(ball.y + r - b.y, b.y + BH - (ball.y - r))
                    if ox < oy then ball.vx = -ball.vx else ball.vy = -ball.vy end
                end
                self:hitBrick(i, b)
                if self.fireT <= 0 then break end
            end
        end
    end
    table.insert(ball.trail, 1, { ball.x, ball.y })
    if #ball.trail > 8 then table.remove(ball.trail) end
end

function Breakout:hitBrick(i, b)
    b.hits = b.hits - (self.fireT > 0 and 3 or 1)
    b.hit = 1
    local cx, cy = b.x + BW / 2, b.y + BH / 2
    if b.hits > 0 then
        audio.play("brick")
        self:shake(2, 0.1)
        return
    end
    table.remove(self.bricks, i)
    self.left = self.left - 1
    self.broken = (self.broken or 0) + 1
    self.combo = self.combo + 1
    local pts = 50 * math.min(8, self.combo)
    self:addScore(pts, cx, cy)
    self:burst(cx, cy, COLORS[b.color][3], 14, 160)
    audio.play("brick_break", { pitch = 1 + math.min(0.6, self.combo * 0.05) })
    if b.special then
        local bonus = BONUSES[love.math.random(#BONUSES)]
        table.insert(self.capsules, { x = cx, y = cy, bonus = bonus, t = 0 })
    end
    if self.combo == 5 or self.combo == 10 then
        self:banner(self.combo == 10 and "СУПЕР!" or "КОМБО!")
    end
    if self.left <= 0 then
        self:wallDone()
    end
end

function Breakout:wallDone()
    self:addScore(500)
    if self.round >= self.rounds then
        self:win()
        return
    end
    self.round = self.round + 1
    self:banner("СТЕНА " .. self.round)
    audio.play("powerup")
    self:buildWall()
    self:resetBalls()
end

function Breakout:takeBonus(bonus, x)
    audio.play("powerup")
    self:popup(x, PADDLE_Y - 30, bonus.text, COLORS[bonus.color][3])
    if bonus.id == "wide" then
        self.paddle.wide = 15
    elseif bonus.id == "multi" then
        local src = self.balls[1]
        for k = 1, 2 do
            local a = -math.pi / 2 + (k == 1 and -0.6 or 0.6)
            table.insert(self.balls, { x = src.x, y = src.y, vx = math.cos(a), vy = math.sin(a), trail = {},
                stuck = false })
        end
        for _, b in ipairs(self.balls) do
            if b.stuck then self:launch(b) end
        end
    elseif bonus.id == "slow" then
        self.slow = 12
    elseif bonus.id == "fire" then
        self.fireT = 8
    elseif bonus.id == "life" then
        self.lives = math.min(self.maxLives + 2, self.lives + 1)
        self.maxLives = math.max(self.maxLives, self.lives)
    end
end

function Breakout:drawGame()
    local lg = love.graphics
    -- the field: a dark glass box
    lg.setColor(0.02, 0.03, 0.1, 0.72)
    lg.rectangle("fill", FIELD.x, FIELD.y, FIELD.w, FIELD.h)
    lg.setColor(0.4, 0.5, 0.9, 0.6)
    lg.setLineWidth(2)
    lg.rectangle("line", FIELD.x - 1, FIELD.y - 1, FIELD.w + 2, FIELD.h + 40)
    local phase = self:beat()
    local pulse = (1 - phase) ^ 4
    for _, b in ipairs(self.bricks) do
        if b.t > 0 then
            local k = math.min(1, b.t * 4)
            local dy = (1 - k) * -30
            lg.setColor(1, 1, 1, k)
            local q = b.special and self.stripeQ[b.stripe] or self.q[b.color]
            lg.draw(self.sheet, q, b.x, b.y + dy, 0, S, S)
            if b.hit > 0 or pulse > 0.5 then
                lg.setBlendMode("add")
                lg.setColor(1, 1, 1, math.max(b.hit * 0.8, (pulse - 0.5) * 0.15))
                lg.draw(self.sheet, q, b.x, b.y + dy, 0, S, S)
                lg.setBlendMode("alpha")
            end
            if b.hits > 1 then
                lg.setColor(0, 0, 0, 0.35)
                lg.rectangle("fill", b.x + 6, b.y + BH - 8, (b.hits - 1) * 8, 4)
            end
        end
    end
    for _, c in ipairs(self.capsules) do
        local q = self.q[c.bonus.color]
        lg.setColor(1, 1, 1, 1)
        local sx = 1.4 * (0.75 + 0.25 * math.cos(c.t * 8))
        lg.draw(self.sheet, q, c.x, c.y, 0, sx, 1.4, 16, 8)
        if c.bonus.id == "life" then
            lg.draw(self.sheet, self.heartQ, c.x, c.y, 0, 2, 2, 5, 4.5)
        end
    end
    -- paddle
    local p = self.paddle
    local w = self:paddleWidth()
    local sq = p.squash
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.sheet, self.fireT > 0 and self.paddleFireQ or self.paddleQ, p.x, PADDLE_Y + 20 * S / 2 - 6,
        0, w / 64 * (1 + sq * 0.08), S * (1 - sq * 0.15), 32, 10)
    -- balls with a trail
    for _, ball in ipairs(self.balls) do
        local color = self.fireT > 0 and { 1, 0.5, 0.2 } or { 0.6, 0.8, 1 }
        for i, t in ipairs(ball.trail) do
            lg.setColor(color[1], color[2], color[3], 0.35 * (1 - i / #ball.trail))
            lg.circle("fill", t[1], t[2], 7 * (1 - i / 10))
        end
        lg.setColor(1, 1, 1, 1)
        lg.draw(self.sheet, self.ballQ[self.fireT > 0 and 3 or 1], ball.x, ball.y, 0, 3, 3, 4, 4)
    end
    if self.balls[1] and self.balls[1].stuck and self.phase == "play" then
        ui.print("[" .. input.keyName("fire") .. "]", p.x, PADDLE_Y - 52, { font = "small", align = "center",
            color = "light", alpha = 0.6 + 0.4 * math.sin(self.time * 6) })
    end
end

function Breakout:idle(dt)
    for _, b in ipairs(self.bricks) do b.hit = math.max(0, b.hit - dt * 5) end
end

return Breakout
