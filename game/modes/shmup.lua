-- Side-scrolling shoot'em up (Gradius / Touhou style): waves of ships and rocks, power-ups,
-- grazing bullets for points, bombs that clear the screen, and a boss at the end.
-- Sprites: "Space Shooter Redux" by Kenney (CC0); explosions: "Explosion Sheet" by StumpyStrust (CC0).
--
--   game.stage "space" { kind = "shmup", level = 2, prize = { coin = 10 } }
--   local r = s:play("shmup", { boss = false, time = 45 })   -- r.win, r.score, r.graze
--
--   boss      false = no boss: survive the waves (and the time) to win
--   waves     your own list of waves (see WAVES below), the default one takes ~55 s + the boss
--   bombs     bombs at the start (default 2)
--   power     power of the gun at the start 1..4 (default 1)
--   lives     hearts (default 3)
-- Keys: arrows - fly, [Space] - fire (hold), [Shift] - slow precise flight (shows the hitbox),
-- [X] - bomb: clears every bullet and hurts every enemy.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local Shmup = class(Arcade)
Shmup.info = {
    title = "Звёздный патруль",
    rules = "Стреляй и уворачивайся. Молния — сильнее пушка, щит — один удар не страшен, звезда — бомба. "
        .. "Пули, пролетевшие впритирку, дают очки. В конце — босс.",
    keys = { { "up", "лететь", "[←↑→↓]" }, { "fire", "огонь" }, { "focus", "точно" }, { "action", "бомба" } },
    background = "black",
    dim = 0,
}

local DIR = "assets/sprites/shmup/"
local PI2 = math.pi / 2

-- enemy kinds: sprite, hit points, radius, score, scale
local KINDS = {
    drone = { image = "enemyBlue2", hp = 2, r = 20, score = 100, scale = 0.45 },
    diver = { image = "enemyGreen3", hp = 3, r = 20, score = 150, scale = 0.45 },
    gunner = { image = "enemyBlack1", hp = 7, r = 22, score = 300, scale = 0.5, drop = "power" },
    spinner = { image = "enemyRed4", hp = 10, r = 22, score = 400, scale = 0.5 },
    heavy = { image = "enemyBlack5", hp = 18, r = 26, score = 700, scale = 0.6, drop = "bomb" },
    rock = { image = "meteorBrown_big1", hp = 6, r = 32, score = 120, scale = 0.7, rock = 2 },
    rock_med = { image = "meteorBrown_med1", hp = 3, r = 16, score = 60, scale = 0.8, rock = 1 },
    rock_small = { image = "meteorBrown_small1", hp = 1, r = 10, score = 30, scale = 0.8, rock = 0 },
    boss = { image = "ufoRed", hp = 260, r = 62, score = 5000, scale = 1.5 },
}

-- the default flight: t = second, then what comes. y in 0..1 of the screen height.
local WAVES = {
    { t = 1.5, kind = "drone", n = 5, move = "sine", y = 0.3 },
    { t = 4.5, kind = "drone", n = 5, move = "sine", y = 0.7 },
    { t = 7.5, kind = "rock", n = 2 },
    { t = 9, kind = "diver", n = 4, move = "dive" },
    { t = 12.5, kind = "gunner", n = 2, move = "stop" },
    { t = 16, kind = "drone", n = 6, move = "wave", y = 0.5 },
    { t = 19, kind = "rock", n = 3 },
    { t = 21, kind = "spinner", n = 1, move = "stop", y = 0.5 },
    { t = 24, kind = "diver", n = 6, move = "dive" },
    { t = 27, kind = "gunner", n = 3, move = "stop" },
    { t = 31, kind = "drone", n = 8, move = "sine", y = 0.25 },
    { t = 32, kind = "drone", n = 8, move = "sine", y = 0.75 },
    { t = 36, kind = "heavy", n = 1, move = "stop", y = 0.5 },
    { t = 40, kind = "rock", n = 4 },
    { t = 42, kind = "spinner", n = 2, move = "stop" },
    { t = 46, kind = "diver", n = 8, move = "dive" },
    { t = 50, kind = "gunner", n = 2, move = "stop" },
    { t = 51, kind = "heavy", n = 1, move = "stop", y = 0.3 },
    { t = 58, kind = "boss" },
}

local DROPS = {
    power = { image = "powerupBlue_bolt", text = "Сильнее!" },
    shield = { image = "powerupGreen_shield", text = "Щит" },
    bomb = { image = "powerupRed_star", text = "+1 бомба" },
    life = { image = "pill_red", text = "+1 жизнь" },
}

function Shmup:setup()
    self.img = {}
    for _, name in ipairs({ "playerShip1_blue", "fire08", "fire09", "laserBlue01", "laserGreen11", "laserRed08", "laserRed01",
        "shield1", "star1", "star2", "star3", "bg_purple" }) do
        self.img[name] = assets.image(DIR .. name .. ".png")
    end
    for _, k in pairs(KINDS) do self.img[k.image] = assets.image(DIR .. k.image .. ".png") end
    for _, d in pairs(DROPS) do self.img[d.image] = assets.image(DIR .. d.image .. ".png") end
    self.img.bg_purple:setWrap("repeat", "repeat")
    self.bgQuad = love.graphics.newQuad(0, 0, screen.width + 256, screen.height + 256, 256, 256)
    self.player = { x = 130, y = screen.height / 2, r = 4, inv = 0, power = self.def.power or 1, shield = false, fireT = 0,
        tilt = 0 }
    self.shots, self.bullets, self.enemies, self.items, self.medals = {}, {}, {}, {}, {}
    self.bombs = self.def.bombs or 2
    self.waves = self.def.waves or WAVES
    self.waveI = 1
    self.clock = 0
    self.chain, self.chainT = 0, 0
    self.grazes = 0
    self.kills = 0
    self.scroll = 0
    self.hard = 0.8 + self.level * 0.1
    self.stars = {}
    for i = 1, 90 do
        table.insert(self.stars, { x = love.math.random() * screen.width, y = love.math.random() * screen.height,
            z = 1 + (i % 3) })
    end
    if self.def.boss == false then
        for i = #self.waves, 1, -1 do
            if self.waves[i].kind == "boss" then
                local copy = {}
                for j, w in ipairs(self.waves) do if j ~= i then table.insert(copy, w) end end
                self.waves = copy
            end
        end
    end
end

function Shmup:goalText()
    if self.def.boss == false then return "Продержись до конца" end
    return "Победи босса"
end

function Shmup:progress()
    if self.boss and not self.boss.dead then return "БОСС" end
    if self.chain >= 2 then return "Цепь x" .. self.chain end
    return nil
end

function Shmup:results()
    self.extraResult = { graze = self.grazes, kills = self.kills }
    return { "Сбито: " .. self.kills .. "   Впритирку: " .. self.grazes }
end

-- spawning --------------------------------------------------------------------------------

function Shmup:spawn(kind, x, y, move, extra)
    local k = KINDS[kind]
    local e = { kind = kind, k = k, x = x, y = y, hp = math.ceil(k.hp * self.hard), r = k.r, move = move or "line",
        t = 0, fireT = 1 + love.math.random(), baseY = y, flash = 0, rot = 0, spin = 0 }
    e.maxHp = e.hp
    for key, v in pairs(extra or {}) do e[key] = v end
    if k.rock then
        e.vx, e.vy = -(70 + love.math.random() * 60), (love.math.random() - 0.5) * 60
        e.spin = (love.math.random() - 0.5) * 2
    end
    table.insert(self.enemies, e)
    return e
end

function Shmup:spawnWave(w)
    local H = screen.height
    local n = w.n or 1
    if w.kind == "boss" then
        self.boss = self:spawn("boss", screen.width + 120, H / 2, "boss")
        self.boss.phase = 1
        self:banner("БОСС!", "red", 1.6)
        audio.play("two_tone")
        return
    end
    for i = 1, n do
        local y = (w.y and w.y * H) or (60 + love.math.random() * (H - 120))
        local x = screen.width + 40 + (i - 1) * 60
        if w.move == "dive" then
            x = screen.width + 30 + (i - 1) * 40
            y = 60 + (i - 1) / math.max(1, n - 1) * (H - 120)
        elseif w.move == "stop" then
            y = w.y and w.y * H or (H * i / (n + 1))
            x = screen.width + 40
        elseif w.move == "wave" then
            y = H / 2 + (i - (n + 1) / 2) * 60
            x = screen.width + 40 + math.abs(i - (n + 1) / 2) * 50
        elseif KINDS[w.kind].rock then
            x = screen.width + 60 + i * 140
        end
        self:spawn(w.kind, x, y, w.move, { delay = (w.move == "sine") and 0 or nil, index = i })
    end
end

-- bullets -----------------------------------------------------------------------------------

function Shmup:bullet(x, y, angle, speed, opts)
    opts = opts or {}
    speed = speed * (0.85 + self.level * 0.075)
    table.insert(self.bullets, { x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
        r = opts.r or 6, laser = opts.laser, t = 0 })
end

function Shmup:aimAt(e)
    local p = self.player
    return math.atan2(p.y - e.y, p.x - e.x)
end

function Shmup:fan(e, n, spread, speed)
    local a = self:aimAt(e)
    for i = 1, n do
        local k = n == 1 and 0 or ((i - 1) / (n - 1) - 0.5)
        self:bullet(e.x - 10, e.y, a + k * spread, speed)
    end
end

function Shmup:ring(e, n, speed, offset)
    for i = 1, n do
        self:bullet(e.x, e.y, (offset or 0) + i / n * math.pi * 2, speed)
    end
end

-- the enemy brain: moving and shooting
function Shmup:think(e, dt)
    local W, H = screen.width, screen.height
    local p = self.player
    e.t = e.t + dt
    e.flash = math.max(0, e.flash - dt * 6)
    if e.k.rock then
        e.x, e.y = e.x + e.vx * dt, e.y + e.vy * dt
        e.rot = e.rot + e.spin * dt
        if e.y < 20 or e.y > H - 20 then e.vy = -e.vy end
        return
    end
    if e.move == "sine" then
        e.x = e.x - 170 * dt
        e.y = e.baseY + math.sin(e.t * 3 + (e.index or 0) * 0.6) * 70
    elseif e.move == "wave" then
        e.x = e.x - 150 * dt
    elseif e.move == "dive" then
        if e.t < 0.9 then
            e.x = e.x + ((W - 140 - (e.index or 0) * 30) - e.x) * math.min(1, dt * 3)
        elseif not e.vx then
            local a = self:aimAt(e)
            e.vx, e.vy = math.cos(a) * 380, math.sin(a) * 380
            e.rot = a + math.pi
            audio.play("dash")
        else
            e.x, e.y = e.x + e.vx * dt, e.y + e.vy * dt
        end
    elseif e.move == "stop" then
        local stopX = W - 120 - (e.index or 0) % 2 * 70
        if e.t < 7 then
            e.x = e.x + (stopX - e.x) * math.min(1, dt * 2)
            e.y = e.baseY + math.sin(e.t * 1.3) * 30
        else
            e.x = e.x + 60 * dt
            e.y = e.y - 120 * dt
        end
    elseif e.move == "boss" then
        return self:thinkBoss(e, dt)
    else
        e.x = e.x - 160 * dt
    end
    -- shooting
    if e.x < W - 20 and e.x > 60 then
        e.fireT = e.fireT - dt * self.hard
        if e.fireT <= 0 then
            local kind = e.kind
            if kind == "gunner" then
                self:fan(e, 3, 0.5, 200)
                e.fireT = 1.6
            elseif kind == "spinner" then
                e.spinA = (e.spinA or 0) + 0.35
                self:ring(e, 6, 150, e.spinA)
                e.fireT = 0.4
            elseif kind == "heavy" then
                self:ring(e, 14, 130, e.t)
                self:fan(e, 5, 0.6, 230)
                e.fireT = 1.8
            elseif kind == "drone" and self.level >= 3 and love.math.random() < 0.25 then
                self:fan(e, 1, 0, 200)
                e.fireT = 2.5
            else
                e.fireT = 2
            end
            audio.play("zap", { volume = 0.25 })
        end
    end
end

function Shmup:thinkBoss(e, dt)
    local W, H = screen.width, screen.height
    e.x = e.x + ((W - 150) - e.x) * math.min(1, dt * 1.2)
    e.y = H / 2 + math.sin(e.t * 0.8) * (H / 2 - 110)
    e.rot = e.rot + dt * 1.5
    if e.t < 2 then return end
    local k = e.hp / e.maxHp
    local phase = k > 0.66 and 1 or (k > 0.33 and 2 or 3)
    if phase ~= e.phase then
        e.phase = phase
        self.bullets = {}
        self:flash({ 1, 0.4, 0.3 }, 0.4)
        self:shake(8, 0.4)
        audio.play("boom_big")
        self:banner(phase == 2 and "ЯРОСТЬ!" or "ПОСЛЕДНИЙ РЫВОК!", "red")
    end
    e.fireT = e.fireT - dt * self.hard
    e.fire2 = (e.fire2 or 0) - dt * self.hard
    if phase == 1 then
        if e.fireT <= 0 then self:fan(e, 5, 0.7, 220); e.fireT = 1.1 end
        if e.fire2 <= 0 then self:ring(e, 16, 120, e.t); e.fire2 = 2.6 end
    elseif phase == 2 then
        if e.fireT <= 0 then
            e.spinA = (e.spinA or 0) + 0.22
            self:ring(e, 4, 170, e.spinA)
            self:ring(e, 4, 170, -e.spinA * 1.3)
            e.fireT = 0.14
        end
    else
        if e.fireT <= 0 then self:ring(e, 22, 140, love.math.random() * 6.28); self:fan(e, 3, 0.25, 280); e.fireT = 1.0 end
        if e.fire2 <= 0 then
            for i = 1, 2 do self:spawn("drone", W + 30, i == 1 and 120 or H - 120, "sine") end
            e.fire2 = 4.5
        end
    end
end

-- hits ---------------------------------------------------------------------------------------

function Shmup:hurtEnemy(e, dmg)
    if e.dead then return end
    e.hp = e.hp - dmg
    e.flash = 1
    if e.hp > 0 then
        if e.kind == "boss" then audio.play("hit", { volume = 0.3 }) end
        return
    end
    e.dead = true
    self.kills = self.kills + 1
    self.chain = math.min(8, self.chain + 1)
    self.chainT = 1.6
    self:addScore(e.k.score * self.chain, e.x, e.y - 20)
    local big = e.r > 24
    self.fx:play("boom", e.x, e.y, { scale = e.r / 22 })
    audio.play(big and "boom_big" or "boom")
    if big then self:shake(4, 0.2) end
    if e.k.rock and e.k.rock > 0 then
        local child = e.k.rock == 2 and "rock_med" or "rock_small"
        for i = 1, 2 do
            local c = self:spawn(child, e.x, e.y)
            c.vy = (i == 1 and -1 or 1) * (40 + love.math.random() * 50)
        end
    end
    -- point medals fly to the player
    for _ = 1, (big and 5 or 2) do
        table.insert(self.medals, { x = e.x, y = e.y, vx = (love.math.random() - 0.3) * 200, vy = (love.math.random() - 0.5) * 200,
            t = 0 })
    end
    local drop = e.k.drop
    if not drop then
        local r = love.math.random()
        if r < 0.1 and self.player.power < 4 then drop = "power"
        elseif r < 0.14 then drop = "shield"
        elseif r < 0.165 then drop = "bomb"
        elseif r < 0.175 then drop = "life" end
    end
    if drop then table.insert(self.items, { kind = drop, x = e.x, y = e.y, t = 0 }) end
    if e.kind == "boss" then self:bossDown(e) end
end

function Shmup:bossDown(e)
    self.bullets = {}
    self.bossDead = true
    self.timer:every(0.18, function()
        self.fx:play("boom", e.x + (love.math.random() - 0.5) * 140, e.y + (love.math.random() - 0.5) * 140,
            { scale = 1 + love.math.random() })
        audio.play("boom")
        self:shake(6, 0.2)
    end, 10)
    self.timer:after(2.2, function()
        e.hidden = true
        self:flash({ 1, 1, 1 }, 0.6)
        audio.play("boom_big")
        self.timer:after(1.0, function() self:win() end)
    end)
end

function Shmup:hurtPlayer()
    local p = self.player
    if p.inv > 0 or self.phase ~= "play" then return end
    if p.shield then
        p.shield = false
        p.inv = 1.2
        audio.play("shield_down")
        self:flash({ 0.4, 1, 0.5 }, 0.2)
        return
    end
    self.fx:play("boom", p.x, p.y, { scale = 1.3 })
    audio.play("boom_big")
    p.power = math.max(1, p.power - 1)
    p.inv = 2.4
    self.chain = 0
    -- the bullets around are blown away
    for i = #self.bullets, 1, -1 do
        local b = self.bullets[i]
        if (b.x - p.x) ^ 2 + (b.y - p.y) ^ 2 < 160 ^ 2 then table.remove(self.bullets, i) end
    end
    self:loseLife()
end

function Shmup:bomb()
    if self.bombs <= 0 then
        audio.play("ui_error")
        return
    end
    self.bombs = self.bombs - 1
    self.bombT = 0.8
    self.player.inv = math.max(self.player.inv, 1.6)
    for _, b in ipairs(self.bullets) do
        table.insert(self.medals, { x = b.x, y = b.y, vx = 0, vy = 0, t = 0.3 })
    end
    self.bullets = {}
    for _, e in ipairs(self.enemies) do
        if e.x < screen.width then self:hurtEnemy(e, e.kind == "boss" and 25 or 30) end
    end
    self:flash({ 1, 0.95, 0.7 }, 0.5)
    self:shake(9, 0.5)
    audio.play("boom_big")
    audio.play("zap")
end

-- the game --------------------------------------------------------------------------------------

function Shmup:step(dt)
    local W, H = screen.width, screen.height
    local p = self.player
    self.clock = self.clock + dt
    self.scroll = self.scroll + dt
    -- waves
    while self.waves[self.waveI] and self.clock >= self.waves[self.waveI].t do
        self:spawnWave(self.waves[self.waveI])
        self.waveI = self.waveI + 1
    end
    -- the ship
    local focus = input.down("focus")
    local speed = focus and 150 or 300
    local dx = (input.down("right") and 1 or 0) - (input.down("left") and 1 or 0)
    local dy = (input.down("down") and 1 or 0) - (input.down("up") and 1 or 0)
    if dx ~= 0 and dy ~= 0 then dx, dy = dx * 0.7071, dy * 0.7071 end
    p.x = math.max(30, math.min(W - 40, p.x + dx * speed * dt))
    p.y = math.max(40, math.min(H - 24, p.y + dy * speed * dt))
    p.tilt = p.tilt + (dy * 0.25 - p.tilt) * math.min(1, dt * 10)
    p.inv = math.max(0, p.inv - dt)
    p.focus = focus
    if self.bombT then
        self.bombT = self.bombT - dt
        if self.bombT <= 0 then self.bombT = nil end
    end
    if input.pressed("action") then self:bomb() end
    -- the gun
    p.fireT = p.fireT - dt
    if (input.down("fire") or self.def.autofire) and p.fireT <= 0 then
        p.fireT = 0.11
        local pw = p.power
        local function shot(oy, a, green)
            table.insert(self.shots, { x = p.x + 30, y = p.y + oy, vx = math.cos(a) * 900, vy = math.sin(a) * 900,
                green = green, rot = a })
        end
        if pw == 1 then shot(0, 0)
        else shot(-7, 0); shot(7, 0) end
        if pw >= 3 then
            local spread = focus and 0.06 or 0.22
            shot(-10, -spread, true); shot(10, spread, true)
        end
        if pw >= 4 then
            local spread = focus and 0.12 or 0.45
            shot(-12, -spread, true); shot(12, spread, true)
        end
        audio.play("laser")
    end
    for i = #self.shots, 1, -1 do
        local s = self.shots[i]
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
        local hit = false
        for _, e in ipairs(self.enemies) do
            if not e.dead and (s.x - e.x) ^ 2 + (s.y - e.y) ^ 2 < (e.r + 6) ^ 2 then
                self:hurtEnemy(e, 1)
                hit = true
                self.fx:burst(s.x, s.y, { color = { 0.6, 0.9, 1 }, count = 3, speed = 90, life = 0.2, size = 2 })
                break
            end
        end
        if hit or s.x > W + 40 or s.y < -40 or s.y > H + 40 then table.remove(self.shots, i) end
    end
    -- enemies
    for i = #self.enemies, 1, -1 do
        local e = self.enemies[i]
        if not e.dead then self:think(e, dt) end
        if not e.dead and p.inv <= 0 and (e.x - p.x) ^ 2 + (e.y - p.y) ^ 2 < (e.r * 0.7 + p.r) ^ 2 then
            self:hurtPlayer()
            if e.kind ~= "boss" then self:hurtEnemy(e, 99) end
        end
        if e.dead or e.x < -120 or e.y < -120 or e.y > H + 120 or (e.x > W + 400 and e.move ~= "boss") then
            if e.dead and e.kind == "boss" then
                -- stays until the explosions are over
            else
                table.remove(self.enemies, i)
            end
        end
    end
    -- enemy bullets, grazes
    local grazeR = 24
    for i = #self.bullets, 1, -1 do
        local b = self.bullets[i]
        b.t = b.t + dt
        b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
        local d2 = (b.x - p.x) ^ 2 + (b.y - p.y) ^ 2
        local gone = b.x < -30 or b.x > W + 30 or b.y < -30 or b.y > H + 30
        if d2 < (b.r + p.r) ^ 2 and p.inv <= 0 then
            self:hurtPlayer()
            gone = true
        elseif not b.grazed and d2 < (b.r + grazeR) ^ 2 and p.inv <= 0 then
            b.grazed = true
            self.grazes = self.grazes + 1
            self:addScore(20)
            self.fx:burst(p.x, p.y, { color = { 1, 1, 1 }, count = 2, speed = 120, life = 0.25, size = 2 })
            audio.play("blip", { volume = 0.2, pitch = 1.5 })
        end
        if gone then table.remove(self.bullets, i) end
    end
    -- medals and power-ups
    for i = #self.medals, 1, -1 do
        local m = self.medals[i]
        m.t = m.t + dt
        if m.t > 0.35 then
            local a = math.atan2(p.y - m.y, p.x - m.x)
            local sp = 300 + m.t * 600
            m.vx, m.vy = m.vx + (math.cos(a) * sp - m.vx) * math.min(1, dt * 8), m.vy + (math.sin(a) * sp - m.vy) * math.min(1, dt * 8)
        else
            m.vx, m.vy = m.vx * 0.92, m.vy * 0.92
        end
        m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
        if (m.x - p.x) ^ 2 + (m.y - p.y) ^ 2 < 24 ^ 2 then
            self:addScore(10 * math.max(1, self.chain))
            audio.play("coin", { volume = 0.15 })
            table.remove(self.medals, i)
        end
    end
    for i = #self.items, 1, -1 do
        local it = self.items[i]
        it.t = it.t + dt
        it.x = it.x - 60 * dt
        it.y = it.y + math.sin(it.t * 3) * 30 * dt
        if (it.x - p.x) ^ 2 + (it.y - p.y) ^ 2 < 34 ^ 2 then
            self:pick(it)
            table.remove(self.items, i)
        elseif it.x < -30 then
            table.remove(self.items, i)
        end
    end
    -- the chain of kills breaks when you wait too long
    if self.chainT > 0 then
        self.chainT = self.chainT - dt
        if self.chainT <= 0 then self.chain = 0 end
    end
    -- without a boss: the waves are over and the screen is clear
    if not self.boss and not self.waves[self.waveI] and #self.enemies == 0 and self.clock > 3 then
        self:win()
    end
end

function Shmup:pick(it)
    local p = self.player
    local d = DROPS[it.kind]
    if it.kind == "power" then
        if p.power < 4 then p.power = p.power + 1 else self:addScore(1000) end
        audio.play("powerup")
    elseif it.kind == "shield" then
        p.shield = true
        audio.play("shield_up")
    elseif it.kind == "bomb" then
        self.bombs = math.min(5, self.bombs + 1)
        audio.play("bonus")
    elseif it.kind == "life" then
        self.lives = math.min(self.maxLives, self.lives + 1)
        audio.play("bonus")
    end
    self:popup(p.x, p.y - 30, d.text, { 0.6, 1, 0.6 })
end

function Shmup:idle(dt)
    for _, e in ipairs(self.enemies) do e.flash = math.max(0, e.flash - dt * 6) end
end

-- drawing ---------------------------------------------------------------------------------------

local function drawCentered(img, x, y, rot, s, alpha)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, x, y, rot or 0, s, s, img:getWidth() / 2, img:getHeight() / 2)
end

function Shmup:drawGame()
    local lg = love.graphics
    local W, H = screen.width, screen.height
    -- space: a scrolling tile and three layers of stars
    lg.setColor(1, 1, 1, 1)
    local ox = (self.scroll * 30) % 256
    lg.draw(self.img.bg_purple, self.bgQuad, -ox, 0)
    for _, s in ipairs(self.stars) do
        local x = (s.x - self.scroll * 40 * s.z) % W
        local a = 0.25 + s.z * 0.2
        if s.z == 3 then
            drawCentered(self.img.star3, x, s.y, 0, 0.35, 0.8)
        else
            lg.setColor(1, 1, 1, a)
            lg.rectangle("fill", x, s.y, s.z, s.z)
        end
    end
    -- items and medals
    for _, it in ipairs(self.items) do
        local img = self.img[DROPS[it.kind].image]
        drawCentered(img, it.x, it.y, math.sin(it.t * 4) * 0.2, 0.9 + math.sin(it.t * 8) * 0.08)
    end
    for _, m in ipairs(self.medals) do
        drawCentered(self.img.star1, m.x, m.y, m.t * 6, 0.45)
    end
    -- enemies
    for _, e in ipairs(self.enemies) do
        if not (e.dead and e.kind ~= "boss") and not e.hidden then
            local img = self.img[e.k.image]
            local rot = e.k.rock and e.rot or (e.kind == "boss" and e.rot or (e.rot ~= 0 and e.rot - PI2 or PI2))
            if e.move == "dive" and e.vx then rot = math.atan2(e.vy, e.vx) - PI2 end
            local s = e.k.scale
            drawCentered(img, e.x, e.y, rot, s)
            if e.flash > 0 then
                lg.setBlendMode("add")
                drawCentered(img, e.x, e.y, rot, s, e.flash * 0.8)
                lg.setBlendMode("alpha")
            end
        end
    end
    -- shots
    for _, s in ipairs(self.shots) do
        drawCentered(s.green and self.img.laserGreen11 or self.img.laserBlue01, s.x, s.y, s.rot + PI2, 0.7)
    end
    -- the ship: blinking while invulnerable, the engine flame flickers
    local p = self.player
    if self.phase ~= "over" or self.won then
        local blink = p.inv > 0 and math.floor(self.time * 16) % 2 == 0
        if not blink then
            local flame = math.floor(self.time * 20) % 2 == 0 and self.img.fire08 or self.img.fire09
            drawCentered(flame, p.x - 30, p.y, PI2, 0.9 + math.sin(self.time * 30) * 0.1)
            drawCentered(self.img.playerShip1_blue, p.x, p.y, PI2 + p.tilt, 0.5)
        end
        if p.shield then
            drawCentered(self.img.shield1, p.x + 4, p.y, PI2, 0.5, 0.55 + 0.2 * math.sin(self.time * 6))
        end
        if p.focus then
            lg.setColor(1, 1, 1, 0.9)
            lg.circle("fill", p.x, p.y, p.r + 1)
            lg.setColor(1, 0.3, 0.3, 1)
            lg.circle("line", p.x, p.y, p.r + 2)
        end
    end
    -- enemy bullets on top of everything
    for _, b in ipairs(self.bullets) do
        drawCentered(self.img.laserRed08, b.x, b.y, b.t * 5, b.r / 16)
        lg.setColor(1, 0.9, 0.9, 1)
        lg.circle("fill", b.x, b.y, b.r * 0.45)
    end
    lg.setColor(1, 1, 1, 1)
    -- the boss bar
    local boss = self.boss
    if boss and not boss.dead then
        ui.bar(W / 2 - 200, 34, 400, 8, boss.hp, boss.maxHp, "red")
    end
    -- bombs and power
    for i = 1, self.bombs do
        drawCentered(self.img.powerupRed_star, 18 + i * 26, H - 22, 0, 0.6)
    end
    ui.print("Пушка " .. string.rep("■", p.power) .. string.rep("□", 4 - p.power), W - 20, H - 32,
        { font = "small", align = "right", color = "blue" })
    if self.bombT then
        local k = self.bombT / 0.8
        lg.setColor(1, 0.9, 0.6, 0.6 * k)
        lg.setLineWidth(18 * k + 2)
        lg.circle("line", p.x, p.y, (1 - k) * 900)
        lg.setLineWidth(1)
        lg.setColor(1, 1, 1, 1)
    end
end

return Shmup
