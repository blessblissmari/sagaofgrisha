-- Saving Lua tables into the LOVE save folder
-- (Windows: %APPDATA%/LOVE/<identity>, Linux: ~/.local/share/love/<identity>).
--
--   save.write("records", { tetris = 12000 })
--   local records = save.read("records", { tetris = 0 })   -- with defaults

local util = require("engine.util")

local save = {}

local function serialize(value, indent)
    local t = type(value)
    if t == "table" then
        indent = indent or ""
        local inner = indent .. "    "
        local keys = {}
        for k in pairs(value) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local lines = { "{" }
        for _, k in ipairs(keys) do
            local key
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                key = k
            else
                key = "[" .. serialize(k) .. "]"
            end
            table.insert(lines, inner .. key .. " = " .. serialize(value[k], inner) .. ",")
        end
        table.insert(lines, indent .. "}")
        return table.concat(lines, "\n")
    elseif t == "string" then
        return string.format("%q", value)
    elseif t == "number" or t == "boolean" then
        return tostring(value)
    end
    return "nil"
end

save.serialize = serialize

function save.write(name, data)
    local ok, err = love.filesystem.write(name .. ".lua", "return " .. serialize(data) .. "\n")
    if not ok then
        print("[save] " .. tostring(err))
    end
    return ok
end

function save.read(name, defaults)
    local path = name .. ".lua"
    if love.filesystem.getInfo(path) then
        local ok, chunk = pcall(love.filesystem.load, path)
        if ok and chunk then
            local ok2, data = pcall(chunk)
            if ok2 and type(data) == "table" then
                return defaults and util.defaults(data, defaults) or data
            end
        end
        print("[save] broken file " .. path .. ", using defaults")
    end
    return defaults and util.deepCopy(defaults) or {}
end

function save.exists(name)
    return love.filesystem.getInfo(name .. ".lua") ~= nil
end

function save.remove(name)
    love.filesystem.remove(name .. ".lua")
end

return save
