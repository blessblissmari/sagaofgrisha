-- Main menu: parallax background, the game title and a menu.
--
--   game.stage "menu" {
--       kind = "title", background = "mountains", music = "calm",
--       subtitle = "демо движка",
--       newGame = "prologue",                  -- where "Новая игра" leads
--       menu = {                               -- extra items (optional)
--           { "Мини-игры", list = {            -- a sub-menu
--               { "Тетрис", play = "tetris_free" },  -- opened on top, back to the menu after
--               { "Остров", go = "island" },          -- switch to a stage
--           } },
--       },
--   }

local engine = require("engine")
local audio = engine.audio
local class = engine.class
local input = engine.input
local screen = engine.screen
local ui = engine.ui
local util = engine.util
local Background = engine.Background
local Mode = require("game.modes.base")

local function G()
    return require("game")
end

local Title = class(Mode)

function Title:init(def)
    Mode.init(self, def)
    local g = G()
    local bg = def.background or "mountains"
    self.background = Background(type(bg) == "table" and bg or g.backgrounds[bg] or g.backgrounds.black)
    self.stack = {}
    self:setMenu(self:mainItems())
end

function Title:enter()
    Mode.enter(self)
end

local function entry(self, item)
    local label = item.label or item[1]
    local e = { label = label, disabled = item.disabled }
    if item.list then
        e.action = function()
            local items = {}
            for _, sub in ipairs(item.list) do
                table.insert(items, entry(self, sub))
            end
            table.insert(items, { label = "Назад", action = function() self:back() end })
            self:pushMenu(items, label)
        end
    elseif item.play then
        e.action = function()
            G().play(item.play, item.opts or item.transition)
        end
        local rec = item.record or (type(item.play) == "string" and item.play)
        if rec and G().records[rec] then
            e.label = label .. "  (" .. G().records[rec] .. ")"
        end
    elseif item.go then
        e.action = function()
            G().newGame()
            G().go(item.go, item.opts or item.transition)
        end
    elseif item.action then
        e.action = function() item.action(self) end
    end
    return e
end

function Title:mainItems()
    local g = G()
    local def = self.def
    local items = {
        { label = "Новая игра", action = function()
            g.newGame()
            g.go(def.newGame or def.next or g.start, def.newGameTransition)
        end },
        { label = "Продолжить", disabled = function() return not g.hasSave() end,
            action = function() g.load() end },
    }
    for _, item in ipairs(def.menu or {}) do
        table.insert(items, entry(self, item))
    end
    table.insert(items, { label = "Настройки", action = function() self:pushMenu(self:settingsItems(), "Настройки") end })
    table.insert(items, { label = "Выход", action = function() love.event.quit() end })
    return items
end

function Title:settingsItems()
    return {
        { label = "Музыка", value = function() return math.floor(audio.musicVolume * 100 + 0.5) .. "%" end,
            change = function(d)
                audio.musicVolume = util.clamp(audio.musicVolume + d * 0.1, 0, 1)
                G().saveSettings()
            end },
        { label = "Звуки", value = function() return math.floor(audio.sfxVolume * 100 + 0.5) .. "%" end,
            change = function(d)
                audio.sfxVolume = util.clamp(audio.sfxVolume + d * 0.1, 0, 1)
                audio.play("ui_select")
                G().saveSettings()
            end },
        { label = "Во весь экран", action = function() screen.toggleFullscreen() end },
        { label = "Назад", action = function() self:back() end },
    }
end

function Title:setMenu(items, caption)
    self.caption = caption
    self.menu = ui.Menu(items, {
        align = "center", width = 360, shadow = false,
        cancel = #self.stack > 0 and function() self:back() end or nil,
    })
end

function Title:pushMenu(items, caption)
    table.insert(self.stack, { items = self.menu.items, index = self.menu.index, caption = self.caption })
    self:setMenu(items, caption)
end

function Title:back()
    local prev = table.remove(self.stack)
    if prev then
        self:setMenu(prev.items, prev.caption)
        self.menu.index = prev.index
    end
end

-- coming back from a mini-game: refresh records in the labels
function Title:returned()
    self.stack = {}
    self:setMenu(self:mainItems())
end

function Title:update(dt)
    Mode.update(self, dt)
    self.background:update(dt)
    self.menu:update(dt)
end

function Title:draw()
    self.background:draw(self.time * 30, 0)
    local g = G()
    local cx = screen.width / 2
    local bob = math.floor(math.sin(self.time * 1.6) * 4 + 0.5)
    ui.print(g.title, cx, 70 + bob, { font = "title", align = "center", color = "gold", outline = { 0.15, 0.08, 0.05 }, shadow = true })
    if self.def.subtitle then
        ui.print(self.def.subtitle, cx, 112 + bob, { font = "body", align = "center", color = "light", shadow = true })
    end
    local w = 440
    local h = self.menu:getHeight() + 40 + (self.caption and 40 or 0)
    local x, y = math.floor(cx - w / 2), math.floor(math.max(160, (screen.height - h) / 2 + 40))
    ui.panel.draw(x, y, w, h)
    local my = y + 20
    if self.caption then
        ui.print(self.caption, cx, my, { font = "body", align = "center", color = "accent" })
        my = my + 40
    end
    self.menu:draw(x + (w - 360) / 2, my)
    ui.print("[" .. input.keyName("confirm") .. "] выбрать   [" .. input.keyName("cancel") .. "] назад   [F11] экран",
        cx, screen.height - 30, { font = "small", align = "center", color = "light", shadow = true, alpha = 0.8 })
end

return Title
