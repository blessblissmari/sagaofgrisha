-- Battles: a live timeline (like Grandia) + action commands (like Mario & Luigi,
-- Sea of Stars) + parries (like Clair Obscur: Expedition 33) + shield breaks
-- (like Octopath Traveler) + duo attacks (like Chrono Trigger).
--
--   s:battle({ "blob_blue", "slime" })                 -- from a script, returns { win = true }
--   game.stage "boss" { kind = "battle", enemies = { "ghost", "ghost" }, sky = "night" }
--
-- The timeline (top of the screen): every unit runs WAIT -> COM -> CAST -> ACT.
--   COM   the unit chooses what to do (enemies show their intent: what and whom)
--   CAST  the action charges (quick attacks fast, heavy ones slow)
--   ACT   the action happens
-- Hitting a casting enemy with "Сбить" (or a perfect stone) cancels its action.
-- Action commands: every attack is a little timing game (rings, bars, mashing...).
-- Defense: when an enemy hits, press [parry] right at the blow: no damage and a
-- counter-attack. A bit off - a block (half damage). [dodge] - jump away.
-- Weaknesses: hit an enemy with the right damage type (sword, axe, spear, stone...)
-- to take its shield down; at 0 it BREAKS: loses its action, takes x1.6 damage.
-- Brave points (★): +1 every turn, skills cost them. "Дружба" fills with good play:
-- when full, Гриша and the pet do a duo attack.
--
-- Stage options: enemies, sky, background, music, intro (false = no camera swing),
--   advantage (the party starts first) / ambush (the enemies do), noFlee, level (enemy level)
-- Settings: game.battle.atb ("active" / "wait"), game.battle.timing (1.4 easy .. 0.75 hard)
-- Keys (game.controls.battle): attack, parry, dodge, view, camLeft, camRight, fast.

local engine = require("engine")
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local util = engine.util
local anim = engine.anim
local Background = engine.Background
local Mode = require("game.modes.base")
local rules = require("game.battle.rules")
local qte = require("game.battle.qte")

local function G()
    return require("game")
end

local Battle = class(Mode)
Battle.keymap = "battle"

local FIELD_W, FIELD_H, CELL = 520, 280, 40
local CX, CY = 480, 262
local COM = rules.COM
local MAX_BP = 5

-- units ------------------------------------------------------------------------------

local function newUnit(opts)
    local u = {
        id = opts.id, name = opts.name, side = opts.side,
        hp = opts.hp, maxHp = opts.maxHp or opts.hp,
        attack = opts.attack or 3, defense = opts.defense or 0, speed = opts.speed or 5,
        skills = opts.skills or { "attack" },
        x = opts.x, y = opts.y, z = 0, homeX = opts.x, homeY = opts.y,
        sprite = anim.new(opts.spriteDef), scale = opts.scale or 1.5,
        back = opts.back and anim.new(opts.back),
        stats = opts.stats, flash = 0, alpha = 1,
        facesLeft = opts.spriteDef.facesLeft,
        -- the timeline
        p = 0, phase = "wait",
        bp = opts.bp or 1, status = {},
        shield = opts.shield or 0, maxShield = opts.shield or 0,
        weak = opts.weak, known = {}, evade = opts.evade or 0,
        level = opts.level or 1, ai = opts.ai,
        squash = 0, knock = 0,
    }
    u.sprite:play("idle", u.side == "party" and "left" or "right")
    return u
end

function Battle:init(def)
    Mode.init(self, def)
    local g = G()
    local st = g.state
    self.background = Background(g.backgrounds[def.background or "forest"] or g.backgrounds.black)
    -- the sky sphere around the field (sky = false: the flat parallax background)
    if def.sky ~= false then
        local sky = def.sky
        if sky == nil then
            sky = (def.background and g.skies[def.background]) and def.background or "day"
        end
        if type(sky) == "string" then
            sky = g.skies[sky] or g.skies.day
        end
        if type(sky) == "table" then
            local copy = {}
            for k, v in pairs(sky) do
                copy[k] = v
            end
            if def.background and g.backgrounds[def.background] and def.sky == nil then
                copy.band = def.background
            end
            self.sky = engine.Sky(copy, g.backgrounds)
        end
    end
    self.party, self.enemies, self.units = {}, {}, {}
    -- the hero and the pets
    local hero = st.hero
    local weapon = g.weapon() or {}
    local members = { {
        id = "hero", name = g.player.name ~= "Hero" and g.player.name or (g.characters.grisha and g.characters.grisha.name or "Герой"),
        stats = hero, spriteDef = g.sprite(g.player.sprite), back = g.sprite(g.player.sprite),
        skills = hero.skills, scale = 2,
    } }
    for _, id in ipairs(st.party) do
        local pet = g.pets[id] or {}
        local b = st.pets[id]
        if b then
            table.insert(members, { id = id, name = pet.name or id, stats = b, spriteDef = g.sprite(pet.sprite or id),
                skills = b.skills, scale = (pet.battleScale or 1.5), pet = pet })
        end
    end
    local n = #members
    for i, m in ipairs(members) do
        local s = m.stats
        local worn = m.id == "hero"
        local u = newUnit({
            id = m.id, name = m.name, side = "party", hp = math.max(1, s.hp), maxHp = s.maxHp or s.hp,
            attack = s.attack + (worn and g.bonus("attack") or 0),
            defense = s.defense + (worn and g.bonus("defense") or 0),
            speed = s.speed + (worn and g.bonus("speed") or 0), skills = m.skills,
            x = 150 + (i % 2) * 30, y = (i - (n + 1) / 2) * 80, spriteDef = m.spriteDef, back = m.back,
            scale = m.scale, stats = s, bp = s.bp or 1, level = s.level,
        })
        if worn then
            u.dtype = weapon.dtype or "blunt"
            u.combo = weapon.combo or 2
            u.weaponSkill = weapon.skill or "bonk"
            u.weaponName = weapon.name
        else
            u.dtype = "bite"
            u.combo = 3
        end
        u.growth = m.pet and m.pet.battle and m.pet.battle.growth or (worn and g.player.battle.growth)
        table.insert(self.party, u)
        table.insert(self.units, u)
    end
    -- the enemies
    local list = def.enemies or { "slime" }
    local m = #list
    local lv = def.level or 1
    for i, kind in ipairs(list) do
        local mob = g.mobs[kind] or error("battle: unknown mob '" .. tostring(kind) .. "'")
        local b = mob.battle or { hp = 10, attack = 3, defense = 0, speed = 4 }
        local k = 1 + (lv - 1) * 0.12
        local u = newUnit({
            id = kind, name = mob.name or kind, side = "enemy",
            hp = math.floor(b.hp * k), attack = b.attack * k, defense = b.defense * k, speed = b.speed,
            skills = b.skills or { "jab" }, shield = b.shield or 2, weak = b.weak, evade = b.evade,
            x = -150 - (i % 2) * 40, y = (i - (m + 1) / 2) * 80, spriteDef = g.sprite(mob.sprite or kind),
            scale = b.scale or mob.battleScale or 1.6, ai = b.ai, level = lv,
        })
        u.mob = mob
        table.insert(self.enemies, u)
        table.insert(self.units, u)
    end
    -- same names get letters: Слизь А, Слизь Б
    local seen = {}
    for _, e in ipairs(self.enemies) do
        seen[e.name] = (seen[e.name] or 0) + 1
    end
    local letters, used = { "А", "Б", "В", "Г", "Д" }, {}
    for _, e in ipairs(self.enemies) do
        if seen[e.name] > 1 then
            used[e.name] = (used[e.name] or 0) + 1
            e.name = e.name .. " " .. letters[used[e.name]]
        end
    end
    -- where everybody starts on the timeline
    for _, u in ipairs(self.units) do
        u.p = love.math.random() * 0.25 + rules.speedOf(u) * 0.02
        if def.advantage then
            u.p = u.side == "party" and COM - 0.04 or love.math.random() * 0.1
        elseif def.ambush then
            u.p = u.side == "enemy" and COM - 0.04 or love.math.random() * 0.1
        end
    end
    -- camera: view 1 -> view 2 with blend 0..1, focus point and zoom
    self.view, self.fromView, self.blend = "iso", "iso", 1
    self.angle = 0
    self.cam = { x = 0, y = 0, zoom = 1, tx = 0, ty = 0, tzoom = 1 }
    if def.intro ~= false then
        self.fromView, self.blend = "behind", 0
        self.angle = -1.3
        self.introT = 0
    end
    self.queue = {}
    self.duo = 0
    self.hitstop, self.slowmo = 0, 0
    self.projectiles = {}
    self.clock = 0
    self.co = coroutine.create(function() self:loop() end)
end

function Battle:enter()
    local m = self.def.music
    if m == nil then
        m = "arcade"
    end
    if m then
        audio.music(m)
    end
end

-- projection -------------------------------------------------------------------------

local function rotate(x, y, a)
    local c, s = math.cos(a), math.sin(a)
    return x * c - y * s, x * s + y * c
end

function Battle:behindCamera()
    local hero = self.aimer or self.party[1]
    local tx, ty, count = 0, 0, 0
    for _, e in ipairs(self.enemies) do
        if e.hp > 0 then
            tx, ty, count = tx + e.x, ty + e.y, count + 1
        end
    end
    if count > 0 then
        tx, ty = tx / count, ty / count
    else
        tx, ty = -150, 0
    end
    local fx, fy = util.normalize(tx - hero.homeX, ty - hero.homeY)
    return hero.homeX - fx * 110, hero.homeY - fy * 110, fx, fy
end

-- world (x, y on the ground, z up) -> screen x, y, scale, depth for one view
function Battle:projectView(view, x, y, z)
    z = z or 0
    local cam = self.cam
    if view == "top" then
        local rx, ry = rotate(x - cam.x, y - cam.y, self.angle)
        local k = 1.35 * cam.zoom
        return CX + rx * k, CY + 10 + ry * k * 0.8 - z * k, k * 0.9, ry
    elseif view == "iso" then
        local rx, ry = rotate(x - cam.x, y - cam.y, self.angle)
        local k = 1.15 * cam.zoom
        return CX + (rx - ry) * k * 0.72, CY + (rx + ry) * k * 0.36 - z * k, k, rx + ry
    else -- behind the hero
        local cx, cy, fx, fy = self:behindCamera()
        local dx, dy = x - cx, y - cy
        local depth = math.max(30, dx * fx + dy * fy)
        local lat = dx * -fy + dy * fx
        local f = 430
        local camH = 70
        local horizon = 150
        return CX + lat * f / depth, horizon + (camH - z) * f / depth, f / depth * 0.85, -depth
    end
end

local SKY_FOV = 1.0
local VIEW_PITCH = { iso = -0.27, top = -0.62, behind = -0.06 }

function Battle:viewYaw(view)
    if view == "behind" then
        local _, _, fx, fy = self:behindCamera()
        return math.atan2(fx, -fy) + self.angle
    end
    return self.angle
end

function Battle:skyYaw()
    local a, b = self:viewYaw(self.view), self:viewYaw(self.fromView)
    local t = util.clamp(self.blend, 0, 1)
    local d = (a - b + math.pi) % (2 * math.pi) - math.pi
    return b + d * t * t * (3 - 2 * t)
end

function Battle:skyPitch()
    local t = util.clamp(self.blend, 0, 1)
    t = t * t * (3 - 2 * t)
    return util.lerp(VIEW_PITCH[self.fromView] or -0.3, VIEW_PITCH[self.view] or -0.3, t)
end

function Battle:project(x, y, z)
    local ax, ay, as, ad = self:projectView(self.view, x, y, z)
    if self.blend >= 1 then
        return ax, ay, as, ad
    end
    local bx, by, bs, bd = self:projectView(self.fromView, x, y, z)
    local t = util.clamp(self.blend, 0, 1)
    t = t * t * (3 - 2 * t)
    return util.lerp(bx, ax, t), util.lerp(by, ay, t), util.lerp(bs, as, t), util.lerp(bd, ad, t)
end

function Battle:setView(view)
    if view == self.view then
        return
    end
    self.fromView, self.view, self.blend = self.view, view, 0
end

-- the camera leans towards the action
function Battle:focus(a, b, zoom)
    local x, y = (a.x + (b and b.x or a.x)) / 2, (a.y + (b and b.y or a.y)) / 2
    self.cam.tx, self.cam.ty, self.cam.tzoom = x * 0.45, y * 0.45, zoom or 1.18
end

function Battle:unfocus()
    self.cam.tx, self.cam.ty, self.cam.tzoom = 0, 0, 1
end

-- coroutine helpers --------------------------------------------------------------------

function Battle:wait(seconds)
    local untilTime = self.clock + seconds
    while self.clock < untilTime do
        coroutine.yield()
    end
end

function Battle:tween(seconds, subject, target, ease)
    local done = false
    self.timer:tween(seconds, subject, target, ease or "quadInOut", function() done = true end)
    while not done do
        coroutine.yield()
    end
end

function Battle:say(text, seconds)
    self.log = text
    if seconds then
        self:wait(seconds)
    end
end

function Battle:popup(u, text, color, size, dy)
    local sx, sy, s = self:project(u.x, u.y, u.z)
    self.fx:popup(sx, sy - 70 * s - (dy or 0), text, { color = color, scale = size or 1.4, life = 1.0 })
end

-- big words in the middle: "BREAK!", "ПАРИРОВАНО!"
function Battle:shout(text, color, time)
    self.shoutText = { text = text, color = color or { 1, 0.9, 0.4 }, t = 0, life = time or 0.9 }
end

function Battle:alive(list)
    local r = {}
    for _, u in ipairs(list) do
        if u.hp > 0 then
            table.insert(r, u)
        end
    end
    return r
end

function Battle:foes(u)
    return u.side == "party" and self.enemies or self.party
end

function Battle:friends(u)
    return u.side == "party" and self.party or self.enemies
end

function Battle:runQte(q)
    self.qteObj = q
    coroutine.yield()
    while not q:update(self.qdt or self.dt) do
        coroutine.yield()
    end
    self.qteObj = nil
    local r = q.result
    if q.kind ~= "parry" then
        local where = q.target or self.party[1]
        if r == "perfect" then
            audio.play("dzing", { volume = 0.6, pitch = 1.2 })
            self:popup(where, "Отлично!", { 1, 0.9, 0.3 }, 1.3, 20)
            self:addDuo(5)
        elseif r == "good" then
            self:popup(where, "Хорошо", { 0.85, 0.95, 1 }, 1.1, 20)
            self:addDuo(2)
        elseif r == "miss" then
            self:popup(where, "Мимо", { 0.7, 0.7, 0.75 }, 1.0, 20)
        end
    end
    return q
end

function Battle:addDuo(n)
    local before = self.duo
    self.duo = math.min(100, self.duo + n)
    if before < 100 and self.duo >= 100 and #self:alive(self.party) >= 2 then
        audio.play("bell", { volume = 0.6 })
        ui.toast("«Дружба» полна: можно Дуэт!", { icon = "carrot", color = { 1, 0.7, 0.85 } })
    end
end

-- menus inside the coroutine -------------------------------------------------------------

-- top = true: the main command menu, [Esc] opens the pause menu there
function Battle:chooseMenu(items, caption, top, help)
    self.menu = ui.Menu(items, { font = ui.font("body") })
    self.menu.visible = 6
    self.menuCaption = caption
    self.menuTop = top
    while true do
        coroutine.yield()
        if top and self:pausePressed() then
            input.consume("pause")
            input.consume("cancel")
            self:openPause()
            coroutine.yield()
        end
        local chosen = self.menu:update(self.dt)
        if chosen then
            self.menu = nil
            return chosen
        end
        if input.pressed("cancel") and not top then
            input.consume("cancel")
            audio.play("ui_back")
            self.menu = nil
            return nil
        end
    end
end

-- arrows pick one of the units (or all of them), returns nil on cancel
function Battle:chooseTarget(list, caption, all)
    local index = 1
    if #list == 0 then
        return nil
    end
    -- start on the weakest-looking enemy the player already hit, or the first
    self.targets = list
    self.targetAll = all
    self.log = caption
    while true do
        self.cursor = list[index]
        coroutine.yield()
        if not all and (input.pressed("left", true) or input.pressed("up", true)) then
            index = (index - 2) % #list + 1
            audio.play("ui_move")
        elseif not all and (input.pressed("right", true) or input.pressed("down", true)) then
            index = index % #list + 1
            audio.play("ui_move")
        elseif input.pressed("confirm") or input.pressed("attack") then
            input.consume("confirm")
            input.consume("attack")
            audio.play("ui_select")
            self.cursor, self.targets, self.targetAll, self.log = nil, nil, nil, nil
            return all and list or list[index]
        elseif input.pressed("cancel") then
            input.consume("cancel")
            audio.play("ui_back")
            self.cursor, self.targets, self.targetAll, self.log = nil, nil, nil, nil
            return nil
        end
    end
end

-- the timeline ---------------------------------------------------------------------------

function Battle:tickTimeline(dt)
    if self.busy or self.finished or self.introT or self.over then
        return
    end
    local scale = 1
    if self.choosing then
        scale = (G().battle.atb == "wait") and 0 or 0.1
    end
    if scale <= 0 then
        return
    end
    for _, u in ipairs(self.units) do
        if u.hp > 0 and u ~= self.choosing and not u.queued then
            local speed = rules.speedOf(u)
            if u.phase == "wait" then
                u.p = u.p + rules.waitRate(speed) * dt * scale
                if u.p >= COM then
                    u.p, u.queued = COM, "com"
                    table.insert(self.queue, u)
                end
            elseif u.phase == "cast" then
                local cast = u.action and u.action.skill.cast or 1
                u.p = u.p + rules.castRate(speed, cast) * dt * scale
                if u.p >= 1 then
                    u.p, u.queued = 1, "act"
                    table.insert(self.queue, u)
                end
            end
        end
    end
end

-- actions first, then choices (in the order they came)
function Battle:nextQueued()
    for i, u in ipairs(self.queue) do
        if u.queued == "act" then
            return table.remove(self.queue, i)
        end
    end
    return table.remove(self.queue, 1)
end

function Battle:unqueue(u)
    for i, other in ipairs(self.queue) do
        if other == u then
            table.remove(self.queue, i)
            break
        end
    end
    u.queued = nil
end

-- the unit's action is cancelled: back on the timeline
function Battle:interrupt(u, knock)
    self:unqueue(u)
    u.action, u.intent = nil, nil
    u.phase = "wait"
    u.p = math.max(0, COM * (0.55 - (knock or 0.25)))
    self:popup(u, "Прервано!", { 1, 0.55, 0.3 }, 1.3, 36)
    audio.play("zap", { volume = 0.6 })
end

function Battle:isOver()
    return #self:alive(self.enemies) == 0 or #self:alive(self.party) == 0 or self.fled
end

function Battle:loop()
    self:wait(0.3)
    self.log = self.def.introText or (#self.enemies > 1 and "Враги нападают!" or (self.enemies[1].name .. " нападает!"))
    if self.def.advantage then
        self.log = "Внезапная атака! Вы успели первыми."
    elseif self.def.ambush then
        self.log = "Засада! Враги напали первыми."
    end
    self:wait(1.3)
    self.log = nil
    while not self:isOver() do
        local u = self:nextQueued()
        if u and u.hp > 0 then
            self.busy = true
            if u.queued == "com" then
                u.queued = nil
                self:commandPhase(u)
            else
                u.queued = nil
                self:actPhase(u)
            end
            self.busy = false
        else
            coroutine.yield()
        end
    end
    self.over = true
    self:ending()
end

-- a new turn of the unit: brave points, statuses, guard ends
function Battle:startTurn(u)
    local g = G()
    u.guarding = false
    if u.side == "party" then
        u.bp = math.min(MAX_BP, (u.bp or 0) + 1)
    end
    if u.broken then
        u.broken = false
        u.shield = u.maxShield
        self:popup(u, "Щит восстановлен", { 0.7, 0.85, 1 }, 1.0, 30)
    end
    local skip = false
    for id, s in pairs(u.status) do
        local def = g.statuses[id]
        if def then
            if def.tick then
                local dmg = math.max(1, math.floor(u.maxHp * def.tick + 0.5))
                self:hurt(u, dmg, { status = id })
                self:wait(0.35)
            end
            if def.skip then
                skip = true
                self:popup(u, def.name .. "!", def.color, 1.2, 30)
            end
        end
        s.turns = s.turns - 1
        if s.turns <= 0 then
            u.status[id] = nil
        end
    end
    return skip
end

function Battle:commandPhase(u)
    local skip = self:startTurn(u)
    if u.hp <= 0 or self:isOver() then
        return
    end
    if skip then
        self:wait(0.5)
        u.p, u.phase = 0, "wait"
        return
    end
    local action
    self.active = u
    if u.side == "party" then
        self.busy = false
        self.choosing = u
        action = self:playerCommand(u)
        self.choosing = nil
        self.busy = true
    else
        action = self:enemyChoose(u)
    end
    self.active = nil
    if not action then
        u.p, u.phase = 0, "wait"
        return
    end
    u.action = action
    if (action.skill.cast or 1) <= 0 then
        self:perform(u, action)
        self:afterAction(u, action)
    else
        u.phase = "cast"
        u.p = COM
        if u.side == "enemy" then
            u.intent = action
        end
    end
end

function Battle:actPhase(u)
    local action = u.action
    if not action or u.hp <= 0 then
        u.phase, u.p = "wait", 0
        return
    end
    self.active = u
    self:perform(u, action)
    self.active = nil
    self:afterAction(u, action)
end

function Battle:afterAction(u, action)
    u.action, u.intent = nil, nil
    u.phase = "wait"
    u.p = action and action.recover or 0
    self:unfocus()
end

-- player commands ------------------------------------------------------------------------

local function costText(sk)
    if sk.cost and sk.cost.bp then
        return "  " .. string.rep("★", sk.cost.bp)
    end
    return ""
end

function Battle:canPay(u, sk)
    local g = G()
    if sk.cost then
        if sk.cost.bp and (u.bp or 0) < sk.cost.bp then
            return false
        end
        if sk.cost.item and not g.state.inventory:has(sk.cost.item, sk.cost.count or 1) then
            return false
        end
    end
    return true
end

function Battle:pay(u, sk)
    local g = G()
    if sk.cost then
        if sk.cost.bp then
            u.bp = u.bp - sk.cost.bp
        end
        if sk.cost.item then
            g.state.inventory:remove(sk.cost.item, sk.cost.count or 1)
        end
    end
end

-- skills inside "Навыки": the weapon's skill + stones + extra ones
function Battle:skillList(u)
    local g = G()
    local ids = {}
    if u.weaponSkill then
        table.insert(ids, u.weaponSkill)
    end
    if u.id == "hero" then
        table.insert(ids, "stone")
        table.insert(ids, "rally")
    end
    for _, id in ipairs(u.stats and u.stats.learned or {}) do
        table.insert(ids, id)
    end
    local items = {}
    for _, id in ipairs(ids) do
        local sk = g.skills[id]
        if sk then
            local label = sk.name .. costText(sk)
            if sk.cost and sk.cost.item then
                label = label .. "  ×" .. g.state.inventory:count(sk.cost.item)
            end
            table.insert(items, { label = label, skill = sk, id = id, disabled = not self:canPay(u, sk) })
        end
    end
    return items
end

function Battle:pickTargets(u, sk)
    local t = sk.target or "enemy"
    if t == "self" then
        return u
    elseif t == "enemy" then
        return self:chooseTarget(self:alive(self:foes(u)), sk.name .. ": кого?")
    elseif t == "enemies" then
        return self:chooseTarget(self:alive(self:foes(u)), sk.name .. ": все враги", true)
    elseif t == "ally" then
        return self:chooseTarget(self:alive(self:friends(u)), sk.name .. ": кого?")
    elseif t == "allies" then
        return self:chooseTarget(self:alive(self:friends(u)), sk.name .. ": весь отряд", true)
    end
end

function Battle:playerCommand(u)
    local g = G()
    while true do
        self.log = nil
        local items = {}
        for _, id in ipairs(u.skills) do
            if id == "skills" then
                local list = self:skillList(u)
                table.insert(items, { label = "Навыки ▸", sub = "skills", disabled = #list == 0,
                    help = "Навыки оружия и особые приёмы. Стоят очки отваги ★." })
            elseif id == "item" then
                table.insert(items, { label = "Предмет ▸", sub = "items", help = g.skills.item.description })
            else
                local sk = g.skills[id]
                if sk then
                    table.insert(items, { label = sk.name .. costText(sk), skill = sk, id = id,
                        disabled = not self:canPay(u, sk), help = sk.description })
                end
            end
        end
        if self.duo >= 100 and #self:alive(self.party) >= 2 then
            table.insert(items, 1, { label = "★ Дуэт", skill = g.skills.duo, id = "duo", help = g.skills.duo.description })
        end
        self.menuHelp = items
        local i = self:chooseMenu(items, u.name, true)
        local choice = i and items[i]
        if choice then
            local sk, id = choice.skill, choice.id
            if choice.sub == "skills" then
                local list = self:skillList(u)
                local j = self:chooseMenu(list, "Навыки")
                if j then
                    sk, id = list[j].skill, list[j].id
                else
                    sk = nil
                end
            elseif choice.sub == "items" then
                local action = self:chooseItem(u)
                if action then
                    return action
                end
                sk = nil
            end
            if sk then
                local target = self:pickTargets(u, sk)
                if target then
                    return { skill = sk, id = id, target = target, recover = sk.kind == "defend" and 0.3 or 0 }
                end
            end
        end
    end
end

function Battle:chooseItem(u)
    local g = G()
    local items = {}
    for _, slot in ipairs(g.state.inventory:list()) do
        local info = g.items[slot.id]
        if info and info.heal then
            table.insert(items, { label = info.name .. "  ×" .. slot.count, id = slot.id, help = info.description })
        end
    end
    if #items == 0 then
        self:say("В сумке нечем лечиться", 1.0)
        return nil
    end
    self.menuHelp = items
    local i = self:chooseMenu(items, "Предмет")
    if not i then
        return nil
    end
    local target = self:chooseTarget(self:alive(self.party), "Кого лечим?")
    if not target then
        return nil
    end
    return { skill = g.skills.item, id = "item", item = items[i].id, target = target }
end

-- enemy brains ---------------------------------------------------------------------------

function Battle:enemyChoose(u)
    local g = G()
    local friends = self:alive(self.enemies)
    local foes = self:alive(self.party)
    if #foes == 0 then
        return nil
    end
    -- a hurt friend and a healing skill: heal it
    local hurt
    for _, f in ipairs(friends) do
        if f.hp < f.maxHp * 0.5 and (not hurt or f.hp / f.maxHp < hurt.hp / hurt.maxHp) then
            hurt = f
        end
    end
    local options, total = {}, 0
    for _, id in ipairs(u.skills) do
        local sk = g.skills[id]
        if sk then
            local w = sk.weight or 1
            if sk.kind == "heal" then
                w = hurt and (u.ai == "support" and 6 or 3) or 0
            elseif sk.kind == "defend" then
                w = (u.hp < u.maxHp * 0.4 or u.broken) and 3 or w
            end
            if w > 0 then
                table.insert(options, { sk = sk, id = id, w = w })
                total = total + w
            end
        end
    end
    if #options == 0 then
        options, total = { { sk = g.skills.jab, id = "jab", w = 1 } }, 1
    end
    local r = love.math.random() * total
    local pick = options[#options]
    for _, o in ipairs(options) do
        r = r - o.w
        if r <= 0 then
            pick = o
            break
        end
    end
    local sk = pick.sk
    local target
    if sk.target == "self" then
        target = u
    elseif sk.target == "ally" then
        target = hurt or u
    elseif sk.target == "allies" then
        target = friends
    else
        -- aggressive: the weakest one more often
        table.sort(foes, function(a, b) return a.hp / a.maxHp < b.hp / b.maxHp end)
        target = (u.ai ~= "random" and love.math.random() < 0.55) and foes[1] or foes[love.math.random(#foes)]
    end
    return { skill = sk, id = pick.id, target = target }
end

-- performing actions -------------------------------------------------------------------

local function validTarget(self, u, t)
    if type(t) == "table" and t.hp and t.hp > 0 then
        return t
    end
    local list = self:alive(t and t.side == "party" and self.party or self:foes(u))
    return list[love.math.random(math.max(1, #list))]
end

function Battle:perform(u, a)
    local sk = a.skill
    if sk.kind == "attack" then
        if u.side == "party" then
            self:partyAttack(u, a)
        else
            self:enemyAttack(u, a)
        end
    elseif sk.kind == "heal" then
        self:healAction(u, a)
    elseif sk.kind == "defend" then
        self:defendAction(u, a)
    elseif sk.kind == "item" then
        self:itemAction(u, a)
    elseif sk.kind == "flee" then
        self:fleeAction(u)
    elseif sk.kind == "buff" then
        self:buffAction(u, a)
    elseif sk.kind == "duo" then
        self:duoAction(u, a)
    end
end

function Battle:moveTo(u, x, y, seconds)
    local dir = x < u.x and "left" or "right"
    u.faceX, u.faceY = util.normalize(x - u.x, y - u.y)
    u.sprite:play("walk", dir)
    self:tween(seconds or 0.3, u, { x = x, y = y }, "quadOut")
    u.faceX, u.faceY = nil, nil
    u.sprite:play("idle", u.side == "party" and "left" or "right")
end

function Battle:goHome(u)
    if math.abs(u.x - u.homeX) + math.abs(u.y - u.homeY) > 2 then
        self:moveTo(u, u.homeX, u.homeY, 0.28)
    end
    u.z = 0
end

function Battle:hop(u, height, seconds)
    seconds = seconds or 0.3
    local t = 0
    while t < 1 do
        coroutine.yield()
        t = math.min(1, t + self.dt / seconds)
        u.z = math.sin(t * math.pi) * height
    end
    u.z = 0
end

function Battle:applyStatus(target, st)
    if not st or target.hp <= 0 then
        return
    end
    if love.math.random() > (st.chance or 1) then
        return
    end
    local def = G().statuses[st.id]
    if not def then
        return
    end
    target.status[st.id] = { turns = st.turns or def.turns or 2 }
    self:popup(target, def.name, def.color, 1.1, 46)
    if def.skip and target.phase == "cast" then
        self:interrupt(target, 0.1)
    end
end

-- one blow of a party member
function Battle:strike(u, t, sk, opts)
    opts = opts or {}
    if t.hp <= 0 then
        return
    end
    local dtype = opts.dtype or (sk.type == "weapon" and u.dtype or sk.type)
    if not opts.crit and t.evade > 0 and love.math.random() < t.evade then
        self:popup(t, "Уклонился", { 0.8, 0.8, 0.9 }, 1.2)
        audio.play("swing", { volume = 0.5, pitch = 1.3 })
        return
    end
    local dmg, info = rules.damage(u, t, sk, { crit = opts.crit, mult = opts.mult, dtype = dtype, pierce = sk.pierce })
    -- weaknesses and the shield
    if dtype and t.side == "enemy" then
        if info.weak then
            t.known[dtype] = "weak"
            if not t.broken and t.maxShield > 0 then
                t.shield = math.max(0, t.shield - (sk.shield or 1))
                if t.shield <= 0 then
                    self:breakUnit(t)
                    info.broken = true
                    dmg = math.floor(dmg * 1.6 + 0.5)
                end
            end
        elseif not t.known[dtype] then
            t.known[dtype] = "no"
        end
    end
    self:hurt(t, dmg, info)
    -- interrupts: "Сбить" always, perfect stones, a perfect normal hit pushes a little
    local inter = sk.interrupt == true or (sk.interrupt == "perfect" and opts.crit)
    if t.hp > 0 and not t.broken then
        if inter and (t.phase == "cast" or t.queued == "act") then
            self:interrupt(t, sk.knock)
            self:addDuo(6)
        elseif inter then
            t.p = math.max(0, t.p - (sk.knock or 0.2) * 0.6)
            self:popup(t, "Сбит с толку", { 1, 0.75, 0.4 }, 1.0, 36)
        elseif opts.crit and t.phase == "wait" then
            t.p = math.max(0, t.p - 0.04)
        end
    end
    if sk.status then
        self:applyStatus(t, sk.status)
    end
    self:addDuo(info.weak and 3 or 1)
end

function Battle:breakUnit(t)
    t.broken = true
    self:unqueue(t)
    t.action, t.intent = nil, nil
    t.phase, t.p = "wait", 0
    self:shout("BREAK!", { 1, 0.85, 0.35 }, 1.0)
    audio.play("explode", { volume = 0.5 })
    self.flashTime = 0.25
    self.slowmo = 0.5
    self:addDuo(15)
end

-- damage numbers, sounds, the little freeze on impact
function Battle:hurt(target, dmg, info)
    info = info or {}
    target.hp = math.max(0, target.hp - dmg)
    target.flash = 0.18
    target.squash = 1
    local sx, sy, s = self:project(target.x, target.y, target.z)
    if not info.status then
        self.fx:play("slash", sx, sy - 24 * s, { scale = (info.crit and 0.95 or 0.7) * s })
        self.fx:burst(sx, sy - 24 * s, { count = info.crit and 16 or 8, color = info.weak and { 1, 0.85, 0.3 } or { 1, 1, 1 },
            speed = 140, life = 0.35, size = 3 })
    end
    local color = { 1, 0.45, 0.4 }
    if info.status then
        color = (G().statuses[info.status] or {}).color or color
    elseif target.side == "enemy" then
        color = info.crit and { 1, 0.85, 0.2 } or (info.weak and { 1, 0.7, 0.35 } or { 1, 1, 1 })
    end
    local text = tostring(dmg)
    if info.crit then
        text = text .. "!"
    end
    self:popup(target, text, color, info.crit and 2.2 or (info.weak and 1.8 or 1.5))
    if info.weak and not info.status then
        self:popup(target, "Слабость!", { 1, 0.7, 0.35 }, 1.0, 34)
    end
    audio.play(info.crit and "punch" or "hit", { pitch = 0.9 + love.math.random() * 0.25 })
    self.shakeTime, self.shakePower = 0.22, info.crit and 9 or 4
    self.hitstop = info.crit and 0.11 or 0.05
    -- knock back a little (away from the center)
    target.knock = 1
    if target.side == "party" then
        self:addDuo(3)
    end
    if target.hp <= 0 then
        audio.play(target.side == "enemy" and "pop" or "death")
        self.timer:tween(0.6, target, { alpha = target.side == "enemy" and 0 or 0.4 }, "quadIn")
        self:unqueue(target)
        target.action, target.intent = nil, nil
        if target.side == "enemy" and #self:alive(self.enemies) == 0 then
            self.slowmo = 0.9 -- the last blow in slow motion
        end
    end
end

function Battle:approach(u, t)
    local side = u.side == "party" and 1 or -1
    self:focus(u, t, 1.15)
    self:moveTo(u, t.x + 48 * side, t.y, 0.26)
end

function Battle:partyAttack(u, a)
    local sk = a.skill
    local targets = type(a.target) == "table" and a.target.hp == nil and a.target or nil
    local t = not targets and validTarget(self, u, a.target)
    if targets then
        targets = self:alive(targets)
        if #targets == 0 then
            return
        end
    elseif not t then
        return
    end
    if not self:canPay(u, sk) then
        self:say("Не хватает: " .. sk.name, 0.8)
        return
    end
    self:pay(u, sk)
    local q = sk.qte or "ring"
    self.log = sk.name
    if sk.ranged then
        return self:rangedAttack(u, t, sk)
    end
    if targets then
        -- all enemies: one ring in the middle, then a sweep
        self:focus(u, nil, 1.05)
        self:hop(u, 18, 0.25)
        local r = self:runQte(qte.ring({ target = targets[1], duration = 0.65 }))
        audio.play("swing")
        for _, e in ipairs(targets) do
            self:strike(u, e, sk, { crit = r.result == "perfect", mult = r.result == "miss" and 0.7 or 1 })
            self:wait(0.12)
        end
        self:wait(0.3)
        self.log = nil
        return
    end
    self:approach(u, t)
    if q == "chain" then
        local maxHits = (sk.type == "weapon" or sk.type == "bite") and (u.combo or 3) or ((sk.hits and sk.hits[2]) or 1)
        local hits = 0
        local durations = { 0.5, 0.4, 0.34, 0.3, 0.28 }
        for i = 1, maxHits do
            local r = self:runQte(qte.ring({ target = t, duration = durations[i] or 0.27 }))
            u.sprite:play("attack", nil, true)
            audio.play("swing", { pitch = 1 + i * 0.08 })
            self:strike(u, t, sk, { crit = r.result == "perfect" })
            hits = hits + 1
            if t.hp <= 0 or r.result == "miss" then
                break
            end
            self:wait(0.06)
        end
        if hits >= 2 then
            self:popup(t, hits .. " удара!", { 0.7, 0.95, 1 }, 1.2, 60)
        end
    elseif q == "mash" then
        local r = self:runQte(qte.mash({ label = sk.name .. ": жми быстро!" }))
        self:hop(u, 26, 0.3)
        audio.play("swing")
        self:strike(u, t, sk, { crit = r.result == "perfect", mult = 0.6 + r.quality * 0.9 })
    elseif q == "hold" then
        local r = self:runQte(qte.hold({ label = sk.name .. ": держи и отпусти в зелёной зоне" }))
        audio.play("dash")
        self:strike(u, t, sk, { crit = r.result == "perfect", mult = 0.45 + r.quality * 0.8 })
    else
        local r = self:runQte(qte.ring({ target = t, duration = 0.6 }))
        u.sprite:play("attack", nil, true)
        audio.play("swing")
        self:strike(u, t, sk, { crit = r.result == "perfect", mult = r.result == "miss" and 0.75 or 1 })
    end
    self:wait(0.25)
    self:goHome(u)
    self.log = nil
end

-- the stone: the camera goes behind the hero, a bar decides how good the throw is
function Battle:rangedAttack(u, t, sk)
    local previous = self.view
    self.aimer = u
    self:setView("behind")
    self:wait(0.45)
    local r = self:runQte(qte.bar({ label = sk.name .. ": останови бегунок в центре!" }))
    audio.play("throw")
    audio.play("viu", { volume = 0.4 })
    local miss = r.result == "miss"
    local tx, ty = t.x, t.y
    if miss then
        tx, ty = t.x + (love.math.random() < 0.5 and -40 or 40), t.y + (love.math.random() * 2 - 1) * 40
    end
    self:projectile(u, { x = tx, y = ty }, 0.5, "stone")
    if miss then
        local sx, sy = self:project(tx, ty, 0)
        self.fx:burst(sx, sy, { count = 10, color = { 0.8, 0.75, 0.65 }, speed = 70, life = 0.4, up = 30, gravity = 200 })
        audio.play("land")
        self.fx:popup(sx, sy - 40, "Мимо!", { color = { 0.85, 0.85, 0.85 }, scale = 1.4 })
    else
        self:strike(u, t, sk, { crit = r.result == "perfect", mult = 0.6 + r.quality * 0.6 })
    end
    self:wait(0.5)
    self:setView(previous ~= "behind" and previous or "iso")
    self.aimer = nil
    self:wait(0.3)
    self.log = nil
end

-- something flies from a to b in an arc (stones, spit)
function Battle:projectile(a, b, seconds, icon, color)
    local p = { x = a.x, y = a.y, z = 30, icon = icon, color = color }
    table.insert(self.projectiles, p)
    local x0, y0 = a.x, a.y
    local t = 0
    while t < 1 do
        coroutine.yield()
        t = math.min(1, t + self.dt / seconds)
        p.x, p.y = util.lerp(x0, b.x, t), util.lerp(y0, b.y, t)
        p.z = 30 + math.sin(t * math.pi) * 60 - t * 10
    end
    for i, q in ipairs(self.projectiles) do
        if q == p then
            table.remove(self.projectiles, i)
            break
        end
    end
end

-- an enemy hits: the player parries, blocks or dodges every blow
function Battle:enemyAttack(u, a)
    local sk = a.skill
    local t = validTarget(self, u, a.target)
    if not t then
        return
    end
    self.log = u.name .. ": " .. sk.name
    local blows = sk.rhythm or { sk.windup or 0.6 }
    if not sk.ranged then
        self:approach(u, t)
    else
        self:focus(u, t, 1.08)
        self:wait(0.15)
    end
    local parried = 0
    for i, windup in ipairs(blows) do
        if t.hp <= 0 then
            break
        end
        local q = qte.parry({ target = t, windup = windup, feint = i == 1 and sk.feint or nil })
        self.qteObj = q
        -- the enemy rises during the windup and comes down on the blow
        local result
        while true do
            coroutine.yield()
            local done = q:update(self.qdt or self.dt)
            if not sk.ranged then
                local k = math.min(1, q.t / q.impact)
                u.z = math.sin(k * math.pi * 0.5) * 22 * (1 - math.max(0, (q.t - q.impact) * 8))
            end
            if done then
                result = q.result
                break
            end
        end
        self.qteObj = nil
        u.z = 0
        if sk.ranged then
            -- the shot flies on the blow
            local sx, sy, s = self:project(t.x, t.y, 20)
            self.fx:play("magic", sx, sy, { scale = 0.5 * s })
        end
        audio.play("swing", { pitch = 0.8 })
        if result == "parry" then
            parried = parried + 1
            self:shout("ПАРИРОВАНО!", { 0.6, 0.9, 1 }, 0.7)
            audio.play("dzing", { pitch = 1.4 })
            self.hitstop = 0.12
            local sx, sy, s = self:project(t.x, t.y, 20)
            self.fx:burst(sx, sy - 10 * s, { count = 14, color = { 0.7, 0.9, 1 }, speed = 160, life = 0.3, size = 3 })
            self:addDuo(8)
        elseif result == "dodge" then
            self:popup(t, "Уклон!", { 0.7, 1, 0.7 }, 1.4)
            audio.play("dash")
            t.dodgeT = 0.35
            self:addDuo(4)
        else
            local mult = result == "block" and 0.5 or 1
            local dmg, info = rules.damage(u, t, sk, { mult = mult })
            if result == "block" then
                self:popup(t, "Блок", { 0.6, 0.85, 1 }, 1.2, 30)
                audio.play("stomp", { volume = 0.6 })
            end
            self:hurt(t, dmg, info)
            if result ~= "block" and sk.status then
                self:applyStatus(t, sk.status)
            end
        end
        self:wait(0.12)
    end
    -- every blow parried: a counter-attack
    if parried == #blows and t.hp > 0 and u.hp > 0 then
        self:wait(0.1)
        t.sprite:play("attack", nil, true)
        audio.play("punch")
        self:popup(t, "Контратака!", { 0.6, 0.9, 1 }, 1.1, 50)
        local dmg, info = rules.damage(t, u, { power = 0.8 }, { crit = true })
        self:hurt(u, dmg, info)
        u.p = 0
    end
    self:wait(0.2)
    self:goHome(u)
    self.log = nil
end

function Battle:healAction(u, a)
    local sk = a.skill
    if not self:canPay(u, sk) then
        return
    end
    self:pay(u, sk)
    local t = validTarget(self, u, a.target)
    if u.side == "enemy" then
        t = (a.target and a.target.hp and a.target.hp > 0) and a.target or u
    end
    local quality = 1
    if u.side == "party" and sk.qte then
        local r = self:runQte(qte.bar({ label = sk.name .. ": останови бегунок в центре!" }))
        quality = 0.5 + r.quality * 0.7
    end
    self:healUnit(t, rules.healAmount(u, t, sk, quality), "cast")
end

function Battle:healUnit(target, amount, fxName)
    local before = target.hp
    target.hp = math.min(target.maxHp, target.hp + amount)
    local sx, sy, s = self:project(target.x, target.y, 0)
    self.fx:play(fxName or "shield", sx, sy - 24 * s, { scale = 0.7 * s })
    self:popup(target, "+" .. (target.hp - before), { 0.5, 1, 0.5 }, 1.6)
    audio.play("powerup")
    self:wait(0.55)
end

function Battle:defendAction(u, a)
    u.guarding = true
    if a.skill.restore and u.maxShield > 0 then
        u.shield = math.min(u.maxShield, u.shield + a.skill.restore)
    end
    if u.side == "party" then
        u.bp = math.min(MAX_BP, u.bp + 1)
    end
    local sx, sy, s = self:project(u.x, u.y, 0)
    self.fx:play("shield", sx, sy - 24 * s, { scale = 0.7 * s })
    audio.play("ui_select")
    self:say(u.name .. ": защита", 0.6)
    self.log = nil
end

function Battle:itemAction(u, a)
    local g = G()
    local info = g.items[a.item]
    if not info or not g.state.inventory:has(a.item) then
        return
    end
    g.state.inventory:remove(a.item, 1)
    local t = validTarget(self, u, a.target)
    self:healUnit(t, math.max(1, math.floor((info.heal or 2) * 5 + t.maxHp * 0.05)), "cast")
end

function Battle:buffAction(u, a)
    local sk = a.skill
    if not self:canPay(u, sk) then
        return
    end
    self:pay(u, sk)
    local list = type(a.target) == "table" and a.target.hp == nil and a.target or { a.target or u }
    audio.play("powerup", { pitch = 0.8 })
    self:say(u.name .. ": " .. sk.name, 0.3)
    for _, t in ipairs(self:alive(list)) do
        local sx, sy, s = self:project(t.x, t.y, 0)
        self.fx:play("cast", sx, sy - 24 * s, { scale = 0.6 * s })
        self:applyStatus(t, sk.status)
    end
    self:wait(0.6)
    self.log = nil
end

function Battle:fleeAction(u)
    local g = G()
    if self.def.noFlee then
        self:say("Отсюда не сбежать!", 1.0)
        return
    end
    local function avg(list)
        local s, n = 0, 0
        for _, x in ipairs(self:alive(list)) do
            s, n = s + rules.speedOf(x), n + 1
        end
        return n > 0 and s / n or 0
    end
    local chance = util.clamp(0.45 + (avg(self.party) - avg(self.enemies)) * 0.08, 0.15, 0.9)
    if love.math.random() < chance then
        audio.play("ui_back")
        self:say("Сбежали!", 0.8)
        self.fled = true
    else
        audio.play("ui_error")
        self:say("Не удалось сбежать!", 0.9)
        self.log = nil
    end
end

-- Гриша + the pet together: everybody jumps, the player mashes
function Battle:duoAction(u, a)
    local sk = a.skill
    local members = self:alive(self.party)
    if #members < 2 or self.duo < 100 then
        return
    end
    self.duo = 0
    self:shout(sk.name .. "!", { 1, 0.7, 0.9 }, 1.2)
    audio.play("powerup")
    self.dimTime = 2.6
    self:focus(members[1], members[2], 1.1)
    for _, m in ipairs(members) do
        local sx, sy, s = self:project(m.x, m.y, 0)
        self.fx:play("cast", sx, sy - 24 * s, { scale = 0.8 * s })
    end
    local r = self:runQte(qte.mash({ label = "Дуэт! Жми быстро-быстро!", duration = 2.2 }))
    for _, m in ipairs(members) do
        self.timer:tween(0.25, m, { z = 60 }, "quadOut")
    end
    self:wait(0.3)
    for _, e in ipairs(self:alive(self.enemies)) do
        local sx, sy, s = self:project(e.x, e.y, 0)
        self.fx:play("magic", sx, sy - 24 * s, { scale = 1.0 * s })
        self:strike(members[1], e, sk, { crit = r.result == "perfect", mult = 0.8 + r.quality, dtype = "magic" })
        self:wait(0.15)
    end
    for _, m in ipairs(members) do
        self.timer:tween(0.25, m, { z = 0 }, "quadIn")
    end
    self.flashTime = 0.3
    self:wait(0.6)
end

-- the end ------------------------------------------------------------------------------------

function Battle:ending()
    local g = G()
    local st = g.state
    for _, u in ipairs(self.party) do
        if u.stats then
            u.stats.hp = math.max(1, u.hp)
            u.stats.bp = 1
        end
    end
    self:unfocus()
    if self.fled then
        self:finish({ win = false, fled = true })
        return
    end
    local win = #self:alive(self.enemies) == 0
    if win then
        audio.stopMusic(0.5)
        audio.play("outro")
        self.banner = "Победа!"
        -- loot, coins and experience
        local loot, xp, coins = {}, 0, 0
        for _, e in ipairs(self.enemies) do
            local b = e.mob.battle or {}
            xp = xp + math.floor(rules.xpOf(b) * (1 + (e.level - 1) * 0.15))
            if b.coins then
                coins = coins + love.math.random(b.coins[1], b.coins[2])
            end
            for _, d in ipairs(e.mob.drops or {}) do
                if love.math.random() < (d.chance or 1) then
                    loot[d.item] = (loot[d.item] or 0) + (d.count or 1)
                end
            end
        end
        if coins > 0 then
            loot.coin = (loot.coin or 0) + coins
        end
        local lines = {}
        for id, n in pairs(loot) do
            if st.inventory:add(id, n) then
                table.insert(lines, { icon = (g.items[id] or {}).icon, text = ((g.items[id] or {}).name or id) .. " ×" .. n })
            end
        end
        local rows = {}
        for _, u in ipairs(self.party) do
            local b = u.stats
            local ups = rules.addXp(b, xp, u.growth)
            table.insert(rows, { unit = u, level = b.level, xp = b.xp, need = rules.xpNeeded(b.level), ups = ups })
            if #ups > 0 then
                audio.play("fanfare", { volume = 0.6 })
            end
        end
        self.results = { xp = xp, loot = lines, rows = rows, t = 0 }
        for _, u in ipairs(self:alive(self.party)) do
            u.faceCamera = true
            u.sprite:play("walk", "down")
        end
        self:wait(1.0)
        -- wait for a key (or 4 seconds)
        local t = 0
        while t < 6 do
            coroutine.yield()
            t = t + self.dt
            if t > 0.6 and (input.pressed("confirm") or input.pressed("attack")) then
                break
            end
        end
        self:finish({ win = true, loot = loot, xp = xp })
    else
        audio.stopMusic(0.5)
        audio.play("die")
        self.banner = "Поражение..."
        self.log = "Отряд без сил."
        self:wait(2.4)
        self:finish({ win = false })
    end
end

-- callbacks ------------------------------------------------------------------------------------

function Battle:update(dt)
    Mode.update(self, dt)
    local real = dt
    -- the little freeze on hits and the slow motion of big moments
    if self.hitstop > 0 then
        self.hitstop = self.hitstop - real
        dt = 0
    elseif self.slowmo > 0 then
        self.slowmo = self.slowmo - real
        dt = dt * 0.35
    end
    if input.down("fast") and not self.qteObj and not self.menu and not self.targets then
        dt = dt * (G().battle.fast or 2.5)
    end
    self.dt = dt
    self.qdt = real
    self.clock = self.clock + dt
    self.background:update(dt)
    if self.introT then
        self.introT = self.introT + real / 1.6
        local k = math.min(1, self.introT)
        local e = 1 - (1 - k) ^ 3
        self.angle = util.lerp(-1.3, 0, e)
        self.blend = e
        if k >= 1 then
            self.introT = nil
        end
    elseif self.blend < 1 then
        self.blend = math.min(1, self.blend + real / 0.6)
    end
    -- the camera eases to its focus
    local cam = self.cam
    cam.x = util.damp(cam.x, cam.tx, 5, real)
    cam.y = util.damp(cam.y, cam.ty, 5, real)
    cam.zoom = util.damp(cam.zoom, cam.tzoom, 5, real)
    -- camera controls (not while aiming)
    if self.view ~= "behind" and not self.introT then
        if input.pressed("view") then
            self:setView(self.view == "iso" and "top" or "iso")
            audio.play("ui_move")
        end
        if input.down("camLeft") then
            self.angle = self.angle - real * 1.2
        elseif input.down("camRight") then
            self.angle = self.angle + real * 1.2
        end
    end
    for _, u in ipairs(self.units) do
        u.sprite:update(dt)
        if u.back then
            u.back:update(dt)
        end
        u.flash = math.max(0, u.flash - real)
        u.squash = math.max(0, u.squash - real * 5)
        u.knock = math.max(0, u.knock - real * 4)
        if u.dodgeT then
            u.dodgeT = u.dodgeT - real
            if u.dodgeT <= 0 then
                u.dodgeT = nil
            end
        end
    end
    if self.shoutText then
        self.shoutText.t = self.shoutText.t + real
        if self.shoutText.t >= self.shoutText.life then
            self.shoutText = nil
        end
    end
    self.flashTime = math.max(0, (self.flashTime or 0) - real)
    self.dimTime = math.max(0, (self.dimTime or 0) - real)
    if self.results then
        self.results.t = self.results.t + real
    end
    if self:pausePressed() and not self.menu and not self.targets and not self.finished and not self.qteObj then
        input.consume("pause")
        self:openPause()
        return
    end
    self:tickTimeline(dt)
    if self.hitstop <= 0 and coroutine.status(self.co) ~= "dead" then
        local ok, err = coroutine.resume(self.co)
        if not ok then
            error("battle: " .. tostring(err) .. "\n" .. debug.traceback(self.co), 0)
        end
    end
end

-- drawing --------------------------------------------------------------------------------------

function Battle:drawField()
    local lg = love.graphics
    local cols, rows = math.floor(FIELD_W / CELL), math.floor(FIELD_H / CELL)
    local x0, y0 = -FIELD_W / 2, -FIELD_H / 2
    local corners = {}
    for r = 0, rows do
        corners[r] = {}
        for c = 0, cols do
            local sx, sy = self:project(x0 + c * CELL, y0 + r * CELL, 0)
            corners[r][c] = { sx, sy }
        end
    end
    local tint = self.def.fieldColor or { 0.36, 0.55, 0.26 }
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local a, b, d, e = corners[r][c], corners[r][c + 1], corners[r + 1][c + 1], corners[r + 1][c]
            local k = (r + c) % 2 == 0 and 1 or 0.88
            lg.setColor(tint[1] * k, tint[2] * k, tint[3] * k, 0.92)
            lg.polygon("fill", a[1], a[2], b[1], b[2], d[1], d[2], e[1], e[2])
        end
    end
    lg.setColor(tint[1] * 0.55, tint[2] * 0.55, tint[3] * 0.55, 0.9)
    lg.setLineWidth(2)
    local outline = {}
    for c = 0, cols do table.insert(outline, corners[0][c][1]); table.insert(outline, corners[0][c][2]) end
    for r = 1, rows do table.insert(outline, corners[r][cols][1]); table.insert(outline, corners[r][cols][2]) end
    for c = cols - 1, 0, -1 do table.insert(outline, corners[rows][c][1]); table.insert(outline, corners[rows][c][2]) end
    for r = rows - 1, 1, -1 do table.insert(outline, corners[r][0][1]); table.insert(outline, corners[r][0][2]) end
    lg.polygon("line", outline)
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end

-- directional sprites look where the unit faces as seen from the camera
function Battle:faceCamera(u, sprite)
    if u.faceCamera or not sprite.name then
        return
    end
    local base = sprite.name:match("^(.-)%.%a+$")
    if not base then
        return
    end
    local fx, fy = u.faceX or (u.side == "party" and -1 or 1), u.faceY or 0
    local ax, ay = self:project(u.x, u.y, 0)
    local bx, by = self:project(u.x + fx * 20, u.y + fy * 20, 0)
    local dx, dy = bx - ax, by - ay
    local d
    if math.abs(dx) > math.abs(dy) * 1.1 then
        d = dx < 0 and "left" or "right"
    else
        d = dy < 0 and "up" or "down"
    end
    if sprite.name ~= base .. "." .. d and sprite:has(base, d) then
        local pos = sprite.current and sprite.current.position or 1
        sprite:play(base, d)
        if sprite.current and sprite.current.frames[pos] then
            sprite.current:gotoFrame(pos)
        end
    end
end

local function shieldBadge(x, y, value, broken)
    local lg = love.graphics
    local w, h = 22, 24
    local pts = { x - w / 2, y - h / 2, x + w / 2, y - h / 2, x + w / 2, y + 2, x, y + h / 2, x - w / 2, y + 2 }
    lg.setColor(0.05, 0.05, 0.15, 0.9)
    lg.polygon("fill", pts)
    if broken then
        lg.setColor(0.55, 0.5, 0.5, 1)
    else
        lg.setColor(0.7, 0.8, 1, 1)
    end
    lg.setLineWidth(2)
    lg.polygon("line", pts)
    lg.setLineWidth(1)
    ui.print(broken and "×" or tostring(value), x, y - 11, { font = "small", align = "center", color = broken and "faded" or "ink" })
end

function Battle:drawUnit(u)
    local lg = love.graphics
    local kx, ky = 0, 0
    if u.knock > 0 then
        local d = u.side == "enemy" and -1 or 1
        kx = d * u.knock * 10
    end
    if u.dodgeT then
        ky = -math.sin(u.dodgeT / 0.35 * math.pi) * 12
        kx = kx + (u.side == "party" and 1 or -1) * math.sin(u.dodgeT / 0.35 * math.pi) * 26
    end
    local sx, sy, s = self:project(u.x + kx, u.y, u.z + math.max(0, ky))
    local behind = self.view == "behind" and self.blend > 0.5
    lg.setColor(0, 0, 0, 0.3 * u.alpha)
    local _, groundY = self:project(u.x + kx, u.y, 0)
    lg.ellipse("fill", sx, groundY, 16 * s, 6 * s)
    local sprite, dir = u.sprite, u.side == "party" and "left" or "right"
    if behind and u == self.aimer and u.back then
        sprite = u.back
        sprite:play("idle", "up")
    else
        self:faceCamera(u, sprite)
    end
    local scale = (sprite.scale or 1) * u.scale * s
    local flip = false
    if not (sprite.name or ""):find(".", 1, true) then
        local facesLeft = u.facesLeft == true
        flip = (dir == "right") == facesLeft
    end
    if u.flash > 0 then
        local flash = engine.shaders.get("flash")
        if flash then
            engine.shaders.send(flash, "amount", 1)
            engine.shaders.send(flash, "flashColor", { 1, 1, 1 })
            lg.setShader(flash)
        end
    end
    -- breathing, squash on hits, a wobble when broken
    local breathe = math.sin(self.clock * 3 + u.homeY) * 0.03
    local sq = u.squash * 0.25
    local rot = u.broken and math.sin(self.clock * 6) * 0.12 or 0
    local bob = 0
    if (self.active == u or self.choosing == u) and not behind then
        bob = math.abs(math.sin(self.clock * 6)) * 4
    end
    lg.push()
    lg.translate(sx, sy - bob)
    lg.rotate(rot)
    lg.scale(1 + sq, 1 - sq + breathe)
    local tint = u.broken and { 0.75, 0.75, 0.85, u.alpha } or { 1, 1, 1, u.alpha }
    lg.setColor(tint)
    sprite:draw(0, 0, { scale = scale, flip = flip, color = tint })
    lg.pop()
    lg.setShader()
    if u.guarding then
        lg.setColor(0.6, 0.85, 1, 0.35 + 0.15 * math.sin(self.clock * 5))
        lg.circle("line", sx, sy - 20 * s, 26 * s)
    end
    u.screenX, u.screenY, u.screenScale = sx, sy, s
    lg.setColor(1, 1, 1, 1)
end

-- hp, shield, weaknesses and statuses over an enemy
function Battle:drawEnemyInfo(u)
    if u.hp <= 0 or not u.screenX then
        return
    end
    local lg = love.graphics
    local sx, sy, s = u.screenX, u.screenY, u.screenScale
    local w = 56
    ui.bar(math.floor(sx - w / 2), math.floor(sy + 10), w, 5, u.hp, u.maxHp, "red")
    if u.maxShield > 0 then
        shieldBadge(sx - w / 2 - 14, sy + 12, u.shield, u.broken)
    end
    -- weaknesses: the icons of the types (unknown = "?")
    if u.weak and #u.weak > 0 then
        local n = #u.weak
        local x = sx - (n * 18) / 2 + 9
        for _, wtype in ipairs(u.weak) do
            if u.known[wtype] == "weak" then
                ui.icon(rules.typeIcons[wtype] or "stone", x - 8, sy + 20, 0.5)
            else
                lg.setColor(0.05, 0.05, 0.15, 0.85)
                lg.rectangle("fill", x - 8, sy + 20, 16, 16)
                ui.print("?", x, sy + 19, { font = "small", align = "center", color = "faded" })
            end
            x = x + 18
        end
    end
    self:drawStatuses(u, sx + w / 2 + 6, sy + 6)
    if u.broken then
        ui.print("BREAK", sx, sy - 80 * s, { font = "small", align = "center", color = "gold" })
        -- little stars around the head
        for i = 1, 3 do
            local a = self.clock * 4 + i * 2.1
            lg.setColor(1, 0.9, 0.3, 0.9)
            lg.circle("fill", sx + math.cos(a) * 18 * s, sy - 62 * s + math.sin(a) * 5 * s, 3)
        end
    end
    -- the intent: what and whom
    if u.intent and u.phase == "cast" then
        local text = u.intent.skill.name
        local t = u.intent.target
        if type(t) == "table" and t.name then
            text = text .. " → " .. t.name
        end
        local font = ui.font("small")
        local tw = font:getWidth(text) + 20
        local ix, iy = math.floor(sx - tw / 2), math.floor(sy - 104 * s - 10)
        ui.panel.draw(ix, iy, tw, font:getHeight() + 8, "small")
        ui.print(text, sx, iy + 4, { font = font, align = "center", color = "red" })
        if type(t) == "table" and t.screenX and t.hp and t.hp > 0 then
            lg.setColor(1, 0.35, 0.3, 0.35 + 0.2 * math.sin(self.clock * 8))
            lg.setLineWidth(2)
            lg.line(sx, iy + font:getHeight() + 8, t.screenX, t.screenY - 60 * t.screenScale)
            lg.setLineWidth(1)
        end
    end
    lg.setColor(1, 1, 1, 1)
end

function Battle:drawStatuses(u, x, y)
    local g = G()
    for id, s in pairs(u.status) do
        local def = g.statuses[id]
        if def then
            local font = ui.font("small")
            local w = font:getWidth(def.short) + 8
            love.graphics.setColor(0.05, 0.05, 0.15, 0.85)
            love.graphics.rectangle("fill", x, y, w, 18)
            ui.print(def.short, x + 4, y - 1, { font = font, color = def.color })
            x = x + w + 3
        end
    end
end

function Battle:draw()
    local lg = love.graphics
    local ox, oy = self:shakeOffset(love.timer.getDelta())
    lg.push()
    lg.translate(ox, oy)
    if self.sky then
        self.sky:draw(self:skyYaw(), self:skyPitch(), SKY_FOV)
    else
        self.background:draw(self.angle * 120, 0)
    end
    self:drawField()
    local order = {}
    for _, u in ipairs(self.units) do
        local _, sy = self:project(u.x, u.y, 0)
        u.sortY = sy
        table.insert(order, u)
    end
    table.sort(order, function(a, b) return a.sortY < b.sortY end)
    for _, u in ipairs(order) do
        self:drawUnit(u)
    end
    for _, p in ipairs(self.projectiles) do
        local sx, sy, s = self:project(p.x, p.y, p.z)
        if p.icon then
            local icon = engine.assets.image("assets/sprites/icons/" .. p.icon .. ".png")
            lg.setColor(1, 1, 1, 1)
            lg.draw(icon, sx, sy, self.clock * 10, 0.5 * s, 0.5 * s, icon:getWidth() / 2, icon:getHeight() / 2)
        end
    end
    for _, u in ipairs(self.enemies) do
        self:drawEnemyInfo(u)
    end
    -- the target cursor (all targets at once for "all")
    if self.cursor then
        local list = self.targetAll and self.targets or { self.cursor }
        for _, u in ipairs(list) do
            local sx, sy, s = self:project(u.x, u.y, 0)
            local bob = math.sin(self.clock * 8) * 4
            ui.panel.cursor(sx - 44 * s, sy - 36 * s + bob, ui.theme.cursorScale)
        end
    end
    if self.dimTime and self.dimTime > 0 then
        lg.setColor(0.05, 0, 0.1, math.min(0.45, self.dimTime))
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    self.fx:draw()
    if self.qteObj and self.qteObj.target then
        self.qteObj:draw(self)
    end
    lg.pop()
    if self.flashTime and self.flashTime > 0 then
        lg.setColor(1, 1, 1, self.flashTime * 2)
        lg.rectangle("fill", 0, 0, screen.width, screen.height)
    end
    self:drawHud()
end

-- a small picture of the unit for the timeline
function Battle:drawIcon(u, x, y, r)
    local lg = love.graphics
    lg.setColor(u.side == "party" and { 0.18, 0.3, 0.75 } or { 0.55, 0.16, 0.16 })
    lg.circle("fill", x, y, r)
    lg.setColor(1, 1, 1, u.hp > 0 and 1 or 0.35)
    lg.setLineWidth(2)
    lg.circle("line", x, y, r)
    lg.setLineWidth(1)
    local sprite = u.sprite
    if sprite.current then
        local fh = sprite.frameHeight or 16
        local k = (r * 1.7) / fh
        lg.stencil(function() lg.circle("fill", x, y, r - 1) end, "replace", 1)
        lg.setStencilTest("greater", 0)
        sprite:draw(x, y + r * 0.95, { scale = k, color = { 1, 1, 1, u.hp > 0 and 1 or 0.35 } })
        lg.setStencilTest()
    end
end

function Battle:drawTimeline()
    local lg = love.graphics
    local x0, x1, y = 200, 760, 34
    local W = x1 - x0
    local cx = x0 + W * COM
    ui.panel.draw(x0 - 24, y - 26, W + 48, 52, "small")
    lg.setColor(0.25, 0.45, 0.9, 0.9)
    lg.rectangle("fill", x0, y - 4, cx - x0, 8)
    lg.setColor(0.95, 0.55, 0.2, 0.95)
    lg.rectangle("fill", cx, y - 4, x1 - cx, 8)
    lg.setColor(1, 1, 1, 1)
    lg.rectangle("fill", cx - 1, y - 9, 3, 18)
    lg.rectangle("fill", x1 - 1, y - 9, 3, 18)
    ui.print("ход", cx, y + 8, { font = "small", align = "center", color = "light", alpha = 0.6 })
    -- enemies below the bar, the party above
    local order = {}
    for _, u in ipairs(self.units) do
        if u.hp > 0 then
            table.insert(order, u)
        end
    end
    table.sort(order, function(a, b) return a.p < b.p end)
    for _, u in ipairs(order) do
        local px = x0 + W * math.min(1, u.p)
        local py = u.side == "party" and y - 16 or y + 16
        if u.phase == "cast" and u.side == "enemy" then
            lg.setColor(1, 0.3, 0.25, 0.5 + 0.3 * math.sin(self.clock * 10))
            lg.circle("fill", px, py, 15)
        end
        self:drawIcon(u, px, py, 12)
    end
end

function Battle:drawHud()
    local lg = love.graphics
    local W, H = screen.width, screen.height
    if not self.results then
        self:drawTimeline()
    end
    -- party window: name, hp, brave points, statuses; the duo gauge under it
    local rowH = 40
    local pw, ph = 470, 26 + #self.party * rowH + 30
    local px, py = W - pw - 14, H - ph - 12
    ui.panel.draw(px, py, pw, ph)
    for i, u in ipairs(self.party) do
        local y = py + 12 + (i - 1) * rowH
        local color = u.hp <= 0 and "faded" or ((self.choosing == u or self.active == u) and "accent" or "ink")
        ui.print(u.name, px + 18, y, { font = "body", color = color })
        ui.print("ур." .. (u.stats and u.stats.level or 1), px + 18, y + 26, { font = "tiny", color = "faded" })
        ui.bar(px + 150, y + 10, 140, 10, u.hp, u.maxHp, u.hp / u.maxHp < 0.3 and "red" or "green")
        ui.print(u.hp .. "/" .. u.maxHp, px + 150, y + 20, { font = "small", color = color })
        -- brave points
        for k = 1, MAX_BP do
            local bx, by = px + 310 + (k - 1) * 15, y + 14
            if k <= (u.bp or 0) then
                lg.setColor(1, 0.85, 0.3, 1)
            else
                lg.setColor(0.2, 0.22, 0.4, 1)
            end
            lg.polygon("fill", bx, by - 6, bx + 5, by, bx, by + 6, bx - 5, by)
        end
        self:drawStatuses(u, px + 392, y + 4)
    end
    local dy = py + ph - 28
    ui.print("Дружба", px + 18, dy - 4, { font = "small", color = self.duo >= 100 and "accent" or "faded" })
    ui.bar(px + 120, dy + 2, pw - 140, 8, self.duo, 100, self.duo >= 100 and "gold" or "blue")
    if self.duo >= 100 and math.floor(self.clock * 3) % 2 == 0 then
        ui.print("★ Дуэт готов", px + pw - 20, dy - 18, { font = "small", align = "right", color = "gold" })
    end
    -- command menu + help line
    if self.menu then
        local mw = math.max(230, self.menu:getWidth() + 90)
        local mh = self.menu:getHeight() + 56
        local mx, my = 14, H - mh - 12
        ui.panel.draw(mx, my, mw, mh)
        ui.print(self.menuCaption or "", mx + 20, my + 8, { font = "small", color = "accent" })
        self.menu:draw(mx + 50, my + 36)
        local sel = self.menu:selected()
        local help = sel and (sel.help or (sel.skill and sel.skill.description))
        if help then
            local hw = math.min(W - 28, 900)
            local font = ui.font("small")
            ui.panel.draw(14, 78, hw, font:getHeight() * 2 + 18, "small")
            ui.print(help, 26, 84, { font = font, width = hw - 24 })
        end
    end
    -- info about the target under the cursor
    if self.cursor and not self.targetAll then
        local u = self.cursor
        local font = ui.font("small")
        local lines = { u.name .. "   " .. u.hp .. "/" .. u.maxHp }
        if u.side == "enemy" then
            local weak = {}
            for _, wt in ipairs(u.weak or {}) do
                table.insert(weak, u.known[wt] == "weak" and rules.typeNames[wt] or "?")
            end
            if #weak > 0 then
                table.insert(lines, "Слабости: " .. table.concat(weak, ", "))
            end
            if u.intent then
                table.insert(lines, "Готовит: " .. u.intent.skill.name)
            end
        end
        local w = 360
        ui.panel.draw(W / 2 - w / 2, 78, w, #lines * font:getHeight() + 16, "small")
        for i, line in ipairs(lines) do
            ui.print(line, W / 2, 86 + (i - 1) * font:getHeight(), { font = font, align = "center", color = i == 1 and "accent" or "ink" })
        end
    end
    -- message line
    if self.log and not self.menu then
        local font = ui.font("body")
        local w = font:getWidth(self.log) + 50
        ui.panel.draw((W - w) / 2, 76, w, font:getHeight() + 14)
        ui.print(self.log, W / 2, 82, { font = font, align = "center" })
    end
    -- QTE windows without a target in the world (bars, mash, hold)
    if self.qteObj and not self.qteObj.target then
        self.qteObj:draw(self)
    end
    if self.shoutText then
        local st = self.shoutText
        local k = st.t / st.life
        local s = 1 + (1 - math.min(1, k * 4)) * 0.6
        lg.push()
        lg.translate(W / 2, 200)
        lg.scale(s, s)
        ui.print(st.text, 0, -16, { font = "title", align = "center", color = st.color, alpha = 1 - math.max(0, k - 0.7) / 0.3,
            outline = { 0.1, 0.05, 0.1 } })
        lg.pop()
    end
    if self.banner then
        ui.banner(self.banner, W / 2, 120, 420, { font = "title" })
    end
    if self.results then
        self:drawResults()
    end
    if not self.menu and not self.results then
        ui.print("[" .. input.keyName("view") .. "] вид  [" .. input.keyName("camLeft") .. "/" .. input.keyName("camRight")
            .. "] камера  [" .. input.keyName("fast") .. "] быстрее", 16, H - 30, { font = "small", color = "light", alpha = 0.6 })
    end
end

function Battle:drawResults()
    local r = self.results
    local W = screen.width
    local w, h = 520, 120 + #r.rows * 46 + math.max(1, #r.loot) * 24
    local x, y = (W - w) / 2, 190
    ui.panel.draw(x, y, w, h)
    ui.print("Опыт: +" .. r.xp, x + 24, y + 14, { font = "body", color = "accent" })
    for i, row in ipairs(r.rows) do
        local ry = y + 56 + (i - 1) * 46
        ui.print(row.unit.name .. "   ур. " .. row.level, x + 24, ry, { font = "body" })
        ui.bar(x + 270, ry + 12, 220, 10, row.xp, row.need, "gold")
        if #row.ups > 0 and math.floor(r.t * 3) % 2 == 0 then
            ui.print("Новый уровень!", x + 270, ry - 12, { font = "small", color = "gold" })
        end
    end
    local ly = y + 64 + #r.rows * 46
    ui.print("Добыча:", x + 24, ly, { font = "small", color = "faded" })
    if #r.loot == 0 then
        ui.print("—", x + 130, ly, { font = "small" })
    end
    for i, l in ipairs(r.loot) do
        if l.icon then
            ui.icon(l.icon, x + 130, ly + (i - 1) * 24 - 2, 0.6)
        end
        ui.print(l.text, x + 160, ly + (i - 1) * 24, { font = "small" })
    end
    ui.keyHints(x + w - 20, y + h - 34, { { "confirm", "Дальше" } }, "right")
end

return Battle
