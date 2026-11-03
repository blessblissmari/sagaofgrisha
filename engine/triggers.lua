-- Trigger zones from the "Triggers" object layer of a Tiled map.
--
-- Every rectangle with a name becomes a zone. Code reacts by name:
--
--   world.triggers:on("test_trigger", {
--       enter = function(zone, who) ... end,
--       leave = function(zone, who) ... end,
--       interact = function(zone, who) ... end,  -- player pressed "interact" inside
--   })
--
-- Custom properties set in Tiled work without any code:
--   dialogue = "bridge"   run game/story/bridge.lua when entered
--   once = true           fire only once
--   interact = true       wait for the interact key instead of firing on enter
--   prompt = "Осмотреть"  hint shown while the player stands inside

local class = require("engine.class")
local util = require("engine.util")

local Triggers = class()

function Triggers:init(objects)
    self.zones = {}
    self.handlers = {}
    self.defaultHandler = nil -- function(zone, who, event), set by the game
    for _, o in ipairs(objects or {}) do
        if o.shape == "rectangle" or o.shape == nil then
            table.insert(self.zones, {
                name = o.name, type = o.type, x = o.x, y = o.y, w = o.width, h = o.height,
                properties = o.properties or {}, inside = false, fired = false, enabled = true,
            })
        end
    end
end

function Triggers:on(name, handlers)
    self.handlers[name] = handlers
end

function Triggers:get(name)
    for _, zone in ipairs(self.zones) do
        if zone.name == name then
            return zone
        end
    end
end

function Triggers:add(name, x, y, w, h, properties)
    local zone = { name = name, x = x, y = y, w = w, h = h, properties = properties or {},
        inside = false, fired = false, enabled = true }
    table.insert(self.zones, zone)
    return zone
end

function Triggers:reset(name)
    for _, zone in ipairs(self.zones) do
        if not name or zone.name == name then
            zone.fired, zone.inside = false, false
        end
    end
end

local function fire(self, zone, event, who)
    if zone.properties.once and zone.fired then
        return
    end
    local h = self.handlers[zone.name]
    local fn = h and h[event]
    if fn then
        zone.fired = true
        fn(zone, who)
    elseif self.defaultHandler then
        if self.defaultHandler(zone, who, event) then
            zone.fired = true
        end
    end
end

-- Call every frame with the entity that activates triggers (the player).
-- interactPressed: the interact key was pressed this frame.
-- Returns the zone the entity stands in that wants a prompt, if any.
function Triggers:update(who, interactPressed)
    local promptZone = nil
    local bx, by, bw, bh = who:getBox()
    for _, zone in ipairs(self.zones) do
        if zone.enabled then
            local inside = util.overlaps(bx, by, bw, bh, zone.x, zone.y, zone.w, zone.h)
            local wantsKey = zone.properties.interact
            if inside and not zone.inside then
                zone.inside = true
                if not wantsKey then
                    fire(self, zone, "enter", who)
                end
            elseif not inside and zone.inside then
                zone.inside = false
                fire(self, zone, "leave", who)
            end
            if inside and wantsKey and not (zone.properties.once and zone.fired) then
                promptZone = zone
                if interactPressed then
                    fire(self, zone, "interact", who)
                end
            end
        end
    end
    return promptZone
end

return Triggers
