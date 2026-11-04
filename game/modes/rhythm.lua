-- Rhythm game like Dance Dance Revolution: arrows fly up to the targets at the top, press the
-- key when an arrow covers its target. The notes follow the real beats of the track:
-- game/data/charts/<music>.lua (made by tools/rhythm_chart.py; without a chart - every beat).
-- Arrows: "Mouse buttons & arrow keys" by qubodup (CC0); dancers: GrafxKid "Classic hero" (CC0)
-- and the bunny of the game.
--
--   game.stage "dance" { kind = "rhythm", goal = 70, time = 60, level = 3 }
--   local r = s:play("rhythm", { level = 1 })   -- r.win, r.score, r.accuracy, r.maxCombo, r.grade
--
--   goal     accuracy in percent to win (default 60)
--   time     length of the dance in seconds (default 60)
--   start    second of the track where the dance begins (default 0)
--   music    the track (default "arcade"; it needs bpm and beatOffset in sounds.lua)
--   speed    speed of the arrows (default 1)
-- Level 1 - an arrow every other beat ... level 5 - quick 16th notes and jumps (two arrows).
-- Keys: arrows (or WASD). Too many misses empty the energy bar - the dance is lost.

local engine = require("engine")
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

local Rhythm = class(Arcade)
Rhythm.keymap = "rhythm"
Rhythm.info = {
    title = "Пляска",
    rules = "Стрелки летят вверх к меткам. Жми ту же стрелку, когда она накроет метку — точно в бит. "
        .. "Промахи опустошают шкалу энергии.",
    keys = { { "laneLeft", "стрелки в такт", "[←↓↑→]" } },
    background = "night",
    dim = 0,
    lives = false,
}
Rhythm.defaultLives = 0

local LANES = { "laneLeft", "laneDown", "laneUp", "laneRight" }
local ARROW = { { 0, 220 }, { 34, 220 }, { 34, 186 }, { 68, 220 } } -- white keys; green ones are 102 px to the right
local TARGET_Y = 92
local LANE_W = 78
local JUDGE = {
    { name = "perfect", text = "ИДЕАЛЬНО", window = 0.045, points = 300, value = 1, energy = 0.025, color = "gold" },
    { name = "great", text = "ОТЛИЧНО", window = 0.09, points = 200, value = 0.75, energy = 0.012, color = "green" },
    { name = "good", text = "ХОРОШО", window = 0.14, points = 80, value = 0.4, energy = 0, color = "blue" },
}
local MISS = { name = "miss", text = "МИМО", value = 0, color = "red" }
local NOTE_COLORS = { [0] = { 1, 0.42, 0.42 }, [2] = { 0.45, 0.65, 1 }, [1] = { 1, 0.9, 0.35 }, [3] = { 1, 0.9, 0.35 } }

local function digit(s, i)
    if not s then return 0 end
    local b = s:byte(i + 1)
    return b and (b - 48) or 0
end

-- how many notes a bar (16 slots of 1/16) gets and the smallest gap between them (in 16ths)
local LEVELS = { { quota = 2, gap = 8 }, { quota = 4, gap = 2 }, { quota = 6, gap = 2 }, { quota = 8, gap = 1 },
    { quota = 11, gap = 1 } }

-- notes from the onsets of the track (see tools/rhythm_chart.py): in every bar the strongest
-- onsets win, beats first, then 8ths, then 16ths; quiet bars get fewer notes
local function buildNotes(chart, info, level, from, to, seed)
    local rng = love.math.newRandomGenerator(seed)
    local bpm = chart and chart.bpm or info.bpm or 120
    local offset = chart and chart.offset or info.beatOffset or 0
    local slot = 60 / bpm / 4
    local L = LEVELS[math.max(1, math.min(5, level))]
    local i0 = math.max(0, math.ceil((from - offset) / slot))
    local i1 = math.floor((to - offset) / slot)
    local picked = {}
    for bar = math.floor(i0 / 16), math.floor(i1 / 16) do
        local cands, loud = {}, 0
        for k = 0, 15 do
            local i = bar * 16 + k
            local pos = i % 4
            loud = loud + (chart and digit(chart.loud, math.floor(i / 4)) or 9) / 16
            if i >= i0 and i <= i1 and (pos == 0 or (pos == 2 and L.gap <= 2) or L.gap == 1) then
                local low, mid, high = 5, 0, 0
                if chart then low, mid, high = digit(chart.low, i), digit(chart.mid, i), digit(chart.high, i) end
                local s = math.max(low, mid * 0.9, high * 0.7) + (pos == 0 and 3 or (pos == 2 and 1.5 or 0))
                    + (i % 16 == 0 and 2 or 0) + (i % 8 == 0 and 1 or 0)
                if pos == 0 or math.max(low, mid, high) >= 3 then
                    table.insert(cands, { i = i, s = s + rng:random() * 0.5, low = low })
                end
            end
        end
        local quota = loud < 1.5 and 0 or math.floor(L.quota * math.max(0.4, math.min(1, loud / 7)) + 0.5)
        table.sort(cands, function(a, b) return a.s > b.s end)
        local n = 0
        for _, c in ipairs(cands) do
            if n >= quota then break end
            local free = true
            for d = -(L.gap - 1), L.gap - 1 do
                if d ~= 0 and picked[c.i + d] then free = false; break end
            end
            if free then picked[c.i] = c; n = n + 1 end
        end
    end
    local list = {}
    for i, c in pairs(picked) do table.insert(list, c) end
    table.sort(list, function(a, b) return a.i < b.i end)
    local notes = {}
    local lastLane, lastT = 2, -1
    for _, c in ipairs(list) do
        local i = c.i
        local t = offset + i * slot
        local pos = i % 4
        local fast = t - lastT < 0.3
        local lane
        repeat
            lane = rng:random(1, 4)
        until not (fast and lane == lastLane) and not (lane == lastLane and rng:random() < 0.6)
        table.insert(notes, { t = t, lane = lane, color = NOTE_COLORS[pos] })
        -- jumps: two arrows at once on strong beats at the start of a bar
        if level >= 3 and i % 16 == 0 and c.low >= 6 and rng:random() < (level - 2) * 0.25 then
            table.insert(notes, { t = t, lane = ({ 4, 3, 2, 1 })[lane], color = NOTE_COLORS[pos], jump = true })
        end
        lastLane, lastT = lane, t
    end
    return notes, bpm, offset
end

function Rhythm:setup()
    self.arrows = assets.image("assets/sprites/arcade/arrows.png")
    self.white, self.green = {}, {}
    for k, xy in ipairs(ARROW) do
        self.white[k] = assets.quad(self.arrows, xy[1], xy[2], 32, 32)
        self.green[k] = assets.quad(self.arrows, xy[1] + 102, xy[2], 32, 32)
    end
    local hero = G().sprites.grisha_side -- Гриша (td_hero): steps in place, punches to the arrows
    self.heroImage = assets.image(hero.image)
    local function hq(col, row) return assets.quad(self.heroImage, (col - 1) * 16, (row - 1) * 16, 16, 16) end
    self.heroPoses = { idle = { hq(5, 1), hq(6, 1), hq(7, 1), hq(8, 1) },
        moves = { hq(2, 3), hq(8, 3), hq(6, 3), hq(4, 3) }, hurt = hq(1, 1) }
    local bunny = G().sprites.bunny
    self.bunnyImage = assets.image(bunny.image)
    local function bq(col, row) return assets.quad(self.bunnyImage, (col - 1) * 128, (row - 1) * 128, 128, 128) end
    self.bunnyPoses = { bq(1, 3), bq(2, 3), bq(3, 3), bq(1, 1), bq(1, 4), bq(2, 5) }
    self.musicName = self.def.music or "arcade"
    self.goal = self.def.goal or 60
    self.duration = self.def.time or 60
    self.timeLimit, self.timeLeft = nil, nil
    self.from = self.def.start or 0
    self.speed = (self.def.speed or 1) * (300 + self.level * 40)
    local ok, chart = pcall(require, "game.data.charts." .. self.musicName)
    self.chart = ok and chart or nil
    local info = (G().sounds.music or {})[self.musicName] or {}
    local lead = (screen.height - TARGET_Y) / self.speed
    self.notes, self.bpm, self.beatOffset = buildNotes(self.chart, info, self.level, self.from + lead + 0.6,
        self.from + self.duration, self.level * 7 + math.floor(self.from))
    self.lead = lead
    self.songT = self.from - 0.0
    self.first = 1
    self.counts = { perfect = 0, great = 0, good = 0, miss = 0 }
    self.judged, self.value = 0, 0
    self.combo, self.maxCombo = 0, 0
    self.energy = 0.6
    self.flashes = { 0, 0, 0, 0 }
    self.pressedT = { 0, 0, 0, 0 }
    self.judgeText = nil
    self.heroPose, self.bunnyPose, self.poseT = nil, nil, 0
    self.eq = {}
    for k = 1, 24 do self.eq[k] = 0 end
    self.windowScale = 1.35 - self.level * 0.1
end

function Rhythm:enter()
    audio.stopMusic(0.5)
    audio.play("lag")
end

function Rhythm:onStart()
    self.source = audio.music(self.musicName, { restart = true, fade = 0 })
    if self.source and self.from > 0 then self.source:seek(self.from) end
    self.songT = self.from
end

function Rhythm:pause()
    if self.phase == "play" then audio.pauseMusic() end
end

function Rhythm:resume()
    if self.phase == "play" then audio.resumeMusic() end
end

function Rhythm:goalText()
    return "Точность от " .. self.goal .. "%  ·  " .. #self.notes .. " стрелок"
end

function Rhythm:accuracy()
    if self.judged == 0 then return 100 end
    return math.floor(self.value / self.judged * 100 + 0.5)
end

function Rhythm:progress()
    return "Точность " .. self:accuracy() .. "%"
end

function Rhythm:grade()
    local a = self:accuracy()
    if self.counts.miss == 0 and self.counts.good == 0 and self.judged > 0 then return "S" end
    return a >= 90 and "A" or a >= 78 and "B" or a >= 64 and "C" or "D"
end

function Rhythm:results()
    local c = self.counts
    self.extraResult = { accuracy = self:accuracy(), maxCombo = self.maxCombo, grade = self:grade() }
    return {
        "Идеально " .. c.perfect .. "   Отлично " .. c.great .. "   Хорошо " .. c.good .. "   Мимо " .. c.miss,
        "Точность " .. self:accuracy() .. "%   Макс. комбо " .. self.maxCombo .. "   Оценка " .. self:grade(),
    }
end

function Rhythm:laneX(k)
    return screen.width / 2 + (k - 2.5) * LANE_W
end

function Rhythm:judge(note, j, dt)
    note.judged = j.name
    self.judged = self.judged + 1
    self.value = self.value + j.value
    self.counts[j.name] = self.counts[j.name] + 1
    self.judgeText = { j = j, t = 0, late = dt }
    if j == MISS then
        self.combo = 0
        self.energy = self.energy - (0.05 + self.level * 0.012)
        self.heroPose, self.poseT = self.heroPoses.hurt, 0.3
        if self.energy <= 0 then
            self.energy = 0
            self:lose()
        end
        return
    end
    self.combo = self.combo + 1
    self.maxCombo = math.max(self.maxCombo, self.combo)
    self.energy = math.min(1, self.energy + j.energy)
    local mult = 1 + math.min(self.combo, 100) / 50
    self:addScore(math.floor(j.points * mult))
    local x = self:laneX(note.lane)
    self.flashes[note.lane] = 1
    self:burst(x, TARGET_Y, j.name == "perfect" and { 1, 0.9, 0.4 } or { 0.6, 1, 0.6 }, j.name == "perfect" and 14 or 8, 160)
    if self.combo % 50 == 0 then
        self:banner(self.combo .. " КОМБО!")
        audio.play("cool")
    end
    local moves = self.heroPoses.moves
    self.heroPose = moves[note.lane] or moves[1] -- a punch to the side of the arrow
    self.bunnyPose = self.bunnyPoses[(note.lane + self.combo) % #self.bunnyPoses + 1]
    self.poseT = 0.25
end

function Rhythm:step(dt)
    -- our own clock, pulled gently to the playback position of the track
    self.songT = self.songT + dt
    if self.source then
        local real = self.source:tell()
        if math.abs(real - self.songT) > 0.25 then
            self.songT = real
        else
            self.songT = self.songT + (real - self.songT) * math.min(1, dt * 4)
        end
    end
    local now = self.songT
    for k = 1, 4 do
        self.flashes[k] = math.max(0, self.flashes[k] - dt * 5)
        if input.down(LANES[k]) then self.pressedT[k] = math.min(1, self.pressedT[k] + dt * 20) else self.pressedT[k] = 0 end
    end
    if self.judgeText then self.judgeText.t = self.judgeText.t + dt end
    self.poseT = self.poseT - dt
    if self.poseT <= 0 then self.heroPose, self.bunnyPose = nil, nil end
    -- presses
    local good = JUDGE[3].window * self.windowScale
    for k = 1, 4 do
        if input.pressed(LANES[k]) then
            local best, bd
            for i = self.first, #self.notes do
                local n = self.notes[i]
                if n.t - now > good then break end
                if not n.judged and n.lane == k and math.abs(n.t - now) <= good and (not bd or math.abs(n.t - now) < bd) then
                    best, bd = n, math.abs(n.t - now)
                end
            end
            if best then
                for _, j in ipairs(JUDGE) do
                    if bd <= j.window * self.windowScale then
                        self:judge(best, j, now - best.t)
                        break
                    end
                end
            end
        end
    end
    -- misses
    for i = self.first, #self.notes do
        local n = self.notes[i]
        if n.t - now > 0 then break end
        if not n.judged and now - n.t > good then self:judge(n, MISS, 0) end
        if self.phase ~= "play" then return end
    end
    while self.notes[self.first] and self.notes[self.first].judged do self.first = self.first + 1 end
    -- the equalizer follows the onsets of the track
    if self.chart then
        local slotI = math.floor((now - self.beatOffset) / (60 / self.bpm / 4))
        for k = 1, 24 do
            local band = k <= 8 and self.chart.low or (k <= 16 and self.chart.mid or self.chart.high)
            local v = digit(band, slotI + (k * 7) % 3) / 9
            self.eq[k] = math.max(v, self.eq[k] - dt * 3)
        end
    end
    if now > self.from + self.duration + 1 and not self.notes[self.first] then
        audio.stopMusic(2.5)
        self:gameOver(self:accuracy() >= self.goal)
    end
end

function Rhythm:idle(dt)
    for k = 1, 4 do self.flashes[k] = math.max(0, self.flashes[k] - dt * 5) end
end

function Rhythm:beatPhase()
    local t = (self.songT or 0) - (self.beatOffset or 0)
    local b = t * (self.bpm or 120) / 60
    return b - math.floor(b), math.floor(b)
end

function Rhythm:drawStage()
    local lg = love.graphics
    local w, h = screen.width, screen.height
    local ph, beatN = self:beatPhase()
    if self.phase == "title" then ph, beatN = 0.5, 0 end
    local pulse = (1 - ph) ^ 3
    -- floor glow
    lg.setColor(0.12, 0.05, 0.2, 1)
    lg.rectangle("fill", 0, h * 0.62, w, h * 0.38)
    -- light cones sweeping from the top corners; the color changes every bar
    local hues = { { 1, 0.3, 0.5 }, { 0.3, 0.6, 1 }, { 0.5, 1, 0.5 }, { 1, 0.8, 0.3 } }
    local c = hues[math.floor(beatN / 4) % 4 + 1]
    for side = -1, 1, 2 do
        local ox = w / 2 + side * (w / 2 - 40)
        local a = math.sin(self.time * 0.9 + side) * 0.5 - side * 0.35
        local tx, ty = ox + math.sin(a) * h * 1.1 - side * 120, h
        lg.setColor(c[1], c[2], c[3], 0.06 + 0.1 * pulse)
        lg.polygon("fill", ox, -10, tx - 90, ty, tx + 90, ty)
        lg.setColor(c[1], c[2], c[3], 0.08 + 0.12 * pulse)
        lg.ellipse("fill", tx, h * 0.86, 90, 18)
    end
    -- the equalizer at the bottom
    local bw = (w - 80) / 24
    for k = 1, 24 do
        local v = self.eq[k]
        local bh = 6 + v * 70
        lg.setColor(c[1] * 0.6 + 0.2, c[2] * 0.6 + 0.2, c[3] * 0.6 + 0.2, 0.35 + v * 0.4)
        lg.rectangle("fill", 40 + (k - 1) * bw + 2, h - 10 - bh, bw - 4, bh, 2)
    end
    -- the dancers bounce on the beat
    local bob = pulse * 6
    lg.setColor(1, 1, 1, 1)
    local hq = self.heroPose or self.heroPoses.idle[beatN % 4 + 1]
    local squash = 1 + pulse * 0.08
    lg.draw(self.heroImage, hq, 150, h * 0.86 - bob, 0, 7 * (2 - squash), 7 * squash, 8, 16)
    local bqd = self.bunnyPose or self.bunnyPoses[(beatN % 2 == 0) and 1 or 2]
    lg.draw(self.bunnyImage, bqd, w - 150, h * 0.86 - bob * 1.5, 0, 1.1 * (2 - squash), 1.1 * squash, 64, 118)
end

function Rhythm:drawGame()
    local lg = love.graphics
    self:drawStage()
    local now = self.songT or 0
    local ph = self:beatPhase()
    local pulse = (1 - ph) ^ 4
    -- the lanes
    local x0 = self:laneX(1) - LANE_W / 2
    lg.setColor(0, 0, 0.05, 0.55)
    lg.rectangle("fill", x0 - 6, 0, LANE_W * 4 + 12, screen.height)
    -- the targets: dim keys that pulse on the beat, green while the key is down
    for k = 1, 4 do
        local x = self:laneX(k)
        local s = 2 * (1 + 0.08 * pulse) * (1 - self.pressedT[k] * 0.1)
        lg.setColor(1, 1, 1, 0.35 + 0.2 * pulse)
        lg.draw(self.arrows, self.white[k], x, TARGET_Y, 0, s, s, 16, 16)
        if self.pressedT[k] > 0 then
            lg.setColor(1, 1, 1, 0.5)
            lg.draw(self.arrows, self.green[k], x, TARGET_Y, 0, s, s, 16, 16)
        end
        if self.flashes[k] > 0 then
            local f = self.flashes[k]
            lg.setColor(1, 1, 1, f)
            lg.draw(self.arrows, self.green[k], x, TARGET_Y, 0, 2 + (1 - f) * 0.8, 2 + (1 - f) * 0.8, 16, 16)
        end
    end
    -- the notes
    for i = self.first, #self.notes do
        local n = self.notes[i]
        local y = TARGET_Y + (n.t - now) * self.speed
        if y > screen.height + 40 then break end
        if not n.judged then
            local x = self:laneX(n.lane)
            local c = n.color
            lg.setColor(c[1], c[2], c[3], 1)
            lg.draw(self.arrows, self.white[n.lane], x, y, 0, 2, 2, 16, 16)
            if n.jump then
                lg.setColor(1, 1, 1, 0.6)
                lg.rectangle("line", x - 34, y - 34, 68, 68, 10)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
    -- the judgement and the combo
    local jt = self.judgeText
    if jt and jt.t < 0.8 then
        local a = math.min(1, (0.8 - jt.t) * 4)
        local s = 1 + math.max(0, 0.15 - jt.t) * 2
        lg.push()
        lg.translate(screen.width / 2, 196)
        lg.scale(s)
        ui.print(jt.j.text, 0, -16, { font = "title", align = "center", color = jt.j.color, alpha = a, outline = { 0, 0, 0, a } })
        lg.pop()
        if jt.j.name ~= "perfect" and jt.j.name ~= "miss" then
            ui.print(jt.late > 0 and "поздно" or "рано", screen.width / 2, 226, { font = "small", align = "center",
                color = "faded", alpha = a })
        end
    end
    if self.combo >= 4 then
        ui.print(self.combo .. " комбо", screen.width / 2, 256, { font = "pixel", align = "center", color = "light",
            alpha = 0.85, outline = { 0, 0, 0, 0.8 } })
    end
    -- energy and the song position
    local ex = screen.width / 2 - 160
    ui.bar(ex, 40, 320, 8, self.energy, 1, self.energy < 0.25 and (math.floor(self.time * 6) % 2 == 0 and "red" or "light")
        or "green")
    local total = math.max(1, self.duration)
    lg.setColor(1, 1, 1, 0.5)
    lg.rectangle("fill", ex, 52, 320 * math.max(0, math.min(1, (now - self.from) / total)), 2)
    lg.setColor(1, 1, 1, 1)
end

return Rhythm
