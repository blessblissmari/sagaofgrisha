-- Virtual resolution: the game always draws into a fixed size canvas
-- (960x540 by default), which is then scaled to the window with black bars.
-- Post effects (CRT, vignette...) are shaders applied to that canvas.
--
--   screen.width, screen.height   virtual size, use it for layout
--   screen.toVirtual(x, y)        window pixels -> virtual pixels (mouse)
--   screen.toggleFullscreen()

local shaders = require("engine.shaders")

local screen = {
    width = 960,
    height = 540,
    scale = 1,
    offsetX = 0,
    offsetY = 0,
    pixelPerfect = false, -- true: only integer scales (sharper, bigger bars)
}

local canvas, temp = nil, {}

function screen.init(width, height, options)
    options = options or {}
    screen.width, screen.height = width or screen.width, height or screen.height
    screen.pixelPerfect = options.pixelPerfect or false
    local settings = { dpiscale = 1 }
    canvas = love.graphics.newCanvas(screen.width, screen.height, settings)
    temp[1] = love.graphics.newCanvas(screen.width, screen.height, settings)
    temp[2] = love.graphics.newCanvas(screen.width, screen.height, settings)
    for _, c in ipairs({ canvas, temp[1], temp[2] }) do
        c:setFilter("nearest", "nearest")
    end
    screen.resize(love.graphics.getDimensions())
end

function screen.resize(windowWidth, windowHeight)
    local scale = math.min(windowWidth / screen.width, windowHeight / screen.height)
    if screen.pixelPerfect and scale >= 1 then
        scale = math.floor(scale)
    end
    screen.scale = scale
    screen.offsetX = math.floor((windowWidth - screen.width * scale) / 2)
    screen.offsetY = math.floor((windowHeight - screen.height * scale) / 2)
end

function screen.getCanvas()
    return canvas
end

function screen.begin()
    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.origin()
end

-- effects: list of shader names, applied in order
function screen.finish(effects)
    love.graphics.setCanvas()
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)

    local source = canvas
    local index = 1
    for _, name in ipairs(effects or {}) do
        local shader = shaders.get(name)
        if shader then
            shaders.send(shader, "screenSize", { screen.width, screen.height })
            local target = temp[index]
            love.graphics.setCanvas(target)
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.setShader(shader)
            love.graphics.draw(source, 0, 0)
            love.graphics.setShader()
            love.graphics.setCanvas()
            source = target
            index = 3 - index
        end
    end

    love.graphics.clear(0, 0, 0, 1)
    love.graphics.draw(source, screen.offsetX, screen.offsetY, 0, screen.scale, screen.scale)
end

function screen.toVirtual(x, y)
    return (x - screen.offsetX) / screen.scale, (y - screen.offsetY) / screen.scale
end

function screen.toggleFullscreen()
    love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    screen.resize(love.graphics.getDimensions())
end

return screen
