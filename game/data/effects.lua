-- Sprite sheet effects: effects:play("slash", x, y).
-- "Free Pixel Effects Pack" by CodeManu (CC0), 100x100 frames;
-- puff and sparkle: GrafxKid "Arcade Platformer Assets" (CC0), 16x16 frames;
-- boom: "Warped Space Shooter" by ansimuz (CC0), 32x32 pixel frames drawn 2x.

local FX = "assets/sprites/fx/"
local PLATFORMER = "assets/sprites/platformer/arcade_platformer.png"

return {
    slash = { image = FX .. "weaponhit.png", frame = 100, columns = 6, count = 30, fps = 60 },
    magic = { image = FX .. "magichit.png", frame = 100, columns = 7, count = 40, fps = 60 },
    shield = { image = FX .. "protection.png", frame = 100, columns = 8, count = 61, fps = 55 },
    cast = { image = FX .. "casting.png", frame = 100, columns = 9, count = 72, fps = 70 },
    puff = { image = PLATFORMER, x = 0, y = 128, frame = 16, columns = 5, count = 5, fps = 18 },
    boom = { image = "assets/sprites/shmup/explosion.png", frame = 32, columns = 6, count = 5, fps = 13, scale = 2 },
    sparkle = { image = PLATFORMER, x = 128, y = 112, frame = 16, columns = 4, count = 4, fps = 14 },
}
