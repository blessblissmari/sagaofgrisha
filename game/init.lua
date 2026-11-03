-- The game API: story.lua describes the whole game with it.
--
--   local game = require("game")
--   game.title = "My game"
--   game.start = "intro"
--   game.stage "intro" { kind = "novel", script = function(s) s:say("Привет!") end, next = "island" }
--
-- The library of things (story.lua can add or change anything):
--   game.sprites, game.characters, game.items, game.mobs, game.pets, game.skills,
--   game.units, game.jokers, game.backgrounds, game.skies, game.sounds, game.surfaces, game.effects
-- Runtime (used by the modes and the script commands):
--   game.go(stage, opts), game.play(stage, opts, onDone), game.finish(mode, result),
--   game.run(script, host, ...), game.state, game.newGame(), game.save(), game.load()

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local scene = engine.scene
local util = engine.util

local config = require("game.config")

local game = {
    title = "Game",
    -- keys: game.controls.common (everywhere) and one keymap per kind of gameplay:
    --   game.controls.topdown.attack = { "space", "j" }
    --   game.controls.raycaster.map = { "m", "tab" }
    config = config,
    controls = config.keymaps,
    start = nil,
    stages = {},
    defaults = { transition = "fade" },
    -- the hero at the start of a new game (story.lua can change it)
    player = {
        name = "Hero", hp = 6, maxHp = 6, slots = 24,
        sprite = "grisha", side = "hero_side",
        items = {}, party = {}, abilities = {},
        equipment = {}, -- { weapon = "sword", body = "tunic" }: put on at the start
        -- battle stats at level 1; growth = added every level
        battle = { hp = 40, attack = 8, defense = 4, speed = 6,
            skills = { "attack", "smash", "skills", "item", "defend", "flee" },
            growth = { hp = 5, attack = 1.1, defense = 0.6, speed = 0.15 } },
        unit = "heroes",
    },
    sprites = require("game.data.sprites"),
    characters = require("game.data.characters"),
    items = require("game.data.items"),
    mobs = require("game.data.mobs"),
    pets = require("game.data.pets"),
    skills = require("game.data.skills"),
    statuses = require("game.data.statuses"),
    -- battle settings (story.lua can change them):
    --   atb     "active": the timeline creeps on (slowly) while you choose; "wait": it stops
    --   timing  windows of the action commands: 1.4 easy, 1 normal, 0.75 hard
    battle = { atb = "active", timing = 1, fast = 2.5 },
    units = require("game.data.units"),
    jokers = require("game.data.jokers"),
    fish = require("game.data.fish"),
    backgrounds = require("game.data.backgrounds"),
    skies = require("game.data.skies"),
    sounds = require("game.data.sounds"),
    surfaces = require("game.data.surfaces"),
    effects = require("game.data.effects"),
    notes = {},  -- texts of letters / notes: items with read = "name" show game.notes[name]
    voices = {}, -- extra voices for characters (see engine/voice.lua)
    -- stage kind -> module with the gameplay
    modes = {
        title = "game.modes.title", novel = "game.modes.novel", topdown = "game.modes.topdown",
        platformer = "game.modes.platformer", raycaster = "game.modes.raycaster",
        battle = "game.modes.battle", tactics = "game.modes.tactics", tetris = "game.modes.tetris",
        puyo = "game.modes.puyo", breakout = "game.modes.breakout", xonix = "game.modes.xonix",
        cards = "game.modes.cards", iso = "game.modes.iso",
        -- mini-games (all of them are built on game/modes/arcade.lua)
        snake = "game.modes.snake", match3 = "game.modes.match3", memory = "game.modes.memory",
        fishing = "game.modes.fishing", rhythm = "game.modes.rhythm", shmup = "game.modes.shmup",
        lockpick = "game.modes.lockpick", dice = "game.modes.dice", racing = "game.modes.racing",
    },
}

game.controls.common = config.keys

-- story.lua helpers --------------------------------------------------------------

-- game.stage("name", def) or game.stage "name" { ... }
function game.stage(name, def)
    if def == nil then
        return function(d) return game.stage(name, d) end
    end
    def.name = name
    game.stages[name] = def
    return def
end

-- A sprite sheet: game.sheet("assets/sprites/cat.png", 32, 32, { idle = { "1-4", 1, 0.2 } }, { scale = 2 })
function game.sheet(image, frameWidth, frameHeight, animations, opts)
    local def = { image = image, frame = { frameWidth, frameHeight or frameWidth }, animations = animations }
    for k, v in pairs(opts or {}) do
        def[k] = v
    end
    def.default = def.default or next(animations)
    return def
end

-- A picture for portraits / novel figures: a whole image or a frame of a sheet.
function game.picture(image, x, y, w, h, scale)
    return { image = image, x = x, y = y, w = w, h = h, scale = scale }
end

function game.sprite(name)
    if type(name) == "table" then
        return name
    end
    local def = game.sprites[name]
    if not def then
        error("unknown sprite '" .. tostring(name) .. "' (add it to game.sprites)", 2)
    end
    return def
end

-- picture description -> { image, quad, scale } for the dialogue box and the novel
local pictures = setmetatable({}, { __mode = "k" })
function game.resolvePicture(p)
    if not p then
        return nil
    end
    if type(p) == "string" then
        p = { image = p }
    end
    if p.quad then
        return p
    end
    if pictures[p] then
        return pictures[p]
    end
    local image = assets.image(p.image, p.colorKey and { colorKey = p.colorKey })
    local x, y = p.x or 0, p.y or 0
    local w, h = p.w or image:getWidth(), p.h or image:getHeight()
    local r = { image = image, quad = assets.quad(image, x, y, w, h), scale = p.scale, w = w, h = h }
    pictures[p] = r
    return r
end

local speakers = {}
function game.speaker(who)
    if who == nil then
        return nil
    end
    if type(who) == "table" then
        return who
    end
    local c = game.characters[who]
    if not c then
        return { name = tostring(who) }
    end
    local s = speakers[who]
    if not s or s.source ~= c then
        s = {
            source = c, id = who, name = c.name or who, voice = c.voice, speed = c.speed,
            color = type(c.color) == "string" and util.hexColor(c.color) or c.color,
            portrait = game.resolvePicture(c.portrait),
            figure = game.resolvePicture(c.figure or c.portrait),
        }
        speakers[who] = s
    end
    return s
end

-- state ----------------------------------------------------------------------------

local Inventory = engine.Inventory
local save = engine.save

function game.newGame()
    local p = game.player
    local st = {
        hp = p.hp, maxHp = p.maxHp or p.hp,
        inventory = Inventory(game.items, p.slots or 24),
        flags = {}, counters = {}, abilities = {}, party = {}, pets = {},
        collected = {}, defeated = {}, equipment = {}, quests = {},
        codex = {},   -- collections: codex.fish[id] = { count, best }, codex.people[id] = true...
        journal = {}, -- the story so far: { text, chapter }, see s:journal()
        memory = {},  -- what the characters remember: memory[who][what] = true (s:remember)
        affinity = {}, -- how much the characters like the hero: affinity[who] = number
        hero = util.deepCopy(p.battle),
    }
    st.hero.maxHp = st.hero.hp
    st.hero.level, st.hero.xp = p.level or 1, 0
    st.hero.bp = 1
    game.state = st
    for id, n in pairs(p.items or {}) do
        st.inventory:add(id, n)
    end
    for _, a in ipairs(p.abilities or {}) do
        st.abilities[a] = true
    end
    for _, id in ipairs(p.party or {}) do
        game.addPet(id)
    end
    for _, id in pairs(p.equipment or {}) do
        game.equip(id)
    end
    -- an equipped thing that leaves the bag is taken off
    st.inventory.onChange = function(id, delta)
        if delta < 0 and not st.inventory:has(id) then
            for slot, eq in pairs(st.equipment) do
                if eq == id then
                    st.equipment[slot] = nil
                end
            end
        end
    end
    return st
end

-- equipment -------------------------------------------------------------------------
-- items.lua: kind = "weapon" | "armor" | "item" | "key"; slot = "weapon" | "body" |
-- "head" | "feet" | "accessory"; bonuses: attack, defense, speed

game.equipSlots = { "weapon", "body", "head", "feet", "accessory" }
game.slotNames = { weapon = "Оружие", body = "Тело", head = "Голова", feet = "Ноги", accessory = "Аксессуар" }
game.kinds = {
    { id = "item", name = "Предметы" }, { id = "weapon", name = "Оружие" },
    { id = "armor", name = "Броня" }, { id = "key", name = "Ценное" },
}

function game.itemKind(id)
    local info = game.items[id] or {}
    if info.kind then
        return info.kind
    elseif info.slot == "weapon" then
        return "weapon"
    elseif info.slot then
        return "armor"
    elseif info.quest then
        return "key"
    end
    return "item"
end

-- How an item is picked up from the ground:
--   "auto"  just walk over it (coins, food, stones...) - it even flies to the hero
--   "press" stand next to it and press [E] (weapons, armor, keys, letters, abilities)
-- items.lua: pickup = "auto" | "press"; a map object can override it (property pickup).
function game.pickupMode(id, override)
    if override == "auto" or override == "press" then
        return override
    end
    local info = game.items[id]
    if not info then
        return "auto"
    end
    if info.pickup then
        return info.pickup
    end
    local kind = info.kind or "item"
    if kind == "weapon" or kind == "armor" or kind == "key" or info.read then
        return "press"
    end
    return "auto"
end

function game.slotOf(id)
    local info = game.items[id] or {}
    return info.slot or (game.itemKind(id) == "weapon" and "weapon" or (game.itemKind(id) == "armor" and "body" or nil))
end

-- puts on a weapon / armor from the bag (adds it to the bag if needed)
function game.equip(id)
    local st = game.state
    local slot = game.slotOf(id)
    if not slot then
        return false
    end
    if not st.inventory:has(id) then
        st.inventory:add(id, 1)
    end
    st.equipment[slot] = id
    return true
end

function game.unequip(slot)
    game.state.equipment[slot] = nil
end

function game.equipped(slot)
    local id = game.state and game.state.equipment[slot]
    return id, id and game.items[id]
end

function game.isEquipped(id)
    for _, eq in pairs(game.state.equipment) do
        if eq == id then
            return true
        end
    end
    return false
end

-- the weapon in hand (or bare fists: game.items.fists)
function game.weapon()
    local id, info = game.equipped("weapon")
    if info then
        return info, id
    end
    return game.items.fists or { name = "Кулаки", icon = "fist", attack = 0 }, "fists"
end

-- sum of a bonus over everything worn: game.bonus("attack")
function game.bonus(stat)
    local total = 0
    for _, id in pairs(game.state and game.state.equipment or {}) do
        local info = game.items[id]
        total = total + (info and tonumber(info[stat]) or 0)
    end
    return total
end

function game.addPet(id)
    local st = game.state
    if not game.pets[id] then
        error("unknown pet '" .. tostring(id) .. "' (add it to game.pets)", 2)
    end
    if util.find(st.party, id) then
        return false
    end
    table.insert(st.party, id)
    if not st.pets[id] then
        local b = util.deepCopy(game.pets[id].battle or { hp = 10, attack = 3, defense = 1, speed = 5, skills = { "attack" } })
        b.maxHp = b.hp
        b.level, b.xp = b.level or 1, 0
        st.pets[id] = b
    end
    return true
end

function game.removePet(id)
    util.removeValue(game.state.party, id)
end

-- "item" or "ability" names for Gate / Trigger requirements
function game.has(thing, count)
    local st = game.state
    if st.abilities[thing] then
        return true
    end
    return st.inventory:has(thing, count or 1)
end

function game.heal(amount)
    local st = game.state
    st.hp = math.min(st.maxHp, st.hp + amount)
end

game.records = save.read("records", {})

function game.saveRecords()
    save.write("records", game.records)
end

function game.record(name, value)
    if value and value > (game.records[name] or 0) then
        game.records[name] = value
        game.saveRecords()
        return true
    end
    return false
end

-- volume settings survive restarts
function game.saveSettings()
    save.write("settings", { music = audio.musicVolume, sfx = audio.sfxVolume })
end

function game.loadSettings()
    local s = save.read("settings")
    if s then
        audio.musicVolume = s.music or audio.musicVolume
        audio.sfxVolume = s.sfx or audio.sfxVolume
    end
end

-- The main menu stage: the first stage of kind "title", or game.start.
function game.menuStage()
    if game.menu then
        return game.menu
    end
    for name, def in pairs(game.stages) do
        if def.kind == "title" then
            return name
        end
    end
    return game.start
end

-- save game: the stage where the player is + everything in game.state
function game.save()
    local st = game.state
    local data = {
        stage = st.stage, spawn = st.spawn,
        hp = st.hp, maxHp = st.maxHp, inventory = st.inventory:serialize(),
        flags = st.flags, counters = st.counters, abilities = st.abilities,
        party = st.party, pets = st.pets, collected = st.collected, defeated = st.defeated,
        hero = st.hero, equipment = st.equipment, quests = st.quests,
        codex = st.codex, journal = st.journal, memory = st.memory, affinity = st.affinity,
    }
    save.write("savegame", data)
end

function game.hasSave()
    return save.exists("savegame")
end

function game.load()
    local data = save.read("savegame")
    if not data or not data.stage or not game.stages[data.stage] then
        return false
    end
    local st = game.newGame()
    for k, v in pairs(data) do
        if k ~= "inventory" then
            st[k] = v
        end
    end
    st.equipment = data.equipment or {}
    st.quests = data.quests or {}
    local onChange = st.inventory.onChange
    st.inventory.onChange = nil
    st.inventory:clear()
    st.inventory:deserialize(data.inventory or {})
    st.inventory.onChange = onChange
    game.go(data.stage, { spawn = data.spawn })
    return true
end

-- stages ---------------------------------------------------------------------------

function game.resolve(name)
    if type(name) == "table" then
        return name
    end
    local def = game.stages[name]
    if def then
        return def
    end
    if game.modes[name] then
        return { kind = name, name = name }
    end
    error("unknown stage '" .. tostring(name) .. "'", 3)
end

function game.create(def, extra)
    local d = {}
    for k, v in pairs(def) do
        d[k] = v
    end
    for k, v in pairs(extra or {}) do
        d[k] = v
    end
    local path = game.modes[d.kind]
    if not path then
        error("stage '" .. tostring(d.name) .. "': unknown kind '" .. tostring(d.kind) .. "'", 0)
    end
    local Mode = require(path)
    return Mode(d)
end

local function options(opts)
    if type(opts) == "string" then
        return { transition = opts }
    end
    return opts or {}
end

-- Switch to another stage (everything else is closed).
function game.go(name, opts)
    opts = options(opts)
    local def = game.resolve(name)
    local kind = opts.transition or def.transition or game.defaults.transition
    scene.transition(function()
        engine.ui.clearToasts()
        if game.state and game.stages[def.name] and def.kind ~= "title" then
            game.state.stage, game.state.spawn = def.name, opts.spawn
        end
        scene.clear(game.create(def, opts))
        if game.state and def.save ~= false and (def.kind == "topdown" or def.kind == "platformer" or def.kind == "raycaster") then
            game.save()
        end
    end, kind, opts)
end

-- Open a stage on top of the current one; onDone(result) after it finishes.
function game.play(name, opts, onDone)
    opts = options(opts)
    local def = game.resolve(name)
    local kind = opts.transition or def.transition or game.defaults.transition
    local previousMusic = audio.musicName()
    scene.transition(function()
        local mode = game.create(def, opts)
        mode.onFinish = function(result)
            scene.transition(function()
                -- close the mode and whatever its scripts opened on top of it
                while #scene.stack > 1 and scene.top() ~= mode do
                    scene.pop()
                end
                scene.pop()
                local top = scene.top()
                if previousMusic and audio.musicName() ~= previousMusic then
                    audio.music(previousMusic)
                end
                if top and top.returned then
                    top:returned(result)
                end
                if onDone then
                    onDone(result)
                end
            end, opts.back or kind, opts)
        end
        scene.push(mode)
    end, kind, opts)
end

local function nextStage(def, result)
    local n = def.next
    if type(n) == "table" then
        n = (result and result.win == false) and (n.lose or n.win) or (n.win or n.lose)
    end
    return n
end

-- Called by a mode when it is over (won, lost, the novel ended...).
function game.finish(mode, result)
    result = result or {}
    if mode.finished then
        return
    end
    mode.finished = true
    if mode.onFinish then
        return mode.onFinish(result)
    end
    local def = mode.def
    local function after()
        if not scene.has(mode) then
            return
        end
        if scene.isTransitioning() then
            engine.timer.after(0.1, after) -- try again when the screen is clear
            return
        end
        local n = nextStage(def, result) or game.start
        game.go(n)
    end
    if def.done then
        game.run(def.done, mode, { result }, after)
    else
        after()
    end
end

-- Run a story script on top of a mode: script(s, ...) with s = director.
function game.run(script, host, args, onDone)
    local Runner = require("game.runner")
    local runner = Runner(script, host, args or {}, onDone)
    scene.push(runner)
    return runner
end

-- dialogue lines from Tiled properties: "Табличка: Привет|Ещё строка"
function game.linesScript(text)
    return function(s)
        for line in (text .. "|"):gsub("\\n", "|"):gmatch("(.-)|") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local who, rest = line:match("^([^:]+):%s*(.+)$")
                local speaker = nil
                if who then
                    for id, c in pairs(game.characters) do
                        if id == who or c.name == who then
                            speaker = id
                        end
                    end
                end
                if speaker then
                    s:say(speaker, rest)
                else
                    s:say(line)
                end
            end
        end
    end
end

-- What a trigger zone does: story handler, then Tiled properties.
function game.trigger(mode, zone, event, who)
    local def = mode.def
    local p = zone.properties or {}
    local handler = def.triggers and def.triggers[zone.name]
    if p.requires and p.requires ~= "" and not game.has(p.requires) then
        local info = game.items[p.requires]
        engine.ui.toast("Нужно: " .. (info and info.name or p.requires), { icon = info and info.icon })
        audio.play("error")
        return false
    end
    if p.sound and p.sound ~= "" then
        audio.play(p.sound)
    end
    if type(handler) == "function" then
        game.run(handler, mode, { zone, event, who })
        return true
    elseif type(handler) == "string" then
        game.go(handler, { transition = p.transition ~= "" and p.transition or nil })
        return true
    elseif type(handler) == "table" then
        game.go(handler.go or handler[1], handler)
        return true
    end
    if p.dialogue and p.dialogue ~= "" then
        game.run(game.linesScript(p.dialogue), mode)
        return true
    end
    if p.finish then
        mode:finish({ win = true, zone = zone.name })
        return true
    end
    if p.go and p.go ~= "" then
        game.go(p.go, { transition = p.transition ~= "" and p.transition or nil, spawn = p.spawn ~= "" and p.spawn or nil })
        return true
    end
    return false
end

-- boot -------------------------------------------------------------------------------

function game.boot(config)
    config.sounds = game.sounds
    config.characters = {}
    config.effects = game.effects
    -- the look of the UI: game.ui = "ff" | "parchment" | { preset = "ff", ... }
    engine.ui.theme.use(game.ui or "ff")
    for name, preset in pairs(game.voices or {}) do
        engine.voice.add(name, preset)
    end
    engine.load(config)
    game.loadSettings()
    love.window.setTitle(game.title)
    game.newGame()
    local start = game.start
    -- love . --tiled (rewrite the Tiled project and templates), love . --map=file.tmx
    local fromTiled = require("game.tiled").command(arg)
    if fromTiled == false then
        return
    end
    for _, a in ipairs(arg or {}) do
        local s = a:match("^%-%-stage=(.+)$")
        if s then
            start = s
        end
    end
    start = fromTiled or start
    assert(start and game.stages[start] or game.modes[start], "story.lua: set game.start to the first stage")
    local def = game.resolve(start)
    scene.clear(game.create(def))
end

return game
