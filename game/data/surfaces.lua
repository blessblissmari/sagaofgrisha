-- Footsteps: surface name (tile property "surface" in Tiled) -> sound folder
-- in assets/audio/steps. Add a surface: put it on tiles in Tiled and add a line here.

return {
    grass = { folder = "grass", volume = 0.3 },
    stone = { folder = "boots", volume = 0.35 },   -- cobblestone path: boots on concrete
    wood = { folder = "wood", volume = 0.45 },     -- the bridge
    water = { folder = "water", volume = 0.45 },
    gravel = { folder = "gravel", volume = 0.35 },
    tile = { folder = "tile", volume = 0.35 },
    metal = { folder = "metal", volume = 0.35 },
    bones = { folder = "bones", volume = 0.35 },
    mech = { folder = "mech", volume = 0.35 },
    paws = { folder = "dog", volume = 0.2 },       -- the bunny on any surface
    default = "grass",
}
