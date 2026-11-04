-- Commands of story scripts. A script is a function(s, ...) and s is a director:
--
--   s:say("bunny", "Привет!")            -- who: id from game.characters, or just s:say("text")
--   s:say("bunny", { "page 1", "page 2" })
--   local n = s:ask("Вы согласны или нет?", { "Да", "Нет" })   -- returns 1 or 2
--   local r = s:play("tetris")           -- mini-game / battle on top, r.win, r.score
--   s:go("island", "swirl")              -- another stage with a transition
--
-- All commands:
--   say(who, text) narrate(text) think([who,] text) ask(question, options, who, opts) wait(seconds)
--   go(stage, transition | { transition, spawn })   play(stage, opts) -> result
--   battle(enemies, opts) -> result        tactics(opts) -> result
--   flag(name [, value]) counter(name [, add]) once(name)
--   give(item, n) take(item, n) has(item, n) count(item)
--   heal(n) hurt(n) addPet(id) removePet(id) hasPet(id)
--   unlock(ability) unlocked(ability)
--   sound(name) music(name) stopMusic() toast(text, icon) save()
-- Storytelling (the journal [N] shows all of it: tasks, decisions, relations, the encyclopedia):
--   remember(who, what [, text]) remembers(who, what)   -- "Кашка запомнит это."
--   like(who, n) affinity(who)                          -- relations: +1 / -1
--   check(talent, difficulty, label) -> ok, sum         -- 2d6 + talent (game/data/talents.lua)
--   talent(id [, add])                                  -- read / raise a talent
--   journal(id, text) journalDone(id)                   -- tasks of the journal
--   learn(group, id, name, text) known(group, id)       -- the encyclopedia: people, places, monsters...
--   choice(id) -> index, answer                         -- what was answered in ask { id = ... }
--   chapter([name]) recap([title])                      -- the chapter; its decisions on one screen
-- Answers of ask can be tables (the number returned is still the place in the list):
--   { "Отдать морковку", requires = "carrot", take = true }  -- grey "(нужно: Морковь)" without it
--   { "Перепрыгнуть", check = { "agility", 9 } }            -- "[Ловкость] Перепрыгнуть 72%", a dice check
--   { "Соврать", flag = "lied", like = { "bunny", -1 }, remember = { "bunny", "lie", "Ты соврал" } }
--   { "Секрет", hidden = not s:flag("knows") }               -- not shown at all
--   local i, ok, late = s:ask("Быстрее!", { "Прыгать", "Ждать" }, nil, { time = 5, default = 2, id = "jump" })
--     ok = the result of the check of the answer, late = the time ran out (the default was taken),
--     id = the decision goes to the journal, s:choice("jump") returns it later
-- and the commands of the current mode, for example in the novel:
--   bg(name) show(who, { at = "left" }) hide(who) shake() flash() title(text)
-- or in the top-down world: spawn(mob, x, y) teleport(spawn) shake() face(dir)

local audio = require("engine.audio")
local scene = require("engine.scene")
local ui = require("engine.ui")

local Director = {}
Director.__index = Director

local function new(script, host, runner)
    local self = { host = host, runner = runner }
    setmetatable(self, {
        __index = function(t, key)
            local v = Director[key]
            if v ~= nil then
                return v
            end
            local h = rawget(t, "host")
            local fn = h and h["cmd_" .. key]
            if fn then
                return function(director, ...)
                    return director:hostCommand(fn, ...)
                end
            end
            return nil
        end,
    })
    self.co = coroutine.create(function(...)
        return script(self, ...)
    end)
    return self
end

local function game()
    return require("game")
end

local function yield()
    return coroutine.yield()
end

-- host commands: nil = go on, number = wait seconds, "wait" = until director:continue()
function Director:hostCommand(fn, ...)
    local result = fn(self.host, self, ...)
    if type(result) == "number" then
        return self:wait(result)
    elseif result == "wait" then
        self.runner:hideBox()
        return yield()
    end
    return result
end

function Director:continue(...)
    self.runner:continue(...)
end

-- dialogue -----------------------------------------------------------------------

function Director:say(who, text)
    if text == nil then
        who, text = nil, who
    end
    self.runner:say(game().speaker(who), text)
    return yield()
end

function Director:narrate(text)
    return self:say(nil, text)
end

-- the text without markup: {accent}, {p}, {@hop}...
local function plain(text)
    return (tostring(text or ""):gsub("{[^{}]*}", ""))
end

local function talentName(id)
    local info = game().talents[id]
    return info and info.name or id
end

-- the label of an answer and whether it can be chosen (see the header)
local function optionView(o)
    local g = game()
    local label = o.label or o[1] or "?"
    local disabled = o.disabled
    if o.requires then
        local item, n = o.requires, 1
        if type(item) == "table" then
            item, n = item[1], item[2] or 1
        end
        if not g.has(item, n) then
            disabled = true
            local info = g.items[item]
            label = label .. " (нужно: " .. (info and info.name or item) .. (n > 1 and " x" .. n or "") .. ")"
        end
    end
    if o.check then
        local t, dc = o.check[1], o.check[2]
        if not label:find("^%[") then
            label = "[" .. talentName(t) .. "] " .. label
        end
        label = label .. "  " .. require("game.ui.check").chance(g.state.talents[t] or 0, dc) .. "%"
    end
    return { label = label, disabled = disabled }
end

-- ask("Вопрос?", options [, who] [, opts]) or ask(who, "Вопрос?", options [, opts])
-- returns the number of the answer, the result of its check, true when the time ran out
function Director:ask(a, b, c, d)
    local question, options, who, opts
    if type(b) == "table" then
        question, options, who, opts = a, b, c, d
        if type(who) == "table" and who.name == nil then
            who, opts = nil, who -- ask("Вопрос?", options, { time = 5 })
        end
    else
        who, question, options, opts = a, b, c, d
    end
    options = options or { "Да", "Нет" }
    opts = opts or {}
    local shown, place = {}, {}
    for i, o in ipairs(options) do
        if type(o) ~= "table" then
            o = { label = o }
        end
        if not o.hidden then
            shown[#shown + 1] = optionView(o)
            place[#shown] = i
        end
    end
    -- never a dead end: when nothing can be chosen, the last answer can
    local any = false
    for _, v in ipairs(shown) do
        any = any or not v.disabled
    end
    if not any and #shown > 0 then
        shown[#shown].disabled = false
    end
    local default
    if opts.time then
        default = #shown
        for k, i in ipairs(place) do
            if i == opts.default then
                default = k
            end
        end
        while default > 1 and shown[default].disabled do
            default = default - 1
        end
    end
    local speaker = game().speaker(who)
    if question then
        game().remember(speaker, question)
    end
    self.runner:ask(speaker, question, shown, { time = opts.time, default = default })
    local k, late = yield()
    local i = place[k] or k
    local o = options[i]
    local chosen = shown[k] and shown[k].label or "?"
    game().remember({ name = "Ответ" }, (late and "(время вышло) " or "") .. chosen, "answer")
    local ok
    if type(o) == "table" then
        if o.take and o.requires then
            local item = o.requires
            if type(item) == "table" then
                self:take(item[1], item[2] or 1)
            else
                self:take(item, 1)
            end
        end
        if o.flag then
            self:flag(o.flag, true)
        end
        if o.like then
            self:like(o.like[1], o.like[2])
        end
        if o.remember then
            self:remember(o.remember[1], o.remember[2], o.remember[3])
        end
    end
    if opts.id then
        self:decide(opts.id, question, o, i, late)
    end
    if type(o) == "table" and o.check then
        local label = plain(o.label or o[1]):gsub("^%[[^%]]*%]%s*", "")
        ok = self:check(o.check[1], o.check[2], o.check.label or label)
    end
    return i, ok, late == true
end

-- the inner voice: s:think("Тут кто-то был...") (the hero) or s:think("bunny", "...")
local thoughts = {}
function Director:think(who, text)
    if text == nil then
        who, text = game().player.speaker or "grisha", who
    end
    local base = game().speaker(who) or {}
    local sp = thoughts[who]
    if not sp or sp.base ~= base then
        sp = { base = base, id = base.id, name = (base.name or "") .. " (про себя)", voice = base.voice,
            speed = base.speed, color = ui.theme.colors.faded }
        thoughts[who] = sp
    end
    if type(text) == "table" then
        local pages = {}
        for k, t in ipairs(text) do
            pages[k] = "{faded}" .. t .. "{/}"
        end
        text = pages
    else
        text = "{faded}" .. text .. "{/}"
    end
    self.runner:say(sp, text)
    return yield()
end

function Director:wait(seconds)
    self.runner:wait(seconds or 1)
    return yield()
end

-- stages -------------------------------------------------------------------------

function Director:go(stage, opts)
    self.runner:hideBox()
    game().go(stage, opts)
    return yield() -- never comes back: the stage is replaced
end

function Director:play(stage, opts)
    self.runner:hideBox()
    game().play(stage, opts, function(result)
        self.runner:continue(result or {})
    end)
    return yield()
end

-- s:battle({ "slime", "slime" }) or s:battle("boss_stage")
function Director:battle(enemies, opts)
    if type(enemies) == "string" then
        return self:play(enemies, opts)
    end
    opts = opts or {}
    opts.enemies = enemies
    opts.transition = opts.transition or "battle"
    return self:play("battle", opts)
end

function Director:tactics(opts)
    opts = opts or {}
    opts.transition = opts.transition or "diamond"
    return self:play("tactics", opts)
end

-- state ---------------------------------------------------------------------------

function Director:flag(name, value)
    local flags = game().state.flags
    if value == nil then
        return flags[name]
    end
    flags[name] = value
    return value
end

function Director:counter(name, add)
    local c = game().state.counters
    c[name] = (c[name] or 0) + (add or 0)
    return c[name]
end

-- true only the first time it is asked
function Director:once(name)
    local flags = game().state.flags
    local key = "once:" .. name
    if flags[key] then
        return false
    end
    flags[key] = true
    return true
end

function Director:give(item, count)
    count = count or 1
    local g = game()
    local info = g.items[item]
    if info and info.ability then
        return self:unlock(info.ability)
    end
    if g.state.inventory:add(item, count) then
        ui.toast("+" .. count .. " " .. (info and info.name or item), { icon = info and info.icon })
        audio.play("pickup")
        return true
    end
    ui.toast("Сумка полна", { color = { 1, 0.5, 0.4 } })
    return false
end

function Director:take(item, count)
    return game().state.inventory:remove(item, count or 1)
end

function Director:has(item, count)
    return game().has(item, count)
end

function Director:count(item)
    return game().state.inventory:count(item)
end

function Director:heal(amount)
    game().heal(amount or 99)
    if self.host and self.host.syncPlayer then
        self.host:syncPlayer()
    end
end

function Director:hurt(amount)
    local st = game().state
    st.hp = math.max(1, st.hp - (amount or 1))
    if self.host and self.host.syncPlayer then
        self.host:syncPlayer()
    end
end

function Director:addPet(id)
    local g = game()
    if g.addPet(id) then
        ui.toast((g.pets[id].name or id) .. " теперь с тобой!", { color = { 0.6, 1, 0.6 } })
        if self.host and self.host.partyChanged then
            self.host:partyChanged()
        end
    end
end

function Director:removePet(id)
    game().removePet(id)
    if self.host and self.host.partyChanged then
        self.host:partyChanged()
    end
end

function Director:hasPet(id)
    for _, p in ipairs(game().state.party) do
        if p == id then
            return true
        end
    end
    return false
end

function Director:unlock(ability)
    local g = game()
    if g.state.abilities[ability] then
        return false
    end
    g.state.abilities[ability] = true
    local info = g.items[ability]
    ui.toast("Новая способность: " .. (info and info.name or ability), { icon = info and info.icon, color = { 1, 0.9, 0.4 } })
    audio.play("powerup")
    return true
end

function Director:unlocked(ability)
    return game().state.abilities[ability] == true
end

-- sound and misc -------------------------------------------------------------------

function Director:sound(name, opts)
    return audio.play(name, opts)
end

function Director:music(name, opts)
    return audio.music(name, opts)
end

function Director:stopMusic(fade)
    audio.stopMusic(fade or 1)
end

function Director:toast(text, icon)
    ui.toast(text, { icon = icon })
end

function Director:random(a, b)
    return love.math.random(a, b)
end

function Director:save()
    game().save()
end

-- storytelling: memory, relations, talents, the journal ------------------------------

local function notice(who, text, color)
    local sp = game().speaker(who)
    ui.toast(text, { side = "right", portrait = sp and sp.portrait, color = color })
end

local function nameOf(who)
    local sp = game().speaker(who)
    return sp and sp.name or tostring(who)
end

-- the character will remember it: s:remember("bunny", "carrot", "Ты отдал ей морковку")
function Director:remember(who, what, text)
    local memory = game().state.memory
    memory[who] = memory[who] or {}
    local first = memory[who][what] == nil
    memory[who][what] = text or true
    if first then
        notice(who, nameOf(who) .. " запомнит это.")
        audio.play("two_tone", { volume = 0.5 })
    end
end

function Director:remembers(who, what)
    local m = game().state.memory[who]
    return m ~= nil and m[what] ~= nil
end

-- relations: s:like("bunny", 1) (or -1); s:like("bunny", 1, "Кашка тронута") with your own notice
function Director:like(who, n, text)
    n = n or 1
    local st = game().state
    st.affinity[who] = (st.affinity[who] or 0) + n
    if n ~= 0 then
        notice(who, text or (nameOf(who) .. (n > 0 and " одобряет" or " не одобряет")), n > 0 and "green" or "red")
        audio.play(n > 0 and "two_tone" or "ui_error", { volume = 0.5 })
    end
    return st.affinity[who]
end

function Director:affinity(who)
    return game().state.affinity[who] or 0
end

-- talents: s:talent("wits") -> 2, s:talent("wits", 1) raises it
function Director:talent(id, add)
    local st = game().state
    if add and add ~= 0 then
        st.talents[id] = (st.talents[id] or 0) + add
        ui.toast(talentName(id) .. (add > 0 and " +" or " ") .. add, { color = add > 0 and "green" or "red" })
        audio.play(add > 0 and "powerup" or "ui_error")
    end
    return st.talents[id] or 0
end

-- a dice check: 2d6 + talent >= difficulty. Two sixes always win, two ones always lose.
function Director:check(talent, difficulty, label)
    self.runner:hideBox()
    local Check = require("game.ui.check")
    scene.push(Check({ talent = talent, dc = difficulty, label = label }, function(ok, sum)
        self.runner:continue(ok, sum)
    end))
    return yield()
end

-- tasks: s:journal("door", "Открыть подземелье") adds or changes, s:journalDone("door") ticks it,
-- s:journal("door") -> { id, text, done, chapter } or nil
function Director:journal(id, text)
    local st = game().state
    for _, e in ipairs(st.journal) do
        if e.id == id then
            if text and text ~= e.text then
                e.text = text
                ui.toast("Дневник: " .. plain(text), { icon = "book" })
            end
            return e
        end
    end
    if not text then
        return nil
    end
    local e = { id = id, text = text, chapter = st.chapter }
    table.insert(st.journal, e)
    ui.toast("Новая запись: " .. plain(text), { icon = "book" })
    audio.play("card_slide")
    return e
end

function Director:journalDone(id)
    local e = self:journal(id)
    if e and not e.done then
        e.done = true
        ui.toast("Выполнено: " .. plain(e.text), { icon = "book", color = "green" })
        audio.play("bonus")
    end
    return e
end

-- the encyclopedia: s:learn("people", "ghost", "Призрак", "Живёт в подземелье.")
-- groups: people, places, monsters, things or your own (fish are added by the fishing)
function Director:learn(group, id, name, text)
    local codex = game().state.codex
    codex[group] = codex[group] or {}
    local first = codex[group][id] == nil
    codex[group][id] = { name = name, text = text }
    if first then
        ui.toast("Энциклопедия: " .. plain(name), { icon = "book" })
    end
end

function Director:known(group, id)
    local codex = game().state.codex
    return codex[group] ~= nil and codex[group][id] ~= nil
end

-- decisions (ask with opts.id): the journal shows them, s:choice(id) -> index, answer
function Director:decide(id, question, option, index, late)
    local st = game().state
    local answer = type(option) == "table" and (option.label or option[1]) or option
    local entry = { id = id, text = plain(question), answer = plain(answer), index = index,
        chapter = st.chapter, late = late or nil }
    for k, e in ipairs(st.choices) do
        if e.id == id then
            st.choices[k] = entry
            return entry
        end
    end
    table.insert(st.choices, entry)
    return entry
end

function Director:choice(id)
    for _, e in ipairs(game().state.choices) do
        if e.id == id then
            return e.index, e.answer
        end
    end
    return nil
end

function Director:chapter(name)
    if name ~= nil then
        game().state.chapter = name
    end
    return game().state.chapter
end

-- the decisions of the chapter on one screen, like at the end of an episode
function Director:recap(title, chapter)
    self.runner:hideBox()
    local Journal = require("game.ui.journal")
    scene.push(Journal.Recap(title, chapter or game().state.chapter, function()
        self.runner:continue()
    end))
    return yield()
end

-- the result of the stage, for scripts that end a mode by hand: s:finish({ win = true })
function Director:finish(result)
    if self.host and self.host.finish then
        self.host:finish(result)
    end
end

return new
