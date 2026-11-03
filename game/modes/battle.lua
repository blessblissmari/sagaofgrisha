-- Turn-based battle in the style of Final Fantasy with "action commands":
-- press [Space] at the right moment for a critical hit or to block.
--
--   s:battle({ "blob_blue", "slime" })           -- from a script, returns { win = true }
--   game.stage "boss" { kind = "battle", enemies = { "ghost", "ghost" },
--                       background = "forest", music = "arcade" }
--
-- The party: the hero (game.state.hero) + pets (game.state.party).
-- Enemies: names from game/data/mobs.lua (their `battle` stats).
-- Skills: game/data/skills.lua (melee, ranged, heal, defend, item, flee).
--
-- Cameras: [V] top-down <-> isometric, [Q]/[E] rotate. Ranged skills switch
-- to a camera behind the hero to aim (arrows), [Space] throws.
-- Every view is the same 3D-ish field projected differently, so switching
-- views is a smooth blend of two projections.

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

local function G()
    return require("game")
end

local Battle = class(Mode)

local FIELD_W, FIELD_H, CELL = 520, 280, 40
local CX, CY = 480, 250

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
        stats = opts.stats, flash = 0, defending = false, alpha = 1,
        facesLeft = opts.spriteDef.facesLeft,
    }
    u.sprite:play("idle", u.side == "party" and "left" or "right")
    return u
end

function Battle:init(def)
    Mode.init(self, def)
    local g = G()
    local st = g.state
    self.background = Background(g.backgrounds[def.background or "forest"] or g.backgrounds.black)
    self.party, self.enemies, self.units = {}, {}, {}
    -- the hero and the pets
    local hero = st.hero
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
                skills = b.skills, scale = (pet.battleScale or 1.5) })
        end
    end
    local n = #members
    for i, m in ipairs(members) do
        local s = m.stats
        local u = newUnit({
            id = m.id, name = m.name, side = "party", hp = math.max(1, s.hp), maxHp = s.maxHp or s.hp,
            attack = s.attack, defense = s.defense, speed = s.speed, skills = m.skills,
            x = 150 + (i % 2) * 30, y = (i - (n + 1) / 2) * 80, spriteDef = m.spriteDef, back = m.back,
            scale = m.scale, stats = s,
        })
        table.insert(self.party, u)
        table.insert(self.units, u)
    end
    -- the enemies
    local list = def.enemies or { "slime" }
    local m = #list
    for i, kind in ipairs(list) do
        local mob = g.mobs[kind] or error("battle: unknown mob '" .. tostring(kind) .. "'")
        local b = mob.battle or { hp = 10, attack = 3, defense = 0, speed = 4 }
        local u = newUnit({
            id = kind, name = mob.name or kind, side = "enemy", hp = b.hp, attack = b.attack,
            defense = b.defense, speed = b.speed, skills = b.skills,
            x = -150 - (i % 2) * 40, y = (i - (m + 1) / 2) * 80, spriteDef = g.sprite(mob.sprite or kind),
            scale = b.scale or mob.battleScale or 1.6,
        })
        u.mob = mob
        table.insert(self.enemies, u)
        table.insert(self.units, u)
    end
    -- camera: view 1 -> view 2 with blend 0..1
    self.view, self.fromView, self.blend = "iso", "iso", 1
    self.angle, self.targetAngle = 0, 0
    self.aim = nil
    self.log = nil
    self.messages = {}
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
    local tx, ty = 0, 0
    local count = 0
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
    if view == "top" then
        local rx, ry = rotate(x, y, self.angle)
        local k = 1.35
        return CX + rx * k, CY + 10 + ry * k * 0.8 - z * k, k * 0.9, ry
    elseif view == "iso" then
        local rx, ry = rotate(x, y, self.angle)
        local k = 1.15
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

-- coroutine helpers --------------------------------------------------------------

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

function Battle:popup(u, text, color, big)
    local sx, sy, s = self:project(u.x, u.y, 0)
    self.fx:popup(sx, sy - 70 * s, text, { color = color, scale = big and 2 or 1.4, life = 1.1 })
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

-- menus inside the coroutine ---------------------------------------------------------

-- top = true: the main command menu, [Esc] opens the pause menu there
function Battle:chooseMenu(items, caption, top)
    self.menu = ui.Menu(items, { font = ui.font("body") })
    self.menuCaption = caption
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

-- arrows pick one of the units, returns nil on cancel
function Battle:chooseTarget(list, caption)
    local index = 1
    self.targets = list
    self.log = caption
    while true do
        self.cursor = list[index]
        coroutine.yield()
        if input.pressed("left", true) or input.pressed("up", true) then
            index = (index - 2) % #list + 1
            audio.play("ui_move")
        elseif input.pressed("right", true) or input.pressed("down", true) then
            index = index % #list + 1
            audio.play("ui_move")
        elseif input.pressed("confirm") or input.pressed("attack") then
            input.consume("confirm")
            input.consume("attack")
            audio.play("ui_select")
            self.cursor, self.targets = nil, nil
            return list[index]
        elseif input.pressed("cancel") then
            input.consume("cancel")
            audio.play("ui_back")
            self.cursor, self.targets = nil, nil
            return nil
        end
    end
end

-- "action command": a ring closes on the target, press at the right moment.
-- Returns true when pressed in time.
function Battle:timing(u, duration)
    duration = duration or 0.7
    self.ring = { unit = u, t = 0, duration = duration }
    local hit = false
    while self.ring.t < duration + 0.12 do
        coroutine.yield()
        self.ring.t = self.ring.t + self.dt
        if input.pressed("attack") or input.pressed("confirm") then
            input.consume("confirm")
            local diff = math.abs(self.ring.t - duration)
            hit = diff < 0.12
            break
        end
    end
    self.ring = nil
    return hit
end

-- damage -------------------------------------------------------------------------------

function Battle:damage(attacker, target, power, crit)
    local base = attacker.attack * (power or 1) * (0.85 + love.math.random() * 0.3)
    local dmg = math.max(1, math.floor(base - target.defense * 0.7 + 0.5))
    if crit then
        dmg = dmg * 2
    end
    if target.defending then
        dmg = math.max(1, math.floor(dmg / 2))
    end
    return dmg
end

function Battle:hurt(target, dmg, crit)
    target.hp = math.max(0, target.hp - dmg)
    target.flash = 0.2
    local sx, sy, s = self:project(target.x, target.y, 0)
    self.fx:play("slash", sx, sy - 24 * s, { scale = 0.7 * s })
    self:popup(target, "-" .. dmg, crit and { 1, 0.85, 0.2 } or { 1, 0.4, 0.35 }, crit)
    audio.play("hit")
    self.shakeTime, self.shakePower = 0.25, crit and 10 or 5
    if target.hp <= 0 then
        audio.play(target.side == "enemy" and "pop" or "death")
        self.timer:tween(0.5, target, { alpha = target.side == "enemy" and 0 or 0.4 }, "quadIn")
    end
end

-- actions ------------------------------------------------------------------------------

function Battle:moveTo(u, x, y, seconds)
    local dir = x < u.x and "left" or "right"
    u.sprite:play("walk", dir)
    self:tween(seconds or 0.35, u, { x = x, y = y }, "quadOut")
    u.sprite:play("idle", u.side == "party" and "left" or "right")
end

function Battle:melee(u, target, skill)
    local side = u.side == "party" and 1 or -1
    self:moveTo(u, target.x + 46 * side, target.y, 0.3)
    u.sprite:play("hit", u.side == "party" and "left" or "right", true)
    u.sprite:play("attack", nil, true)
    local crit = false
    if u.side == "party" then
        crit = self:timing(target, 0.55)
        if crit then
            audio.play("fa")
            self:popup(target, "КРИТ!", { 1, 0.9, 0.3 }, true)
        end
    else
        -- the player can block an enemy hit with good timing
        local block = self:timing(target, 0.6)
        if block then
            target.defending = true
            self:popup(target, "Блок!", { 0.6, 0.85, 1 })
            audio.play("ui_select")
        end
    end
    audio.play("swing")
    local dmg = self:damage(u, target, skill.power or 1, crit)
    self:hurt(target, dmg, crit)
    if u.side == "enemy" and target.defending and not target.reallyDefending then
        target.defending = false
    end
    self:wait(0.25)
    self:moveTo(u, u.homeX, u.homeY, 0.3)
end

function Battle:ranged(u, skill)
    local g = G()
    if skill.cost and skill.cost.item and not g.state.inventory:has(skill.cost.item) then
        self:say("Нет предмета: " .. ((g.items[skill.cost.item] or {}).name or skill.cost.item), 1.0)
        return false
    end
    local previous = self.view
    self.aimer = u
    self:setView("behind")
    self:wait(0.5)
    -- the aim point moves on its own, arrows steer it
    self.aim = { x = -150, y = 0, t = 0 }
    self.log = "Целься стрелками, [" .. input.keyName("attack") .. "] — бросок!"
    local thrown = false
    while not thrown do
        coroutine.yield()
        local a = self.aim
        a.t = a.t + self.dt
        local cx, cy, fx, fy = self:behindCamera()
        local rx, ry = -fy, fx
        local steer = 0
        if input.down("left") then steer = steer - 1 end
        if input.down("right") then steer = steer + 1 end
        a.offset = (a.offset or 0) + steer * 140 * self.dt
        local sway = math.sin(a.t * 2.4) * 70 + a.offset
        local far = 260 + math.sin(a.t * 1.3) * 40
        a.x = u.homeX + fx * (far - 110) + rx * sway
        a.y = u.homeY + fy * (far - 110) + ry * sway
        a.x = util.clamp(a.x, -FIELD_W / 2, FIELD_W / 2)
        a.y = util.clamp(a.y, -FIELD_H / 2, FIELD_H / 2)
        if input.pressed("attack") or input.pressed("confirm") then
            input.consume("confirm")
            thrown = true
        elseif input.pressed("cancel") then
            input.consume("cancel")
            self.aim = nil
            self:setView(previous)
            self.aimer = nil
            return false
        end
    end
    if skill.cost and skill.cost.item then
        g.state.inventory:remove(skill.cost.item, skill.cost.count or 1)
    end
    audio.play("throw")
    audio.play("viu", { volume = 0.5 })
    -- the stone flies in an arc to the aim point
    local ax, ay = self.aim.x, self.aim.y
    self.aim.locked = true
    self.stone = { x = u.x, y = u.y, z = 30 }
    local sx0, sy0 = u.x, u.y
    local t = 0
    while t < 1 do
        coroutine.yield()
        t = math.min(1, t + self.dt / 0.55)
        self.stone.x = util.lerp(sx0, ax, t)
        self.stone.y = util.lerp(sy0, ay, t)
        self.stone.z = 30 + math.sin(t * math.pi) * 60 - t * 30
    end
    self.stone = nil
    local best, bestD = nil, 34
    for _, e in ipairs(self:alive(self.enemies)) do
        local d = util.distance(e.x, e.y, ax, ay)
        if d < bestD then
            best, bestD = e, d
        end
    end
    self.aim = nil
    if best then
        local crit = bestD < 12
        if crit then
            audio.play("fa")
            self:popup(best, "В яблочко!", { 1, 0.9, 0.3 }, true)
        end
        local sx, sy, s = self:project(best.x, best.y, 0)
        self.fx:play("magic", sx, sy - 24 * s, { scale = 0.6 * s })
        self:hurt(best, self:damage(u, best, (skill.power or 1.5) * (crit and 1.5 or 1), false), crit)
    else
        local sx, sy = self:project(ax, ay, 0)
        self.fx:burst(sx, sy, { count = 10, color = { 0.8, 0.75, 0.65 }, speed = 70, life = 0.4, up = 30, gravity = 200 })
        audio.play("land")
        self.fx:popup(sx, sy - 40, "Мимо!", { color = { 0.85, 0.85, 0.85 }, scale = 1.4 })
    end
    self:wait(0.6)
    self:setView(previous ~= "behind" and previous or "iso")
    self.aimer = nil
    self:wait(0.4)
    return true
end

function Battle:healUnit(u, target, amount, fxName)
    local before = target.hp
    target.hp = math.min(target.maxHp, target.hp + amount)
    local sx, sy, s = self:project(target.x, target.y, 0)
    self.fx:play(fxName or "shield", sx, sy - 24 * s, { scale = 0.7 * s })
    self:popup(target, "+" .. (target.hp - before), { 0.5, 1, 0.5 })
    audio.play("powerup")
    self:wait(0.6)
end

function Battle:useItem(u)
    local g = G()
    local items = {}
    for _, slot in ipairs(g.state.inventory:list()) do
        local info = g.items[slot.id]
        if info and info.heal then
            table.insert(items, { label = info.name .. " x" .. slot.count, id = slot.id })
        end
    end
    if #items == 0 then
        self:say("В сумке нечем лечиться", 1.0)
        return false
    end
    local i = self:chooseMenu(items, "Предмет")
    if not i then
        return false
    end
    local target = self:chooseTarget(self:alive(self.party), "Кого лечим?")
    if not target then
        return false
    end
    local id = items[i].id
    g.state.inventory:remove(id, 1)
    self:healUnit(u, target, (g.items[id].heal or 2) * 4, "cast")
    return true
end

-- turns ----------------------------------------------------------------------------

function Battle:playerTurn(u)
    local g = G()
    while true do
        self.log = "Ход: " .. u.name
        local items = {}
        for _, id in ipairs(u.skills) do
            local sk = g.skills[id]
            if sk then
                local label = sk.name
                if sk.cost and sk.cost.item then
                    label = label .. " (" .. g.state.inventory:count(sk.cost.item) .. ")"
                end
                table.insert(items, { label = label, skill = sk, id = id })
            end
        end
        local i = self:chooseMenu(items, u.name, true)
        local choice = i and items[i]
        if choice then
            local sk = choice.skill
            local done = false
            if sk.kind == "melee" then
                local target = self:chooseTarget(self:alive(self.enemies), "Кого бьём?")
                if target then
                    self.log = nil
                    self:melee(u, target, sk)
                    done = true
                end
            elseif sk.kind == "ranged" then
                done = self:ranged(u, sk)
            elseif sk.kind == "defend" then
                u.defending, u.reallyDefending = true, true
                local sx, sy, s = self:project(u.x, u.y, 0)
                self.fx:play("shield", sx, sy - 24 * s, { scale = 0.7 * s })
                audio.play("ui_select")
                self:say(u.name .. " защищается", 0.7)
                done = true
            elseif sk.kind == "heal" then
                local target = self:chooseTarget(self:alive(self.party), "Кого лечим?")
                if target then
                    self:healUnit(u, target, sk.power or 8, sk.fx)
                    done = true
                end
            elseif sk.kind == "item" then
                done = self:useItem(u)
            elseif sk.kind == "flee" then
                if self.def.noFlee then
                    self:say("Отсюда не сбежать!", 1.0)
                    done = true
                elseif love.math.random() < (sk.chance or 0.5) then
                    audio.play("ui_back")
                    self:say("Сбежали!", 0.8)
                    self.fled = true
                    done = true
                else
                    audio.play("ui_error")
                    self:say("Не удалось сбежать!", 0.9)
                    done = true
                end
            end
            if done then
                return
            end
        end
    end
end

function Battle:enemyTurn(u)
    local targets = self:alive(self.party)
    if #targets == 0 then
        return
    end
    local target = targets[love.math.random(#targets)]
    self.log = u.name .. " атакует!"
    self:wait(0.3)
    self:melee(u, target, { power = 1 })
end

function Battle:isOver()
    return #self:alive(self.enemies) == 0 or #self:alive(self.party) == 0 or self.fled
end

function Battle:loop()
    self:wait(0.4)
    self.log = self.def.intro or (#self.enemies > 1 and "Враги нападают!" or (self.enemies[1].name .. " нападает!"))
    self:wait(1.0)
    local first = self.def.advantage
    if first then
        self.log = "Внезапная атака! Ваш ход первый."
        self:wait(0.9)
    end
    while not self:isOver() do
        local order = {}
        for _, u in ipairs(self.units) do
            if u.hp > 0 then
                table.insert(order, u)
            end
        end
        table.sort(order, function(a, b)
            if first and a.side ~= b.side then
                return a.side == "party"
            end
            if a.speed == b.speed then
                return a.side == "party" and b.side ~= "party"
            end
            return a.speed > b.speed
        end)
        first = false
        for _, u in ipairs(order) do
            if u.hp > 0 and not self:isOver() then
                self.active = u
                if not u.reallyDefending then
                    u.defending = false
                end
                u.reallyDefending = false
                if u.side == "party" then
                    self:playerTurn(u)
                else
                    self:enemyTurn(u)
                end
                self.active = nil
                self:wait(0.2)
            end
        end
    end
    self:ending()
end

function Battle:ending()
    local g = G()
    local st = g.state
    -- remember hp of the party
    for _, u in ipairs(self.party) do
        if u.stats then
            u.stats.hp = math.max(1, u.hp)
        end
    end
    if self.fled then
        self:finish({ win = false, fled = true })
        return
    end
    local win = #self:alive(self.enemies) == 0
    if win then
        audio.stopMusic(0.5)
        audio.play("outro")
        self.banner = "Победа!"
        local loot = {}
        for _, e in ipairs(self.enemies) do
            for _, d in ipairs(e.mob.drops or {}) do
                if love.math.random() < (d.chance or 1) then
                    loot[d.item] = (loot[d.item] or 0) + (d.count or 1)
                end
            end
        end
        local lines = {}
        for id, n in pairs(loot) do
            if st.inventory:add(id, n) then
                table.insert(lines, ((g.items[id] or {}).name or id) .. " x" .. n)
            end
        end
        self.log = #lines > 0 and ("Добыча: " .. table.concat(lines, ", ")) or "Враги повержены!"
        for _, u in ipairs(self:alive(self.party)) do
            u.sprite:play("walk", "down")
        end
        self:wait(2.6)
        self:finish({ win = true, loot = loot })
    else
        audio.stopMusic(0.5)
        audio.play("die")
        self.banner = "Поражение..."
        self.log = "Отряд без сил."
        self:wait(2.4)
        self:finish({ win = false })
    end
end

-- callbacks ------------------------------------------------------------------------

function Battle:update(dt)
    Mode.update(self, dt)
    self.dt = dt
    self.clock = self.clock + dt
    self.background:update(dt)
    if self.blend < 1 then
        self.blend = math.min(1, self.blend + dt / 0.6)
    end
    -- camera controls (not while aiming)
    if self.view ~= "behind" then
        if input.pressed("view") then
            self:setView(self.view == "iso" and "top" or "iso")
            audio.play("ui_move")
        end
        if input.down("camLeft") then
            self.angle = self.angle - dt * 1.2
        elseif input.down("camRight") and not (self.menu or self.targets) then
            self.angle = self.angle + dt * 1.2
        end
    end
    for _, u in ipairs(self.units) do
        u.sprite:update(dt)
        if u.back then
            u.back:update(dt)
        end
        u.flash = math.max(0, u.flash - dt)
    end
    if self:pausePressed() and not self.menu and not self.targets and not self.finished then
        input.consume("pause")
        self:openPause()
        return
    end
    if coroutine.status(self.co) ~= "dead" then
        local ok, err = coroutine.resume(self.co)
        if not ok then
            error("battle: " .. tostring(err) .. "\n" .. debug.traceback(self.co), 0)
        end
    end
end

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
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local a, b, d, e = corners[r][c], corners[r][c + 1], corners[r + 1][c + 1], corners[r + 1][c]
            if (r + c) % 2 == 0 then
                lg.setColor(0.36, 0.55, 0.26, 0.92)
            else
                lg.setColor(0.31, 0.49, 0.22, 0.92)
            end
            lg.polygon("fill", a[1], a[2], b[1], b[2], d[1], d[2], e[1], e[2])
        end
    end
    lg.setColor(0.2, 0.32, 0.14, 0.9)
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

function Battle:drawUnit(u)
    local lg = love.graphics
    local sx, sy, s = self:project(u.x, u.y, u.z)
    local behind = self.view == "behind" and self.blend > 0.5
    -- shadow
    lg.setColor(0, 0, 0, 0.3 * u.alpha)
    lg.ellipse("fill", sx, sy, 16 * s, 6 * s)
    local sprite, dir = u.sprite, u.side == "party" and "left" or "right"
    if behind and u == self.aimer and u.back then
        sprite = u.back
        sprite:play("idle", "up")
    end
    local scale = (sprite.scale or 1) * u.scale * s
    local flip = false
    if not (sprite.name or ""):find(".", 1, true) then
        -- sprites without directions: mirror them to face the other side
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
    local bob = 0
    if self.active == u and not behind then
        bob = math.abs(math.sin(self.clock * 6)) * 4
    end
    lg.setColor(1, 1, 1, u.alpha)
    sprite:draw(sx, sy - bob, { scale = scale, flip = flip, color = { 1, 1, 1, u.alpha } })
    lg.setShader()
    if u.defending then
        lg.setColor(0.6, 0.85, 1, 0.35 + 0.15 * math.sin(self.clock * 5))
        lg.circle("line", sx, sy - 20 * s, 26 * s)
    end
    -- enemy hp bar
    if u.side == "enemy" and u.hp > 0 then
        local w = 50
        ui.bar(math.floor(sx - w / 2), math.floor(sy + 8), w, 5, u.hp, u.maxHp, "red")
    end
    lg.setColor(1, 1, 1, 1)
    u.screenX, u.screenY, u.screenScale = sx, sy, s
end

function Battle:draw()
    local lg = love.graphics
    local ox, oy = self:shakeOffset(love.timer.getDelta())
    lg.push()
    lg.translate(ox, oy)
    self.background:draw(self.angle * 120, 0)
    self:drawField()
    -- aim marker on the ground
    if self.aim then
        local sx, sy, s = self:project(self.aim.x, self.aim.y, 0)
        lg.setColor(1, 0.25, 0.2, 0.9)
        lg.setLineWidth(3)
        lg.ellipse("line", sx, sy, 26 * s, 10 * s)
        lg.line(sx - 34 * s, sy, sx + 34 * s, sy)
        lg.line(sx, sy - 14 * s, sx, sy + 14 * s)
        lg.setLineWidth(1)
    end
    local order = {}
    for _, u in ipairs(self.units) do
        table.insert(order, u)
    end
    for _, u in ipairs(order) do
        local _, sy = self:project(u.x, u.y, 0)
        u.sortY = sy
    end
    table.sort(order, function(a, b) return a.sortY < b.sortY end)
    for _, u in ipairs(order) do
        self:drawUnit(u)
    end
    if self.stone then
        local sx, sy, s = self:project(self.stone.x, self.stone.y, self.stone.z)
        local icon = engine.assets.image("assets/sprites/icons/stone.png")
        lg.setColor(1, 1, 1, 1)
        lg.draw(icon, sx, sy, self.clock * 10, 0.5 * s, 0.5 * s, 17, 17)
    end
    -- timing ring
    if self.ring then
        local u = self.ring.unit
        local sx, sy, s = self:project(u.x, u.y, 0)
        local k = 1 - self.ring.t / self.ring.duration
        local r = 22 * s + math.max(0, k) * 80
        lg.setLineWidth(3)
        lg.setColor(1, 1, 1, 0.5)
        lg.circle("line", sx, sy - 20 * s, 22 * s)
        lg.setColor(1, 0.85, 0.3, 0.95)
        lg.circle("line", sx, sy - 20 * s, r)
        lg.setLineWidth(1)
    end
    -- target cursor
    if self.cursor then
        local u = self.cursor
        local sx, sy, s = self:project(u.x, u.y, 0)
        local arrow = ui.theme.image("next")
        lg.setColor(1, 1, 1, 1)
        lg.draw(arrow, math.floor(sx - 14), math.floor(sy - 80 * s - 30 + math.sin(self.clock * 8) * 4))
    end
    self.fx:draw()
    lg.pop()
    self:drawHud()
end

function Battle:drawHud()
    local lg = love.graphics
    local W, H = screen.width, screen.height
    -- party panel
    local pw, ph = 400, 34 + #self.party * 34
    local px, py = W - pw - 16, H - ph - 14
    ui.panel.draw(px, py, pw, ph)
    for i, u in ipairs(self.party) do
        local y = py + 14 + (i - 1) * 34
        local color = u.hp <= 0 and "faded" or (self.active == u and "accent" or "ink")
        ui.print(u.name, px + 22, y, { font = "body", color = color })
        ui.bar(px + 170, y + 8, 140, 12, u.hp, u.maxHp, u.hp / u.maxHp < 0.3 and "red" or "green")
        ui.print(u.hp .. "/" .. u.maxHp, px + 380, y, { font = "small", align = "right", color = color })
    end
    -- command menu
    if self.menu then
        local mw = math.max(200, self.menu:getWidth() + 80)
        local mh = self.menu:getHeight() + 60
        local mx, my = 16, H - mh - 14
        ui.panel.draw(mx, my, mw, mh)
        ui.print(self.menuCaption or "", mx + 22, my + 12, { font = "small", color = "accent" })
        self.menu:draw(mx + 50, my + 38)
        local sel = self.menu:selected()
        if sel and sel.skill and sel.skill.description then
            ui.print(sel.skill.description, mx + mw + 12, H - 40, { font = "small", color = "light", shadow = true })
        end
    end
    -- message line
    if self.log then
        local font = ui.font("body")
        local w = font:getWidth(self.log) + 50
        ui.panel.draw((W - w) / 2, 16, w, 46)
        ui.print(self.log, W / 2, 26, { font = font, align = "center" })
    end
    if self.banner then
        ui.banner(self.banner, W / 2, 180, 420, { font = "title" })
    end
    local hint = self.view == "behind" and "" or ("[" .. input.keyName("view") .. "] вид   [" .. input.keyName("camLeft") .. "/" .. input.keyName("camRight") .. "] поворот")
    ui.print(hint, 16, 72, { font = "small", color = "light", shadow = true, alpha = 0.75 })
    if self.ring then
        ui.print("Жми [" .. input.keyName("attack") .. "], когда круг сойдётся!", W / 2, 70, { font = "small", align = "center", color = "gold", shadow = true })
    end
end

return Battle
