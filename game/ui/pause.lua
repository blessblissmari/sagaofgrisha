-- Pause menu on top of any stage: continue, bag, journal, volume, full screen, main menu.
--
--   scene.push(Pause(mode, { { label = "Сдаться", action = function() ... end } }))

local engine = require("engine")
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

local Pause = class()
Pause.transparent = true

function Pause:init(host, extra)
    self.host = host
    local items = {
        { label = "Продолжить", action = function() self:close() end },
    }
    if host and host.world and host.def.kind ~= "novel" then
        table.insert(items, { label = "Сумка", action = function()
            local Bag = require("game.ui.inventory")
            scene.push(Bag(host))
        end })
    end
    if host and host.def and host.def.kind ~= "title" then
        table.insert(items, { label = "Дневник", action = function()
            local Journal = require("game.ui.journal")
            scene.push(Journal(host))
        end })
    end
    for _, item in ipairs(extra or {}) do
        table.insert(items, item)
    end
    table.insert(items, {
        label = "Музыка",
        value = function() return math.floor(audio.musicVolume * 100 + 0.5) .. "%" end,
        change = function(d)
            audio.musicVolume = util.clamp(audio.musicVolume + d * 0.1, 0, 1)
            G().saveSettings()
        end,
    })
    table.insert(items, {
        label = "Звуки",
        value = function() return math.floor(audio.sfxVolume * 100 + 0.5) .. "%" end,
        change = function(d)
            audio.sfxVolume = util.clamp(audio.sfxVolume + d * 0.1, 0, 1)
            audio.play("ui_select")
            G().saveSettings()
        end,
    })
    table.insert(items, { label = "Во весь экран", action = function() screen.toggleFullscreen() end })
    local menuStage = G().menuStage()
    if host and host.def.kind ~= "title" and menuStage then
        table.insert(items, { label = "В главное меню", action = function()
            self:close()
            G().go(menuStage)
        end })
    end
    self.menu = ui.Menu(items, { cancel = function() self:close() end })
    self.time = 0
end

function Pause:enter()
    audio.play("ui_pause")
end

function Pause:close()
    if scene.top() == self then
        scene.pop()
    end
    -- the key hints of the stage show up again for a moment
    require("game.ui.hud").showHints()
end

function Pause:update(dt)
    self.time = self.time + dt
    if self.time > 0.1 and input.pressed("pause") then
        input.consume("pause")
        input.consume("cancel")
        audio.play("ui_back")
        self:close()
        return
    end
    self.menu:update(dt)
end

function Pause:draw()
    ui.dim(0.6)
    local w = math.max(360, self.menu:getWidth() + 120)
    local h = self.menu:getHeight() + 110
    local x, y = math.floor((screen.width - w) / 2), math.floor((screen.height - h) / 2)
    ui.panel.draw(x, y, w, h)
    ui.print("Пауза", screen.width / 2, y + 18, { font = "title", align = "center", color = "accent" })
    self.menu:draw(x + 60, y + 70)
end

return Pause
