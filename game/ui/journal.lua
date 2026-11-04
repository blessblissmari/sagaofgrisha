-- The journal ([N] in the world or "Дневник" in the pause menu): five tabs
--   Задания       s:journal(id, text) / s:journalDone(id)
--   Решения       answers of s:ask(..., { id = "..." }), by chapters
--   Отношения     s:like / s:remember of every character, the talents of Гриша (s:talent)
--   Энциклопедия  the fish that were caught and everything from s:learn(group, id, name, text)
--   Разговоры     the last lines of the dialogues and the answers ([L] in the novel opens it)
--   [←/→] or [Q/E] tabs   [↑/↓] scroll   [Esc] / [N] close.   The mouse works too.
-- Journal.Recap(title, chapter, onDone): the decisions of one chapter (s:recap() in scripts).

local engine = require("engine")
local assets = engine.assets
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

local function plain(text)
    return (tostring(text or ""):gsub("{[^{}]*}", ""))
end

local TABS = { "Задания", "Решения", "Отношения", "Энциклопедия", "Разговоры" }
local TAB_IDS = { tasks = 1, choices = 2, relations = 3, codex = 4, history = 5 }
local GROUPS = { -- names of the encyclopedia groups (s:learn), in this order
    { "people", "Люди и звери" }, { "places", "Места" }, { "monsters", "Монстры" }, { "things", "Вещи" },
}
local AREA = { x = 40, y = 92, w = 880, h = 380 }

-- rows -----------------------------------------------------------------------------
-- every row: { h = height, draw = function(x, y, w) }

local function wrap(text, font, width)
    local _, lines = font:getWrap(text, width)
    return lines
end

local function header(text)
    return { h = 40, draw = function(x, y, w)
        ui.print(text, x, y + 8, { font = "small", color = "accent" })
        love.graphics.setColor(1, 1, 1, 0.18)
        love.graphics.rectangle("fill", x, y + 34, w, 2)
        love.graphics.setColor(1, 1, 1, 1)
    end }
end

-- wrapped text; opts: font, color, indent, left (a function drawing something in the indent)
local function textRow(text, opts)
    opts = opts or {}
    local font = ui.font(opts.font or "small")
    local indent = opts.indent or 0
    local lines = wrap(plain(text), font, AREA.w - 60 - indent - (opts.right or 0))
    local lh = font:getHeight() + 2
    return { h = math.max(#lines * lh, opts.minH or 0) + (opts.gap or 6), draw = function(x, y, w)
        if opts.left then
            opts.left(x, y)
        end
        for i, line in ipairs(lines) do
            ui.print(line, x + indent, y + (i - 1) * lh, { font = font, color = opts.color or "ink" })
        end
        if opts.after then
            opts.after(x, y, w)
        end
    end }
end

local function placeholder(text)
    return textRow(text, { font = "body", color = "faded", gap = 10 })
end

local function checkbox(done)
    return function(x, y)
        local lg = love.graphics
        local c = ui.theme.color(done and "green" or "ink")
        lg.setColor(c[1], c[2], c[3], 1)
        lg.setLineWidth(2)
        lg.rectangle("line", x + 3, y + 4, 16, 16)
        if done then
            lg.line(x + 6, y + 12, x + 10, y + 17, x + 17, y + 6)
        end
        lg.setLineWidth(1)
        lg.setColor(1, 1, 1, 1)
    end
end

local function taskRows()
    local st = G().state
    local rows, active, done = {}, {}, {}
    for _, e in ipairs(st.journal or {}) do
        table.insert(e.done and done or active, e)
    end
    if #active == 0 and #done == 0 then
        return { placeholder("Пока ни одной записи. Поговори с кем-нибудь!") }
    end
    if #active > 0 then
        table.insert(rows, header("Текущие"))
        for _, e in ipairs(active) do
            table.insert(rows, textRow(e.text, { font = "body", indent = 32, left = checkbox(false), gap = 8 }))
        end
    end
    if #done > 0 then
        table.insert(rows, header("Выполнено"))
        for _, e in ipairs(done) do
            table.insert(rows, textRow(e.text, { color = "faded", indent = 32, left = checkbox(true), gap = 8 }))
        end
    end
    return rows
end

-- decisions of one chapter (or of all chapters with headers)
local function choiceRows(onlyChapter)
    local st = G().state
    local rows, last = {}, false
    for _, e in ipairs(st.choices or {}) do
        if onlyChapter == nil or e.chapter == onlyChapter then
            if onlyChapter == nil and e.chapter ~= last then
                last = e.chapter
                table.insert(rows, header(e.chapter or "Начало"))
            end
            table.insert(rows, textRow(e.text, { color = "faded", indent = 12, gap = 2 }))
            local answer = (e.late and "(не успел ответить) " or "") .. e.answer
            table.insert(rows, textRow(answer, { font = "body", indent = 44, gap = 14, left = function(x, y)
                ui.panel.cursor(x + 30, y + 14)
            end }))
        end
    end
    if #rows == 0 then
        return { placeholder(onlyChapter and "В этой главе обошлось без важных решений." or "Важных решений пока не было.") }
    end
    return rows
end

local MOODS = { { 5, "не разлей вода" }, { 3, "дружба" }, { 1, "тепло" }, { 0, "ровно" }, { -2, "холодно" }, { -99, "обида" } }
local function mood(n)
    for _, m in ipairs(MOODS) do
        if n >= m[1] then
            return m[2]
        end
    end
    return ""
end

-- pips: filled squares for the value, like the talent bars of old RPG menus
local function pips(x, y, value, max, color)
    local lg = love.graphics
    local c = ui.theme.color(color or "accent")
    for i = 1, max do
        lg.setColor(0, 0, 0, 0.35)
        lg.rectangle("fill", x + (i - 1) * 18 + 2, y + 2, 14, 14)
        if i <= value then
            lg.setColor(c[1], c[2], c[3], 1)
        else
            lg.setColor(1, 1, 1, 0.18)
        end
        lg.rectangle("fill", x + (i - 1) * 18, y, 14, 14)
    end
    lg.setColor(1, 1, 1, 1)
end

local function relationRows()
    local g = G()
    local st = g.state
    local rows, seen, list = {}, {}, {}
    local function add(id)
        if not seen[id] and g.characters[id] then
            seen[id] = true
            table.insert(list, id)
        end
    end
    for _, id in ipairs(st.party or {}) do
        add(id)
    end
    local rest = {}
    for id in pairs(st.affinity or {}) do
        table.insert(rest, id)
    end
    for id in pairs(st.memory or {}) do
        table.insert(rest, id)
    end
    table.sort(rest)
    for _, id in ipairs(rest) do
        add(id)
    end
    table.insert(rows, header("Отношения"))
    if #list == 0 then
        table.insert(rows, placeholder("Пока никого."))
    end
    for _, id in ipairs(list) do
        local sp = g.speaker(id)
        local n = st.affinity[id] or 0
        local memories = {}
        for _, text in pairs(st.memory[id] or {}) do
            if type(text) == "string" then
                table.insert(memories, plain(text))
            end
        end
        table.sort(memories)
        local note = #memories > 0 and ("Помнит: " .. table.concat(memories, "; ") .. ".") or "Ничего особенного не помнит."
        local font = ui.font("small")
        local lines = wrap(note, font, AREA.w - 60 - 80)
        local lh = font:getHeight() + 2
        table.insert(rows, { h = math.max(70, 38 + #lines * lh) + 10, draw = function(x, y, w)
            ui.panel.draw(x, y, 64, 64, "small")
            if sp.portrait then
                local p = sp.portrait
                local _, _, qw, qh = p.quad:getViewport()
                local k = math.min(52 / qw, 52 / qh)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(p.image, p.quad, math.floor(x + 32 - qw * k / 2), math.floor(y + 32 - qh * k / 2), 0, k, k)
            end
            ui.print(sp.name or id, x + 80, y, { font = "body", color = "accent" })
            local text = mood(n) .. " (" .. (n > 0 and "+" or "") .. n .. ")"
            ui.print(text, x + w - 20, y + 6, { font = "small", align = "right",
                color = n < 0 and "red" or (n > 0 and "green" or "ink") })
            for i, line in ipairs(lines) do
                ui.print(line, x + 80, y + 36 + (i - 1) * lh, { font = font, color = "faded" })
            end
        end })
    end
    table.insert(rows, header("Таланты Гриши"))
    local ids = {}
    for id in pairs(g.talents or {}) do
        table.insert(ids, id)
    end
    table.sort(ids, function(a, b)
        return (g.talents[a].order or 0) < (g.talents[b].order or 0) or
            ((g.talents[a].order or 0) == (g.talents[b].order or 0) and a < b)
    end)
    for _, id in ipairs(ids) do
        local v = st.talents[id] or 0
        local info = g.talents[id]
        table.insert(rows, textRow(info.text or "", { color = "faded", indent = 330, gap = 8, left = function(x, y)
            ui.print(info.name or id, x + 12, y - 2, { font = "small" })
            pips(x + 150, y + 3, v, math.max(5, v), "accent")
            ui.print(v, x + 150 + math.max(5, v) * 18 + 10, y - 2, { font = "small", color = "accent" })
        end }))
    end
    return rows
end

local fishImage, fishQuads
local function fishIcon(cell)
    if not fishImage then
        fishImage = assets.image("assets/sprites/arcade/fish.png")
        fishQuads = {}
    end
    if not fishQuads[cell] then
        fishQuads[cell] = assets.quad(fishImage, ((cell - 1) % 5) * 32, math.floor((cell - 1) / 5) * 32, 32, 32)
    end
    return fishQuads[cell]
end

local function codexRows()
    local g = G()
    local codex = g.state.codex or {}
    local rows = {}
    -- fish: from the fishing mini-game
    local caught, total = {}, 0
    for id in pairs(g.fish or {}) do
        total = total + 1
        if codex.fish and codex.fish[id] then
            table.insert(caught, id)
        end
    end
    table.sort(caught, function(a, b)
        return (g.fish[a].cell or 0) < (g.fish[b].cell or 0)
    end)
    if total > 0 then
        table.insert(rows, header("Рыбы — поймано " .. #caught .. " из " .. total))
        if #caught == 0 then
            table.insert(rows, placeholder("Пока ни одной. Удочку можно закинуть с края моста."))
        end
        for _, id in ipairs(caught) do
            local f, c = g.fish[id], codex.fish[id]
            table.insert(rows, { h = 40, draw = function(x, y, w)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(fishImage or assets.image("assets/sprites/arcade/fish.png"), fishIcon(f.cell), x + 8, y)
                ui.print(f.name or id, x + 56, y + 4, { font = "small" })
                ui.print("поймано " .. (c.count or 1) .. "  ·  рекорд " .. (c.best or 0) .. " см", x + w - 20, y + 4,
                    { font = "small", align = "right", color = "faded" })
            end })
        end
    end
    -- everything learned in the story: known groups first, then the others
    local order, known = {}, {}
    for _, gr in ipairs(GROUPS) do
        table.insert(order, gr)
        known[gr[1]] = true
    end
    local extra = {}
    for group in pairs(codex) do
        if group ~= "fish" and not known[group] then
            table.insert(extra, group)
        end
    end
    table.sort(extra)
    for _, group in ipairs(extra) do
        table.insert(order, { group, group })
    end
    for _, gr in ipairs(order) do
        local entries = codex[gr[1]]
        if entries and next(entries) then
            table.insert(rows, header(gr[2]))
            local ids = {}
            for id in pairs(entries) do
                table.insert(ids, id)
            end
            table.sort(ids, function(a, b)
                return plain(entries[a].name or a) < plain(entries[b].name or b)
            end)
            for _, id in ipairs(ids) do
                local e = entries[id]
                table.insert(rows, textRow(e.name or id, { font = "body", color = "accent", indent = 12, gap = 0 }))
                if e.text then
                    table.insert(rows, textRow(e.text, { indent = 12, gap = 12 }))
                end
            end
        end
    end
    if #rows == 0 then
        return { placeholder("Здесь появится всё, что Гриша узнает о мире.") }
    end
    return rows
end

-- what was said lately (game.history): the newest at the bottom
local function historyRows()
    local g = G()
    local rows = {}
    for _, e in ipairs(g.history or {}) do
        if e.kind == "answer" then
            table.insert(rows, textRow(e.text, { color = "accent", indent = 44, gap = 10, left = function(x, y)
                ui.panel.cursor(x + 30, y + 10)
            end }))
        else
            local name = e.who
            local font = ui.font("small")
            local lines = wrap(e.text, font, AREA.w - 60 - 12)
            local lh = font:getHeight() + 2
            local top = name and 24 or 0
            table.insert(rows, { h = top + #lines * lh + 10, draw = function(x, y, w)
                if name then
                    ui.print(name, x, y, { font = "small", color = e.color and ui.theme.nameColor(e.color) or "accent" })
                end
                for i, line in ipairs(lines) do
                    ui.print(line, x + 12, y + top + (i - 1) * lh, { font = font, color = name and "ink" or "faded" })
                end
            end })
        end
    end
    if #rows == 0 then
        return { placeholder("Пока никто ничего не сказал.") }
    end
    return rows
end

local BUILD = { taskRows, function() return choiceRows(nil) end, relationRows, codexRows, historyRows }

-- a scrolling list of rows inside a rectangle ----------------------------------------

local function lastFirst(rows, h)
    local sum = 0
    for i = #rows, 1, -1 do
        sum = sum + rows[i].h
        if sum > h then
            return math.min(#rows, i + 1)
        end
    end
    return 1
end

local function drawRows(rows, first, x, y, w, h)
    local cy, last = y, first - 1
    for i = first, #rows do
        if cy + rows[i].h > y + h and i > first then
            break
        end
        rows[i].draw(x, cy, w)
        cy = cy + rows[i].h
        last = i
    end
    return last
end

-- the journal --------------------------------------------------------------------------

local Journal = class()
Journal.transparent = true

-- tab: a number or "tasks", "choices", "relations", "codex", "history"
function Journal:init(host, tab)
    self.host = host
    self.tab = TAB_IDS[tab] or tonumber(tab) or 1
    self.first = {}
    self.time = 0
    self.rects = {}
    self:build()
end

function Journal:build()
    self.rows = BUILD[self.tab]()
    self.maxFirst = lastFirst(self.rows, AREA.h - 36)
    if self.tab == TAB_IDS.history and not self.first[self.tab] then
        self.first[self.tab] = self.maxFirst -- the conversation: from the end
    end
end

function Journal:enter()
    audio.play("card_slide")
end

function Journal:close()
    audio.play("ui_back")
    if scene.top() == self then
        scene.pop()
    end
    require("game.ui.hud").showHints()
end

function Journal:switchTab(d)
    self.tab = (self.tab - 1 + d) % #TABS + 1
    audio.play("ui_move")
    self:build()
end

function Journal:scroll(d)
    local f = util.clamp((self.first[self.tab] or 1) + d, 1, self.maxFirst)
    if f ~= (self.first[self.tab] or 1) then
        self.first[self.tab] = f
        audio.play("ui_move")
    end
end

function Journal:update(dt)
    self.time = self.time + dt
    if self.time > 0.1 and (input.pressed("journal") or input.pressed("cancel") or input.pressed("pause")) then
        input.consume("pause")
        input.consume("cancel")
        input.consume("journal")
        self:close()
        return
    end
    if input.pressed("left", true) or input.pressed("tabLeft") then
        self:switchTab(-1)
    elseif input.pressed("right", true) or input.pressed("tabRight") then
        self:switchTab(1)
    end
    if input.pressed("up", true) then
        self:scroll(-1)
    elseif input.pressed("down", true) then
        self:scroll(1)
    end
    local m = input.mouse
    if m.wheel ~= 0 then
        self:scroll(m.wheel > 0 and -1 or 1)
    end
    for _, r in ipairs(self.rects) do
        if m.pressed[1] and util.pointInRect(m.x, m.y, r[1], r[2], r[3], r[4]) and r.tab ~= self.tab then
            m.pressed[1] = nil
            self.tab = r.tab
            audio.play("ui_move")
            self:build()
            return
        end
    end
end

function Journal:draw()
    ui.dim(0.55)
    self.rects = {}
    local tx, ty, tw = 40, 22, math.floor(880 / #TABS)
    ui.panel.draw(tx, ty, 880, 58)
    for i, name in ipairs(TABS) do
        local x = tx + (i - 1) * tw
        if i == self.tab then
            ui.panel.draw(x + 8, ty + 8, tw - 16, 42, "active")
        end
        ui.print(name, x + tw / 2, ty + 15, { font = "small", align = "center", color = i == self.tab and "accent" or "ink" })
        table.insert(self.rects, { x, ty, tw, 58, tab = i })
    end
    ui.print("Q", tx + 14, ty + 18, { font = "small", color = "faded" })
    ui.print("E", tx + 880 - 24, ty + 18, { font = "small", color = "faded" })
    local a = AREA
    ui.panel.draw(a.x, a.y, a.w, a.h)
    local first = self.first[self.tab] or 1
    local last = drawRows(self.rows, first, a.x + 30, a.y + 18, a.w - 60, a.h - 36)
    local wob = math.floor(math.sin(self.time * 6) * 2)
    if first > 1 then
        ui.panel.arrow(a.x + a.w - 24, a.y + 16 - wob, "up", 12, ui.theme.colors.accent)
    end
    if last < #self.rows then
        ui.panel.arrow(a.x + a.w - 24, a.y + a.h - 18 + wob, "down", 12, ui.theme.colors.accent)
    end
    local chapter = G().state.chapter
    ui.panel.draw(40, 484, 880, 42)
    if chapter then
        ui.print(chapter, 62, 494, { font = "small", color = "faded" })
    end
    ui.keyHints(900, 490, { { "up" }, { "down", "листать" }, { "cancel", "Закрыть" } }, "right")
end

-- the decisions of a chapter on one screen --------------------------------------------

local Recap = class()
Recap.transparent = true

function Recap:init(title, chapter, onDone)
    self.title = title or "Итоги главы"
    self.chapter = chapter
    self.onDone = onDone
    self.time = 0
    self.rows = choiceRows(chapter)
    self.first = 1
    self.maxFirst = lastFirst(self.rows, 300)
end

function Recap:enter()
    audio.play("bell")
end

function Recap:update(dt)
    self.time = self.time + dt
    if input.pressed("up", true) then
        self.first = math.max(1, self.first - 1)
    elseif input.pressed("down", true) then
        self.first = math.min(self.maxFirst, self.first + 1)
    end
    if self.time > 0.6 and (input.pressed("confirm") or input.pressed("interact") or input.pressed("cancel") or input.mouse.pressed[1]) then
        input.consume("confirm")
        input.consume("interact")
        input.consume("cancel")
        input.mouse.pressed[1] = nil
        audio.play("ui_select")
        if scene.top() == self then
            scene.pop()
        end
        if self.onDone then
            self.onDone()
        end
    end
end

function Recap:draw()
    local alpha = math.min(1, self.time * 3)
    ui.dim(0.65 * alpha)
    local w, h = 760, 440
    local x, y = math.floor((screen.width - w) / 2), math.floor((screen.height - h) / 2)
    ui.panel.draw(x, y, w, h)
    ui.print(self.title, screen.width / 2, y + 22, { font = "title", align = "center", color = "accent" })
    if self.chapter then
        ui.print(self.chapter, screen.width / 2, y + 66, { font = "small", align = "center", color = "faded" })
    end
    local last = drawRows(self.rows, self.first, x + 40, y + 100, w - 80, 300)
    if last < #self.rows then
        ui.panel.arrow(x + w - 28, y + h - 30, "down", 12, ui.theme.colors.accent)
    end
    if self.time > 0.6 then
        ui.keyHint(screen.width / 2, y + h + 8, "confirm", "Дальше")
    end
end

Journal.Recap = Recap
return Journal
