-- Synthesized "voices" for dialogue text: every letter makes a short tone,
-- the pitch depends on the letter (like Animal Crossing / Undertale).
-- No sound files needed: the sounds are generated at start.
--
--   voice.say("female", "а")                 -- one blip
--   voice.say({ preset = "male", pitch = 95 }, "о")
--   voice.presets.dragon = { wave = "saw", pitch = 55, noise = 0.4 }  -- or game.voices in story.lua
--
-- Preset fields (all optional):
--   wave     "square" | "saw" | "triangle" | "sine" | "noise"
--   pitch    base frequency, Hz (male ~110, female ~220, kid ~330)
--   spread   how far letters go from the base pitch, semitones
--   length   one blip, seconds       every   one blip per N letters
--   duty     width of the square wave (0.5 = hollow, 0.15 = nasal)
--   soft     0..1 low-pass, rounder sound      noise   0..1 breath / growl
--   vibrato  Hz, vibratoDepth (0.05 = 5%)     glide   pitch change during a blip (-0.15 = falls)
--   ring     ring-modulation ratio (metal / alien voices)   crush  bit-crush levels (robot)
--   volume

local audio = require("engine.audio")
local utf8 = require("utf8")

local voice = {}

voice.presets = {
    male = { wave = "square", pitch = 110, spread = 5, length = 0.075, duty = 0.38, soft = 0.55, glide = -0.08, every = 2, volume = 0.32 },
    female = { wave = "square", pitch = 225, spread = 6, length = 0.065, duty = 0.27, soft = 0.45, glide = 0.04, every = 2, volume = 0.26 },
    kid = { wave = "triangle", pitch = 340, spread = 7, length = 0.05, glide = 0.1, every = 1, volume = 0.3 },
    old = { wave = "square", pitch = 135, spread = 3, length = 0.09, duty = 0.3, soft = 0.6, vibrato = 9, vibratoDepth = 0.045, every = 2, volume = 0.3 },
    monster = { wave = "saw", pitch = 62, spread = 3, length = 0.11, noise = 0.35, soft = 0.3, glide = -0.2, every = 2, volume = 0.38 },
    alien = { wave = "sine", pitch = 620, spread = 12, length = 0.055, ring = 1.73, vibrato = 28, vibratoDepth = 0.12, every = 1, volume = 0.25 },
    robot = { wave = "square", pitch = 175, spread = 0, length = 0.06, duty = 0.5, ring = 0.5, crush = 6, every = 2, volume = 0.22 },
    ghost = { wave = "sine", pitch = 300, spread = 5, length = 0.14, vibrato = 5, vibratoDepth = 0.07, noise = 0.12, soft = 0.7, every = 3, volume = 0.3 },
    animal = { wave = "triangle", pitch = 520, spread = 9, length = 0.045, glide = 0.18, every = 1, volume = 0.26 },
    narrator = { wave = "sine", pitch = 180, spread = 2, length = 0.05, soft = 0.8, every = 3, volume = 0.18 },
    beep = { wave = "square", pitch = 880, spread = 0, length = 0.025, duty = 0.5, every = 2, volume = 0.12 },
}

voice.enabled = true
voice.volume = 1

local RATE = 22050
local STEPS = { 0, 2, 4, 5, 7, 9, 11, 12 } -- a major scale: speech sounds "musical"
local VOWELS = {}
for _, v in ipairs({ "а", "е", "ё", "и", "о", "у", "ы", "э", "ю", "я", "a", "e", "i", "o", "u", "y",
    "А", "Е", "Ё", "И", "О", "У", "Ы", "Э", "Ю", "Я", "A", "E", "I", "O", "U", "Y" }) do
    VOWELS[v] = true
end
local SILENT = { [" "] = true, ["."] = true, [","] = true, ["!"] = true, ["?"] = true, ["-"] = true,
    ["—"] = true, [":"] = true, [";"] = true, ["…"] = true, ["\""] = true, ["«"] = true, ["»"] = true,
    ["("] = true, [")"] = true, ["'"] = true }

local function resolve(spec)
    if type(spec) == "string" then
        return voice.presets[spec] or voice.presets.male, spec
    end
    local base = voice.presets[spec.preset or "male"] or voice.presets.male
    local p = {}
    for k, v in pairs(base) do
        p[k] = v
    end
    for k, v in pairs(spec) do
        p[k] = v
    end
    return p, nil
end

local function synth(p, step, vowel)
    local length = (p.length or 0.06) * (vowel and 1.25 or 0.8)
    local n = math.max(32, math.floor(RATE * length))
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    local freq0 = (p.pitch or 150) * 2 ^ ((STEPS[step] or 0) * (p.spread or 4) / 12 / 12)
    local duty = p.duty or 0.5
    local soft = p.soft or 0
    local noise = p.noise or 0
    local phase, ringPhase, lp, held, holdCount = 0, 0, 0, 0, 0
    local random = love.math.random
    for i = 0, n - 1 do
        local t = i / RATE
        local k = i / n
        local f = freq0 * (1 + (p.glide or 0) * k)
        if p.vibrato then
            f = f * (1 + math.sin(t * p.vibrato * 2 * math.pi) * (p.vibratoDepth or 0.05))
        end
        phase = (phase + f / RATE) % 1
        local s
        local wave = p.wave or "square"
        if wave == "square" then
            s = phase < duty and 1 or -1
        elseif wave == "saw" then
            s = phase * 2 - 1
        elseif wave == "triangle" then
            s = phase < 0.5 and phase * 4 - 1 or 3 - phase * 4
        elseif wave == "noise" then
            s = random() * 2 - 1
        else
            s = math.sin(phase * 2 * math.pi)
        end
        if not vowel then
            noise = math.max(noise, 0.12)
        end
        if noise > 0 then
            s = s * (1 - noise) + (random() * 2 - 1) * noise
        end
        if p.ring then
            ringPhase = (ringPhase + f * p.ring / RATE) % 1
            s = s * math.sin(ringPhase * 2 * math.pi)
        end
        -- one-pole low-pass: softer, more "voice-like"
        lp = lp + (s - lp) * (1 - soft * 0.93)
        s = lp
        if p.crush then
            holdCount = holdCount - 1
            if holdCount <= 0 then
                held = math.floor(s * p.crush + 0.5) / p.crush
                holdCount = 3
            end
            s = held
        end
        -- envelope: quick attack, smooth release
        local env = math.min(1, k * 40) * (1 - k) ^ 1.6
        data:setSample(i, s * env * 0.9)
    end
    return data
end

local cache = {}

local function sourceFor(p, key, step, vowel)
    local id = (key or tostring(p)) .. "#" .. step .. (vowel and "v" or "c")
    local src = cache[id]
    if not src then
        src = love.audio.newSource(synth(p, step, vowel), "static")
        cache[id] = src
    end
    return src
end

-- one blip for the letter `char`; n = number of the letter (for "every")
function voice.say(spec, char, n)
    if not voice.enabled or not spec or SILENT[char] then
        return
    end
    local p, key = resolve(spec)
    local every = p.every or 2
    if n and every > 1 and n % every ~= 1 then
        return
    end
    local ok, code = pcall(utf8.codepoint, char)
    code = ok and code or (char:byte(1) or 0)
    local step = code % #STEPS + 1
    local src = sourceFor(p, key, step, VOWELS[char])
    src:stop()
    src:setVolume((p.volume or 0.3) * voice.volume * (audio.sfxVolume or 1) * (audio.master or 1))
    src:setPitch(1 + (love.math.random() - 0.5) * 0.04)
    src:play()
end

-- a preset by name (with game.voices merged in at start)
function voice.add(name, preset)
    voice.presets[name] = preset
    for id in pairs(cache) do
        if id:sub(1, #name + 1) == name .. "#" then
            cache[id] = nil
        end
    end
end

return voice
