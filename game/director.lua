-- Commands of story scripts. A script is a function(s, ...) and s is a director:
--
--   s:say("bunny", "Привет!")            -- who: id from game.characters, or just s:say("text")
--   s:say("bunny", { "page 1", "page 2" })
--   local n = s:ask("Вы согласны или нет?", { "Да", "Нет" })   -- returns 1 or 2
--   local r = s:play("tetris")           -- mini-game / battle on top, r.win, r.score
--   s:go("island", "swirl")              -- another stage with a transition
--
-- All commands:
--   say(who, text) narrate(text) ask(question, options, who) wait(seconds)
--   go(stage, transition | { transition, spawn })   play(stage, opts) -> result
--   battle(enemies, opts) -> result        tactics(opts) -> result
--   flag(name [, value]) counter(name [, add]) once(name)
--   give(item, n) take(item, n) has(item, n) count(item)
--   heal(n) hurt(n) addPet(id) removePet(id) hasPet(id)
--   unlock(ability) unlocked(ability)
--   sound(name) music(name) stopMusic() toast(text, icon) save()
-- and the commands of the current mode, for example in the novel:
--   bg(name) show(who, { at = "left" }) hide(who) shake() flash() title(text)
-- or in the top-down world: spawn(mob, x, y) teleport(spawn) shake() face(dir)

local audio = require("engine.audio")
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

-- ask("Вопрос?", { "Да", "Нет" }, who) or ask(who, "Вопрос?", { "Да", "Нет" })
function Director:ask(a, b, c)
    local question, options, who
    if type(b) == "table" then
        question, options, who = a, b, c
    else
        who, question, options = a, b, c
    end
    self.runner:ask(game().speaker(who), question, options or { "Да", "Нет" })
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

-- the result of the stage, for scripts that end a mode by hand: s:finish({ win = true })
function Director:finish(result)
    if self.host and self.host.finish then
        self.host:finish(result)
    end
end

return new
