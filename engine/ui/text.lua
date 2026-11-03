-- Rich text: colors, effects, word wrap, typewriter, pauses and events.
--
--   local t = Text("Привет, {accent}Гриша{/}! {wave}Ура!{/}", { width = 600, speed = 45 })
--   t:update(dt)     -- reveals letters (speed = letters per second, 0 = all at once)
--   t:skip()         -- show everything now
--   t:isDone()
--   t:draw(x, y)
--
-- Markup (UTF-8, Russian is fine):
--   {accent} {gold} {red} ...  a color of the theme      {#ff8800}  any color
--   {wave}    letters wave         {shake}  letters tremble (fear, anger)
--   {rainbow} shimmering colors    {slow} {fast} {speed=12}  typing speed
--   {/}       closes the last tag  {p} pause 0.5 s   {p=1.5} pause 1.5 s
--   {@hop} {@shake} {@emote=anger} {@sound=coin} ...  events: when the typewriter
--             reaches them the dialogue tells the game (emotions of characters)

local class = require("engine.class")
local theme = require("engine.ui.theme")
local util = require("engine.util")
local utf8 = require("utf8")

local Text = class()

local PAUSES = { ["."] = 0.25, ["!"] = 0.25, ["?"] = 0.25, [","] = 0.1, [":"] = 0.12, [";"] = 0.12, ["…"] = 0.35 }

local function newStyle(base, changes)
    local s = {}
    for k, v in pairs(base) do
        s[k] = v
    end
    for k, v in pairs(changes) do
        s[k] = v
    end
    return s
end

-- returns tokens: { text = "...", style = {...} } or { event = name, value = v }
local function parse(str, defaultColor)
    local tokens = {}
    local stack = { { color = defaultColor, speed = 1 } }
    local pos = 1
    while pos <= #str do
        local s, e, tag = str:find("{([^{}]*)}", pos)
        if not s then
            table.insert(tokens, { text = str:sub(pos), style = stack[#stack] })
            break
        end
        if s > pos then
            table.insert(tokens, { text = str:sub(pos, s - 1), style = stack[#stack] })
        end
        local top = stack[#stack]
        local name, value = tag:match("^([^=]+)=(.*)$")
        name = name or tag
        if name:sub(1, 1) == "/" then
            if #stack > 1 then
                table.remove(stack)
            end
        elseif name:sub(1, 1) == "@" then
            table.insert(tokens, { event = name:sub(2), value = value })
        elseif name == "p" or name == "pause" then
            table.insert(tokens, { event = "pause", value = tonumber(value) or 0.5 })
        elseif name:sub(1, 1) == "#" then
            table.insert(stack, newStyle(top, { color = util.hexColor(name) }))
        elseif name == "wave" or name == "shake" or name == "rainbow" then
            table.insert(stack, newStyle(top, { [name] = true }))
        elseif name == "slow" then
            table.insert(stack, newStyle(top, { speed = 0.35 }))
        elseif name == "fast" then
            table.insert(stack, newStyle(top, { speed = 2.5 }))
        elseif name == "speed" then
            table.insert(stack, newStyle(top, { speed = (tonumber(value) or 45) / math.max(theme.textSpeed, 1) }))
        elseif theme.colors[name] then
            table.insert(stack, newStyle(top, { color = theme.colors[name] }))
        else
            -- unknown tag: keep it as text
            table.insert(tokens, { text = "{" .. tag .. "}", style = top })
        end
        pos = e + 1
    end
    return tokens
end

-- opts: font, width, color, speed, lineHeight (multiplier), align, onChar(char), onEvent(name, value), shadow
function Text:init(str, opts)
    opts = opts or {}
    self.font = opts.font or theme.font("body")
    self.width = opts.width or 400
    self.color = opts.color or theme.colors.ink
    self.speed = opts.speed or 0
    self.lineHeight = math.floor(self.font:getHeight() * (opts.lineHeight or 1.05))
    self.align = opts.align or "left"
    self.onChar = opts.onChar
    self.onEvent = opts.onEvent
    self.shadow = opts.shadow
    self.time = 0
    self:set(str or "")
end

function Text:set(str)
    self.source = str
    self.lines = {}
    self.chars = {}   -- every visible letter: { c = "а", speed = 1 }
    self.events = {}  -- events[k] = list, fired when k letters are shown
    self.total = 0
    self.shown = self.speed > 0 and 0 or math.huge
    self.timer = 0
    self.delay = 0
    self.fired = -1
    local font = self.font
    local line = { runs = {}, width = 0 }
    table.insert(self.lines, line)
    local spaceWidth = font:getWidth(" ")
    local function newLine()
        line = { runs = {}, width = 0 }
        table.insert(self.lines, line)
    end
    local function addChars(text, style)
        for _, c in utf8.codes(text) do
            table.insert(self.chars, { c = utf8.char(c), speed = style.speed or 1 })
        end
    end
    for _, token in ipairs(parse(str, self.color)) do
        if token.event then
            local k = #self.chars
            self.events[k] = self.events[k] or {}
            table.insert(self.events[k], token)
        else
            local text, style = token.text, token.style
            local i = 1
            while i <= #text do
                local c = text:sub(i, i)
                if c == "\n" then
                    newLine()
                    i = i + 1
                elseif c == " " then
                    if #line.runs > 0 then
                        table.insert(line.runs, { text = " ", style = style, x = line.width, count = 1, space = true })
                        line.width = line.width + spaceWidth
                        addChars(" ", style)
                    end
                    i = i + 1
                else
                    local s, e = text:find("[^ \n]+", i)
                    local word = text:sub(s, e)
                    local w = font:getWidth(word)
                    if line.width + w > self.width and #line.runs > 0 then
                        local last = line.runs[#line.runs]
                        if last.space then
                            table.remove(line.runs)
                            line.width = line.width - spaceWidth
                            table.remove(self.chars)
                        end
                        newLine()
                    end
                    local count = util.ulen(word)
                    table.insert(line.runs, { text = word, style = style, x = line.width, count = count })
                    line.width = line.width + w
                    addChars(word, style)
                    i = e + 1
                end
            end
        end
    end
    self.total = #self.chars
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
    return self.shown >= self.total and self.delay <= 0
end

local function fire(self, k, skipping)
    local list = self.events[k]
    if not list then
        return
    end
    for _, e in ipairs(list) do
        if e.event == "pause" then
            if not skipping then
                self.delay = self.delay + e.value
            end
        elseif self.onEvent then
            self.onEvent(e.event, e.value)
        end
    end
end

function Text:skip()
    for k = math.max(self.fired + 1, 0), self.total do
        fire(self, k, true)
    end
    self.fired = self.total
    self.shown = math.huge
    self.delay = 0
end

-- the n-th visible letter (for pauses and sounds)
function Text:charAt(n)
    local c = self.chars[n]
    return c and c.c or ""
end

function Text:update(dt)
    self.time = self.time + dt
    if self.shown >= self.total and self.delay <= 0 then
        return
    end
    if self.fired < 0 then
        self.fired = 0
        fire(self, 0)
    end
    if self.delay > 0 then
        self.delay = self.delay - dt
        return
    end
    local nextChar = self.chars[self.shown + 1]
    self.timer = self.timer + dt * self.speed * (nextChar and nextChar.speed or 1)
    while self.timer >= 1 and self.shown < self.total do
        self.timer = self.timer - 1
        self.shown = self.shown + 1
        local c = self.chars[self.shown].c
        if self.onChar and c ~= " " then
            self.onChar(c, self.shown)
        end
        self.fired = self.shown
        fire(self, self.shown)
        local after = self.chars[self.shown + 1]
        if PAUSES[c] and self.shown < self.total and (not after or after.c == " ") then
            self.delay = self.delay + PAUSES[c] / math.max(self.chars[self.shown].speed, 0.5)
        end
        if self.delay > 0 then
            self.timer = 0
            break
        end
    end
end

local function hsv(h)
    local i = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local q, t = 1 - f, f
    local list = { { 1, t, 0 }, { q, 1, 0 }, { 0, 1, t }, { 0, q, 1 }, { t, 0, 1 }, { 1, 0, q } }
    local c = list[i + 1]
    return 0.55 + c[1] * 0.45, 0.55 + c[2] * 0.45, 0.55 + c[3] * 0.45
end

-- opts: alpha, shadow (color, or false to turn it off)
function Text:draw(x, y, opts)
    opts = opts or {}
    local lg = love.graphics
    local alpha = opts.alpha or 1
    local font = self.font
    lg.setFont(font)
    local shadow = opts.shadow
    if shadow == nil then
        shadow = self.shadow
    end
    if shadow == nil and theme.textShadow then
        shadow = theme.colors.shadow
    end
    local px = theme.pixelOf(font)
    local left = self.shown
    local index = 0
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
                lg.setColor(1, 1, 1, 1)
                return
            end
            local text = run.text
            local count = math.min(left, run.count)
            if count < run.count then
                text = util.usub(text, 1, count)
            end
            left = left - run.count
            local st = run.style
            local c = st.color
            if st.wave or st.shake or st.rainbow then
                local cx = math.floor(lx + run.x)
                for _, code in utf8.codes(text) do
                    local ch = utf8.char(code)
                    index = index + 1
                    local dx, dy = 0, 0
                    if st.wave then
                        dy = math.floor(math.sin(self.time * 8 - index * 0.7) * px * 1.5 + 0.5)
                    end
                    if st.shake then
                        dx = love.math.random(-1, 1) * px * 0.5
                        dy = dy + love.math.random(-1, 1) * px * 0.5
                    end
                    if shadow then
                        lg.setColor(shadow[1], shadow[2], shadow[3], (shadow[4] or 1) * alpha)
                        lg.print(ch, math.floor(cx + dx + px), math.floor(ly + dy + px))
                    end
                    if st.rainbow then
                        local r, g, b = hsv((self.time * 0.6 + index * 0.08) % 1)
                        lg.setColor(r, g, b, alpha)
                    else
                        lg.setColor(c[1], c[2], c[3], (c[4] or 1) * alpha)
                    end
                    lg.print(ch, math.floor(cx + dx), math.floor(ly + dy))
                    cx = cx + font:getWidth(ch)
                end
            else
                index = index + count
                if shadow then
                    lg.setColor(shadow[1], shadow[2], shadow[3], (shadow[4] or 1) * alpha)
                    lg.print(text, math.floor(lx + run.x) + px, ly + px)
                end
                lg.setColor(c[1], c[2], c[3], (c[4] or 1) * alpha)
                lg.print(text, math.floor(lx + run.x), ly)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

return Text
