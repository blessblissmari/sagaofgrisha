-- Text with colors, word wrap and a typewriter effect.
--
--   local t = Text("Привет, {accent}Гриша{/}! Как дела?", { width = 600 })
--   t:update(dt)     -- reveals letters (speed = letters per second, 0 = all at once)
--   t:skip()         -- show everything now
--   t:isDone()
--   t:draw(x, y)
--
-- Markup: {name}...{/} where name is a color from the theme (accent, red,
-- gold...) or a hex color {#ff8800}. Russian text is fine: everything is UTF-8.

local class = require("engine.class")
local theme = require("engine.ui.theme")
local util = require("engine.util")

local Text = class()

local PAUSES = { ["."] = 0.25, ["!"] = 0.25, ["?"] = 0.25, [","] = 0.1, [":"] = 0.12, [";"] = 0.12 }

local function parse(str, defaultColor)
    local segments = {}
    local stack = { defaultColor }
    local pos = 1
    while pos <= #str do
        local s, e, tag = str:find("{([^{}]*)}", pos)
        if not s then
            table.insert(segments, { text = str:sub(pos), color = stack[#stack] })
            break
        end
        if s > pos then
            table.insert(segments, { text = str:sub(pos, s - 1), color = stack[#stack] })
        end
        if tag == "/" then
            if #stack > 1 then
                table.remove(stack)
            end
        elseif tag:sub(1, 1) == "#" then
            table.insert(stack, util.hexColor(tag))
        else
            table.insert(stack, theme.colors[tag] or stack[#stack])
        end
        pos = e + 1
    end
    return segments
end

-- opts: font, width, color, speed, lineHeight (multiplier), align, onChar(char)
function Text:init(str, opts)
    opts = opts or {}
    self.font = opts.font or theme.font("body")
    self.width = opts.width or 400
    self.color = opts.color or theme.colors.ink
    self.speed = opts.speed or 0
    self.lineHeight = math.floor(self.font:getHeight() * (opts.lineHeight or 1.1))
    self.align = opts.align or "left"
    self.onChar = opts.onChar
    self:set(str or "")
end

function Text:set(str)
    self.source = str
    self.lines = {}
    self.total = 0
    self.shown = self.speed > 0 and 0 or math.huge
    self.timer = 0
    self.delay = 0
    local font = self.font
    local line = { runs = {}, width = 0 }
    table.insert(self.lines, line)
    local spaceWidth = font:getWidth(" ")
    local function newLine()
        line = { runs = {}, width = 0 }
        table.insert(self.lines, line)
    end
    for _, seg in ipairs(parse(str, self.color)) do
        local text = seg.text
        local i = 1
        while i <= #text do
            local c = text:sub(i, i)
            if c == "\n" then
                newLine()
                i = i + 1
            elseif c == " " then
                if #line.runs > 0 then
                    table.insert(line.runs, { text = " ", color = seg.color, x = line.width, count = 1, space = true })
                    line.width = line.width + spaceWidth
                end
                i = i + 1
            else
                local s, e = text:find("[^ \n]+", i)
                local word = text:sub(s, e)
                local w = font:getWidth(word)
                if line.width + w > self.width and #line.runs > 0 then
                    -- remove the trailing space before wrapping
                    local last = line.runs[#line.runs]
                    if last.space then
                        table.remove(line.runs)
                        line.width = line.width - spaceWidth
                    end
                    newLine()
                end
                local count = util.ulen(word)
                table.insert(line.runs, { text = word, color = seg.color, x = line.width, count = count })
                line.width = line.width + w
                i = e + 1
            end
        end
    end
    for _, l in ipairs(self.lines) do
        for _, run in ipairs(l.runs) do
            self.total = self.total + run.count
        end
    end
end

function Text:getHeight()
    return #self.lines * self.lineHeight
end

function Text:getWidth()
    local w = 0
    for _, l in ipairs(self.lines) do
        w = math.max(w, l.width)
    end
    return w
end

function Text:isDone()
    return self.shown >= self.total
end

function Text:skip()
    self.shown = math.huge
end

-- the n-th visible letter (for pauses and sounds)
function Text:charAt(n)
    for _, l in ipairs(self.lines) do
        for _, run in ipairs(l.runs) do
            if n <= run.count then
                return util.usub(run.text, n, n)
            end
            n = n - run.count
        end
    end
    return ""
end

function Text:update(dt)
    if self:isDone() then
        return
    end
    if self.delay > 0 then
        self.delay = self.delay - dt
        return
    end
    self.timer = self.timer + dt * self.speed
    while self.timer >= 1 and not self:isDone() do
        self.timer = self.timer - 1
        self.shown = self.shown + 1
        local c = self:charAt(self.shown)
        if self.onChar and c ~= " " then
            self.onChar(c, self.shown)
        end
        if PAUSES[c] and self.shown < self.total then
            self.delay = PAUSES[c]
            self.timer = 0
            break
        end
    end
end

-- opts: alpha, shadow (color of a 1px shadow)
function Text:draw(x, y, opts)
    opts = opts or {}
    local alpha = opts.alpha or 1
    love.graphics.setFont(self.font)
    local left = self.shown
    for i, l in ipairs(self.lines) do
        local lx = x
        if self.align == "center" then
            lx = x + math.floor((self.width - l.width) / 2)
        elseif self.align == "right" then
            lx = x + self.width - l.width
        end
        local ly = y + (i - 1) * self.lineHeight
        for _, run in ipairs(l.runs) do
            if left <= 0 then
                return
            end
            local text = run.text
            if left < run.count then
                text = util.usub(text, 1, left)
            end
            left = left - run.count
            if opts.shadow then
                love.graphics.setColor(opts.shadow[1], opts.shadow[2], opts.shadow[3], (opts.shadow[4] or 1) * alpha)
                love.graphics.print(text, math.floor(lx + run.x) + 2, ly + 2)
            end
            local c = run.color
            love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * alpha)
            love.graphics.print(text, math.floor(lx + run.x), ly)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Text
