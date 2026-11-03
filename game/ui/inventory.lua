-- The bag (FF style): tabs Предметы / Оружие / Броня / Ценное, the list of
-- things, what is worn, stats and the party.
--   [←/→] or [Q/E] tabs   [↑/↓] choose   [Enter] use / put on / take off / read
--   [Esc] / [I] close.   The mouse works too.

local engine = require("engine")
local assets = engine.assets
local audio = engine.audio
local class = engine.class
local input = engine.input
local scene = engine.scene
local screen = engine.screen
local ui = engine.ui
local util = engine.util

local function G()
    return require("game")
end

local Bag = class()
Bag.transparent = true

local ROW_H = 46
local VISIBLE = 6

function Bag:init(host, opts)
    opts = opts or {}
    self.host = host
    self.tab = opts.tab or 1
    self.index = {}
    self.scroll = {}
    self.time = 0
    self.rects = {}
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

function Bag:list()
    local g = G()
    local kind = g.kinds[self.tab].id
    local result = {}
    for _, slot in ipairs(g.state.inventory:list()) do
        if g.itemKind(slot.id) == kind then
            table.insert(result, slot)
        end
    end
    return result
end

function Bag:current()
    local list = self:list()
    local i = self.index[self.tab] or 1
    return list[i], list
end

function Bag:sync()
    if self.host and self.host.syncPlayer then
        self.host:syncPlayer()
    end
end

function Bag:use()
    local g = G()
    local slot = self:current()
    if not slot then
        audio.play("ui_error")
        return
    end
    local info = g.items[slot.id] or {}
    local kind = g.itemKind(slot.id)
    if kind == "weapon" or kind == "armor" then
        local where = g.slotOf(slot.id)
        if g.state.equipment[where] == slot.id then
            g.unequip(where)
            audio.play("ui_back")
            ui.toast("Снято: " .. (info.name or slot.id), { icon = info.icon })
        else
            g.equip(slot.id)
            audio.play("unlock")
            ui.toast("Надето: " .. (info.name or slot.id), { icon = info.icon })
        end
        self:sync()
    elseif info.read or info.text then
        self.note = { title = info.name, text = ui.Text((g.notes and g.notes[info.read]) or info.text or tostring(info.read),
            { width = 600, font = ui.font("body") }) }
        audio.play("card_flip")
    elseif info.heal then
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
        self:sync()
    elseif info.use then
        info.use(g, self.host)
    else
        audio.play("ui_error")
    end
end

function Bag:switchTab(d)
    local n = #G().kinds
    self.tab = (self.tab - 1 + d) % n + 1
    audio.play("ui_move")
end

function Bag:update(dt)
    self.time = self.time + dt
    if self.note then
        if input.pressed("confirm") or input.pressed("cancel") or input.pressed("interact") or input.mouse.pressed[1] then
            input.consume("confirm")
            input.consume("cancel")
            input.mouse.pressed[1] = nil
            self.note = nil
            audio.play("ui_back")
        end
        return
    end
    if self.time > 0.1 and (input.pressed("inventory") or input.pressed("cancel") or input.pressed("pause")) then
        input.consume("pause")
        input.consume("cancel")
        self:close()
        return
    end
    if input.pressed("left", true) or input.pressed("camLeft") then
        self:switchTab(-1)
    elseif input.pressed("right", true) or input.pressed("camRight") then
        self:switchTab(1)
    end
    local list = self:list()
    local i = util.clamp(self.index[self.tab] or 1, 1, math.max(1, #list))
    if #list > 0 then
        if input.pressed("up", true) then
            i = (i - 2) % #list + 1
            audio.play("ui_move")
        elseif input.pressed("down", true) then
            i = i % #list + 1
            audio.play("ui_move")
        end
    end
    -- mouse
    local m = input.mouse
    for _, r in ipairs(self.rects) do
        if util.pointInRect(m.x, m.y, r[1], r[2], r[3], r[4]) then
            if r.tab and m.pressed[1] and r.tab ~= self.tab then
                self.tab = r.tab
                audio.play("ui_move")
                m.pressed[1] = nil
                return
            elseif r.row then
                if m.moved and r.row ~= i then
                    i = r.row
                    audio.play("ui_move")
                end
                if m.pressed[1] then
                    m.pressed[1] = nil
                    self.index[self.tab] = r.row
                    self:use()
                    return
                end
            end
        end
    end
    self.index[self.tab] = i
    local scroll = self.scroll[self.tab] or 0
    if i > scroll + VISIBLE then
        scroll = i - VISIBLE
    elseif i <= scroll then
        scroll = i - 1
    end
    self.scroll[self.tab] = scroll
    if input.pressed("confirm") or input.pressed("interact") then
        input.consume("confirm")
        input.consume("interact")
        self:use()
    end
end

local function statLine(label, value, x, y, w, bonus)
    ui.print(label, x, y, { font = "small", color = "faded" })
    local text = tostring(value)
    if bonus and bonus ~= 0 then
        text = text .. (bonus > 0 and "  (+" .. bonus .. ")" or "  (" .. bonus .. ")")
    end
    ui.print(text, x + w, y, { font = "small", align = "right" })
end

function Bag:draw()
    local g = G()
    local st = g.state
    ui.dim(0.55)
    self.rects = {}
    local lg = love.graphics
    -- tabs
    local tabs = g.kinds
    local tx, ty, tw = 40, 22, math.floor(880 / #tabs)
    ui.panel.draw(tx, ty, 880, 58)
    for i, t in ipairs(tabs) do
        local x = tx + (i - 1) * tw
        if i == self.tab then
            ui.panel.draw(x + 8, ty + 8, tw - 16, 42, "active")
        end
        ui.print(t.name, x + tw / 2, ty + 15, { font = "small", align = "center", color = i == self.tab and "accent" or "ink" })
        table.insert(self.rects, { x, ty, tw, 58, tab = i })
    end
    ui.print("Q", tx + 14, ty + 18, { font = "small", color = "faded" })
    ui.print("E", tx + 880 - 24, ty + 18, { font = "small", color = "faded" })
    -- the list
    local lx, ly, lw, lh = 40, 92, 530, VISIBLE * ROW_H + 30
    ui.panel.draw(lx, ly, lw, lh)
    local slot, list = self:current()
    local scroll = self.scroll[self.tab] or 0
    if #list == 0 then
        ui.print("Пусто", lx + lw / 2, ly + lh / 2 - 20, { font = "body", align = "center", color = "faded" })
    end
    for row = 1, VISIBLE do
        local i = row + scroll
        local s = list[i]
        if not s then
            break
        end
        local info = g.items[s.id] or {}
        local y = ly + 15 + (row - 1) * ROW_H
        local selected = i == (self.index[self.tab] or 1)
        if selected then
            lg.setColor(1, 1, 1, 0.1)
            lg.rectangle("fill", lx + 10, y, lw - 20, ROW_H - 2, 4)
            lg.setColor(1, 1, 1, 1)
            ui.panel.cursor(lx + 44 + math.floor(math.abs(math.sin(self.time * 5)) * 4), y + ROW_H / 2)
        end
        ui.icon(info.icon or "coin", lx + 50, y + 5, 1)
        local equipped = g.isEquipped(s.id)
        ui.print(info.name or s.id, lx + 94, y + 1, { font = "body", color = equipped and "accent" or "ink" })
        if equipped then
            ui.print("E", lx + lw - 70, y + 9, { font = "small", color = "accent" })
        end
        if s.count > 1 then
            ui.print("×" .. s.count, lx + lw - 22, y + 9, { font = "small", align = "right" })
        end
        table.insert(self.rects, { lx, y, lw, ROW_H, row = i })
    end
    if scroll > 0 then
        ui.panel.arrow(lx + lw / 2, ly + 8, "up", 10)
    end
    if scroll + VISIBLE < #list then
        ui.panel.arrow(lx + lw / 2, ly + lh - 8, "down", 10)
    end
    -- equipment and stats
    local ex, ey, ew = 582, 92, 338
    ui.panel.draw(ex, ey, ew, lh)
    local y = ey + 12
    for _, where in ipairs(g.equipSlots) do
        local id, info = g.equipped(where)
        ui.print(g.slotNames[where], ex + 18, y + 4, { font = "small", color = "faded" })
        if info then
            ui.icon(info.icon or "coin", ex + 128, y - 2, 0.8)
            ui.print(info.name or id, ex + 162, y + 4, { font = "small" })
        else
            ui.print("—", ex + 162, y + 4, { font = "small", color = "faded" })
        end
        y = y + 32
    end
    y = y + 6
    lg.setColor(1, 1, 1, 0.2)
    lg.rectangle("fill", ex + 16, y, ew - 32, 2)
    lg.setColor(1, 1, 1, 1)
    y = y + 10
    local hero = st.hero or {}
    local w = ew - 36
    statLine("Сердца", st.hp .. "/" .. st.maxHp, ex + 18, y, w)
    statLine("Атака", (hero.attack or 0) + g.bonus("attack"), ex + 18, y + 26, w, g.bonus("attack"))
    statLine("Защита", (hero.defense or 0) + g.bonus("defense"), ex + 18, y + 52, w, g.bonus("defense"))
    local names = {}
    for _, id in ipairs(st.party) do
        table.insert(names, (g.pets[id] or {}).name or id)
    end
    ui.print("Спутники: " .. (#names > 0 and table.concat(names, ", ") or "никого"), ex + 18, y + 80,
        { font = "small", color = "faded" })
    -- description and hints
    local dx, dy, dw, dh = 40, ly + lh + 12, 880, 540 - (ly + lh + 12) - 16
    ui.panel.draw(dx, dy, dw, dh)
    if slot then
        local info = g.items[slot.id] or {}
        ui.print(info.description or "", dx + 22, dy + 14, { font = "small" })
        local kind = g.itemKind(slot.id)
        local action = (kind == "weapon" or kind == "armor") and (g.isEquipped(slot.id) and "Снять" or "Надеть")
            or ((info.read or info.text) and "Читать") or (info.heal and "Съесть") or (info.use and "Использовать")
        self.action = action
    else
        self.action = nil
    end
    local hints = {}
    if self.action then
        table.insert(hints, { "confirm", self.action })
    end
    table.insert(hints, { "cancel", "Закрыть" })
    ui.keyHints(dx + dw - 20, dy + dh - 36, hints, "right")
    -- a letter / note on top
    if self.note then
        ui.dim(0.4)
        local n = self.note
        local nw, nh = 680, n.text:getHeight() + 110
        local nx, ny = (screen.width - nw) / 2, (screen.height - nh) / 2
        ui.panel.draw(nx, ny, nw, nh)
        ui.print(n.title or "", screen.width / 2, ny + 16, { font = "small", align = "center", color = "accent" })
        n.text:draw(nx + 40, ny + 52)
    end
end

return Bag
