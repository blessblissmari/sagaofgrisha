-- A tiny 3D renderer in the spirit of the PlayStation 1 (the world map uses it).
--
--   local r3d = require("engine.r3d")
--   local tower = r3d.model("assets/models/kenney/tower.obj")  -- OBJ + MTL, cached
--   local atlas = r3d.Atlas()                 -- all model textures in one image
--   local b = r3d.Builder(atlas)              -- collects triangles in world space
--   b:model(tower, { x = 3, y = 0, z = 5, rot = 0.5, scale = 1 })
--   local mesh = b:build()                    -- one Mesh = one draw call
--   local view = r3d.View(320, 180, { fov = 0.9, curve = 0.004 })
--   view:look(ex, ey, ez, tx, ty, tz)         -- the camera
--   view:begin(sky)  view:draw(mesh)  view:finish()
--   love.graphics.draw(view.canvas, 0, 0, 0, 3, 3)
--
-- The PS1 look lives in assets/shaders/ps1.glsl: a low resolution canvas, vertices
-- snapped to its pixels, affine textures, per-vertex fog, 15-bit colour with ordered
-- dithering, dithered transparency. "curve" bends the world down with the distance
-- from the point the camera looks at, like the world maps of Final Fantasy VII-IX.
--
-- Coordinates: x to the east, y up, z to the south (a Tiled map seen from above).
-- Matrices are row-major tables of 16 numbers.

local class = require("engine.class")

local r3d = {}

-- matrices ---------------------------------------------------------------------------

function r3d.mul(a, b)
    local c = {}
    for i = 0, 12, 4 do
        local a1, a2, a3, a4 = a[i + 1], a[i + 2], a[i + 3], a[i + 4]
        for j = 1, 4 do
            c[i + j] = a1 * b[j] + a2 * b[4 + j] + a3 * b[8 + j] + a4 * b[12 + j]
        end
    end
    return c
end

function r3d.perspective(fovy, aspect, near, far)
    local f = 1 / math.tan(fovy / 2)
    return {
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (far + near) / (near - far), 2 * far * near / (near - far),
        0, 0, -1, 0,
    }
end

function r3d.lookAt(ex, ey, ez, tx, ty, tz)
    local fx, fy, fz = tx - ex, ty - ey, tz - ez
    local l = math.sqrt(fx * fx + fy * fy + fz * fz)
    fx, fy, fz = fx / l, fy / l, fz / l
    -- s = f x up (up = 0, 1, 0)
    local sx, sy, sz = -fz, 0, fx
    l = math.sqrt(sx * sx + sz * sz)
    sx, sz = sx / l, sz / l
    -- u = s x f
    local ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
    return {
        sx, sy, sz, -(sx * ex + sy * ey + sz * ez),
        ux, uy, uz, -(ux * ex + uy * ey + uz * ez),
        -fx, -fy, -fz, fx * ex + fy * ey + fz * ez,
        0, 0, 0, 1,
    }
end

-- texture atlas ----------------------------------------------------------------------

-- Every texture of every model goes into one image: a chunk of the world with houses,
-- trees and fences is then one Mesh. Models repeat their textures (uv beyond 0..1),
-- the shader does it inside the texture's rectangle (fract), so nothing bleeds.
local Atlas = class()
r3d.Atlas = Atlas

function Atlas:init(size)
    self.size = size or 1024
    self.data = love.image.newImageData(self.size, self.size)
    self.rects = {}
    self.x, self.y, self.row = 0, 0, 0
    self.dirty = true
    -- a white corner for the untextured triangles (Builder:quad without a rect)
    local white = love.image.newImageData(4, 4)
    white:mapPixel(function() return 1, 1, 1, 1 end)
    self.white = self:rect(white)
end

-- the rectangle { u, v, w, h } (0..1) of an image file or an ImageData in the atlas
function Atlas:rect(source)
    local key = source
    local r = self.rects[key]
    if r then
        return r
    end
    local data = source
    if type(source) == "string" then
        local ok, d = pcall(love.image.newImageData, source)
        if not ok then
            print("[r3d] no texture " .. source)
            d = love.image.newImageData(1, 1)
            d:setPixel(0, 0, 1, 0, 1, 1)
        end
        data = d
    end
    local w, h = data:getDimensions()
    if self.x + w > self.size then
        self.x, self.y, self.row = 0, self.y + self.row, 0
    end
    assert(self.y + h <= self.size, "r3d atlas is full")
    self.data:paste(data, self.x, self.y, 0, 0, w, h)
    local s = self.size
    r = { self.x / s, self.y / s, w / s, h / s, x = self.x, y = self.y, w = w, h = h }
    self.x = self.x + w
    self.row = math.max(self.row, h)
    self.rects[key] = r
    self.dirty = true
    return r
end

function Atlas:image()
    if self.dirty or not self.img then
        if self.img then
            self.img:release()
        end
        self.img = love.graphics.newImage(self.data)
        self.img:setFilter("nearest", "nearest")
        self.dirty = false
    end
    return self.img
end

-- OBJ models -------------------------------------------------------------------------

local function readMtl(path, dir, out)
    if not love.filesystem.getInfo(path) then
        return out
    end
    local current
    for line in love.filesystem.lines(path) do
        local cmd, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
        if cmd == "newmtl" then
            current = { name = rest, color = { 1, 1, 1 } }
            out[rest] = current
        elseif current and cmd == "Kd" then
            local r, g, b = rest:match("(%S+)%s+(%S+)%s+(%S+)")
            current.color = { tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1 }
        elseif current and cmd == "map_Kd" then
            current.texture = dir .. rest:gsub("\\", "/")
        end
    end
    return out
end

local cache = {}

-- Loads an OBJ (+ its MTL). opts.texture: one texture for the whole model (when the MTL
-- has none), opts.flipV = false keeps the OBJ texture rows as they are.
-- Returns { verts = { { x, y, z, u, v, nx, ny, nz, r, g, b, texture }, ... }, min, max }
function r3d.model(path, opts)
    opts = opts or {}
    local key = path .. "|" .. tostring(opts.texture)
    if cache[key] then
        return cache[key]
    end
    local dir = path:match("^(.*/)") or ""
    local pos, uvs, nrm = {}, {}, {}
    local mats = {}
    local mat = { color = { 1, 1, 1 }, texture = opts.texture }
    local verts = {}
    local minx, miny, minz, maxx, maxy, maxz = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
    local function corner(token)
        local vi, ti, ni = token:match("^(%-?%d+)/?(%-?%d*)/?(%-?%d*)$")
        vi, ti, ni = tonumber(vi), tonumber(ti), tonumber(ni)
        if vi and vi < 0 then vi = #pos + 1 + vi end
        if ti and ti < 0 then ti = #uvs + 1 + ti end
        if ni and ni < 0 then ni = #nrm + 1 + ni end
        return pos[vi], ti and uvs[ti], ni and nrm[ni]
    end
    for line in love.filesystem.lines(path) do
        local cmd, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
        if cmd == "v" then
            local t = {}
            for n in rest:gmatch("%S+") do t[#t + 1] = tonumber(n) end
            pos[#pos + 1] = t
            minx, maxx = math.min(minx, t[1]), math.max(maxx, t[1])
            miny, maxy = math.min(miny, t[2]), math.max(maxy, t[2])
            minz, maxz = math.min(minz, t[3]), math.max(maxz, t[3])
        elseif cmd == "vt" then
            local u, v = rest:match("(%S+)%s+(%S+)")
            uvs[#uvs + 1] = { tonumber(u), tonumber(v) }
        elseif cmd == "vn" then
            local x, y, z = rest:match("(%S+)%s+(%S+)%s+(%S+)")
            nrm[#nrm + 1] = { tonumber(x), tonumber(y), tonumber(z) }
        elseif cmd == "mtllib" then
            readMtl(dir .. rest, dir, mats)
        elseif cmd == "usemtl" then
            mat = mats[rest] or { color = { 1, 1, 1 } }
            if opts.texture then
                mat = { color = mat.color, texture = opts.texture }
            end
        elseif cmd == "f" then
            local face = {}
            for token in rest:gmatch("%S+") do
                local p, t, n = corner(token)
                face[#face + 1] = { p, t, n }
            end
            -- face normal (for models without normals)
            local a, b, c = face[1][1], face[2][1], face[3][1]
            local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
            local fx, fy, fz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
            if fl > 0 then fx, fy, fz = fx / fl, fy / fl, fz / fl end
            for i = 2, #face - 1 do
                for _, k in ipairs({ 1, i, i + 1 }) do
                    local p, t, n = face[k][1], face[k][2], face[k][3]
                    local cr, cg, cb = p[4] or 1, p[5] or 1, p[6] or 1
                    local u, v = 0, 0
                    if t then
                        u, v = t[1], t[2]
                        if opts.flipV ~= false then v = 1 - v end
                    end
                    verts[#verts + 1] = {
                        p[1], p[2], p[3], u, v,
                        n and n[1] or fx, n and n[2] or fy, n and n[3] or fz,
                        cr * mat.color[1], cg * mat.color[2], cb * mat.color[3], mat.texture,
                    }
                end
            end
        end
    end
    local m = { verts = verts, min = { minx, miny, minz }, max = { maxx, maxy, maxz }, path = path }
    cache[key] = m
    return m
end

-- mesh builders ----------------------------------------------------------------------

r3d.FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "byte", 4 },
    { "a_rect", "float", 4 },
}

-- the ground (shader "terrain"): VertexTexCoord = world x, z; a_w1, a_w2 = how much of
-- each of the 8 ground textures is at the vertex
r3d.TERRAIN_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "byte", 4 },
    { "a_w1", "float", 4 },
    { "a_w2", "float", 4 },
}

-- the light baked into the vertex colours: ambient + sun (Lambert)
r3d.light = { sun = { 0.45, 0.8, 0.4 }, ambient = 0.55, diffuse = 0.6 }

function r3d.shade(nx, ny, nz, light)
    light = light or r3d.light
    local s = light.sun
    local d = nx * s[1] + ny * s[2] + nz * s[3]
    return math.min(1, light.ambient + light.diffuse * math.max(0, d))
end

local Builder = class()
r3d.Builder = Builder

function Builder:init(atlas, light)
    self.atlas = atlas
    self.light = light
    self.verts = {}
end

-- t = { x, y, z, rot (radians around y), scale or sx, sy, sz, tint = { r, g, b },
--       center = true (the middle of the model at x, z), base = true (its bottom at y) }
function Builder:model(m, t)
    local x, y, z = t.x or 0, t.y or 0, t.z or 0
    local sx = t.sx or t.scale or 1
    local sy, sz = t.sy or t.scale or 1, t.sz or t.scale or 1
    local c, s = math.cos(t.rot or 0), math.sin(t.rot or 0)
    local cx, cy, cz = 0, 0, 0
    if t.center then
        cx, cz = (m.min[1] + m.max[1]) / 2, (m.min[3] + m.max[3]) / 2
    end
    if t.base then
        cy = m.min[2]
    end
    local tint = t.tint
    local out = self.verts
    local atlas = self.atlas
    local light = self.light
    for _, v in ipairs(m.verts) do
        local px, py, pz = (v[1] - cx) * sx, (v[2] - cy) * sy, (v[3] - cz) * sz
        local nx, nz = v[6] * c + v[8] * s, -v[6] * s + v[8] * c
        local ny = v[7]
        local shade = r3d.shade(nx, ny, nz, light)
        local r, g, b = v[9] * shade, v[10] * shade, v[11] * shade
        if tint then r, g, b = r * tint[1], g * tint[2], b * tint[3] end
        local rect = v[12] and atlas:rect(v[12]) or nil
        out[#out + 1] = {
            x + px * c + pz * s, y + py, z - px * s + pz * c,
            v[4], v[5], r, g, b, 1,
            rect and rect[1] or 0, rect and rect[2] or 0, rect and rect[3] or 0, rect and rect[4] or 0,
        }
    end
end

-- a group of models (game/data/prefabs.lua): def = { scale, parts = { { model, x, z,
-- y, rot, scale, tint, texture, center } } }, t = { x, y, z, rot, tint }
function Builder:prefab(def, t)
    local S = def.scale or 1
    local R = t.rot or 0
    local c, s = math.cos(R), math.sin(R)
    for _, p in ipairs(def.parts or {}) do
        local m = r3d.model("assets/models/" .. p[1] .. ".obj", { texture = p.texture })
        local px, pz = (p[2] or 0) * S, (p[3] or 0) * S
        local tint = p.tint or t.tint
        if p.tint and t.tint then
            tint = { p.tint[1] * t.tint[1], p.tint[2] * t.tint[2], p.tint[3] * t.tint[3] }
        end
        self:model(m, {
            x = (t.x or 0) + px * c + pz * s, z = (t.z or 0) - px * s + pz * c,
            y = (t.y or 0) + (p.y or 0) * S,
            rot = R + (p.rot or 0), scale = (p.scale or 1) * S,
            tint = tint, center = p.center, base = p.base,
        })
    end
end

-- a quad: four corners { x, y, z } in order, uv of the image rect (whole rect = 0..1)
function Builder:quad(p1, p2, p3, p4, rect, color, uv)
    uv = uv or { 0, 0, 1, 1 }
    color = color or { 1, 1, 1 }
    local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
    local r = rect
    if not r then
        local w = self.atlas and self.atlas.white
        -- the middle of the white corner: every uv lands on white
        r = w and { w[1] + w[3] * 0.25, w[2] + w[4] * 0.25, w[3] * 0.5, w[4] * 0.5 } or { 0, 0, 0, 0 }
    end
    local function V(p, u, v)
        return { p[1], p[2], p[3], u, v, color[1], color[2], color[3], color[4] or 1, r[1], r[2], r[3], r[4] }
    end
    local out = self.verts
    local a, b, c, d = V(p1, u0, v0), V(p2, u1, v0), V(p3, u1, v1), V(p4, u0, v1)
    out[#out + 1], out[#out + 2], out[#out + 3] = a, b, c
    out[#out + 1], out[#out + 2], out[#out + 3] = a, c, d
end

function Builder:count()
    return #self.verts
end

function Builder:build(mode)
    if #self.verts == 0 then
        return nil
    end
    local mesh = love.graphics.newMesh(r3d.FORMAT, self.verts, "triangles", mode or "static")
    if self.atlas then
        mesh:setTexture(self.atlas:image())
    end
    return mesh
end

-- Sprites standing in the 3D world (hero, pets, effects): quads that turn to the camera.
-- One Batch per texture, refilled every frame.
local Batch = class()
r3d.Batch = Batch

function Batch:init(texture, max)
    self.texture = texture
    self.max = max or 64
    local verts = {}
    for i = 1, self.max * 6 do
        verts[i] = { 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0 }
    end
    self.mesh = love.graphics.newMesh(r3d.FORMAT, verts, "triangles", "stream")
    self.mesh:setTexture(texture)
    self.verts = {}
    self.n = 0
end

function Batch:clear()
    self.n = 0
end

-- x, y, z: the feet; w, h: size in world units; quad: a love Quad of the texture;
-- rx, rz: the camera's right vector (horizontal); flip: mirror; color { r, g, b, a }
function Batch:add(x, y, z, w, h, quad, rx, rz, flip, color)
    if self.n >= self.max then
        return
    end
    local qx, qy, qw, qh = quad:getViewport()
    local tw, th = self.texture:getDimensions()
    local u0, v0, u1, v1 = qx / tw, qy / th, (qx + qw) / tw, (qy + qh) / th
    if flip then u0, u1 = u1, u0 end
    local hw = w / 2
    local ax, az = x - rx * hw, z - rz * hw
    local bx, bz = x + rx * hw, z + rz * hw
    local r, g, b, a = 1, 1, 1, 1
    if color then r, g, b, a = color[1], color[2], color[3], color[4] or 1 end
    local base = self.n * 6
    local verts = self.verts
    local function set(i, px, py, pz, u, v)
        local t = verts[base + i]
        if not t then
            t = {}
            verts[base + i] = t
        end
        t[1], t[2], t[3], t[4], t[5] = px, py, pz, u, v
        t[6], t[7], t[8], t[9] = r, g, b, a
        t[10], t[11], t[12], t[13] = 0, 0, 0, 0
    end
    set(1, ax, y + h, az, u0, v0)
    set(2, bx, y + h, bz, u1, v0)
    set(3, bx, y, bz, u1, v1)
    set(4, ax, y + h, az, u0, v0)
    set(5, bx, y, bz, u1, v1)
    set(6, ax, y, az, u0, v1)
    self.n = self.n + 1
end

-- a quad lying on the ground (shadows, boats): centre x, z, size w x d, turned by rot
function Batch:addFlat(x, y, z, w, d, quad, rot, color)
    if self.n >= self.max then
        return
    end
    local qx, qy, qw, qh = quad:getViewport()
    local tw, th = self.texture:getDimensions()
    local u0, v0, u1, v1 = qx / tw, qy / th, (qx + qw) / tw, (qy + qh) / th
    local c, s = math.cos(rot or 0), math.sin(rot or 0)
    local hw, hd = w / 2, d / 2
    local function P(px, pz)
        return x + px * c + pz * s, z - px * s + pz * c
    end
    local r, g, b, a = 1, 1, 1, 1
    if color then r, g, b, a = color[1], color[2], color[3], color[4] or 1 end
    local base = self.n * 6
    local verts = self.verts
    local function set(i, px, pz, u, v)
        local wx, wz = P(px, pz)
        local t = verts[base + i]
        if not t then
            t = {}
            verts[base + i] = t
        end
        t[1], t[2], t[3], t[4], t[5] = wx, y, wz, u, v
        t[6], t[7], t[8], t[9] = r, g, b, a
        t[10], t[11], t[12], t[13] = 0, 0, 0, 0
    end
    set(1, -hw, -hd, u0, v0)
    set(2, hw, -hd, u1, v0)
    set(3, hw, hd, u1, v1)
    set(4, -hw, -hd, u0, v0)
    set(5, hw, hd, u1, v1)
    set(6, -hw, hd, u0, v1)
    self.n = self.n + 1
end

function Batch:flush()
    if self.n == 0 then
        return false
    end
    local count = self.n * 6
    local verts = self.verts
    -- setVertices with a table of exactly the used vertices
    local used = verts
    if #verts > count then
        used = {}
        for i = 1, count do used[i] = verts[i] end
    end
    self.mesh:setVertices(used, 1)
    self.mesh:setDrawRange(1, count)
    return true
end

-- shaders ----------------------------------------------------------------------------

local shaderCache = {}

-- kind: "model" (textured triangles and sprites), "terrain" (the ground blend),
-- "water". All three come from assets/shaders/ps1.glsl.
function r3d.shader(kind)
    if shaderCache[kind] ~= nil then
        return shaderCache[kind] or nil
    end
    local code = love.filesystem.read("assets/shaders/ps1.glsl")
    local defines = { model = "", terrain = "#define TERRAIN\n", water = "#define WATER\n" }
    local ok, sh = pcall(love.graphics.newShader, (defines[kind] or "") .. code)
    if not ok then
        print("[r3d] shader " .. kind .. ": " .. tostring(sh))
        sh = false
    end
    shaderCache[kind] = sh
    return sh or nil
end

local function send(sh, name, ...)
    if sh:hasUniform(name) then
        sh:send(name, ...)
    end
end
r3d.send = send

-- the camera and its low resolution canvas ----------------------------------------------

local View = class()
r3d.View = View

-- opts: fov (vertical, radians), near, far, curve, fog = { start, end }, fogColor,
-- snap = false (no vertex snapping), affine = 0..1 (texture wobble)
function View:init(w, h, opts)
    opts = opts or {}
    self.w, self.h = w, h
    self.canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
    self.canvas:setFilter("nearest", "nearest")
    self.fov = opts.fov or 0.9
    self.near, self.far = opts.near or 0.1, opts.far or 200
    self.proj = r3d.perspective(self.fov, w / h, self.near, self.far)
    self.curve = opts.curve or 0
    self.fog = opts.fog or { 18, 34 }
    self.fogColor = opts.fogColor or { 0.75, 0.85, 0.95 }
    self.snap = opts.snap ~= false
    self.affine = opts.affine or 0.6
    self.time = 0
    self.shaders = {}
    for _, kind in ipairs({ "model", "terrain", "water" }) do
        self.shaders[kind] = r3d.shader(kind)
    end
    self.ok = self.shaders.model ~= nil
    self:look(0, 5, 5, 0, 0, 0)
end

function View:look(ex, ey, ez, tx, ty, tz)
    self.eye = { ex, ey, ez }
    self.center = { tx, ty, tz }
    self.view = r3d.lookAt(ex, ey, ez, tx, ty, tz)
    self.viewProj = r3d.mul(self.proj, self.view)
end

-- world point -> canvas pixels (x, y, depth); nil when behind the camera
function View:project(x, y, z)
    local dx, dz = x - self.center[1], z - self.center[3]
    y = y - (dx * dx + dz * dz) * self.curve
    local m = self.viewProj
    local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
    local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
    local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
    if cw <= 0.01 then
        return nil
    end
    return (cx / cw * 0.5 + 0.5) * self.w, (0.5 - cy / cw * 0.5) * self.h, cw
end

function View:begin(clear)
    local lg = love.graphics
    lg.push("all")
    lg.setCanvas({ self.canvas, depth = true })
    lg.origin()
    local c = clear or self.fogColor
    lg.clear(c[1], c[2], c[3], 1)
    for kind, sh in pairs(self.shaders) do
        if sh then
            send(sh, "u_proj", "row", self.proj)
            send(sh, "u_view", "row", self.view)
            send(sh, "u_center", self.center)
            send(sh, "u_curve", self.curve)
            send(sh, "u_snap", self.snap and { self.w / 2, self.h / 2 } or { 0, 0 })
            send(sh, "u_fog", self.fog)
            send(sh, "u_fogColor", self.fogColor)
            send(sh, "u_affine", self.affine)
            send(sh, "u_time", self.time)
            send(sh, "u_wave", self.time)
            send(sh, "u_offset", { 0, 0, 0 })
            send(sh, "u_rot", { 1, 0 })
            send(sh, "u_focus", { 0, 0, 0, 0 })
        end
    end
    self.current = nil
end

-- 2D drawing on the canvas before the 3D (the sky): fn()
function View:background(fn)
    love.graphics.setDepthMode("always", false)
    fn(self.w, self.h)
    love.graphics.setShader()
end

-- draw a mesh: kind = "model" | "terrain" | "water", moved by ox, oy, oz and turned
-- around y by rot (radians, the same way as Builder:model)
function View:draw(mesh, kind, ox, oy, oz, rot)
    local sh = self.shaders[kind or "model"]
    if not sh or not mesh then
        return
    end
    local lg = love.graphics
    if kind == "water" then
        lg.setDepthMode("lequal", false)
        lg.setBlendMode("alpha")
    else
        lg.setDepthMode("lequal", true)
        lg.setBlendMode("replace")
    end
    if self.current ~= sh then
        lg.setShader(sh)
        self.current = sh
    end
    send(sh, "u_offset", { ox or 0, oy or 0, oz or 0 })
    rot = rot or 0
    send(sh, "u_rot", { math.cos(rot), math.sin(rot) })
    lg.draw(mesh)
end

-- models nearer than depth inside a circle (canvas pixels) become see-through
-- (the hero stays visible behind trees); radius 0 = off
function View:focus(x, y, radius, depth)
    local sh = self.shaders.model
    if sh then
        send(sh, "u_focus", { x or 0, y or 0, radius or 0, depth or 0 })
    end
end

function View:finish()
    love.graphics.setShader()
    love.graphics.setDepthMode()
    love.graphics.pop()
    self.current = nil
end

return r3d
