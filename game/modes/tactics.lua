-- Tactics battle like in Heroes of Might and Magic 3: two armies of stacks on a hex field.
-- A stack is N creatures of one kind (game/data/units.lua). Stacks move in the order of their
-- speed; a stack that is hit strikes back once a round; shooters shoot across the field, but
-- with an enemy next to them they fight hand to hand at half strength. Гриша also has a spell book.
-- Field: "Hexset v.01.1" by Miguel Bartelsman (mbartelsm, CC0); creatures: GrafxKid "Various Creatures" (CC0);
-- Гриша and Кашка are the same sprites as in the rest of the game.
--
--   local r = s:tactics({ enemies = { { "slimes", 12 }, { "crabs", 4 } } })   -- r.win, r.losses, r.army
--   game.stage "bridge_fight" { kind = "tactics", terrain = "meadow", obstacles = 6,
--       army = { { "grisha", 1 }, { "kashka", 1 }, { "beetles", 6 } }, enemies = { { "radishes", 30 }, { "owls", 5 } } }
--
--   army       your stacks { { unit, count }, ... }; default: Гриша, the pets of the party and a few troops
--   enemies    the enemy stacks (default: chosen by the level)
--   terrain    grass, meadow, forest, snow, desert, swamp, stone
--   obstacles  how many rocks and mountains (default 5) or a list of { col, row, "hill"/"mont"/"water" }
--              (0-based, the field is 12 x 8)
--   mana       Гриша's magic points (default 12), power = strength of the spells (default 2);
--              spells = false: no spell book
-- Result: r.win, r.score, r.rounds, r.losses = { beetles = 3 }, r.kills, r.army = survivors { { unit, count } }
-- Keys: arrows / mouse choose a hex, [Enter] / click move or attack, [Tab] another side to attack
-- from, [Q] wait (move at the end of the round), [E] defend, [C] spell book. Pause menu: auto battle.

local engine = require("engine")
local anim = require("engine.anim")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local Arcade = require("game.modes.arcade")

local function G()
    return require("game")
end

local Tactics = class(Arcade)
Tactics.keymap = "tactics"
Tactics.info = {
    title = "Тактика",
    rules = "Отряды ходят по очереди: кто быстрее, тот раньше. Ударь врага — он ответит один раз за раунд. "
        .. "Стрелки бьют издалека, но вплотную к врагу — вполсилы. Разбей все отряды противника.",
    keys = { { "confirm", "ход" }, { "wait", "ждать" }, { "defend", "защита" }, { "spell", "магия" } },
    background = "hills",
    dim = 0.2,
    music = "arcade",
    lives = false,
    keysHint = false,
}
Tactics.defaultLives = 0

local HEX = "assets/sprites/hex/"
local COLS, ROWS = 12, 8
local SX, SY, HALF = 64, 42, 32       -- step between hexes, the shift of odd rows
local X0, Y0 = 80, 36                 -- the top left tile
local TS = 2                          -- tiles are 32 x 48 pixel art, drawn twice as big
local CX, CY = 32, 40                 -- the center of the top face inside a (scaled) tile
local POLY = { 0, -29, 32, -13, 32, 13, 0, 29, -32, 13, -32, -13 }
local FAR = 6                         -- shots further than this: half damage
local LUCK = 0.1                      -- chance of a lucky (double) blow

-- ground = the name of the Hexset tiles: <ground>_flat_01..03, _hill_, _mont_
local TERRAINS = {
    grass = { ground = "temperate", background = "hills", water = true },
    meadow = { ground = "warm", background = "mountains", water = true },
    forest = { ground = "boreal", background = "forest", water = true },
    snow = { ground = "snow", background = "snowy" },
    desert = { ground = "desert", background = "cliffs" },
    swamp = { ground = "swamp", background = "forest", water = true },
    stone = { ground = "stone1", background = "mountains" },
}

local function tileName(ground, kind)
    return HEX .. ground .. "_" .. kind .. "_0" .. love.math.random(1, 3) .. ".png"
end

local SPELLS = {
    { id = "lightning", name = "Молния", cost = 5, target = "enemy", text = "бьёт один отряд врага" },
    { id = "fireball", name = "Огненный шар", cost = 8, target = "area", text = "клетка и все соседние" },
    { id = "cure", name = "Лечение", cost = 4, target = "ally", text = "лечит и поднимает павших" },
    { id = "haste", name = "Ускорение", cost = 3, target = "ally", text = "+3 к скорости на 3 раунда" },
}

-- the enemies by level when the stage does not list them
local ENEMIES = {
    { { "radishes", 14 }, { "slimes", 6 } },
    { { "radishes", 18 }, { "slimes", 9 }, { "owls", 4 } },
    { { "slimes", 12 }, { "crabs", 5 }, { "stoners", 6 }, { "radishes", 20 } },
    { { "beetles", 8 }, { "crabs", 7 }, { "owls", 7 }, { "frogs", 8 } },
    { { "beetles", 12 }, { "ghosts", 12 }, { "stoners", 10 }, { "frogs", 10 }, { "crabs", 9 } },
}
local ARMY = { { "grisha", 1 }, { "stoners", 6 }, { "beetles", 5 } }

local ABILITIES = {
    { "flying", "летает" }, { "noRetaliation", "без ответа" }, { "hitAndRun", "бьёт и отскакивает" },
    { "breath", "задевает второго" }, { "sticky", "липкие: замедляют" }, { "hero", "герой" },
}

-- hex math (odd rows are shifted right) ---------------------------------------------------

local NB = {
    [0] = { { 1, 0 }, { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } },
    [1] = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 1 } },
}

local function inside(c, r)
    return c >= 0 and r >= 0 and c < COLS and r < ROWS
end

local function key(c, r)
    return r * COLS + c
end

local function neighbor(c, r, dir)
    local d = NB[r % 2][dir]
    return c + d[1], r + d[2]
end

local function center(c, r)
    return X0 + c * SX + (r % 2 == 1 and HALF or 0) + CX, Y0 + r * SY + CY
end

local function cube(c, r)
    local x = c - (r - r % 2) / 2
    return x, r, -x - r
end

local function dist(c1, r1, c2, r2)
    local x1, z1, y1 = cube(c1, r1)
    local x2, z2, y2 = cube(c2, r2)
    return math.max(math.abs(x1 - x2), math.abs(y1 - y2), math.abs(z1 - z2))
end

local function dirTo(c1, r1, c2, r2)
    for d = 1, 6 do
        local nc, nr = neighbor(c1, r1, d)
        if nc == c2 and nr == r2 then return d end
    end
end

local function totalHp(st)
    return (st.count - 1) * st.unit.hp + st.hp
end

local function pick(list)
    return list[love.math.random(#list)]
end

-- coroutine helpers: the actions are written as plain sequences of steps
local function pause(t)
    while t > 0 do
        t = t - coroutine.yield()
    end
end

local function tween(t, fn)
    local e = 0
    while e < t do
        e = math.min(t, e + coroutine.yield())
        fn(e / t)
    end
end

local boltRandom = love.math.newRandomGenerator()

local function smooth(k)
    return k * k * (3 - 2 * k)
end

-- setup ----------------------------------------------------------------------------------

function Tactics:init(def)
    self.terrain = TERRAINS[def.terrain or "grass"] or TERRAINS.grass
    if def.background == nil then
        def.background = self.terrain.background
    end
    Arcade.init(self, def)
end

function Tactics:setup()
    local def = self.def
    self.round = 1
    self.mana = def.mana or 12
    self.maxMana = self.mana
    self.power = def.power or 2
    self.spells = def.spells ~= false
    self.stacks = {}
    self.cur = { c = 2, r = 3 }
    self.log = {}
    self.projectiles = {}
    self.bolts = {}
    self.mode = "wait"
    self.kills, self.losses = {}, {}
    self:buildField()
    self:deploy(def.army or self:defaultArmy(), "player")
    self:deploy(def.enemies or ENEMIES[math.max(1, math.min(5, self.level))], "enemy")
end

function Tactics:defaultArmy()
    local army = {}
    for _, a in ipairs(ARMY) do table.insert(army, a) end
    local state = G().state
    local pets, units = G().pets or {}, G().units
    for _, name in ipairs(state and state.party or {}) do
        local p = pets[type(name) == "table" and name.name or name]
        local u = p and p.unit and units[p.unit]
        if u then
            table.insert(army, 2, { p.unit, u.single and 1 or 6 })
        end
    end
    return army
end

function Tactics:buildField()
    local def, t = self.def, self.terrain
    for _ = 1, 40 do
        self.cells = {}
        for r = 0, ROWS - 1 do
            for c = 0, COLS - 1 do
                self.cells[key(c, r)] = { c = c, r = r, tile = tileName(t.ground, "flat") }
            end
        end
        if type(def.obstacles) == "table" then
            for _, o in ipairs(def.obstacles) do
                self:addObstacle(o[1], o[2], o[3])
            end
            break
        end
        local n = def.obstacles or 5
        local placed = 0
        if t.water and love.math.random() < 0.5 then
            -- a small lake in the middle
            local c, r = love.math.random(3, COLS - 4), love.math.random(1, ROWS - 2)
            self:addObstacle(c, r, "water")
            for _ = 1, love.math.random(1, 2) do
                local nc, nr = neighbor(c, r, love.math.random(6))
                if nc >= 2 and nc <= COLS - 3 and inside(nc, nr) then self:addObstacle(nc, nr, "water") end
            end
            placed = 1
        end
        local tries = 0
        while placed < n and tries < 200 do
            tries = tries + 1
            local c, r = love.math.random(2, COLS - 3), love.math.random(0, ROWS - 1)
            local cell = self.cells[key(c, r)]
            if not cell.obstacle then
                self:addObstacle(c, r, love.math.random() < 0.6 and "hill" or "mont")
                placed = placed + 1
            end
        end
        if self:connected() then break end
    end
end

function Tactics:addObstacle(c, r, kind)
    if not inside(c, r) then return end
    local cell = self.cells[key(c, r)]
    kind = kind or "hill"
    if kind == "water" then
        cell.tile = tileName("wdeep", "flat")
    else
        cell.tile = tileName(self.terrain.ground, kind == "mont" and "mont" or "hill")
    end
    cell.obstacle = { kind = kind }
end

-- can one walk from the left edge to the right one?
function Tactics:connected()
    local seen, queue = {}, {}
    for r = 0, ROWS - 1 do
        local k = key(0, r)
        if not self.cells[k].obstacle then
            seen[k] = true
            table.insert(queue, { 0, r })
        end
    end
    local i = 1
    while queue[i] do
        local c, r = queue[i][1], queue[i][2]
        i = i + 1
        if c == COLS - 1 then return true end
        for d = 1, 6 do
            local nc, nr = neighbor(c, r, d)
            local k = key(nc, nr)
            if inside(nc, nr) and not seen[k] and not self.cells[k].obstacle then
                seen[k] = true
                table.insert(queue, { nc, nr })
            end
        end
    end
    return false
end

function Tactics:deploy(list, side)
    local n = math.min(#list, ROWS)
    local units = G().units
    for i = 1, n do
        local entry = list[i]
        local name, count = entry[1] or entry.unit, entry[2] or entry.count or 1
        local u = units[name]
        if u then
            local r = math.floor((i - 0.5) * ROWS / n)
            local c = side == "player" and 0 or COLS - 1
            local cell = self.cells[key(c, r)]
            if cell.obstacle then
                cell.obstacle = nil
                cell.tile = tileName(self.terrain.ground, "flat")
            end
            local st = self:newStack(name, u, count, side, c, r)
            table.insert(self.stacks, st)
        end
    end
end

function Tactics:newStack(name, u, count, side, c, r)
    local sdef = G().sprites[u.sprite] or G().sprites.slime
    local x, y = center(c, r)
    local st = {
        id = #self.stacks + 1, name = name, unit = u, side = side, count = count, maxCount = count, hp = u.hp,
        c = c, r = r, x = x, y = y, shots = u.shots or 0, retal = u.retaliations or 1,
        facing = side == "player" and 1 or -1, sprite = anim.new(sdef), sdef = sdef,
        scale = u.scale or sdef.scale or 1, alpha = 1, hitT = 0, lift = 0, bob = love.math.random() * 6,
    }
    self:pose(st, "idle")
    return st
end

-- stacks ---------------------------------------------------------------------------------

function Tactics:pose(st, name, restart)
    local spr = st.sprite
    local dir = st.facing > 0 and "right" or "left"
    if name == "attack" and not spr:has("attack") and not spr:has("attack", dir) then
        name = (spr:has("hit", dir) or spr:has("hit")) and "hit" or (spr:has("punch") and "punch" or "walk")
    end
    if spr:has(name, dir) then
        spr:play(name, dir, restart)
        st.flip = false
    elseif spr:has(name) then
        spr:play(name, nil, restart)
        st.flip = (st.facing < 0) ~= (st.sdef.facesLeft == true)
    elseif name ~= "idle" and name ~= "walk" then
        self:pose(st, name == "attack" and "walk" or "idle", restart)
    end
end

function Tactics:stackAt(c, r)
    for _, st in ipairs(self.stacks) do
        if not st.dead and st.c == c and st.r == r then return st end
    end
end

function Tactics:free(c, r, except)
    if not inside(c, r) or self.cells[key(c, r)].obstacle then return false end
    local st = self:stackAt(c, r)
    return st == nil or st == except
end

function Tactics:alive(side)
    local list = {}
    for _, st in ipairs(self.stacks) do
        if not st.dead and (side == nil or st.side == side) then table.insert(list, st) end
    end
    return list
end

function Tactics:speedOf(st)
    local s = st.unit.speed
    if st.hasteUntil and st.hasteUntil >= self.round then s = s + 3 end
    if st.slowUntil and st.slowUntil >= self.round then s = math.max(1, s - 2) end
    return s
end

function Tactics:defenseOf(st)
    local d = st.unit.defense
    if st.defending then d = d + math.max(2, math.ceil(d * 0.3)) end
    return d
end

-- damage multiplier of attack against defense (HoMM3)
function Tactics:factor(a, t, half)
    local A, D = a.unit.attack, self:defenseOf(t)
    local k = A >= D and math.min(4, 1 + 0.05 * (A - D)) or math.max(0.3, 1 - 0.025 * (D - A))
    return half and k * 0.5 or k
end

function Tactics:damageRange(a, t, half)
    local k = self:factor(a, t, half)
    local d = a.unit.damage
    return math.max(1, math.floor(d[1] * a.count * k)), math.max(1, math.floor(d[2] * a.count * k))
end

function Tactics:rollDamage(a, t, half)
    local d = a.unit.damage
    local rolls, sum = math.min(a.count, 10), 0
    for _ = 1, rolls do
        sum = sum + love.math.random(d[1], d[2])
    end
    return math.max(1, math.floor(sum * a.count / rolls * self:factor(a, t, half) + 0.5))
end

local function killsFor(st, dmg)
    local left = totalHp(st) - dmg
    if left <= 0 then return st.count end
    return st.count - math.ceil(left / st.unit.hp)
end

-- an enemy next to the stack?
function Tactics:blocked(st)
    for d = 1, 6 do
        local o = self:stackAt(neighbor(st.c, st.r, d))
        if o and o.side ~= st.side then return true end
    end
    return false
end

function Tactics:canShoot(st)
    return st.shots > 0 and not self:blocked(st)
end

-- where the stack can go this turn: key -> { c, r, d, prev }
function Tactics:reach(st)
    local speed = self:speedOf(st)
    local res = { [key(st.c, st.r)] = { c = st.c, r = st.r, d = 0 } }
    if st.unit.flying then
        for _, cell in pairs(self.cells) do
            local d = dist(st.c, st.r, cell.c, cell.r)
            if d > 0 and d <= speed and self:free(cell.c, cell.r) then
                res[key(cell.c, cell.r)] = { c = cell.c, r = cell.r, d = d }
            end
        end
        return res
    end
    local queue, i = { res[key(st.c, st.r)] }, 1
    while queue[i] do
        local n = queue[i]
        i = i + 1
        if n.d < speed then
            for d = 1, 6 do
                local nc, nr = neighbor(n.c, n.r, d)
                local k = key(nc, nr)
                if not res[k] and self:free(nc, nr) then
                    res[k] = { c = nc, r = nr, d = n.d + 1, prev = n }
                    table.insert(queue, res[k])
                end
            end
        end
    end
    return res
end

local function pathOf(node)
    local path = {}
    while node do
        table.insert(path, 1, node)
        node = node.prev
    end
    return path
end

-- turn order -----------------------------------------------------------------------------

function Tactics:sorted(list, reverse)
    table.sort(list, function(a, b)
        local sa, sb = self:speedOf(a), self:speedOf(b)
        if sa ~= sb then
            if reverse then return sa < sb end
            return sa > sb
        end
        if a.side ~= b.side then return a.side == "player" end
        return a.id < b.id
    end)
    return list
end

-- who moves next in this round: first the ones that did not move, then the ones that waited
-- (the slowest of them first, like in HoMM3)
function Tactics:upcoming()
    local now, waiting = {}, {}
    for _, st in ipairs(self.stacks) do
        if not st.dead and not st.acted and st ~= self.active then
            table.insert(st.waited and waiting or now, st)
        end
    end
    self:sorted(now)
    self:sorted(waiting, true)
    for _, st in ipairs(waiting) do table.insert(now, st) end
    return now
end

function Tactics:newRound()
    self.round = self.round + 1
    for _, st in ipairs(self.stacks) do
        st.acted, st.waited = false, false
        st.retal = st.unit.retaliations or 1
    end
    self.castRound = nil
    self:banner("Раунд " .. self.round, "gold", 0.9)
end

function Tactics:nextTurn()
    if self:checkEnd() then return end
    local list = self:upcoming()
    if #list == 0 then
        self:newRound()
        list = self:upcoming()
    end
    local st = list[1]
    if not st then return end
    self.active = st
    st.defending = false
    self.reachable = self:reach(st)
    if st.side == "player" and not self.auto then
        self.mode = "input"
        self.cur.c, self.cur.r = st.c, st.r
        self.attackPick = nil
    else
        self.mode = "ai"
        self.aiDelay = st.side == "player" and 0.25 or 0.45
    end
end

function Tactics:checkEnd()
    if self.phase ~= "play" then return true end
    local mine, theirs = #self:alive("player"), #self:alive("enemy")
    if theirs == 0 or mine == 0 then
        self.mode = "end"
        self.active = nil
        local win = theirs == 0
        if win then
            self:addScore(100 + 50 * self.level)
        end
        self.extraResult = { rounds = self.round, losses = self.losses, kills = self.kills, army = self:survivors() }
        self.timer:after(0.8, function() self:gameOver(win) end)
        return true
    end
    return false
end

function Tactics:survivors()
    local list = {}
    for _, st in ipairs(self.stacks) do
        if st.side == "player" and not st.dead then table.insert(list, { st.name, st.count }) end
    end
    return list
end

function Tactics:say(text, color)
    table.insert(self.log, 1, { text = text, color = color or "light", t = 0 })
    while #self.log > 3 do table.remove(self.log) end
end

-- actions (run as coroutines) ------------------------------------------------------------

function Tactics:perform(fn)
    self.mode = "busy"
    self.task = coroutine.create(fn)
end

function Tactics:walk(st, path)
    if #path < 2 then return end
    local last = path[#path]
    if st.unit.flying then
        local x0, y0 = st.x, st.y
        local x1, y1 = center(last.c, last.r)
        st.facing = x1 >= x0 and 1 or -1
        self:pose(st, "walk")
        audio.play("dash")
        local d = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        tween(math.max(0.25, d / 420), function(k)
            local e = smooth(k)
            st.x, st.y = x0 + (x1 - x0) * e, y0 + (y1 - y0) * e
            st.lift = math.sin(k * math.pi) * math.min(60, d * 0.25)
        end)
        st.lift = 0
    else
        self:pose(st, "walk")
        for i = 2, #path do
            local x0, y0 = center(path[i - 1].c, path[i - 1].r)
            local x1, y1 = center(path[i].c, path[i].r)
            if x1 ~= x0 then st.facing = x1 > x0 and 1 or -1 end
            self:pose(st, "walk")
            audio.play("ui_move")
            tween(0.13, function(k)
                st.x, st.y = x0 + (x1 - x0) * k, y0 + (y1 - y0) * k
                st.lift = math.sin(k * math.pi) * 4
            end)
        end
        st.lift = 0
    end
    st.c, st.r = last.c, last.r
    st.x, st.y = center(st.c, st.r)
    self:pose(st, "idle")
end

function Tactics:face(st, other)
    if other.x ~= st.x then
        st.facing = other.x > st.x and 1 or -1
    end
end

-- one blow: a lunge, the damage, numbers and maybe a death
function Tactics:strike(a, t, opts)
    opts = opts or {}
    self:face(a, t)
    self:face(t, a)
    self:pose(t, "idle")
    if not opts.ranged then
        self:pose(a, "attack", true)
        audio.play("swing")
        local dx, dy = (t.x - a.x) * 0.3, (t.y - a.y) * 0.3
        local bx, by = a.x, a.y
        tween(0.12, function(k)
            a.x, a.y = bx + dx * k, by + dy * k
        end)
        self:hitStack(a, t, opts)
        tween(0.14, function(k)
            a.x, a.y = bx + dx * (1 - k), by + dy * (1 - k)
        end)
        a.x, a.y = center(a.c, a.r)
        self:pose(a, "idle")
    else
        self:hitStack(a, t, opts)
    end
    pause(0.18)
end

function Tactics:hitStack(a, t, opts)
    local dmg = self:rollDamage(a, t, opts.half)
    local lucky = love.math.random() < LUCK
    if lucky then
        dmg = dmg * 2
        self:popup(t.x, t.y - 74, "Удача!", { 0.5, 1, 0.5 })
    end
    local kills = self:damage(t, dmg, a)
    local who = a.unit.name .. (opts.retaliation and (a.unit.single and " отвечает" or " отвечают") or "")
    self:say(who .. ": " .. dmg .. " урона" .. (kills > 0 and (", убито " .. kills) or ""),
        a.side == "player" and "green" or "red")
    if a.unit.sticky and not t.dead then
        t.slowUntil = self.round + 1
        self:popup(t.x + 18, t.y - 50, "медленнее", { 0.6, 0.9, 0.5 })
    end
    if a.unit.breath and not opts.ranged then
        local d = dirTo(a.c, a.r, t.c, t.r)
        if d then
            local b = self:stackAt(neighbor(t.c, t.r, d))
            if b then
                local dmg2 = self:rollDamage(a, b)
                self:damage(b, dmg2, a)
            end
        end
    end
end

-- takes the hp away; returns how many creatures died
function Tactics:damage(t, dmg, by)
    local before = t.count
    local left = totalHp(t) - dmg
    if left <= 0 then
        t.count, t.hp = 0, 0
    else
        t.count = math.ceil(left / t.unit.hp)
        t.hp = left - (t.count - 1) * t.unit.hp
    end
    local kills = before - t.count
    t.hitT = 0.3
    self:pose(t, "hurt", true)
    audio.play(kills > 0 and "hit" or "punch")
    self:popup(t.x, t.y - 46, "-" .. dmg, { 1, 0.55, 0.4 })
    if kills > 0 then
        self:popup(t.x + 22, t.y - 26, "†" .. kills, { 1, 1, 1 })
    end
    self.fx:play("slash", t.x, t.y - 24, { scale = 0.6 })
    self:shake(math.min(8, 2 + kills), 0.18)
    local book = t.side == "enemy" and self.kills or self.losses
    book[t.name] = (book[t.name] or 0) + kills
    if t.side == "enemy" then
        self:addScore(kills * (t.unit.value or t.unit.hp))
    end
    if t.count <= 0 then
        self:killStack(t)
    end
    return kills
end

function Tactics:killStack(t)
    t.dead = true
    t.deadT = 0
    self:pose(t, "hurt")
    self.fx:play("puff", t.x, t.y - 12, { scale = 2 })
    audio.play(t.unit.hero and "death" or "pop")
    self:say(t.unit.name .. (t.unit.single and " выбывает из боя!" or " — отряд разбит!"), t.side == "player" and "red" or "gold")
end

function Tactics:meleeAttack(a, t, from)
    local start = { c = a.c, r = a.r }
    if from and (from.c ~= a.c or from.r ~= a.r) then
        self:walk(a, from.path or { { c = a.c, r = a.r }, from })
    end
    local half = a.unit.shots ~= nil
    self:strike(a, t, { half = half })
    if not t.dead and not a.dead and t.retal > 0 and not a.unit.noRetaliation then
        t.retal = t.retal - 1
        self:strike(t, a, { retaliation = true, half = t.unit.shots ~= nil })
    end
    if a.unit.strikes == 2 and not a.dead and not t.dead then
        self:strike(a, t, { half = half })
    end
    if a.unit.hitAndRun and not a.dead and (start.c ~= a.c or start.r ~= a.r) and self:free(start.c, start.r) then
        self:walk(a, { { c = a.c, r = a.r }, { c = start.c, r = start.r } })
    end
end

function Tactics:shoot(a, t)
    a.shots = a.shots - 1
    self:face(a, t)
    self:pose(a, "attack", true)
    audio.play("throw")
    local p = { x0 = a.x + a.facing * 14, y0 = a.y - 30, x1 = t.x, y1 = t.y - 24, t = 0,
        kind = a.unit.missile or "stone" }
    local d = math.sqrt((p.x1 - p.x0) ^ 2 + (p.y1 - p.y0) ^ 2)
    p.dur = math.max(0.25, d / 650)
    table.insert(self.projectiles, p)
    pause(p.dur)
    self:pose(a, "idle")
    local far = dist(a.c, a.r, t.c, t.r) > FAR
    self:strike(a, t, { ranged = true, half = far })
end

function Tactics:castSpell(spell, c, r)
    self.mana = self.mana - spell.cost
    self.castRound = self.round
    local x, y = center(c, r)
    local t = self:stackAt(c, r)
    self:say("Гриша: " .. spell.name, "blue")
    audio.play("zap")
    if spell.id == "lightning" and t then
        table.insert(self.bolts, { x = t.x, y = t.y - 20, t = 0 })
        self:flash({ 0.8, 0.9, 1 }, 0.25)
        pause(0.15)
        self:damage(t, 10 + 10 * self.power, nil)
    elseif spell.id == "fireball" then
        self.fx:play("boom", x, y - 16, { scale = 2.2 })
        audio.play("boom_big")
        self:shake(9, 0.35)
        pause(0.2)
        local targets = { self:stackAt(c, r) }
        for d = 1, 6 do
            table.insert(targets, self:stackAt(neighbor(c, r, d)))
        end
        for _, st in pairs(targets) do
            if st and not st.dead then self:damage(st, 5 + 6 * self.power, nil) end
        end
    elseif spell.id == "cure" and t then
        local heal = 15 + 10 * self.power
        local maxHp = t.maxCount * t.unit.hp
        local now = math.min(maxHp, totalHp(t) + heal)
        local before = t.count
        t.count = math.ceil(now / t.unit.hp)
        t.hp = now - (t.count - 1) * t.unit.hp
        self:burst(t.x, t.y - 20, { 0.5, 1, 0.5 }, 18, 90)
        self.fx:play("magic", t.x, t.y - 26, { scale = 0.8 })
        self:popup(t.x, t.y - 50, "+" .. heal, { 0.5, 1, 0.5 })
        if t.count > before then
            self:popup(t.x + 20, t.y - 28, "+" .. (t.count - before), { 1, 1, 1 })
            self.losses[t.name] = math.max(0, (self.losses[t.name] or 0) - (t.count - before))
        end
        audio.play("powerup")
    elseif spell.id == "haste" and t then
        t.hasteUntil = self.round + 2
        self.fx:play("cast", t.x, t.y - 26, { scale = 0.7 })
        self:popup(t.x, t.y - 50, "скорость +3", { 0.6, 0.85, 1 })
        audio.play("powerup")
    end
    pause(0.4)
end

-- the player's choice under the cursor ----------------------------------------------------

-- what happens when the active stack is told to go to the hex (c, r)
function Tactics:actionAt(c, r)
    local st = self.active
    if not st or not inside(c, r) then return nil end
    local t = self:stackAt(c, r)
    if t == st then return { kind = "self" } end
    if t and t.side ~= st.side then
        if self:canShoot(st) then
            return { kind = "shoot", target = t, far = dist(st.c, st.r, c, r) > FAR }
        end
        local options = {}
        for d = 1, 6 do
            local nc, nr = neighbor(c, r, d)
            local n = inside(nc, nr) and self.reachable[key(nc, nr)]
            if n then
                table.insert(options, { c = nc, r = nr, d = n.d, node = n, dir = d })
            end
        end
        if #options == 0 then return { kind = "far", target = t } end
        table.sort(options, function(a, b) return a.d < b.d or (a.d == b.d and a.dir < b.dir) end)
        local choice = options[1]
        if self.usingMouse then
            -- the side of the enemy hex under the mouse pointer
            local best
            for _, o in ipairs(options) do
                local ox, oy = center(o.c, o.r)
                local dd = (ox - input.mouse.x) ^ 2 + (oy - input.mouse.y) ^ 2
                if not best or dd < best then best, choice = dd, o end
            end
        elseif self.attackPick then
            choice = options[(self.attackPick - 1) % #options + 1]
        end
        return { kind = "attack", target = t, from = choice, options = #options }
    end
    if t then return { kind = "ally", target = t } end
    local n = self.reachable[key(c, r)]
    if n then return { kind = "move", node = n } end
    return nil
end

function Tactics:doAction(a)
    local st = self.active
    if not a or a.kind == "far" or a.kind == "ally" or a.kind == "self" then
        audio.play("ui_error")
        return
    end
    audio.play("ui_select")
    if a.kind == "move" then
        self:perform(function() self:walk(st, pathOf(a.node)) end)
    elseif a.kind == "shoot" then
        self:perform(function() self:shoot(st, a.target) end)
    elseif a.kind == "attack" then
        local from = { c = a.from.c, r = a.from.r, path = st.unit.flying and nil or pathOf(a.from.node) }
        if st.unit.flying then from.path = { { c = st.c, r = st.r }, { c = from.c, r = from.r } } end
        self:perform(function() self:meleeAttack(st, a.target, from) end)
    end
end

function Tactics:moveCursor(dc, dr)
    local c, r = self.cur.c + dc, self.cur.r + dr
    if inside(c, r) then
        self.cur.c, self.cur.r = c, r
        self.usingMouse = false
        self.attackPick = nil
        audio.play("ui_move")
    end
end

function Tactics:hexAt(x, y)
    local best, bc, br
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            local cx, cy = center(c, r)
            local d = (cx - x) ^ 2 + (cy - y) ^ 2
            if not best or d < best then best, bc, br = d, c, r end
        end
    end
    if best and best < 36 * 36 then return bc, br end
end

function Tactics:canCast()
    if not self.spells or self.castRound == self.round then return false end
    for _, st in ipairs(self:alive("player")) do
        if st.unit.hero then return true end
    end
    return false
end

function Tactics:spellTargets(spell)
    local list = {}
    for _, st in ipairs(self:alive()) do
        if (spell.target == "enemy" and st.side == "enemy") or (spell.target == "ally" and st.side == "player") then
            list[key(st.c, st.r)] = true
        end
    end
    if spell.target == "area" then
        for _, cell in pairs(self.cells) do list[key(cell.c, cell.r)] = true end
    end
    return list
end

function Tactics:inputStep()
    local st = self.active
    local m = input.mouse
    if m.moved or m.pressed[1] then
        local c, r = self:hexAt(m.x, m.y)
        if c and self.mode ~= "book" then
            self.cur.c, self.cur.r = c, r
            self.usingMouse = true
        end
    end
    if self.mode == "book" then
        local n = #SPELLS
        if input.pressed("up", true) then self.bookIndex = (self.bookIndex - 2) % n + 1; audio.play("ui_move") end
        if input.pressed("down", true) then self.bookIndex = self.bookIndex % n + 1; audio.play("ui_move") end
        local clicked = false
        if m.pressed[1] and self.bookRows then
            for i, row in ipairs(self.bookRows) do
                if m.x >= row[1] and m.x <= row[1] + row[3] and m.y >= row[2] and m.y <= row[2] + row[4] then
                    self.bookIndex = i
                    clicked = true
                end
            end
        end
        if input.pressed("cancel") or input.pressed("spell") or m.pressed[2] then
            input.consume("cancel")
            self.mode = "input"
            audio.play("ui_back")
        elseif input.pressed("confirm") or clicked then
            local spell = SPELLS[self.bookIndex]
            if spell.cost > self.mana then
                audio.play("ui_error")
            else
                self.spell = spell
                self.mode = "target"
                audio.play("ui_select")
            end
        end
        return
    end
    local dc, dr = 0, 0
    if input.pressed("left", true) then dc = -1 elseif input.pressed("right", true) then dc = 1 end
    if input.pressed("up", true) then dr = -1 elseif input.pressed("down", true) then dr = 1 end
    if dc ~= 0 or dr ~= 0 then self:moveCursor(dc, dr) end
    if self.mode == "target" then
        if input.pressed("cancel") or m.pressed[2] then
            input.consume("cancel")
            self.mode = "book"
            audio.play("ui_back")
        elseif input.pressed("confirm") or m.pressed[1] then
            local targets = self:spellTargets(self.spell)
            if targets[key(self.cur.c, self.cur.r)] then
                local spell, c, r = self.spell, self.cur.c, self.cur.r
                self:perform(function()
                    self:castSpell(spell, c, r)
                    self.backToInput = true
                end)
            else
                audio.play("ui_error")
            end
        end
        return
    end
    if input.pressed("cycle") then
        self.attackPick = (self.attackPick or 1) + 1
        self.usingMouse = false
        audio.play("ui_move")
    end
    if input.pressed("wait") then
        if st.waited then
            audio.play("ui_error")
            self:say("Уже ждали в этом раунде")
        else
            st.waited = true
            self.justWaited = true
            audio.play("ui_select")
            self:say(st.unit.name .. (st.unit.single and " ждёт" or " ждут"))
            self:perform(function() pause(0.1) end)
        end
    elseif input.pressed("defend") then
        st.defending = true
        audio.play("shield_up")
        self.fx:play("shield", st.x, st.y - 26, { scale = 0.6 })
        self:say(st.unit.name .. (st.unit.single and " защищается" or " в защите"))
        self:perform(function()
            st.acted = true
            pause(0.35)
        end)
    elseif input.pressed("spell") then
        if self:canCast() then
            self.mode = "book"
            self.bookIndex = self.bookIndex or 1
            audio.play("ui_select")
        else
            audio.play("ui_error")
            self:say(self.spells and "Магия — раз в раунд, и нужен Гриша" or "Книги заклинаний нет")
        end
    elseif input.pressed("confirm") or m.pressed[1] then
        self:doAction(self:actionAt(self.cur.c, self.cur.r))
    end
end

-- AI ---------------------------------------------------------------------------------------

function Tactics:threat(st)
    local d = st.unit.damage
    return st.count * (d[1] + d[2]) / 2 * (1 + 0.05 * st.unit.attack)
end

function Tactics:attackValue(a, t, half, ranged)
    local lo, hi = self:damageRange(a, t, half)
    local hpT = totalHp(t)
    local dmg = math.min((lo + hi) / 2, hpT)
    local frac = dmg / hpT
    local v = self:threat(t) * frac * (frac >= 1 and 1.5 or 1)
    if t.shots > 0 then v = v * 1.3 end
    if not ranged and frac < 1 and t.retal > 0 and not a.unit.noRetaliation then
        local left = hpT - dmg
        local cnt = math.ceil(left / t.unit.hp)
        local d = t.unit.damage
        local back = cnt * (d[1] + d[2]) / 2 * self:factor(t, a, t.unit.shots ~= nil)
        v = v - 0.6 * self:threat(a) * math.min(1, back / totalHp(a))
    end
    return v
end

-- the best thing to do for the active stack: { kind, target, from }
function Tactics:think(st)
    local foes = {}
    for _, o in ipairs(self:alive()) do
        if o.side ~= st.side then table.insert(foes, o) end
    end
    if #foes == 0 then return nil end
    if self:canShoot(st) then
        local best, bestV
        for _, t in ipairs(foes) do
            local v = self:attackValue(st, t, dist(st.c, st.r, t.c, t.r) > FAR, true)
            if not bestV or v > bestV then best, bestV = t, v end
        end
        return { kind = "shoot", target = best }
    end
    local reach = self.reachable
    local best, bestV
    for _, t in ipairs(foes) do
        for d = 1, 6 do
            local nc, nr = neighbor(t.c, t.r, d)
            local n = inside(nc, nr) and reach[key(nc, nr)]
            if n then
                local v = self:attackValue(st, t, st.unit.shots ~= nil) - 0.02 * n.d
                if not bestV or v > bestV then
                    best, bestV = { kind = "attack", target = t, from = { c = nc, r = nr, d = n.d, node = n } }, v
                end
            end
        end
    end
    if best then return best end
    -- nobody to hit: go to the most tempting enemy (shooters stay at home if they still can shoot later)
    local goal, goalV
    for _, t in ipairs(foes) do
        local v = self:threat(t) / (1 + dist(st.c, st.r, t.c, t.r))
        if not goalV or v > goalV then goal, goalV = t, v end
    end
    local field = self:distances(goal, st)
    local node, nodeD
    for k, n in pairs(reach) do
        local d = field[k]
        if d and (not nodeD or d < nodeD or (d == nodeD and n.d < node.d)) then node, nodeD = n, d end
    end
    if node and node.d > 0 then return { kind = "move", node = node } end
    return { kind = "defend" }
end

-- walking distance from every hex to the target (flyers: straight distance)
function Tactics:distances(t, mover)
    local field = {}
    if mover.unit.flying then
        for k, cell in pairs(self.cells) do field[k] = dist(cell.c, cell.r, t.c, t.r) end
        return field
    end
    local queue, i = { { t.c, t.r, 0 } }, 1
    field[key(t.c, t.r)] = 0
    while queue[i] do
        local c, r, d = queue[i][1], queue[i][2], queue[i][3]
        i = i + 1
        for dir = 1, 6 do
            local nc, nr = neighbor(c, r, dir)
            local k = key(nc, nr)
            if inside(nc, nr) and not field[k] and not self.cells[k].obstacle then
                local o = self:stackAt(nc, nr)
                -- other stacks are walls, but far ones may move away: a small penalty instead
                field[k] = d + 1 + ((o and o ~= mover) and 3 or 0)
                table.insert(queue, { nc, nr, field[k] })
            end
        end
    end
    return field
end

function Tactics:aiStep(dt)
    self.aiDelay = self.aiDelay - dt
    if self.aiDelay > 0 then return end
    local st = self.active
    local a = self:think(st)
    if not a then
        self:perform(function() pause(0.1) end)
        return
    end
    if a.kind == "shoot" then
        self:perform(function() self:shoot(st, a.target) end)
    elseif a.kind == "attack" then
        local from = { c = a.from.c, r = a.from.r, path = pathOf(a.from.node) }
        if st.unit.flying then from.path = { { c = st.c, r = st.r }, { c = from.c, r = from.r } } end
        self:perform(function() self:meleeAttack(st, a.target, from) end)
    elseif a.kind == "move" then
        local path = st.unit.flying and { { c = st.c, r = st.r }, a.node } or pathOf(a.node)
        self:perform(function() self:walk(st, path) end)
    else
        st.defending = true
        self.fx:play("shield", st.x, st.y - 26, { scale = 0.6 })
        self:perform(function()
            st.acted = true
            pause(0.3)
        end)
    end
end

-- the loop ---------------------------------------------------------------------------------

function Tactics:onStart()
    self.round = 1
    self:nextTurn()
end

function Tactics:step(dt)
    self:animate(dt)
    if self.task then
        local ok, err = coroutine.resume(self.task, dt)
        if not ok then error(err) end
        if coroutine.status(self.task) == "dead" then
            self.task = nil
            local st = self.active
            if self.backToInput and st and not st.dead then
                -- a spell does not take the stack's turn
                self.backToInput = nil
                self.reachable = self:reach(st)
                if self:checkEnd() then return end
                self.mode = "input"
                return
            end
            self.backToInput = nil
            if st then
                if self.justWaited then
                    self.justWaited = nil
                else
                    st.acted = true
                end
            end
            self.active = nil
            self:nextTurn()
        end
        return
    end
    if self.mode == "input" or self.mode == "book" or self.mode == "target" then
        self:inputStep()
    elseif self.mode == "ai" then
        self:aiStep(dt)
    end
end

function Tactics:animate(dt)
    for _, st in ipairs(self.stacks) do
        st.sprite:update(dt)
        st.hitT = math.max(0, st.hitT - dt)
        if st.dead then
            st.deadT = (st.deadT or 0) + dt
        elseif st.hitT <= 0 and st.sprite.name and st.sprite.name:find("^hurt") then
            self:pose(st, "idle")
        end
    end
    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        p.t = p.t + dt
        if p.t >= p.dur then table.remove(self.projectiles, i) end
    end
    for i = #self.bolts, 1, -1 do
        local b = self.bolts[i]
        b.t = b.t + dt
        if b.t > 0.4 then table.remove(self.bolts, i) end
    end
    for _, l in ipairs(self.log) do l.t = l.t + dt end
end

function Tactics:idle(dt)
    self:animate(dt)
end

function Tactics:pauseItems()
    local items = Arcade.pauseItems(self)
    table.insert(items, 1, { label = self.auto and "Автобой: выкл" or "Автобой", action = function()
        engine.scene.pop()
        self.auto = not self.auto
        if self.auto and (self.mode == "input" or self.mode == "book" or self.mode == "target") then
            self.mode = "ai"
            self.aiDelay = 0.2
        end
    end })
    return items
end

function Tactics:goalText()
    return "Цель: разбить все отряды врага"
end

function Tactics:progress()
    return nil
end

function Tactics:results()
    local lines = { "Раундов: " .. self.round }
    local function list(book)
        local parts = {}
        for name, n in pairs(book) do
            if n > 0 then table.insert(parts, G().units[name].name .. " " .. n) end
        end
        table.sort(parts)
        return #parts > 0 and table.concat(parts, ", ") or "нет"
    end
    table.insert(lines, "Убито: " .. list(self.kills))
    table.insert(lines, "Потери: " .. list(self.losses))
    return lines
end

-- drawing ------------------------------------------------------------------------------------

local function hexPoly(x, y, inset)
    local k = 1 - (inset or 0) / 32
    local v = {}
    for i = 1, #POLY, 2 do
        v[i] = x + POLY[i] * k
        v[i + 1] = y + POLY[i + 1] * k
    end
    return v
end

local function fillHex(c, r, color, alpha, inset)
    local x, y = center(c, r)
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.polygon("fill", hexPoly(x, y, inset or 2))
end

local function lineHex(c, r, color, alpha, width, inset)
    local x, y = center(c, r)
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.setLineWidth(width or 2)
    love.graphics.polygon("line", hexPoly(x, y, inset or 3))
    love.graphics.setLineWidth(1)
end

function Tactics:drawGame()
    local lg = love.graphics
    local shade = self:shaded()
    -- row by row, so the lower rows (closer to us) cover the upper ones
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            local cell = self.cells[key(c, r)]
            local x, y = center(c, r)
            lg.setColor(1, 1, 1, 1)
            lg.draw(assets.image(cell.tile), x - CX, y - CY, 0, TS, TS)
            local sh = shade[key(c, r)]
            if sh then fillHex(c, r, sh[1], sh[2]) end
        end
        for _, st in ipairs(self.stacks) do
            if st.dead and st.r == r then self:drawStack(st) end
        end
        for _, st in ipairs(self.stacks) do
            if not st.dead and math.floor((st.y - Y0 - CY) / SY + 0.5) == r then self:drawStack(st) end
        end
    end
    self:drawMarks()
    for _, st in ipairs(self.stacks) do
        if not st.dead then self:drawBadge(st) end
    end
    self:drawMissiles()
end

-- hexes painted under the stacks: where the active stack can go, the targets of a spell
function Tactics:shaded()
    local list = {}
    local st = self.active
    local playerTurn = st and st.side == "player" and (self.mode == "input" or self.mode == "target" or self.mode == "book")
    if st and self.reachable and (self.mode == "input" or self.mode == "ai" or self.mode == "book") then
        for k in pairs(self.reachable) do
            list[k] = { { 0.02, 0.06, 0.12 }, playerTurn and 0.28 or 0.14 }
        end
    end
    if playerTurn and self.mode == "target" and self.spell then
        if self.spell.target == "area" then
            local c, r = self.cur.c, self.cur.r
            list[key(c, r)] = { { 1, 0.5, 0.2 }, 0.5 }
            for d = 1, 6 do
                local nc, nr = neighbor(c, r, d)
                if inside(nc, nr) then list[key(nc, nr)] = { { 1, 0.5, 0.2 }, 0.32 } end
            end
        else
            for k in pairs(self:spellTargets(self.spell)) do
                list[k] = { self.spell.target == "enemy" and { 1, 0.3, 0.3 } or { 0.4, 1, 0.5 }, 0.3 }
            end
        end
    end
    return list
end

-- the cursor, the path and the attack arrow (on top of everything)
function Tactics:drawMarks()
    local lg = love.graphics
    local st = self.active
    if st then
        lineHex(st.c, st.r, { 1, 0.85, 0.3 }, 0.55 + 0.35 * math.sin(self.time * 6), 3)
    end
    self.hover = nil
    local playerTurn = st and st.side == "player" and (self.mode == "input" or self.mode == "target")
    if not playerTurn then return end
    local c, r = self.cur.c, self.cur.r
    if self.mode == "target" then
        lineHex(c, r, { 1, 1, 1 }, 0.9, 2)
        return
    end
    local a = self:actionAt(c, r)
    self.hover = a
    if a and a.kind == "move" then
        local path = st.unit.flying and { a.node } or pathOf(a.node)
        lg.setColor(1, 0.95, 0.6, 0.85)
        for i = 2, #path do
            local x, y = center(path[i].c, path[i].r)
            lg.circle("fill", x, y, i == #path and 5 or 3)
        end
        lineHex(c, r, { 1, 0.95, 0.6 }, 0.9, 2)
    elseif a and a.kind == "attack" then
        lineHex(a.from.c, a.from.r, { 1, 0.95, 0.6 }, 0.9, 2)
        lineHex(c, r, { 1, 0.3, 0.25 }, 0.95, 3)
        local x0, y0 = center(a.from.c, a.from.r)
        local x1, y1 = center(c, r)
        lg.setColor(1, 0.9, 0.4, 0.9)
        lg.setLineWidth(3)
        lg.line(x0, y0, x0 + (x1 - x0) * 0.55, y0 + (y1 - y0) * 0.55)
        lg.setLineWidth(1)
        ui.icon("sword", x1 - 9, y1 - 34, 0.55)
    elseif a and a.kind == "shoot" then
        lineHex(c, r, { 1, 0.3, 0.25 }, 0.95, 3)
        local x, y = center(c, r)
        ui.icon("skill_throw", x - 9, y - 40, 0.55)
    else
        lineHex(c, r, { 1, 1, 1 }, 0.6, 2)
    end
end

function Tactics:drawStack(st)
    local lg = love.graphics
    local x, y = st.x, st.y + 8 - st.lift
    if st.dead then
        -- the fallen lie on the ground
        local a = math.max(0.35, 1 - st.deadT * 2)
        lg.push()
        lg.translate(st.x, st.y + 6)
        lg.rotate(st.facing * math.pi / 2 * math.min(1, st.deadT * 4))
        st.sprite:draw(0, 0, { scale = st.scale, flip = st.flip, color = { 0.6, 0.55, 0.55, a } })
        lg.pop()
        return
    end
    -- a shadow
    lg.setColor(0, 0, 0, 0.25)
    lg.ellipse("fill", st.x, st.y + 9, 16, 5)
    lg.setColor(1, 1, 1, 1)
    local bob = math.sin(self.time * 3 + st.bob) * 0.8
    st.sprite:draw(x, y + bob, { scale = st.scale, flip = st.flip })
    if st.hitT > 0 then
        lg.setBlendMode("add")
        st.sprite:draw(x, y + bob, { scale = st.scale, flip = st.flip, color = { 1, 0.4, 0.3, st.hitT * 3 } })
        lg.setBlendMode("alpha")
    end
    if st.defending then
        ui.icon("skill_defend", st.x - 30, st.y - 30, 0.45, 0.85)
    end
end

function Tactics:drawBadge(st)
    local lg = love.graphics
    local font = ui.font("tiny")
    local text = tostring(st.count)
    local w = math.max(20, font:getWidth(text) + 8)
    local x, y = math.floor(st.x + 30 - w), math.floor(st.y + 13)
    local c = st.side == "player" and { 0.18, 0.42, 0.75 } or { 0.72, 0.2, 0.2 }
    if st.slowUntil and st.slowUntil >= self.round then c = { 0.35, 0.55, 0.25 } end
    if st.hasteUntil and st.hasteUntil >= self.round then c = { 0.75, 0.55, 0.15 } end
    lg.setColor(0, 0, 0, 0.7)
    lg.rectangle("fill", x - 1, y - 1, w + 2, 15)
    lg.setColor(c)
    lg.rectangle("fill", x, y, w, 13)
    ui.print(text, x + w / 2, y + 3, { font = font, align = "center", color = "light", shadow = false })
    -- health of the top creature
    local k = st.hp / st.unit.hp
    if k < 1 then
        lg.setColor(0, 0, 0, 0.7)
        lg.rectangle("fill", x, y + 14, w, 3)
        lg.setColor(0.4, 1, 0.4)
        lg.rectangle("fill", x, y + 14, w * k, 3)
    end
end

function Tactics:drawMissiles()
    local lg = love.graphics
    for _, p in ipairs(self.projectiles) do
        local k = math.min(1, p.t / p.dur)
        local x = p.x0 + (p.x1 - p.x0) * k
        local y = p.y0 + (p.y1 - p.y0) * k - math.sin(k * math.pi) * 50
        if p.kind == "stone" then
            ui.icon("stone", x - 8, y - 8, 0.5)
        else
            local nx = p.x0 + (p.x1 - p.x0) * math.min(1, k + 0.05)
            local ny = p.y0 + (p.y1 - p.y0) * math.min(1, k + 0.05) - math.sin(math.min(1, k + 0.05) * math.pi) * 50
            local a = math.atan2(ny - y, nx - x)
            lg.setColor(0.95, 0.92, 0.85)
            lg.setLineWidth(2)
            lg.line(x - math.cos(a) * 12, y - math.sin(a) * 12, x, y)
            lg.setColor(1, 1, 1)
            lg.circle("fill", x, y, 2)
            lg.setLineWidth(1)
        end
    end
    for _, b in ipairs(self.bolts) do
        local a = 1 - b.t / 0.4
        boltRandom:setSeed(math.floor(self.time * 30))
        local pts, y = { b.x, -10 }, -10
        while y < b.y do
            y = y + 30
            table.insert(pts, b.x + boltRandom:random(-18, 18))
            table.insert(pts, math.min(y, b.y))
        end
        lg.setColor(0.6, 0.8, 1, a)
        lg.setLineWidth(6)
        lg.line(pts)
        lg.setColor(1, 1, 1, a)
        lg.setLineWidth(2)
        lg.line(pts)
        lg.setLineWidth(1)
    end
    lg.setColor(1, 1, 1, 1)
end

-- the HUD: round, what happens, the queue and the card of a stack
function Tactics:drawHud()
    local lg = love.graphics
    ui.print("Раунд " .. self.round, 16, 12, { font = "pixel", color = "gold", outline = { 0, 0, 0, 0.8 } })
    if self.spells then
        ui.print("Мана " .. self.mana .. "/" .. self.maxMana, screen.width - 16, 12,
            { font = "pixel", align = "right", color = "blue", outline = { 0, 0, 0, 0.8 } })
    end
    local status, color = self:statusText()
    if status then
        ui.print(status, screen.width / 2, 12, { font = "small", align = "center", color = color or "light",
            outline = { 0, 0, 0, 0.85 } })
    end
    -- bottom panel
    local py = 448
    ui.panel.draw(8, py, screen.width - 16, screen.height - py - 6)
    self:drawQueue(20, py + 8)
    local st = self.hoverStack or self.active
    if st then self:drawStackCard(st, 612, py + 8) end
    if self.mode == "book" then self:drawBook() end
end

function Tactics:statusText()
    local st = self.active
    self.hoverStack = nil
    if self.mode == "target" and self.spell then
        return self.spell.name .. ": выбери цель", "blue"
    end
    if st and st.side == "player" and self.mode == "input" and self.phase == "play" then
        local a = self.hover
        local t = self:stackAt(self.cur.c, self.cur.r)
        self.hoverStack = t
        if a and (a.kind == "attack" or a.kind == "shoot") then
            local half = a.kind == "shoot" and a.far or (a.kind == "attack" and st.unit.shots ~= nil)
            local lo, hi = self:damageRange(st, a.target, half)
            local k1, k2 = killsFor(a.target, lo), killsFor(a.target, hi)
            local kills = k1 == k2 and tostring(k1) or (k1 .. "–" .. k2)
            local verb = a.kind == "shoot" and "Выстрел" or "Атака"
            return verb .. " → " .. a.target.unit.name .. ": урон " .. lo .. "–" .. hi .. ", убьёт " .. kills
                .. (half and " (½)" or ""), "accent"
        elseif a and a.kind == "far" then
            return a.target.unit.name .. ": не достать", "faded"
        end
    end
    local l = self.log[1]
    if l and l.t < 3 then
        return l.text, l.color
    end
    if st and st.side == "player" and self.mode == "input" then
        return "Ход: " .. st.unit.name, "accent"
    end
end

function Tactics:drawQueue(x, y)
    local lg = love.graphics
    local list = {}
    if self.active then table.insert(list, { st = self.active, now = true }) end
    for _, st in ipairs(self:upcoming()) do table.insert(list, { st = st }) end
    local nextRound = self:sorted(self:alive())
    table.insert(list, { sep = self.round + 1 })
    for _, st in ipairs(nextRound) do table.insert(list, { st = st }) end
    local cw, ch = 40, 44
    local maxN = 13
    for i = 1, math.min(#list, maxN) do
        local e = list[i]
        if e.sep then
            lg.setColor(1, 0.85, 0.4, 0.8)
            lg.rectangle("fill", x + 1, y + 4, 2, ch - 8)
            x = x + 8
        else
            local st = e.st
            local side = st.side == "player" and { 0.18, 0.42, 0.75 } or { 0.72, 0.2, 0.2 }
            lg.setColor(side[1] * 0.5, side[2] * 0.5, side[3] * 0.5, 0.9)
            lg.rectangle("fill", x, y, cw, ch)
            lg.setColor(side)
            lg.setLineWidth(e.now and 3 or 1)
            lg.rectangle("line", x, y, cw, ch)
            lg.setLineWidth(1)
            if e.now then
                lg.setColor(1, 0.85, 0.3, 0.6 + 0.4 * math.sin(self.time * 6))
                lg.setLineWidth(2)
                lg.rectangle("line", x - 2, y - 2, cw + 4, ch + 4)
                lg.setLineWidth(1)
            end
            lg.setColor(1, 1, 1, 1)
            st.sprite:draw(x + cw / 2, y + ch - 8, { scale = st.scale * 0.6, flip = st.flip })
            ui.print(st.count, x + cw - 3, y + ch - 10, { font = "tiny", align = "right", color = "light",
                outline = { 0, 0, 0, 0.9 } })
            x = x + cw + 4
        end
    end
    -- the keys under the queue
    if self.active and self.active.side == "player" and self.mode == "input" then
        local hints = { { "wait", "ждать" }, { "defend", "защита" } }
        if self.spells then table.insert(hints, { "spell", "магия" }) end
        ui.keyHints(20, y + ch + 6, hints)
    end
end

function Tactics:drawStackCard(st, x, y)
    local u = st.unit
    local name = u.name .. (st.count > 1 and (" ×" .. st.count) or "")
    ui.print(name, x, y, { font = "small", color = st.side == "player" and "blue" or "red" })
    local tags = {}
    if st.defending then table.insert(tags, "защита") end
    if st.waited and not st.acted then table.insert(tags, "ждёт") end
    if st.hasteUntil and st.hasteUntil >= self.round then table.insert(tags, "быстрее") end
    if st.slowUntil and st.slowUntil >= self.round then table.insert(tags, "медленнее") end
    if #tags > 0 then
        ui.print(table.concat(tags, ", "), x + 330, y, { font = "small", align = "right", color = "gold" })
    end
    local cx = x
    local function stat(icon, text)
        ui.icon(icon, cx, y + 26, 0.5)
        cx = cx + 19
        cx = cx + ui.print(text, cx, y + 26, { font = "small", color = "ink" }) + 12
    end
    stat("sword", u.attack)
    stat("skill_defend", self:defenseOf(st))
    stat("fist", u.damage[1] .. "–" .. u.damage[2])
    stat("potion", st.hp .. "/" .. u.hp)
    stat("boots", self:speedOf(st))
    if u.shots then stat("stone", st.shots) end
    local abil = {}
    for _, a in ipairs(ABILITIES) do
        if u[a[1]] then table.insert(abil, a[2]) end
    end
    if u.retaliations and u.retaliations > 1 then table.insert(abil, "отвечает " .. u.retaliations .. " раза") end
    if u.strikes == 2 then table.insert(abil, "бьёт дважды") end
    if u.shots then table.insert(abil, "стреляет") end
    if #abil > 0 then
        ui.print(table.concat(abil, " · "), x, y + 52, { font = "small", color = "faded" })
    end
end

function Tactics:drawBook()
    local w, h = 400, 64 + #SPELLS * 40
    local x, y = math.floor((screen.width - w) / 2), 120
    ui.panel.draw(x, y, w, h)
    ui.print("Книга заклинаний", x + w / 2, y + 14, { font = "small", align = "center", color = "accent" })
    self.bookRows = {}
    for i, sp in ipairs(SPELLS) do
        local ry = y + 44 + (i - 1) * 40
        local can = sp.cost <= self.mana
        if i == self.bookIndex then
            love.graphics.setColor(1, 1, 1, 0.12)
            love.graphics.rectangle("fill", x + 10, ry - 4, w - 20, 36)
        end
        self.bookRows[i] = { x + 10, ry - 4, w - 20, 36 }
        ui.print(sp.name, x + 22, ry, { font = "small", color = can and (i == self.bookIndex and "accent" or "ink") or "faded" })
        ui.print(sp.cost, x + w - 22, ry, { font = "small", align = "right", color = can and "blue" or "faded" })
        ui.print(sp.text, x + 22, ry + 17, { font = "tiny", color = "faded" })
    end
end

return Tactics
