local Voice = require("lib/voice")
local music = require 'musicutil'
local mod = require 'core/mods'



local V5_default0 = controlspec.def {
    min = -5.0,
    max = 5.0,
    warp = 'lin',
    step = 0.00,
    default = 0.0,
    quantum = 0.01,
    wrap = false,
    units = 'V'
}

local V5_default1 = controlspec.def {
    min = -5.0,
    max = 5.0,
    warp = 'lin',
    step = 0.00,
    default = 1.0,
    quantum = 0.01,
    wrap = false,
    units = 'V'
}

local V5_default5 = controlspec.def {
    min = -5.0,
    max = 5.0,
    warp = 'lin',
    step = 0.00,
    default = 5.0,
    quantum = 0.01,
    wrap = false,
    units = 'V'
}

local V5_default_neg5 = controlspec.def {
    min = -5.0,
    max = 5.0,
    warp = 'lin',
    step = 0.00,
    default = -5.0,
    quantum = 0.01,
    wrap = false,
    units = 'V'
}

local N16 = controlspec.def {
    min = 1,
    max = 16,
    warp = 'lin',
    step = 1,
    default = 1,
    quantum = 0.01,
    wrap = false,
    units = ''
}

local v5 = controlspec.new(-5.0, 5.0, 'lin', 0, 0.0, "", 0.1, false)

if note_players == nil then
    note_players = {}
end

local player = {
    allocator = Voice.new(4, Voice.LRU),
    is_active = false,
    notes = {},
    modulation = 0,
    channel_map = {0,0,0,0}
}

local WSYN_SUSTAIN_STEAL = 1
local WSYN_PLUCK = 2

function player:add_params()
    params:add_group("nb_w/syn", "w/syn", 9)

    params:add_option("nb_w/style", "style", { "dynamic poly", "pluck" }, 1)
    params:set_action("nb_w/style", function(param)
        if not self.is_active then
            return
        end
        if param == WSYN_PLUCK then
            crow.ii.wsyn.ar_mode(1)
        else
            crow.ii.wsyn.ar_mode(0)
        end
        crow.ii.wsyn.voices(4)
    end)

    params:add_control("nb_w/curve", "curve", V5_default5)
    params:set_action("nb_w/curve", function(param)
        if not self.is_active then
            return
        end
        crow.ii.wsyn.curve(param)
    end)

    params:add_control("nb_w/ramp", "ramp", V5_default0)
    params:set_action("nb_w/ramp", function(param)
        if not self.is_active then
            return
        end
        crow.ii.wsyn.ramp(param)
    end)

    params:add_control("nb_w/fm_index", "fm index", V5_default1)
    params:set_action("nb_w/fm_index", function(param)
        if not self.is_active then
            return
        end        
        crow.ii.wsyn.fm_index(param + self.modulation)
    end)

    params:add_control("nb_w/fm_env", "fm envelope", V5_default1)
    params:set_action("nb_w/fm_env", function(param)
        if not self.is_active then
            return
        end        
        crow.ii.wsyn.fm_env(param)
    end)

    params:add_control("nb_w/fm_num", "ratio numerator", N16)
    params:set_action("nb_w/fm_num", function(param)
        if not self.is_active then
            return
        end        
        crow.ii.wsyn.fm_ratio(param, params:get("nb_w/fm_denom"))
    end)

    params:add_control("nb_w/fm_denom", "ratio denominator", N16)
    params:set_action("nb_w/fm_denom", function(param)
        if not self.is_active then
            return
        end        
        crow.ii.wsyn.fm_ratio(params:get("nb_w/fm_num"), param)
    end)

    params:add_control("nb_w/lpg_time", "lpg time", V5_default0)
    params:set_action("nb_w/lpg_time", function(param)
        if not self.is_active then
            return
        end        
        crow.ii.wsyn.lpg_time(param)
    end)

    params:add_control("nb_w/lpg_symmetry", "lpg symmetry", V5_default_neg5)
    params:set_action("nb_w/lpg_symmetry", function(param)
        if not self.is_active then
            return
        end
        crow.ii.wsyn.lpg_symmetry(param)
    end)

    params:hide("nb_w/syn")
end

function player:modulate(val)
    self.modulation = val
    params:lookup_param("nb_w/fm_index"):bang()
end

function player:note_on(note, vel)
    local v8 = (note - 60) / 12
    local v_vel = vel * 5
    if params:get("nb_w/style") == WSYN_SUSTAIN_STEAL then
        local slot = self.allocator:get()
        self.notes[note] = slot
        local index = self.channel_map[slot.id] + 1
        self.channel_map[slot.id] = index
        crow.ii.wsyn.play_voice(slot.id, v8, v_vel)
        slot.on_release = function(slot)
            if self.channel_map[slot.id] == index then
                crow.ii.wsyn.velocity(slot.id, 0)
            end
        end
    else
        crow.ii.wsyn.play_note(v8, v_vel)
    end
end

function player:delayed_active()
    params:show("nb_w/syn")
    for _, p in ipairs({
        "nb_w/style", 
        "nb_w/ramp", 
        "nb_w/fm_index", 
        "nb_w/curve",
        "nb_w/fm_env",
        "nb_w/fm_num",
        "nb_w/fm_denom",
        "nb_w/lpg_time",
        "nb_w/lpg_symmetry"}) do
            local prm = params:lookup_param(p)
            prm:bang()
    end
end

function player:inactive()
    self.is_active = false
    if self.active_routine ~= nil then
        clock.cancel(self.active_routine)
    end
end

function player:stop_all()
    for v=1,4 do
        crow.ii.wsyn.velocity(v, 0)
    end
    self.notes = {}
end

function player:note_off(note)
    local slot = self.notes[note]
    if slot then
        self.allocator:release(slot)
    end
end

function player:describe()
    return {
        name = "w/syn",
        supports_bend = false,
        supports_slew = false,
        modulate_description = "index",
    }
end


mod.hook.register("script_pre_init", "nb w/syn pre init", function()
    note_players["w/syn"] = player
end)
