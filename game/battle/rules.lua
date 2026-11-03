-- Numbers of the battle: damage, weaknesses, statuses, experience and levels.
-- Pure functions, so the balance can be tuned (and tested) in one place.

local rules = {}

local function G()
    return require("game")
end

-- damage types -> the icon shown under an enemy (weakness icons are the weapons)
rules.typeIcons = {
    slash = "sword", chop = "axe", thrust = "spear", blunt = "club",
    stone = "stone", bite = "skill_bite", magic = "staff",
}
rules.typeNames = {
    slash = "рубящий", chop = "дробящий топором", thrust = "колющий", blunt = "тупой",
    stone = "камень", bite = "укус", magic = "магия",
}

-- timeline: WAIT 0..COM, CAST COM..1, ACT at 1
rules.COM = 0.72

-- timeline speed per second in the WAIT zone
function rules.waitRate(speed)
    return 0.12 + math.max(0, speed) * 0.034
end

-- the CAST zone is shorter: a "normal" action charges in about 0.7 s
function rules.castRate(speed, cast)
    return (0.22 + math.max(0, speed) * 0.012) * (cast or 1)
end

function rules.statMul(u, stat)
    local m = 1
    for id, s in pairs(u.status or {}) do
        local def = G().statuses[id]
        if def and def[stat] then
            m = m * def[stat]
        end
    end
    return m
end

function rules.speedOf(u)
    return u.speed * rules.statMul(u, "speed")
end

function rules.isWeak(target, dtype)
    if not dtype or not target.weak then
        return false
    end
    for _, w in ipairs(target.weak) do
        if w == dtype then
            return true
        end
    end
    return false
end

-- opts: crit (timing), mult (extra multiplier), pierce (ignore defense)
-- Returns the damage and a table describing it (weak, broken, guarded).
function rules.damage(attacker, target, skill, opts)
    opts = opts or {}
    local atk = attacker.attack * rules.statMul(attacker, "attack")
    local base = atk * (skill.power or 1) * (opts.mult or 1)
    local def = opts.pierce and 0 or target.defense * rules.statMul(target, "defense")
    if target.broken then
        def = 0
    end
    -- smooth formula: never 0, defense matters but never wins completely
    local dmg = base * base / (base + def * 1.2)
    dmg = dmg * (0.92 + love.math.random() * 0.16)
    local info = {}
    if opts.crit then
        dmg = dmg * 1.5
        info.crit = true
    end
    if rules.isWeak(target, opts.dtype) then
        dmg = dmg * 1.3
        info.weak = true
    end
    if target.broken then
        dmg = dmg * 1.6
        info.broken = true
    end
    dmg = dmg * rules.statMul(target, "damage")
    if target.guarding then
        dmg = dmg * 0.5
        info.guarded = true
    end
    return math.max(1, math.floor(dmg + 0.5)), info
end

function rules.healAmount(healer, target, skill, quality)
    local k = skill.heal or 0.3
    return math.max(1, math.floor(target.maxHp * k * (quality or 1) + healer.attack * 0.4 + 0.5))
end

-- experience -----------------------------------------------------------------------

function rules.xpNeeded(level)
    return math.floor(14 * level ^ 1.55 + 0.5)
end

function rules.xpOf(mobBattle)
    return mobBattle.xp or math.floor((mobBattle.hp or 10) * 0.5 + (mobBattle.attack or 3) * 1.5)
end

-- adds xp to battle stats `b` (st.hero or st.pets[id]); returns a list of level-ups
-- { level = 3, gains = { hp = 5, attack = 1, ... } }
function rules.addXp(b, xp, growth)
    growth = growth or { hp = 4, attack = 1, defense = 0.5, speed = 0.15 }
    b.level, b.xp = b.level or 1, (b.xp or 0) + xp
    local ups = {}
    while b.xp >= rules.xpNeeded(b.level) do
        b.xp = b.xp - rules.xpNeeded(b.level)
        b.level = b.level + 1
        local gains = {}
        -- fractional growth piles up, so every few levels the stat goes up by one more
        b.growthAcc = b.growthAcc or {}
        for stat, add in pairs(growth) do
            local acc = (b.growthAcc[stat] or 0) + add
            local whole = math.floor(acc)
            b.growthAcc[stat] = acc - whole
            if whole > 0 then
                gains[stat] = whole
                if stat == "hp" then
                    b.maxHp = (b.maxHp or b.hp) + whole
                    b.hp = b.hp + whole
                else
                    b[stat] = (b[stat] or 0) + whole
                end
            end
        end
        table.insert(ups, { level = b.level, gains = gains })
    end
    return ups
end

return rules
