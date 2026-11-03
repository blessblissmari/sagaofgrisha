-- Skies for the sky sphere behind battles (see engine/sky.lua for all fields).
-- In story.lua: game.stage "fight" { kind = "battle", sky = "sunset", ... }
-- or a table: sky = { top = "#203060", horizon = "#e09060", band = "mountains", clouds = 0.4 }
-- band = a background from backgrounds.lua wrapped around the horizon.

return {
    day = {
        top = "#3a6fc4", horizon = "#bfe0f5", ground = "#3d5f2a", groundHorizon = "#8fae7a",
        sun = { yaw = 0.8, pitch = 0.5, color = "#fff6d8" }, clouds = 0.55, band = "mountains",
    },
    meadow = {
        top = "#4a86d0", horizon = "#d8f0ff", ground = "#4f7a33", groundHorizon = "#a6c98a",
        sun = { yaw = -0.6, pitch = 0.6 }, clouds = 0.4, band = "hills", bandRepeat = 7,
    },
    sunset = {
        top = "#2b2d5c", horizon = "#f09a6a", ground = "#2c2030", groundHorizon = "#a0607a",
        sun = { yaw = 0.2, pitch = 0.06, color = "#ffd09a", size = 0.06 }, clouds = 0.35,
        cloudColor = "#f4b8a0", band = "mountains",
    },
    night = {
        top = "#05060f", horizon = "#1c2448", ground = "#0a0c14", groundHorizon = "#1a2034",
        sun = { yaw = 2.2, pitch = 0.4, color = "#c8d8ff", size = 0.03 }, stars = 1, clouds = 0.15,
        cloudColor = "#303a60", band = "mountains",
    },
    forest = {
        top = "#2f5f8a", horizon = "#a8d0c0", ground = "#24361c", groundHorizon = "#5a7a48",
        sun = { yaw = 1.2, pitch = 0.7 }, clouds = 0.3, band = "forest", bandRepeat = 6, bandDrop = 0.05,
    },
    snow = {
        top = "#5a7fc0", horizon = "#e8f2ff", ground = "#c8d4e0", groundHorizon = "#eef4fa",
        sun = { yaw = -1.0, pitch = 0.3, color = "#ffffff" }, clouds = 0.6, band = "snowy", bandRepeat = 7,
    },
    dungeon = {
        top = "#07070b", horizon = "#2a2230", ground = "#141018", groundHorizon = "#2e2632",
        sun = false, stars = 0.15, clouds = 0, grid = 0.9,
    },
}
