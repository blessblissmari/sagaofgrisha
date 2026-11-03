-- Items with counts. What an item IS (name, icon, effect) is described in
-- game/data/items.lua, the inventory only stores ids and numbers.
--
--   local bag = Inventory(require("game.data.items"), 12)
--   bag:add("carrot", 2)
--   bag:has("key")         -- true / false
--   bag:remove("carrot")
--   for _, slot in ipairs(bag:list()) do print(slot.id, slot.count) end

local class = require("engine.class")

local Inventory = class()

function Inventory:init(db, slots)
    self.db = db or {}
    self.slots = slots or 12
    self.items = {}
    self.onChange = nil -- function(id, delta)
end

function Inventory:info(id)
    return self.db[id] or { name = id }
end

function Inventory:find(id)
    for i, slot in ipairs(self.items) do
        if slot.id == id then
            return slot, i
        end
    end
end

-- Returns false when there is no free slot.
function Inventory:add(id, count)
    count = count or 1
    local max = self:info(id).stack or 99
    local slot = self:find(id)
    if slot then
        slot.count = math.min(max, slot.count + count)
    else
        if #self.items >= self.slots then
            return false
        end
        table.insert(self.items, { id = id, count = math.min(max, count) })
    end
    if self.onChange then
        self.onChange(id, count)
    end
    return true
end

function Inventory:remove(id, count)
    count = count or 1
    local slot, index = self:find(id)
    if not slot or slot.count < count then
        return false
    end
    slot.count = slot.count - count
    if slot.count <= 0 then
        table.remove(self.items, index)
    end
    if self.onChange then
        self.onChange(id, -count)
    end
    return true
end

function Inventory:count(id)
    local slot = self:find(id)
    return slot and slot.count or 0
end

function Inventory:has(id, count)
    return self:count(id) >= (count or 1)
end

function Inventory:list()
    return self.items
end

function Inventory:clear()
    self.items = {}
end

function Inventory:serialize()
    local result = {}
    for i, slot in ipairs(self.items) do
        result[i] = { id = slot.id, count = slot.count }
    end
    return result
end

function Inventory:deserialize(list)
    self.items = {}
    for _, slot in ipairs(list or {}) do
        table.insert(self.items, { id = slot.id, count = slot.count })
    end
end

return Inventory
