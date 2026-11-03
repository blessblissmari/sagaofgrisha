-- Every sound of the game by name: audio.play("hit"), audio.music("calm").
-- Paths are inside assets/audio. See engine/audio.lua for all fields.
-- Sounds that are not listed here are still found by file name in
-- searchFolders: audio.play("fa") plays instans/Fa.mp3.

return {
    root = "assets/audio/",
    searchFolders = { "instans", "sfx", "ui", "speech", "fx" },

    music = {
        calm = { file = "bg/m_bg.mp3", volume = 0.55 },
        -- "Dj Bewan" hard techno: ~143.5 BPM, first beat at 0.33 s (for beat effects)
        arcade = { file = "bg/m_arcade.mp3", volume = 0.6, bpm = 143.5, beatOffset = 0.33 },
    },

    sounds = {
        -- interface (Juhani Junkala, "512 Sound Effects", CC0)
        ui_move = { file = "ui/move.ogg", volume = 0.35 },
        ui_select = { file = "ui/select.ogg", volume = 0.5 },
        ui_back = { file = "ui/back.ogg", volume = 0.5 },
        ui_error = { file = "ui/error.ogg", volume = 0.5 },
        ui_text = { file = "ui/text.ogg", volume = 0.25, cooldown = 0.03 },
        ui_pause = { file = "ui/pause.ogg", volume = 0.5 },
        error = { file = "ui/error.ogg", volume = 0.5 },

        -- world and battle (the same pack)
        swing = { file = "sfx/swing.ogg", volume = 0.5, pitchVariation = 0.08 },
        hit = { file = "sfx/hit.ogg", volume = 0.6, pitchVariation = 0.1 },
        hurt = { file = "sfx/hurt.ogg", volume = 0.7 },
        pickup = { file = "sfx/pickup.ogg", volume = 0.6, pitchVariation = 0.05 },
        powerup = { file = "sfx/powerup.ogg", volume = 0.6 },
        pop = { file = "sfx/pop.ogg", volume = 0.6, pitchVariation = 0.1 },
        jump = { file = "sfx/jump.ogg", volume = 0.5, pitchVariation = 0.1 },
        land = { file = "sfx/land.ogg", volume = 0.5 },
        throw = { file = "sfx/throw.ogg", volume = 0.6, pitchVariation = 0.08 },
        lowhp = { file = "sfx/lowhp.ogg", volume = 0.5, cooldown = 2 },
        fanfare = { file = "sfx/fanfare.ogg", volume = 0.6 },
        stomp = { file = "sfx/stomp.ogg", volume = 0.6, pitchVariation = 0.1 },
        punch = { file = "sfx/punch.ogg", volume = 0.5, pitchVariation = 0.1 },
        dash = { file = "sfx/dash.ogg", volume = 0.45, maxDuration = 0.45, fadeOut = 0.2 },
        crumble = { file = "sfx/crumble.ogg", volume = 0.6 },
        unlock = { file = "sfx/unlock.ogg", volume = 0.6 },
        door = { file = "sfx/door.ogg", volume = 0.6 },
        coin = { file = "sfx/coin.ogg", volume = 0.45, pitchVariation = 0.05 },
        fall = { file = "sfx/fall.ogg", volume = 0.5 },
        portal = { file = "sfx/portal.ogg", volume = 0.5 },
        bonus = { file = "sfx/bonus.ogg", volume = 0.5 },
        zap = { file = "sfx/zap.ogg", volume = 0.5, pitchVariation = 0.1 },

        -- puzzles and arcade games
        blip = { file = "sfx/blip.ogg", volume = 0.4, pitchVariation = 0.05 },
        brick = { file = "sfx/brick.ogg", volume = 0.4, pitchVariation = 0.1 },
        brick_break = { file = "sfx/brick_break.ogg", volume = 0.45, pitchVariation = 0.1 },
        puyo_pop = { file = "sfx/puyo_pop.ogg", volume = 0.5 },
        chain = { file = "sfx/chain.ogg", volume = 0.55 },
        capture = { file = "sfx/capture.ogg", volume = 0.5 },
        card_flip = { file = "sfx/card_flip.ogg", volume = 0.5, pitchVariation = 0.08 },
        card_deal = { file = "sfx/card_deal.ogg", volume = 0.5, pitchVariation = 0.1 },
        chips = { file = "sfx/chips.ogg", volume = 0.5 },

        -- tetris
        t_move = { file = "sfx/t_move.ogg", volume = 0.3 },
        t_rotate = { file = "sfx/t_rotate.ogg", volume = 0.35 },
        t_lock = { file = "sfx/t_lock.ogg", volume = 0.45 },
        t_drop = { file = "sfx/t_drop.ogg", volume = 0.5 },
        t_line = { file = "sfx/t_line.ogg", volume = 0.6 },
        t_hold = { file = "sfx/t_hold.ogg", volume = 0.4 },
        t_level = { file = "sfx/t_level.ogg", volume = 0.6 },

        -- the game's own samples (assets/audio/instans), long ones are cut
        horn = { file = "instans/Horn.mp3", maxDuration = 2.5, fadeOut = 0.5 },        -- tetris: 4 lines
        rizz = { file = "instans/Rizz.mp3", volume = 0.8 },                            -- tetris: combo
        longsad = { file = "instans/LongSad.mp3", maxDuration = 6, fadeOut = 1.5 },    -- tetris: game over
        cool = { file = "instans/Cool.mp3" },                                          -- new record
        bdoom = { file = "instans/Bdoom.mp3" },                                        -- battle starts
        outro = { file = "instans/Outro.mp3", maxDuration = 8, fadeOut = 2 },          -- battle won
        die = { file = "instans/Die2.mp3" },                                           -- battle lost
        death = { file = "instans/Death.mp3", volume = 0.8 },                          -- someone died
        bell = { file = "instans/Bell.mp3", maxDuration = 3, fadeOut = 1 },            -- novel chapter
        bell2 = { file = "instans/Bell2.mp3", maxDuration = 2.5, fadeOut = 1 },        -- the bridge question
        what = { file = "instans/What.mp3", maxDuration = 2.5, fadeOut = 0.5 },        -- "no"
        dzing = { file = "instans/Dzing.mp3" },                                        -- "yes"
        snore = { file = "instans/Snore.mp3", volume = 0.45, cooldown = 8 },           -- the bunny sleeps
        illuminati = { file = "instans/Illuminati.mp3", maxDuration = 7.9 },           -- easter egg
        alien = { file = "speech/Alien.mp3", volume = 0.8 },                           -- the bunny says hi
        sos = { file = "instans/Sos.mp3", maxDuration = 3, fadeOut = 0.5, cooldown = 20 }, -- low hp
        lag = { file = "instans/Lag.mp3", maxDuration = 1.2, fadeOut = 0.3 },          -- arcade opens
        fa = { file = "instans/Fa.mp3", maxDuration = 1.2, fadeOut = 0.3 },            -- critical hit
        viu = { file = "instans/Viu.mp3", maxDuration = 1, fadeOut = 0.3 },            -- stone flies
        taunt = { files = { "instans/CHa.mp3", "instans/NHa.mp3", "instans/BHa.mp3" },
            maxDuration = 2, fadeOut = 0.4, volume = 0.7, cooldown = 3 },              -- enemies laugh
        blink = { file = "instans/Blink.mp3", volume = 0.7 },                          -- inventory
        favsong = { file = "instans/FavSong.mp3", volume = 0.8 },
        litvin = { file = "instans/Litvin.mp3", volume = 0.8 },
        explode = { file = "fx/Explode.mp3", volume = 0.6 },
    },
}
