function love.conf(t)
    t.identity = "SagaOfGrisha"   -- save folder name
    t.version = "11.4"            -- works with LOVE 11.4 and 11.5
    t.window.title = "Сага о Грише"
    t.window.width = 960
    t.window.height = 540
    t.window.minwidth = 480
    t.window.minheight = 270
    t.window.resizable = true
    t.window.vsync = 1
    t.modules.physics = false
end
