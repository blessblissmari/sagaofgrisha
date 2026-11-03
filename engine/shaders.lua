-- Shaders live in assets/shaders/<name>.glsl and are loaded on first use.
-- A shader that fails to compile prints an error and is simply skipped,
-- so the game keeps running on weak GPUs.
--
--   local water = shaders.get("water")
--   shaders.send(water, "zoom", 2)        -- safe even if the uniform is unused
--   shaders.send("crt", "strength", 0.5)  -- by name
--
-- Every shader that declares "extern number time;" gets the time in seconds.

local shaders = { folder = "assets/shaders/", time = 0 }

local cache = {} -- name -> Shader or false (failed)

function shaders.get(name)
    local shader = cache[name]
    if shader == nil then
        local path = shaders.folder .. name .. ".glsl"
        local ok, result = pcall(function()
            local code = assert(love.filesystem.read(path), "file not found: " .. path)
            return love.graphics.newShader(code)
        end)
        if ok then
            shader = result
        else
            print("[shaders] " .. name .. ": " .. tostring(result))
            shader = false
        end
        cache[name] = shader
    end
    return shader or nil
end

function shaders.send(shader, uniform, ...)
    if type(shader) == "string" then
        shader = shaders.get(shader)
    end
    if shader and shader:hasUniform(uniform) then
        shader:send(uniform, ...)
    end
end

function shaders.update(dt)
    shaders.time = shaders.time + dt
    for _, shader in pairs(cache) do
        if shader and shader:hasUniform("time") then
            shader:send("time", shaders.time)
        end
    end
end

return shaders
