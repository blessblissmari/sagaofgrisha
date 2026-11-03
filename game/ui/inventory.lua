-- The bag: items in slots, description of the selected one, abilities and
-- the party. [Enter] uses a healing item, [Esc] / [I] closes.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui

local function G()
    return require("game")
end

local Bag = class()
Bag.transparent = true

local COLS, ROWS = 8, 3
local SLOT_W, SLOT_H = 75 * 0.8, 83 * 0.8

function Bag:init(host)
    self.host = host
    self.index = 1
    self.time = 0
end

function Bag:enter()
    audio.play("blink")
end

function Bag:close()
    audio.play("ui_back")
    if scene.top() == self then
        scene.pop()
    end
end

function Bag:selectedSlot()
    return G().state.inventory:list()[self.index]
end

function Bag:use()
    local g = G()
    local slot = self:selectedSlot()
    if not slot then
        return
    end
    local info = g.items[slot.id] or {}
    if info.heal then
        local st = g.state
        if st.hp >= st.maxHp then
            ui.toast("Здоровье и так полное")
            audio.play("ui_error")
            return
        end
        g.heal(info.heal)
        st.inventory:remove(slot.id, 1)
        audio.play("powerup")
        ui.toast("Съедено: " .. (info.name or slot.id), { icon = info.icon })
        if self.host and self.host.syncPlayer then
            self.host:syncPlayer()
        end
    elseif info.use then
        info.use(g, self.host)
    else
        audio.play("ui_error")
    end
end

function Bag:update(dt)
    self.time = self.time + dt
    if self.time > 0.1 and (input.pressed("inventory") or input.pressed("cancel") or input.pressed("pause")) then
        input.consume("pause")
        input.consume("cancel")
        self:close()
        return
    end
    local n = COLS * ROWS
    local moved = false
    if input.pressed("left", true) then self.index = self.index - 1; moved = true end
    if input.pressed("right", true) then self.index = self.index + 1; moved = true end
    if input.pressed("up", true) then self.index = self.index - COLS; moved = true end
    if input.pressed("down", true) then self.index = self.index + COLS; moved = true end
    if moved then
        self.index = (self.index - 1) % n + 1
        audio.play("ui_move")
    end
    if input.pressed("confirm") then
        input.consume("confirm")
        self:use()
    end
end

function Bag:draw()
    local g = G()
    local st = g.state
    ui.dim(0.6)
    local w, h = COLS * SLOT_W + 80, ROWS * SLOT_H + 250
    local x, y = math.floor((screen.width - w) / 2), math.floor((screen.height - h) / 2)
    ui.panel.draw(x, y, w, h)
    ui.print("Сумка", screen.width / 2, y + 16, { font = "title", align = "center", color = "accent" })
    local slotImage, selectedImage = ui.theme.image("slot"), ui.theme.image("slotSelected")
    local list = st.inventory:list()
    local gx, gy = x + 40, y + 60
    for i = 1, COLS * ROWS do
        local cx = gx + ((i - 1) % COLS) * SLOT_W
        local cy = gy + math.floor((i - 1) / COLS) * SLOT_H
        love.graphics.draw(i == self.index and selectedImage or slotImage, cx, cy, 0, 0.8, 0.8)
        local slot = list[i]
        if slot then
            local info = g.items[slot.id] or { icon = "coin" }
            local icon = assets.image("assets/sprites/icons/" .. (info.icon or "coin") .. ".png")
            love.graphics.draw(icon, math.floor(cx + SLOT_W / 2 - 17), math.floor(cy + SLOT_H / 2 - 19))
            if slot.count > 1 then
                ui.print(slot.count, cx + SLOT_W - 12, cy + SLOT_H - 26, { font = "small", align = "right", color = "light", shadow = true })
            end
        end
    end
    local slot = list[self.index]
    local ty = gy + ROWS * SLOT_H + 12
    if slot then
        local info = g.items[slot.id] or {}
        ui.print(info.name or slot.id, x + 40, ty, { font = "body", color = "accent" })
        ui.print(info.description or "", x + 40, ty + 30, { font = "small" })
        if info.heal then
            ui.keyHint(x + w - 120, ty, "confirm", "Съесть")
        end
    else
        ui.print("Пусто", x + 40, ty, { font = "body", color = "faded" })
    end
    -- abilities and party
    local ay = ty + 66
    local ax = x + 40
    ui.print("Способности:", ax, ay, { font = "small", color = "faded" })
    ax = ax + 130
    local any = false
    for id, info in pairs(g.items) do
        if info.ability and st.abilities[info.ability] then
            ui.icon(info.icon or "skill_run", ax, ay - 6, 0.75)
            ax = ax + 30
            any = true
        end
    end
    if not any then
        ui.print("пока нет", ax, ay, { font = "small", color = "faded" })
    end
    local py = ay + 34
    ui.print("Спутники:", x + 40, py, { font = "small", color = "faded" })
    local names = {}
    for _, id in ipairs(st.party) do
        table.insert(names, (g.pets[id] or {}).name or id)
    end
    ui.print(#names > 0 and table.concat(names, ", ") or "никого", x + 170, py, { font = "small" })
    ui.keyHint(x + w / 2, y + h - 36, "cancel", "Закрыть")
end

return Bag
