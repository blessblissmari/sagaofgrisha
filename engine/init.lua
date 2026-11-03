-- The engine: everything a small LOVE game needs, game code lives in game/.
--
--   local engine = require("engine")
--   engine.load(require("game.config"))   -- in love.load
--   engine.hook()                          -- sets love.update, love.draw, love.keypressed...
--
-- Modules (all of them can also be required one by one):
--   class, util, timer, input, screen, scene, assets, shaders, audio, anim,
--   fx, ui, dialogue, tiled, Camera, World, Entity, Triggers, Inventory,
--   Background, Trail (followers), physics (platformers), save, debug, voice,
--   IsoMap (isometric Tiled maps with height levels)

local engine = {
    class = require("engine.class"),
    util = require("engine.util"),
    timer = require("engine.timer"),
    input = require("engine.input"),
    screen = require("engine.screen"),
    scene = require("engine.scene"),
    assets = require("engine.assets"),
    shaders = require("engine.shaders"),
    audio = require("engine.audio"),
    anim = require("engine.anim"),
    fx = require("engine.fx"),
    ui = require("engine.ui"),
    dialogue = require("engine.dialogue"),
    tiled = require("engine.tiled"),
    Camera = require("engine.camera"),
    World = require("engine.world"),
    Entity = require("engine.entity"),
    Triggers = require("engine.triggers"),
    Inventory = require("engine.inventory"),
    Background = require("engine.background"),
    Trail = require("engine.followers"),
    physics = require("engine.physics"),
    save = require("engine.save"),
    debug = require("engine.debug"),
    voice = require("engine.voice"),
    emote = require("engine.emote"),
    Weather = require("engine.weather"),
    Sky = require("engine.sky"),
    IsoMap = require("engine.isomap"),
}

local input, screen, scene = engine.input, engine.screen, engine.scene

-- config fields: width, height, pixelPerfect, keys, pad, sounds, characters,
--                effects, storyFolder, musicVolume, sfxVolume
function engine.load(config)
    engine.config = config
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    screen.init(config.width, config.height, { pixelPerfect = config.pixelPerfect })
    input.setBindings(config.keys, config.pad, config.keymaps)
    if config.sounds then
        engine.audio.load(config.sounds)
    end
    engine.audio.musicVolume = config.musicVolume or engine.audio.musicVolume
    engine.audio.sfxVolume = config.sfxVolume or engine.audio.sfxVolume
    engine.dialogue.characters = config.characters or engine.dialogue.characters
    engine.dialogue.folder = config.storyFolder or engine.dialogue.folder
    for name, def in pairs(config.effects or {}) do
        engine.fx.define(name, def)
    end
    engine.fx.font = engine.ui.font("small")
    love.graphics.setFont(engine.ui.font("small"))
end

function engine.update(dt)
    dt = math.min(dt, 1 / 20) -- a long frame (window drag) must not break physics
    if input.pressed("fullscreen") then
        screen.toggleFullscreen()
    end
    if input.pressed("debug") then
        engine.debug.toggle()
    end
    engine.timer.update(dt)
    engine.shaders.update(dt)
    engine.audio.update(dt)
    engine.ui.update(dt)
    scene.update(dt)
    input.endFrame()
end

function engine.draw()
    screen.begin()
    scene.draw()
    engine.ui.drawToasts()
    love.graphics.setFont(engine.ui.font("small"))
    engine.debug.draw(scene.stack)
    screen.finish(scene.effects())
end

function engine.keypressed(key, scancode, isrepeat)
    input.keypressed(key, scancode, isrepeat)
    scene.forward("keypressed", key, scancode, isrepeat)
end

function engine.keyreleased(key, scancode)
    input.keyreleased(key, scancode)
    scene.forward("keyreleased", key, scancode)
end

function engine.textinput(text)
    scene.forward("textinput", text)
end

function engine.mousepressed(x, y, button)
    local vx, vy = screen.toVirtual(x, y)
    input.mousepressed(vx, vy, button)
    scene.forward("mousepressed", vx, vy, button)
end

function engine.mousereleased(x, y, button)
    local vx, vy = screen.toVirtual(x, y)
    input.mousereleased(vx, vy, button)
end

function engine.mousemoved(x, y)
    input.mousemoved(screen.toVirtual(x, y))
end

function engine.wheelmoved(x, y)
    input.wheelmoved(x, y)
end

function engine.gamepadpressed(joystick, button)
    input.gamepadpressed(joystick, button)
end

function engine.gamepadreleased(joystick, button)
    input.gamepadreleased(joystick, button)
end

function engine.resize(w, h)
    screen.resize(w, h)
end

function engine.focus(focused)
    scene.forward("focus", focused)
end

local CALLBACKS = {
    "update", "draw", "keypressed", "keyreleased", "textinput", "mousepressed",
    "mousereleased", "mousemoved", "wheelmoved", "gamepadpressed", "gamepadreleased",
    "resize", "focus",
}

-- Points the LOVE callbacks to the engine (love.load stays in main.lua).
function engine.hook()
    for _, name in ipairs(CALLBACKS) do
        love[name] = function(...)
            return engine[name](...)
        end
    end
end

return engine
