-- Asset cache: every image and font is loaded only once.
--
--   assets.image("assets/sprites/td_hero.png")
--   assets.image("assets/sprites/mobs/creatures.png", { colorKey = { { 157, 142, 135 } } })
--   assets.font("assets/fonts/Tiny5.ttf", 20)
--   assets.quad(image, x, y, w, h)
--   assets.tiled(image, x, y, w, h)  -- a piece of an image that can be repeated

local assets = {}

local images, fonts, pieces = {}, {}, {}

local function imageKey(path, opts)
    if not (opts and (opts.colorKey or opts.filter)) then
        return path
    end
    local parts = { path, opts.filter or "nearest" }
    for _, c in ipairs(opts.colorKey or {}) do
        table.insert(parts, table.concat(c, ","))
    end
    return table.concat(parts, "|")
end

-- opts.colorKey: list of { r, g, b } (0..255) that become transparent,
--               for old sprite sheets with a solid background color
-- opts.filter:  "linear" for smooth scaling (default "nearest", pixel art)
function assets.image(path, opts)
    local key = imageKey(path, opts)
    local image = images[key]
    if image then
        return image
    end
    if opts and opts.colorKey then
        local data = love.image.newImageData(path)
        local keys = opts.colorKey
        data:mapPixel(function(_, _, r, g, b, a)
            for _, c in ipairs(keys) do
                if math.abs(r * 255 - c[1]) < 2 and math.abs(g * 255 - c[2]) < 2
                    and math.abs(b * 255 - c[3]) < 2 then
                    return 0, 0, 0, 0
                end
            end
            return r, g, b, a
        end)
        image = love.graphics.newImage(data)
    else
        image = love.graphics.newImage(path)
    end
    local filter = opts and opts.filter or "nearest"
    image:setFilter(filter, filter)
    images[key] = image
    return image
end

-- Pixel fonts look crisp only with "mono" hinting and nearest filtering.
function assets.font(path, size, hinting)
    local key = path .. "@" .. size
    local font = fonts[key]
    if not font then
        font = love.graphics.newFont(path, size, hinting or "mono")
        font:setFilter("nearest", "nearest")
        fonts[key] = font
    end
    return font
end

function assets.quad(image, x, y, w, h)
    return love.graphics.newQuad(x, y, w, h, image:getWidth(), image:getHeight())
end

-- Cuts a region out of an image into its own image with "repeat" wrapping,
-- so it can be tiled over any area with a single quad (panel backgrounds).
function assets.tiled(path, x, y, w, h)
    local key = string.format("%s#%d,%d,%d,%d", path, x, y, w, h)
    local image = pieces[key]
    if not image then
        local source = love.image.newImageData(path)
        local data = love.image.newImageData(w, h)
        data:paste(source, 0, 0, x, y, w, h)
        image = love.graphics.newImage(data)
        image:setFilter("nearest", "nearest")
        image:setWrap("repeat", "repeat")
        pieces[key] = image
    end
    return image
end

-- All files with one of the extensions in a folder, sorted by name.
function assets.list(folder, extensions)
    local result = {}
    for _, file in ipairs(love.filesystem.getDirectoryItems(folder)) do
        local ext = file:match("%.(%w+)$")
        if ext and extensions[ext:lower()] then
            table.insert(result, folder .. "/" .. file)
        end
    end
    table.sort(result)
    return result
end

return assets
