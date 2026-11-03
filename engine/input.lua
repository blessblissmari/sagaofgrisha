-- Keyboard / gamepad / mouse input by ACTION names, not keys.
--
--   input.down("left")       held right now
--   input.pressed("confirm") pressed this frame (true once per press)
--   input.pressed("up", true) same, but also true on key repeat (menus)
--   input.released("attack")
--   input.direction()        -> dx, dy (-1, 0, 1) from up/down/left/right
--
-- Bindings live in game/config.lua (input.bindings), so changing a key
-- never needs changes in the game code.

local input = {
    bindings = {},    -- action -> { "key", ... }
    padBindings = {}, -- action -> { "gamepadbutton", ... }
    locked = false,   -- while true nothing is down/pressed (scene transitions)
    mouse = { x = 0, y = 0, moved = false, wheel = 0, pressed = {}, released = {} },
}

local keyActions = {}    -- key -> { action, ... }
local buttonActions = {} -- gamepad button -> { action, ... }
local pressed, released, repeated = {}, {}, {}

local function rebuild()
    keyActions, buttonActions = {}, {}
    for action, keys in pairs(input.bindings) do
        for _, key in ipairs(keys) do
            keyActions[key] = keyActions[key] or {}
            table.insert(keyActions[key], action)
        end
    end
    for action, buttons in pairs(input.padBindings) do
        for _, button in ipairs(buttons) do
            buttonActions[button] = buttonActions[button] or {}
            table.insert(buttonActions[button], action)
        end
    end
end

function input.setBindings(keys, pads)
    input.bindings = keys or {}
    input.padBindings = pads or {}
    rebuild()
end

-- Change one action at runtime: input.bind("attack", { "space", "j" })
function input.bind(action, keys)
    input.bindings[action] = keys
    rebuild()
end

-- callbacks (main.lua forwards LOVE events here) ----------------------------

function input.keypressed(key, scancode, isrepeat)
    for _, action in ipairs(keyActions[key] or {}) do
        repeated[action] = true
        if not isrepeat then
            pressed[action] = true
        end
    end
end

function input.keyreleased(key)
    for _, action in ipairs(keyActions[key] or {}) do
        released[action] = true
    end
end

function input.gamepadpressed(joystick, button)
    for _, action in ipairs(buttonActions[button] or {}) do
        pressed[action] = true
        repeated[action] = true
    end
end

function input.gamepadreleased(joystick, button)
    for _, action in ipairs(buttonActions[button] or {}) do
        released[action] = true
    end
end

function input.mousemoved(x, y)
    input.mouse.x, input.mouse.y = x, y
    input.mouse.moved = true
end

function input.mousepressed(x, y, button)
    input.mouse.x, input.mouse.y = x, y
    input.mouse.pressed[button] = true
end

function input.mousereleased(x, y, button)
    input.mouse.released[button] = true
end

function input.wheelmoved(x, y)
    input.mouse.wheel = input.mouse.wheel + y
end

-- queries -------------------------------------------------------------------

local function stickDown(action)
    local joysticks = love.joystick and love.joystick.getJoysticks() or {}
    for _, js in ipairs(joysticks) do
        if js:isGamepad() then
            local buttons = input.padBindings[action]
            if buttons and js:isGamepadDown(unpack(buttons)) then
                return true
            end
            local ax, ay = js:getGamepadAxis("leftx"), js:getGamepadAxis("lefty")
            if (action == "left" and ax < -0.5) or (action == "right" and ax > 0.5)
                or (action == "up" and ay < -0.5) or (action == "down" and ay > 0.5) then
                return true
            end
        end
    end
    return false
end

function input.down(action)
    if input.locked then
        return false
    end
    local keys = input.bindings[action]
    if keys and #keys > 0 and love.keyboard.isDown(unpack(keys)) then
        return true
    end
    return stickDown(action)
end

function input.pressed(action, allowRepeat)
    if input.locked then
        return false
    end
    if allowRepeat then
        return repeated[action] == true
    end
    return pressed[action] == true
end

function input.released(action)
    return not input.locked and released[action] == true
end

-- Marks an action as handled, so nothing else reacts to it this frame.
function input.consume(action)
    pressed[action], repeated[action] = nil, nil
end

function input.anyPressed()
    return not input.locked and next(pressed) ~= nil
end

function input.direction()
    local dx, dy = 0, 0
    if input.down("left") then dx = dx - 1 end
    if input.down("right") then dx = dx + 1 end
    if input.down("up") then dy = dy - 1 end
    if input.down("down") then dy = dy + 1 end
    return dx, dy
end

-- Name of the first key bound to an action, for hints like "[E] поговорить".
local KEY_NAMES = {
    space = "Пробел", ["return"] = "Enter", escape = "Esc", lshift = "Shift",
    rshift = "Shift", tab = "Tab", backspace = "Backspace", lctrl = "Ctrl",
    up = "↑", down = "↓", left = "←", right = "→",
}
function input.keyName(action)
    local key = (input.bindings[action] or {})[1]
    if not key then
        return "?"
    end
    return KEY_NAMES[key] or key:upper()
end

-- Called by the engine at the end of every frame.
function input.endFrame()
    pressed, released, repeated = {}, {}, {}
    input.mouse.pressed, input.mouse.released = {}, {}
    input.mouse.moved = false
    input.mouse.wheel = 0
end

function input.lock(flag)
    input.locked = flag and true or false
end

return input
