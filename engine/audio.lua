-- Sounds by NAME. Names, files and settings live in game/data/sounds.lua.
--
--   audio.play("hit")                   -- one shot, copies may overlap
--   audio.play("horn", { volume = 0.5, maxDuration = 2 })
--   audio.music("arcade")               -- crossfades from the current track
--   audio.musicTime()                   -- playback position in seconds (beat sync)
--   audio.step("grass")                 -- random footstep from assets/audio/steps/grass
--
-- Fields of a sound in sounds.lua:
--   file / files    path(s) inside the audio folder, "files" picks a random one
--   volume, pitch   multipliers
--   pitchVariation  random pitch +- (0.05 = 5%), makes repeated sounds less boring
--   maxDuration     cut long samples after N seconds ...
--   fadeOut         ... with a fade of N seconds
--   cooldown        ignore plays that come faster than N seconds

local assets = require("engine.assets")

local audio = {
    master = 1,
    musicVolume = 0.8,
    sfxVolume = 1,
    root = "assets/audio/",
    stepsFolder = "steps/",
}

local sounds, tracks = {}, {}
local prototypes = {} -- path -> static Source (cloned for every play) or false
local limited = {}    -- playing sounds with maxDuration
local lastPlay = {}   -- name -> clock (cooldowns)
local stepFiles, lastStep = {}, {}
local fallback = nil  -- lowercase file name -> path, for sounds missing in sounds.lua
local clock = 0
local current = nil   -- playing music
local fading = {}     -- music that fades out

local EXTENSIONS = { ogg = true, mp3 = true, wav = true, flac = true }

function audio.load(bank)
    sounds = bank.sounds or {}
    tracks = bank.music or {}
    audio.root = bank.root or audio.root
    audio.searchFolders = bank.searchFolders or {}
end

local function prototype(path)
    local p = prototypes[path]
    if p == nil then
        local ok, result = pcall(love.audio.newSource, path, "static")
        if ok then
            p = result
        else
            print("[audio] " .. tostring(result))
            p = false
        end
        prototypes[path] = p
    end
    return p or nil
end

-- "fa" -> "instans/Fa.mp3" when the sound is not described in sounds.lua
local function findFile(name)
    if not fallback then
        fallback = {}
        for _, folder in ipairs(audio.searchFolders) do
            for _, path in ipairs(assets.list(audio.root .. folder, EXTENSIONS)) do
                local file = path:match("([^/]+)%.%w+$"):lower()
                fallback[file] = fallback[file] or path:sub(#audio.root + 1)
            end
        end
    end
    local file = fallback[name:lower()]
    return file and { file = file } or nil
end

function audio.has(name)
    return sounds[name] ~= nil or findFile(name) ~= nil
end

-- Preloads sounds so the first play does not stutter.
function audio.preload(names)
    for _, name in ipairs(names) do
        local def = sounds[name] or findFile(name)
        if def then
            for _, file in ipairs(def.files or { def.file }) do
                prototype(audio.root .. file)
            end
        end
    end
end

-- opts: volume, pitch, maxDuration, fadeOut (override sounds.lua)
function audio.play(name, opts)
    opts = opts or {}
    local def = sounds[name] or findFile(name)
    if not def then
        print("[audio] unknown sound: " .. tostring(name))
        return nil
    end
    if def.cooldown and lastPlay[name] and clock - lastPlay[name] < def.cooldown then
        return nil
    end
    lastPlay[name] = clock
    local file = def.files and def.files[love.math.random(#def.files)] or def.file
    local proto = prototype(audio.root .. file)
    if not proto then
        return nil
    end
    local source = proto:clone()
    local volume = (opts.volume or 1) * (def.volume or 1)
    source:setVolume(volume * audio.sfxVolume * audio.master)
    local pitch = (opts.pitch or 1) * (def.pitch or 1)
    local variation = opts.pitchVariation or def.pitchVariation
    if variation then
        pitch = pitch * (1 + (love.math.random() * 2 - 1) * variation)
    end
    source:setPitch(pitch)
    source:play()
    local maxDuration = opts.maxDuration or def.maxDuration
    if maxDuration then
        table.insert(limited, {
            source = source, volume = volume,
            stopAt = clock + maxDuration, fade = opts.fadeOut or def.fadeOut or 0.3,
        })
    end
    return source
end

-- Footsteps: a random file from <audio root>/steps/<folder>,
-- never the same file twice in a row, with a little pitch variation.
function audio.step(folder, opts)
    opts = opts or {}
    local list = stepFiles[folder]
    if not list then
        list = assets.list(audio.root .. audio.stepsFolder .. folder, EXTENSIONS)
        stepFiles[folder] = list
    end
    if #list == 0 then
        return nil
    end
    local i = love.math.random(#list)
    if i == lastStep[folder] and #list > 1 then
        i = i % #list + 1
    end
    lastStep[folder] = i
    local proto = prototype(list[i])
    if not proto then
        return nil
    end
    local source = proto:clone()
    source:setVolume((opts.volume or 0.5) * audio.sfxVolume * audio.master)
    source:setPitch((opts.pitch or 1) * (1 + (love.math.random() * 2 - 1) * 0.08))
    source:play()
    return source
end

-- music ---------------------------------------------------------------------

-- opts: fade (seconds, default 0.8), volume, pitch, restart
function audio.music(name, opts)
    opts = opts or {}
    if current and current.name == name and not opts.restart then
        return current.source
    end
    local fade = opts.fade or 0.8
    audio.stopMusic(fade)
    if not name then
        return nil
    end
    local def = tracks[name] or { file = name }
    local ok, source = pcall(love.audio.newSource, audio.root .. def.file, "stream")
    if not ok then
        print("[audio] " .. tostring(source))
        return nil
    end
    source:setLooping(def.loop ~= false)
    source:setPitch(opts.pitch or 1)
    current = {
        name = name, def = def, source = source,
        volume = (opts.volume or 1) * (def.volume or 1),
        level = fade > 0 and 0 or 1, fadeIn = fade,
    }
    source:setVolume(current.volume * current.level * audio.musicVolume * audio.master)
    source:play()
    return source
end

function audio.stopMusic(fade)
    if not current then
        return
    end
    if fade and fade > 0 then
        current.fadeOut = fade
        table.insert(fading, current)
    else
        current.source:stop()
    end
    current = nil
end

function audio.musicName()
    return current and current.name
end

-- Info from sounds.lua (bpm, beatOffset...) of the playing track.
function audio.musicInfo()
    return current and current.def or {}
end

function audio.musicTime()
    return current and current.source:tell() or 0
end

function audio.setMusicPitch(pitch)
    if current then
        current.source:setPitch(pitch)
    end
end

function audio.setMusicVolume(volume)
    if current then
        current.volume = volume * (current.def.volume or 1)
    end
end

function audio.pauseMusic()
    if current then
        current.source:pause()
    end
end

function audio.resumeMusic()
    if current and not current.source:isPlaying() then
        current.source:play()
    end
end

function audio.stopAll()
    audio.stopMusic()
    for _, item in ipairs(fading) do
        item.source:stop()
    end
    fading, limited = {}, {}
    love.audio.stop()
end

function audio.update(dt)
    clock = clock + dt
    if current then
        if current.level < 1 then
            current.level = math.min(1, current.level + dt / math.max(current.fadeIn, 1e-3))
        end
        current.source:setVolume(current.volume * current.level * audio.musicVolume * audio.master)
    end
    for i = #fading, 1, -1 do
        local item = fading[i]
        item.level = item.level - dt / item.fadeOut
        if item.level <= 0 then
            item.source:stop()
            table.remove(fading, i)
        else
            item.source:setVolume(item.volume * item.level * audio.musicVolume * audio.master)
        end
    end
    for i = #limited, 1, -1 do
        local item = limited[i]
        if not item.source:isPlaying() or clock >= item.stopAt then
            item.source:stop()
            table.remove(limited, i)
        elseif clock >= item.stopAt - item.fade then
            local k = (item.stopAt - clock) / item.fade
            item.source:setVolume(item.volume * k * audio.sfxVolume * audio.master)
        end
    end
end

return audio
