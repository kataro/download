---@diagnostic disable: undefined-global, undefined-field
local ffi = require "ffi"
local vector = require "vector"
local http = require "gamesense/http"
-- local pui = require "libraries/pui"
local pui = require "gamesense/pui"
local csgo_weapons = require "gamesense/csgo_weapons"
local inspect = require "gamesense/inspect"
local base64 = require 'gamesense/base64'
local clipboard = require "gamesense/clipboard"
local c_entity = require "gamesense/entity"
local screen = vector(client.screen_size())
function lerp(a, b, t)
    return a + (b - a) * t
end
function round(value)
    return math.floor(value + 0.5)
end

local function ticks_to_time()
	return globals.tickinterval( ) * 15
end 

local function is_can_emulate()
    local enemies = entity.get_players(true)
    if not enemies or #enemies == 0 then
        return false
    end

    local me = entity.get_local_player()
    local eyePos = vector(client.eye_position())
    local velocity = vector(entity.get_prop(me, "m_vecVelocity"))
    local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    
    local prediction_time = ticks_to_time()
    
    local speed_factor = math.min(1.0, speed / 250)
    prediction_time = prediction_time * (0.8 + speed_factor * 0.7)

    local accel_factor = 1.0
    if speed < 80 then
        accel_factor = 1.3
    elseif speed > 240 then
        accel_factor = 0.85
    end
    
    local predictedPos = vector(
        eyePos.x + velocity.x * prediction_time * accel_factor,
        eyePos.y + velocity.y * prediction_time * accel_factor,
        eyePos.z + velocity.z * prediction_time * accel_factor
    )

    for i = 1, #enemies do
        local enemy = enemies[i]
        if entity.is_dormant(enemy) then goto continue end
        
        local enemy_weapon = entity.get_player_weapon(enemy)
        if enemy_weapon then
            local weapon_info = csgo_weapons(enemy_weapon)
            if weapon_info and weapon_info.weapon_type_int <= 2 then
                goto continue
            end
        end
        
        local enemyVelocity = vector(entity.get_prop(enemy, "m_vecVelocity"))
        local enemySpeed = math.sqrt(enemyVelocity.x * enemyVelocity.x + enemyVelocity.y * enemyVelocity.y)
        
        local enemy_factor = enemySpeed >= 0 and 1.0 or math.min(1.2, 1.0 + enemySpeed / 320)
        
        local enemyHeadPos = vector(entity.hitbox_position(enemy, 0))
        
        local visible_now = client.visible(enemyHeadPos.x, enemyHeadPos.y, enemyHeadPos.z)
        if visible_now then
            local _, current_damage = client.trace_bullet(
                me, 
                eyePos.x, eyePos.y, eyePos.z,
                enemyHeadPos.x, enemyHeadPos.y, enemyHeadPos.z
            )
            
            if current_damage > 10 then goto continue end
        end

        local predictedEnemyPos = vector(
            enemyHeadPos.x + enemyVelocity.x * prediction_time * enemy_factor,
            enemyHeadPos.y + enemyVelocity.y * prediction_time * enemy_factor,
            enemyHeadPos.z + enemyVelocity.z * prediction_time
        )
        
        local trace_entity, damage = client.trace_bullet(
            me,
            predictedPos.x, predictedPos.y, predictedPos.z,
            predictedEnemyPos.x, predictedEnemyPos.y, predictedEnemyPos.z
        )
        
        if damage > 20 then

            return true
        end
        
        local elevated_pos = vector(
            predictedPos.x,
            predictedPos.y,
            predictedPos.z + 32
        )
        
        trace_entity, damage = client.trace_bullet(
            me,
            elevated_pos.x, elevated_pos.y, elevated_pos.z,
            predictedEnemyPos.x, predictedEnemyPos.y, predictedEnemyPos.z
        )
        
        if damage > 55 then

            return true
        end
        
        ::continue::
    end

    return false
end
local new_class = (function()
    local class_mt = {}
    local class_data = {}
    local instance_mt = {}

    class_mt.__metatable = false

    class_data.struct = (function(self, name, ...)
        assert(type(name) == "string", "invalid class name")
        assert(rawget(self, name) == nil, "cannot overwrite subclass")

        local parents = {...}

        return (function(data, callbacks)
            assert(type(data) == "table", "invalid class data")

            for _, parent in ipairs(parents) do
                for k, v in pairs(parent) do
                    if not data[k] then
                        data[k] = v
                    end
                end
            end

            rawset(self, name, setmetatable(data, {
                __metatable = false,
                __index = (function(self, key)
                    for _, parent in ipairs(parents) do
                        if parent[key] then
                            return parent[key]
                        end
                    end
                    return rawget(class_mt, key) or rawget(instance_mt, key)
                end)
            }))

            data.callbacks = {}

            if callbacks then
                for _, method in ipairs(callbacks) do
                    local func = data[method]
                    if func and type(func) == "function" then
                        data.callbacks[method] = func
                    end
                end
            end

            return instance_mt
        end)
    end)

    instance_mt = setmetatable(class_data, class_mt)

    return instance_mt
end)

do 
    math.clamp = (function (v, min, max)
        if min > v then
            return min
        elseif max < v then
            return max
        else
            return v
        end
    end)
    
    table.contains = (function(tbl, i)
        if not tbl then
            return false
        end
        for _, v in pairs(tbl) do
            if v == i then
                return true
            end
        end
        return false
    end)
    table.remove_id = (function(tbl, value)
        for i, v in ipairs(tbl) do
            if v == value then
                table.remove(tbl, i)
                return
            end
        end
    end)
    
    entity.have_flag = (function(p, f)
        if not p then return false end
    
        local flags = {
            [1] = "Helmet",
            [2] = "Kevlar",
            [4] = "Helmet + Kevlar",
            [8] = "Zoom",
            [16] = "Blind",
            [32] = "Reload",
            [64] = "Bomb",
            [128] = "Vip",
            [256] = "Defuse",
            [512] = "Fakeduck",
            [1024] = "Pin pulled",
            [2048] = "Hit",
            [4096] = "Occluded",
            [8192] = "Exploiter",
            [131072] = "Defensive dt"
        }
    
        local esp_data = entity.get_esp_data(p)
        local result = false
    
        for i, name in pairs(flags) do
            if bit.band(esp_data.flags, i) == i and name == f then
                result = true
                break
            end
        end
    
        return result
    end)
    entity.lethal = (function(me, player, boolean)
        if not me then
            return
        end

        if not player then
            return
        end

        local active_weapon = entity.get_player_weapon(me)
        if not active_weapon then return false end
        local weapon_id = entity.get_prop(active_weapon, "m_iItemDefinitionIndex")
        if not weapon_id then return false end
        local weapon_struct = csgo_weapons[weapon_id]
        if not weapon_struct then return false end
        local player_origin = vector(entity.get_origin(me))
        local distance = player_origin:dist(vector(entity.get_origin(player)))
        local health = entity.get_prop(player, "m_iHealth")
        local dmg_after_range = (weapon_struct.damage * math.pow(weapon_struct.range_modifier, (distance * 0.002))) * 1.25
        local armor = entity.get_prop(player, "m_ArmorValue")
        local newdmg = dmg_after_range * (weapon_struct.armor_ratio * 0.5)
        if dmg_after_range - (dmg_after_range * (weapon_struct.armor_ratio * 0.5)) * 0.5 > armor then
            newdmg = dmg_after_range - (armor / 0.5)
        end

        local result = boolean and (newdmg >= health * 0.5) or (newdmg >= health)
        return result, math.floor(newdmg)
    end)
    
    globals.clock_offset = (function()
        return toticks(client.latency())
    end)
    globals.client_tick = (function()
        return globals.tickcount() - globals.clock_offset()
    end)
    globals.estimated_tickbase = (function()
        return entity.get_prop(entity.get_local_player(), "m_nTickBase")
    end)
    globals.next_attack = (function()
        local active_weapon = entity.get_player_weapon(entity.get_local_player())
        if not active_weapon then return globals.curtime() end
        local next_attack_tick = math.max(entity.get_prop(active_weapon, "m_flNextPrimaryAttack"), entity.get_prop(active_weapon, "m_flNextSecondaryAttack"), entity.get_prop(entity.get_local_player(), "m_flNextAttack"))
        return next_attack_tick
    end)
end
local pui_musor_refs = {
    dt = {ui.reference("RAGE", "Aimbot", "Double tap")},
}
local lua = {
    refs = {
        rage = {
            forcebodyaim = pui.reference("RAGE", "Aimbot", "Force body aim"),
            forcesafepoint = pui.reference("RAGE", "Aimbot", "Force safe point"),
        },
        aa = {
            enabled = pui.reference("AA", "Anti-Aimbot angles", "Enabled"),
            pitch = { pui.reference("AA", "Anti-Aimbot angles", "Pitch") },
            yaw_base = pui.reference("AA", "Anti-Aimbot angles", "Yaw base"),
            yaw = { pui.reference("AA", "Anti-Aimbot angles", "Yaw") },
            jyaw = { pui.reference("AA", "Anti-Aimbot angles", "Yaw jitter") },
            byaw = { pui.reference("AA", "Anti-Aimbot angles", "Body yaw") },
            fs = pui.reference("AA", "Anti-Aimbot angles", "Freestanding"),
            fs_byaw = pui.reference("AA", "Anti-Aimbot angles", "Freestanding body yaw"),
            edge_yaw = pui.reference("AA", "Anti-Aimbot angles", "Edge yaw"),
            roll = pui.reference("AA", "Anti-Aimbot angles", "Roll"),
        },
        fakelag = {
            enabled = pui.reference("AA","Fake lag", "Enabled"),
            amount = pui.reference("AA", "Fake lag", "Amount"),
            variance = pui.reference("AA", "Fake lag", "Variance"),
            limit = pui.reference("AA", "Fake lag", "Limit"),
        },
        exploits = {
            fl = pui.reference("AA", "Fake lag", "Limit"),
            dt = { pui.reference("RAGE", "Aimbot", "Double tap") },
            dt_fl = pui.reference("RAGE", "Aimbot", "Double tap fake lag limit"),
            hs = pui.reference("AA", "Other", "On shot anti-aim"),
            fd = pui.reference("RAGE", "Other", "Duck peek assist"),
        },
        other = {
            sw = pui.reference("AA", "Other", "Slow motion"),
            leg_movement = pui.reference("AA", "Other", "Leg movement"),
            weapon_type = ui.reference('Rage', 'Weapon type', 'Weapon type'),
            hide_shots = pui.reference("AA", "Other", "On shot anti-aim"),
            fake_peek = pui.reference("AA", "Other", "Fake peek"),
            menu_color = ui.reference("MISC", "Settings", "Menu color"),
            thirdperson = pui.reference("Visuals", "Effects", "Force third person (alive)"),
            damageoverride = {ui.reference("RAGE", "Aimbot", "Minimum damage override")},
            damage = pui.reference("RAGE", "Aimbot", "Minimum damage")
        },
    },
    vars = {
        state_list = {
            "Stand",
            "Move",
            "Walk",
            "Air",
            "Air duck",
            "Duck",
            "Duck move",
        },
    
        team_list = {
            "unknown",
            "T",
            "CT",
        },
    
        defensive_data = {
            tick = 0,
            check = 0,
            cmd = 0,
        },
    
        manual_yaw = {
            last_press = 0,
        },
    
        anti_aim_data = {
            delay = {
                value = 0,
                ticks = 0,
            },
            hold = {
                ticks = 1,
                delay = 0,
                jitter = 0,
            },
            way = {
                ticks = 1,
                cycle = { },
                jitter = 0,
            },
            aa = {
                side = 1,
                jside = 1,
                broken = 0,
                yaw = 0,
                jitter = 0,
            },
            defensive = {
                last = false,
                pitch = 0,
                random_pitch = 0,
                yaw = 0,
                random_yaw = 0,
                yaw_mod = 0,
            },
        }
    },
    ui = {
        tabs = {
            aa = pui.group("AA", "Anti-Aimbot angles"),
            fakelag = pui.group("AA", "Fake lag"),
            other = pui.group("AA", "Other"),
        },
        func = {
            aa = {
                global = { },
                builder = { },
            },
            fakelag = {},
            other = {
                visual = { },
                def = { },
                misc = { },
            },
        },
    },
}

local menu = {}; do
    local tab_aa = lua.ui.tabs.aa
    local tab_other = lua.ui.tabs.other
    local tab_fakelag = lua.ui.tabs.fakelag
    local vars = lua.vars
    local function feature(element, callback)
        element = element.__type == "pui::element" and {
            element
        } or element

        local elements_list, get_turn = callback(element[1])

        for _, element_visible in pairs(elements_list) do
            element_visible:depend({
                element[1],
                get_turn
            })
        end

        elements_list[element.key or "on"] = element[1]

        return elements_list
    end
    local function tabs()
        menu.home.main_tab = tab_fakelag:combobox("Main", {"Home", "Aimbot", "Anti-aim"})
        menu.home.sub_tab = tab_other:combobox("Other", {"Visual", "Misc", "Other"})
    end
    
    local configs = {}; do
        local DATABASE_KEY = 'aviros'
        local DATABASE = database.read(DATABASE_KEY) or {}
        local CONFIG_SIGNATURE = 'avirossystem'
    
        local function encode(data)
            local encoded_data = base64.encode(json.stringify(data))
            return table.concat({ CONFIG_SIGNATURE, encoded_data, CONFIG_SIGNATURE }, '::')
        end
        
        local function decode(data)
            local encoded = data:match(CONFIG_SIGNATURE .. '::(.+)::' .. CONFIG_SIGNATURE)
            if not encoded then
                print('Error: Invalid config format')
                return nil
            end
        
            local success, result = pcall(base64.decode, encoded)
            if not success then
                print('Error: Unable to decode data')
                return nil
            end
        
            success, result = pcall(json.parse, result)
            if not success then
                print('Error: Decoded data is invalid')
                return nil
            end
        
            return result
        end
        
        function configs:export(name)
            local configuration = {
                name = name or 'Untitled',
                code = menu.config:save()
            }
    
            return encode(configuration)
        end
    
        function configs:import(config, ...)
            local data = decode(config)
            if not data then
                return nil
            end
    
            menu.config:load(data.code, ...)
            return data
        end
    
        function configs:get_configs()
            local list = {}
            for i, data in ipairs(DATABASE) do
                list[i] = data.name
            end
    
            return list
        end
    
        function configs:get(id)
            return DATABASE[id]
        end
    
        function configs:delete(id)
            table.remove(DATABASE, id)
        end
    
        function configs:create(name, code)
            table.insert(DATABASE, { name = name, code = code })
        end
        
        function configs:save(id, code)
            if DATABASE[id] then
                DATABASE[id].code = code
            end
        end

        function configs:create_from_encoded_data(config)
            local data = decode(config)
            if not data then
                error("Invalid config data.")
                return
            end
        
            local original_name = data.name
            local candidate_name = original_name
            local counter = 0
        
            local existing_configs = configs:get_configs()
        
            local function name_exists(name)
                for _, existing_name in ipairs(existing_configs) do
                    if existing_name == name then
                        return true
                    end
                end
                return false
            end
        
            while name_exists(candidate_name) do
                counter = counter + 1
                candidate_name = original_name .. "(" .. counter .. ")"
            end
        
            data.name = candidate_name
            self:create(data.name, config)
        end              
    
        client.set_event_callback('shutdown', function ()
            database.write(DATABASE_KEY, DATABASE)
            database.flush()
        end)
    end

    menu = {
        config = {},
        home = {},
        aimbot = {},
        builder = {},
        antiaim = {},
        visuals = {},
        misc = {},
    }
    accent_color_pui = ui.get(lua.refs.other.menu_color)
    local function aimbot()
        menu.aimbot.aimtools = tab_aa:multiselect("Aimbot enhancements", {"Auto Enemy Correction", "Prediction [cmd]", "Advanced aimlogic", "Backtrack Breaker", "Reduce on shot"}):depend({menu.home.main_tab, "Aimbot"})
        menu.aimbot.aimtools_debuglog = tab_aa:checkbox("Resolver debug log"):depend({menu.aimbot.aimtools, "Auto Enemy Correction"}, {menu.home.main_tab, "Aimbot"})
    end

    local function antiaim()
        menu.antiaim.dynamic_yaw = { }
        menu.antiaim.dynamic_yaw.value = tab_fakelag:checkbox("Dynamic yaw"):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.dynamic_yaw.disabler = tab_fakelag:multiselect("Disablers", {"Manual yaw"}):depend( {menu.antiaim.dynamic_yaw.value, true}, {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.warmup_preset = tab_fakelag:multiselect("Other anti-aim on", {"Warmup", "Static dormant"}):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.dodge_bruteforce = tab_fakelag:checkbox("\aFF3636FFDodge Bruteforce"):depend( {menu.home.main_tab, "Anti-aim"})
        -- menu.antiaim.dodge_bruteforce:set_enabled(true)
        menu.antiaim.legit_antiaim = tab_fakelag:hotkey("Legit anti-aim"):depend( {menu.home.main_tab, "Anti-aim"} )

        menu.antiaim.freestanding = { }
        menu.antiaim.freestanding.value = tab_fakelag:checkbox("\nfreestanding_b"):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.freestanding.key = tab_fakelag:hotkey("Freestanding", false):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.freestanding.force = tab_fakelag:checkbox("Force static \nfs"):depend( {menu.antiaim.freestanding.value, true}, {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.freestanding.disabler = tab_fakelag:multiselect("Disablers \nfs", vars.state_list):depend( {menu.antiaim.freestanding.value, true}, {menu.home.main_tab, "Anti-aim"} )

        menu.antiaim.manual_yaw = { }
        menu.antiaim.manual_yaw.value = tab_fakelag:checkbox("Manual yaw"):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.manual_yaw.left = tab_fakelag:hotkey("Left", false):depend( {menu.antiaim.manual_yaw.value, true}, {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.manual_yaw.right = tab_fakelag:hotkey("Right", false):depend( {menu.antiaim.manual_yaw.value, true}, {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.manual_yaw.back = tab_fakelag:hotkey("Back", false):depend( {menu.antiaim.manual_yaw.value, true}, {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.manual_yaw.forward = tab_fakelag:hotkey("Forward", false):depend( {menu.antiaim.manual_yaw.value, true}, {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.manual_yaw.force = tab_fakelag:checkbox("Force static \nmy"):depend( {menu.antiaim.manual_yaw.value, true}, {menu.home.main_tab, "Anti-aim"} )

        menu.antiaim.safe_head = { }
        menu.antiaim.safe_head.value = tab_fakelag:multiselect("Safe head", {"Knife", "Taser", "All"}):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.safe_head.trigger = tab_fakelag:multiselect("Trigger", {"Stand", "Air duck", "Duck", "Duck move"})
            :depend( {menu.antiaim.safe_head.value, "Knife", "Taser", "All"}, {menu.home.main_tab, "Anti-aim"} )

        menu.antiaim.safe_head.disabler = tab_fakelag:multiselect("Disablers \nsh", {"Lethal"})
            :depend( {menu.antiaim.safe_head.value, "Knife", "Taser", "All"}, {menu.antiaim.safe_head.trigger, "Stand", "Air duck", "Duck", "Duck move"}, {menu.home.main_tab, "Anti-aim"} )

        menu.antiaim.avoid_backstab = { }
        menu.antiaim.avoid_backstab.value = tab_fakelag:checkbox("Avoid backstab"):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.antiaim.avoid_backstab.disabler = tab_fakelag:checkbox("Disable in dangerous situation")
            :depend( {menu.antiaim.avoid_backstab.value, true}, {menu.home.main_tab, "Anti-aim"} )

        menu.builder.preset = tab_aa:combobox("Preset", vars.state_list):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.builder.team = tab_aa:combobox("\nTEAM", {"T", "CT"}):depend( {menu.home.main_tab, "Anti-aim"} )
        menu.presets = { }

        for j, state_name in ipairs(vars.state_list) do
            menu.presets[state_name] = {}
            for a = 2, 3 do
                local t = vars.team_list[a]
                menu.presets[state_name][t] = { }
                local preset = menu.presets[state_name][t]
                
            
                preset.yaw = { }
                preset.yaw.left = tab_aa:slider("Left offset\n" .. state_name .. t, -180, 180, 0, 1, "°")
                preset.yaw.right = tab_aa:slider("Right offset\n" .. state_name .. t, -180, 180, 0, 1, "°")
            
                preset.yaw.randomized = tab_aa:slider("Randomization yaw\n" .. state_name .. t, 0, 100, 0, 1, "%")
            
                preset.yaw.left:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.yaw.right:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.yaw.randomized:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
            
                preset.jitter = { }
                preset.jitter.value = tab_aa:combobox("Jitter\n" .. state_name .. t, {"Disabled", "Center", "Between", "Static Way", "Dynamic Way"})
            
                preset.jitter.offset = tab_aa:slider("Offset\n" .. state_name .. t, -180, 180, 0, 1, "°")
                preset.jitter.randomized = tab_aa:slider("Offset randomization\n" .. state_name .. t, 0, 100, 0, 1, "%")
            
                preset.jitter.hold = tab_aa:slider("Hold\n" .. state_name .. t, 1, 10, 1, 1, "t")
                preset.jitter.switch = tab_aa:slider("Switch\n" .. state_name .. t, 1, 10, 1, 1, "t")
                preset.jitter.switch_offset = tab_aa:slider("Switch offset\n" .. state_name .. t, -180, 180, 0)
            
                preset.jitter.way = tab_aa:slider("Way\n" .. state_name .. t, 3, 7, 0)
                preset.jitter.dynamic = tab_aa:checkbox("Dynamic way\n" .. state_name .. t)
            
                preset.jitter.value:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.jitter.offset:depend( {preset.jitter.value, "Center", "Between", "Static Way", "Dynamic Way"} , {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.jitter.randomized:depend( {preset.jitter.value, "Center", "Between", "Static Way", "Dynamic Way"} , {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.jitter.hold:depend( {preset.jitter.value, "Between"} , {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.jitter.switch:depend( {preset.jitter.value, "Between"} , {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.jitter.switch_offset:depend( {preset.jitter.value, "Between"} , {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.jitter.way:depend( {preset.jitter.value, "Dynamic Way"} , {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.jitter.dynamic:depend( {preset.jitter.value, "Dynamic Way"} , {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                
                preset.body = { }
                preset.body.value = tab_aa:combobox("Body yaw\n" .. state_name .. t, {"Custom", "Default", "Reversed", "Jitter", "Dynamic"})
                preset.body.amount = tab_aa:slider("\n" .. state_name .. t, -1, 1, 0, 1, "°") 
            
                preset.body.delay = tab_aa:slider("Delay\n" .. state_name .. t, 0, 10, 0, 1, "t")
                preset.body.dynamic = tab_aa:checkbox("Dynamic delay\n" .. state_name .. t)
            
                preset.body.value:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.body.amount:depend( {preset.body.value, "Custom"}, {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.body.delay:depend( {preset.body.value, "Jitter", "Dynamic"}, {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.body.dynamic:depend( {preset.body.value, "Jitter", "Dynamic"}, {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
            
                preset.safe_lc = { }
                preset.safe_lc.value = tab_aa:multiselect("Force defensive\n" .. state_name .. t, {"Doubletap", "Hideshot"})
                preset.safe_lc.value:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
            
                preset.hidden = { }
                preset.hidden.value = tab_aa:checkbox("Hidden\n" .. state_name .. t)
            
                preset.hidden.pitch = tab_aa:combobox("Pitch\n" .. state_name .. t, {"Global", "Custom", "Random", "Jitter", "Spin", "Random static"})
                preset.hidden.pitch_offset = tab_aa:slider("\nHIDDEN_PITCH" .. state_name .. t, -89, 89, 0, 1, "°")
                preset.hidden.pitch_offset2 = tab_aa:slider("\nHIDDEN_PITCH2" .. state_name .. t, -89, 89, 0, 1, "°")
                preset.hidden.pitch_spin_speed = tab_aa:slider("\nHIDDEN_PITCH_SPIN_SPEED" .. state_name .. t, -50, 50, 0, 0.1, "%")
            
                preset.hidden.yaw = tab_aa:combobox("Yaw\nHIDDEN" .. state_name .. t, {"Global", "Custom", "Random", "Jitter", "Left/Right", "Spin", "Random static", "Flick"})
                preset.hidden.yaw_main = tab_aa:slider("\nHIDDEN_YAW" .. state_name .. t, -180, 180, 0, 1, "°")
                preset.hidden.yaw_offset = tab_aa:slider("\nHIDDEN_YAW_OFFSET" .. state_name .. t, -180, 180, 0, 1, "°")
                preset.hidden.yaw_spin_speed = tab_aa:slider("\nHIDDEN_YAW_SPIN_SPEED" .. state_name .. t, -50, 50, 0, 0.1, "%")
                preset.hidden.yaw_offset2 = tab_aa:slider("\nHIDDEN_YAW_OFFSET2" .. state_name .. t, -180, 180, 0, 1, "°")
                preset.hidden.yaw_apply = tab_aa:checkbox("Apply global\n" .. state_name .. t)
            
                preset.hidden.body = tab_aa:combobox("Body yaw\nHIDDEN" .. state_name .. t, {"Global", "Custom", "Default", "Reversed", "Jitter", "Dynamic"})
                preset.hidden.body_amount = tab_aa:slider("\nBODYHIDDEN" .. state_name .. t, -1, 1, 0, 1, "°") 
                preset.hidden.body_delay = tab_aa:slider("Delay\nHIDDEN" .. state_name .. t, 0, 10, 0, 1, "t")
                preset.hidden.body_delay2 = tab_aa:checkbox("Dynamic delay\nHIDDEN" .. state_name .. t)
            
                preset.hidden.value:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.pitch:depend( {preset.hidden.value, true}, {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.pitch_offset:depend( {preset.hidden.value, true}, {preset.hidden.pitch, "Random", "Jitter", "Custom", "Spin", 'Random static'}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.pitch_spin_speed:depend( {preset.hidden.value, true}, {preset.hidden.pitch, "Spin"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.pitch_offset2:depend( {preset.hidden.value, true}, {preset.hidden.pitch, "Random", "Jitter", 'Random static', 'Spin'}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.yaw:depend( {preset.hidden.value, true}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.yaw_main:depend( {preset.hidden.value, true}, {preset.hidden.yaw, "Random", "Jitter", "Left/Right", "Custom", "Spin", "Random static", "Flick"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.yaw_spin_speed:depend( {preset.hidden.value, true}, {preset.hidden.yaw, "Spin"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.yaw_offset:depend( {preset.hidden.value, true}, {preset.hidden.yaw, "Random", "Jitter", "Left/Right", "Spin", "Random static", "Flick"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.yaw_offset2:depend( {preset.hidden.value, true}, {preset.hidden.yaw, "Random", "Jitter", "Left/Right", "Random static", "Flick"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.yaw_apply:depend( {preset.hidden.value, true}, {preset.hidden.yaw, "Random", "Jitter", "Left/Right", "Custom"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.body:depend( {preset.hidden.value, true}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.body_amount:depend( {preset.hidden.value, true}, {preset.hidden.body, "Custom"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.body_delay:depend( {preset.hidden.value, true}, {preset.hidden.body, "Jitter", "Dynamic"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                preset.hidden.body_delay2:depend( {preset.hidden.value, true}, {preset.hidden.body, "Jitter", "Dynamic"}, {menu.builder.preset, state_name} , {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
                
                if t == "T" then
                    preset.send = tab_aa:button("Send to CT", function()
                        local send = menu.presets[state_name]["CT"]
                    
                        send.yaw.left:set(preset.yaw.left:get())
                        send.yaw.right:set(preset.yaw.right:get())
                        send.yaw.randomized:set(preset.yaw.randomized:get())
                        send.yaw.value:set(preset.yaw.value:get())
                        send.yaw.broken:set(preset.yaw.broken:get())
                    
                        send.jitter.value:set(preset.jitter.value:get())
                        send.jitter.offset:set(preset.jitter.offset:get())
                        send.jitter.randomized:set(preset.jitter.randomized:get())
                        send.jitter.hold:set(preset.jitter.hold:get())
                        send.jitter.switch:set(preset.jitter.switch:get())
                        send.jitter.switch_offset:set(preset.jitter.switch_offset:get())
                        send.jitter.way:set(preset.jitter.way:get())
                        send.jitter.dynamic:set(preset.jitter.dynamic:get())
                    
                        send.body.value:set(preset.body.value:get())
                        send.body.amount:set(preset.body.amount:get())
                        send.body.delay:set(preset.body.delay:get())
                        send.body.dynamic:set(preset.body.dynamic:get())
                    
                        send.safe_lc.value:set(preset.safe_lc.value:get())
                    
                        send.hidden.value:set(preset.hidden.value:get())
                        send.hidden.pitch:set(preset.hidden.pitch:get())
                        send.hidden.pitch_spin_speed:set(preset.hidden.pitch_spin_speed:get())
                        send.hidden.pitch_offset:set(preset.hidden.pitch_offset:get())
                        send.hidden.pitch_offset2:set(preset.hidden.pitch_offset2:get())
                        send.hidden.yaw:set(preset.hidden.yaw:get())
                        send.hidden.yaw_main:set(preset.hidden.yaw_main:get())
                        send.hidden.yaw_spin_speed:set(preset.hidden.yaw_spin_speed:get())
                        send.hidden.yaw_offset:set(preset.hidden.yaw_offset:get())
                        send.hidden.yaw_offset2:set(preset.hidden.yaw_offset2:get())
                        send.hidden.yaw_apply:set(preset.hidden.yaw_apply:get())
                        send.hidden.body:set(preset.hidden.body:get())
                        send.hidden.body_amount:set(preset.hidden.body_amount:get())
                        send.hidden.body_delay:set(preset.hidden.body_delay:get())
                        send.hidden.body_delay2:set(preset.hidden.body_delay2:get())
                    end)
                else
                    preset.send = tab_aa:button("Send to T", function()
                        local send = menu.presets[state_name]["T"]
                    
                        send.yaw.left:set(preset.yaw.left:get())
                        send.yaw.right:set(preset.yaw.right:get())
                        send.yaw.randomized:set(preset.yaw.randomized:get())
                        send.yaw.value:set(preset.yaw.value:get())
                        send.yaw.broken:set(preset.yaw.broken:get())
                    
                        send.jitter.value:set(preset.jitter.value:get())
                        send.jitter.offset:set(preset.jitter.offset:get())
                        send.jitter.randomized:set(preset.jitter.randomized:get())
                        send.jitter.hold:set(preset.jitter.hold:get())
                        send.jitter.switch:set(preset.jitter.switch:get())
                        send.jitter.switch_offset:set(preset.jitter.switch_offset:get())
                        send.jitter.way:set(preset.jitter.way:get())
                        send.jitter.dynamic:set(preset.jitter.dynamic:get())
                    
                        send.body.value:set(preset.body.value:get())
                        send.body.amount:set(preset.body.amount:get())
                        send.body.delay:set(preset.body.delay:get())
                        send.body.dynamic:set(preset.body.dynamic:get())
                    
                        send.safe_lc.value:set(preset.safe_lc.value:get())
                    
                        send.hidden.value:set(preset.hidden.value:get())
                        send.hidden.pitch:set(preset.hidden.pitch:get())
                        send.hidden.pitch_spin_speed:set(preset.hidden.pitch_spin_speed:get())
                        send.hidden.pitch_offset:set(preset.hidden.pitch_offset:get())
                        send.hidden.pitch_offset2:set(preset.hidden.pitch_offset2:get())
                        send.hidden.yaw:set(preset.hidden.yaw:get())
                        send.hidden.yaw_main:set(preset.hidden.yaw_main:get())
                        send.hidden.yaw_offset:set(preset.hidden.yaw_offset:get())
                        send.hidden.yaw_spin_speed:set(preset.hidden.yaw_spin_speed:get())
                        send.hidden.yaw_offset2:set(preset.hidden.yaw_offset2:get())
                        send.hidden.yaw_apply:set(preset.hidden.yaw_apply:get())
                        send.hidden.body:set(preset.hidden.body:get())
                        send.hidden.body_amount:set(preset.hidden.body_amount:get())
                        send.hidden.body_delay:set(preset.hidden.body_delay:get())
                        send.hidden.body_delay2:set(preset.hidden.body_delay2:get())
                    end)
                end
                preset.send:depend( {menu.builder.preset, state_name}, {menu.builder.team, t}, {menu.home.main_tab, "Anti-aim"} )
            end
        end
    end
    local function misc()
        menu.misc.animations = tab_other:checkbox("Animations"):depend({menu.home.sub_tab, "Misc"})
        menu.misc.animmoving = tab_other:combobox("Moving anims", {"None", "Jitter", "Static", "Smoothing"}):depend(menu.misc.animations, {menu.home.sub_tab, "Misc"})
        menu.misc.animair = tab_other:combobox("Air anims", {"None", "Static", "Kangaroo"}):depend(menu.misc.animations, {menu.home.sub_tab, "Misc"})
        menu.misc.pitch_on_land = tab_other:checkbox("Pitch on land"):depend(menu.misc.animations, {menu.home.sub_tab, "Misc"})
        menu.misc.fastladder = tab_other:checkbox("Fast ladder"):depend({menu.home.sub_tab, "Misc"})
        menu.misc.eventlog = tab_other:checkbox("Display logs"):depend({menu.home.sub_tab, "Misc"})
        menu.misc.consolefilter = tab_other:checkbox("Console filter"):depend({menu.home.sub_tab, "Misc"})
        menu.misc.automaticfpsoptimizer = tab_other:checkbox("Automatic FPS Optimizer"):depend({menu.home.sub_tab, "Misc"})
        menu.misc.aspectratio = feature({tab_other:checkbox("Aspect ratio"):depend({menu.home.sub_tab, "Misc"})}, function (value)
            local aspectratio_table = {
                [0] = "Off",
                [math.floor(16 / 9 * 100)] = "16:9",
                [math.floor(16 / 10 * 100)] = "16:10",
                [math.floor(3 / 2 * 100)] = "3:2",
                [math.floor(4 / 3 * 100)] = "4:3",
                [math.floor(5 / 4 * 100)] = "5:4",
            }

            return {
                slider = tab_other:slider("\nASPECT_RATIO", 0, 200, 0, true, "°", 0.01, aspectratio_table):depend({menu.home.sub_tab, "Misc"})
            }, true
        end)
        menu.misc.viewmodel = tab_other:checkbox("Viewmodel"):depend({menu.home.sub_tab, "Misc"})
        menu.misc.viewmodel_fov = tab_other:slider("FOV", -10000, 10000, 0, true, '', 0.01):depend(menu.misc.viewmodel, {menu.home.sub_tab, "Misc"})
        menu.misc.viewmodel_x = tab_other:slider("Offset X", -3000, 3000, 0, true, '', 0.01):depend(menu.misc.viewmodel, {menu.home.sub_tab, "Misc"})
        menu.misc.viewmodel_y = tab_other:slider("Offset Y", -3000, 3000, 0, true, '', 0.01):depend(menu.misc.viewmodel, {menu.home.sub_tab, "Misc"})
        menu.misc.viewmodel_z = tab_other:slider("Offset Z", -3000, 3000, 0, true, '', 0.01):depend(menu.misc.viewmodel, {menu.home.sub_tab, "Misc"})
        menu.misc.thirdperson = tab_other:checkbox("Camera Distance"):depend({menu.home.sub_tab, "Misc"})
        menu.misc.thirdperson_dist = tab_other:slider("Dist Value", 30, 200, 90):depend(menu.misc.thirdperson, {menu.home.sub_tab, "Misc"})
    end

    local function visual()
        menu.visuals.inds = tab_other:combobox("Inds", {"Unselected", "Aviros [1]", "Aviros [2]", "Aviros [3]", "Aviros [old]"}, {225, 225, 225}):depend( {menu.home.sub_tab, "Visual"} )
        menu.visuals.inds_offset = tab_other:slider("Main offset", 0, 50, 0, 1, "px"):depend( {menu.visuals.inds, "Aviros [1]", "Aviros [2]", "Aviros [3]", "Aviros [old]"}, {menu.home.sub_tab, "Visual"} )
        menu.visuals.arrows_offset = tab_other:slider("Arrows offset", 0, 50, 0, 1, "px"):depend( {menu.visuals.inds, "Aviros [1]", "Aviros [2]", "Aviros [3]", "Aviros [old]"}, {menu.home.sub_tab, "Visual"} )
        menu.visuals.stylelogs = tab_other:combobox("Logs type", {"Default", "Centered", "All"}, {225, 225, 225}):depend(menu.misc.eventlog, {menu.home.sub_tab, "Visual"} )
        menu.visuals.second_style_logs = tab_other:combobox("Logs style", {"Aviros", "Rounded"}):depend(menu.misc.eventlog, {menu.home.sub_tab, "Visual"} )

    end

    local function config_system()
        local config_information = { list = {}, id = 1 }
        local config_list = tab_aa:listbox('Configs', #configs:get_configs() > 0 and configs:get_configs() or { "No configs" }):depend({menu.home.main_tab, "Home"})
        local selected = tab_aa:label('Selected: \a8ea5e5FF' .. 'Nothing'):depend({menu.home.main_tab, "Home"})
        local config_name = tab_aa:textbox('Name config'):depend({menu.home.main_tab, "Home"})

        client.set_event_callback('paint_ui', function()
            local list = configs:get_configs()
        
            -- print("Checking configs list: " .. inspect(list))
        
            if #list ~= #config_information.list then
                -- print("List has changed. Updating...")
                config_information.list = list
        
                if #list == 0 then
                    -- print("List is empty after update! Resetting values.")
                    config_list:update({ "No configs" })
                    config_list.value = 1
                    config_information.id = 1
                    return
                else
                    config_list:update(list)
                end
            end
        
            if config_list.value == nil then
                -- print("config_list.value is nil! Fixing...")
                config_list.value = 1
            end
        
            local id = (config_list.value or 1) + 1
            -- print("Current config ID:" .. id)
        
            if id ~= config_information.id then
                config_information.id = id
                -- print("Updated config ID: " .. config_information.id)
            end

            local config = configs:get(config_information.id) or nil
            if config ~= nil then
                selected:set('Selected: \a8ea5e5FF' .. config.name)
            else
                selected:set('Selected: \a8ea5e5FF' .. 'Nothing')
            end
        end)

        config_list:set_callback(function(item)
            local config = configs:get(item:get() + 1) or configs:get(config_information.id)
            if config == nil then
                return
            end
            config_name:set(config.name)
        end)
        
        local function validate_config_name()
            local name = config_name:get():gsub(' ', '')
            if name == '' then
                -- print('Config name is empty.')
                return true, 'Untitled'
            end

            return true, name
        end

        local function validate_config_exists(id)
            if #configs:get_configs() <= 0 then
                print('No configs available')
                return false, nil
            end

            local config = configs:get(id)
            if not config then
                print('Config not found.')
                return false, nil
            end

            return true, config
        end

        local function load_aa_config()
            local valid, config = validate_config_exists(config_information.id)
            if not valid or not config then
                print('Config issue')
                return
            end

            configs:import(config.code)
            print('Config loaded successfully: ' .. config.name)
        end

        local default_config = "avirossystem::eyJuYW1lIjoibWFpbjIiLCJjb2RlIjpbeyJ3YXJtdXBfcHJlc2V0IjpbIn4iXSwibWFudWFsX3lhdyI6eyJyaWdodCI6WzEsNjcsIn4iXSwibGVmdCI6WzEsOTAsIn4iXSwiYmFjayI6WzEsMCwifiJdLCJ2YWx1ZSI6dHJ1ZSwiZm9yd2FyZCI6WzEsMCwifiJdLCJmb3JjZSI6dHJ1ZX0sImxlZ2l0X2FudGlhaW0iOlsxLDY5LCJ+Il0sImZyZWVzdGFuZGluZyI6eyJmb3JjZSI6ZmFsc2UsInZhbHVlIjpmYWxzZSwia2V5IjpbMSwwLCJ+Il0sImRpc2FibGVyIjpbIn4iXX0sInNhZmVfaGVhZCI6eyJ0cmlnZ2VyIjpbIkFpciBkdWNrIiwiRHVjayIsIkR1Y2sgbW92ZSIsIn4iXSwiZGlzYWJsZXIiOlsiTGV0aGFsIiwifiJdLCJ2YWx1ZSI6WyJLbmlmZSIsIlRhc2VyIiwiQWxsIiwifiJdfSwiYXZvaWRfYmFja3N0YWIiOnsiZGlzYWJsZXIiOnRydWUsInZhbHVlIjp0cnVlfSwiZHluYW1pY195YXciOnsiZGlzYWJsZXIiOlsiTWFudWFsIHlhdyIsIn4iXSwidmFsdWUiOnRydWV9fSx7IldhbGsiOnsiVCI6eyJoaWRkZW4iOnsicGl0Y2hfc3Bpbl9zcGVlZCI6MzAsInBpdGNoIjoiUmFuZG9taXplZCIsInlhd19tYWluIjotMSwieWF3X29mZnNldCI6LTE1NCwieWF3IjoiSml0dGVyIiwicGl0Y2hfb2Zmc2V0MiI6LTI5LCJwaXRjaF9vZmZzZXQiOi02NSwiYm9keV9kZWxheSI6NCwiYm9keV9kZWxheTIiOmZhbHNlLCJib2R5X2Ftb3VudCI6MCwieWF3X2FwcGx5Ijp0cnVlLCJ5YXdfc3Bpbl9zcGVlZCI6MCwiYm9keSI6IkppdHRlciIsInZhbHVlIjp0cnVlLCJ5YXdfb2Zmc2V0MiI6MTMxfSwic2FmZV9sYyI6eyJ2YWx1ZSI6WyJEb3VibGV0YXAiLCJIaWRlc2hvdCIsIn4iXX0sImppdHRlciI6eyJyYW5kb21pemVkIjoyMCwib2Zmc2V0IjoxMiwiZHluYW1pYyI6ZmFsc2UsInZhbHVlIjoiSG9sZCIsIndheSI6MywiaG9sZCI6NSwic3dpdGNoX29mZnNldCI6LTUsInN3aXRjaCI6MX0sInlhdyI6eyJyaWdodCI6MjEsImxlZnQiOi0xMiwidmFsdWUiOnRydWUsImJyb2tlbiI6LTcyLCJyYW5kb21pemVkIjoxOX0sImJvZHkiOnsiYW1vdW50IjotMSwiZGVsYXkiOjIsImR5bmFtaWMiOnRydWUsInZhbHVlIjoiSml0dGVyIn19LCJDVCI6eyJoaWRkZW4iOnsicGl0Y2hfc3Bpbl9zcGVlZCI6MzAsInBpdGNoIjoiSml0dGVyIiwieWF3X21haW4iOjEsInlhd19vZmZzZXQiOi0xNTQsInlhdyI6IlJhbmRvbWl6ZWQiLCJwaXRjaF9vZmZzZXQyIjo4OSwicGl0Y2hfb2Zmc2V0IjotNDcsImJvZHlfZGVsYXkiOjQsImJvZHlfZGVsYXkyIjpmYWxzZSwiYm9keV9hbW91bnQiOjAsInlhd19hcHBseSI6dHJ1ZSwieWF3X3NwaW5fc3BlZWQiOjIyLCJib2R5IjoiSml0dGVyIiwidmFsdWUiOnRydWUsInlhd19vZmZzZXQyIjoxMzF9LCJzYWZlX2xjIjp7InZhbHVlIjpbIkRvdWJsZXRhcCIsIkhpZGVzaG90IiwifiJdfSwiaml0dGVyIjp7InJhbmRvbWl6ZWQiOjIwLCJvZmZzZXQiOjEyLCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJIb2xkIiwid2F5IjozLCJob2xkIjo1LCJzd2l0Y2hfb2Zmc2V0IjotNSwic3dpdGNoIjoxfSwieWF3Ijp7InJpZ2h0IjoyMSwibGVmdCI6LTEyLCJ2YWx1ZSI6dHJ1ZSwiYnJva2VuIjotNzIsInJhbmRvbWl6ZWQiOjE5fSwiYm9keSI6eyJhbW91bnQiOi0xLCJkZWxheSI6MiwiZHluYW1pYyI6dHJ1ZSwidmFsdWUiOiJKaXR0ZXIifX19LCJBaXIiOnsiVCI6eyJoaWRkZW4iOnsicGl0Y2hfc3Bpbl9zcGVlZCI6LTIzLCJwaXRjaCI6IlJhbmRvbWl6ZWQiLCJ5YXdfbWFpbiI6MjUsInlhd19vZmZzZXQiOi0xMjcsInlhdyI6IlNwaW4iLCJwaXRjaF9vZmZzZXQyIjotNDQsInBpdGNoX29mZnNldCI6LTg5LCJib2R5X2RlbGF5IjowLCJib2R5X2RlbGF5MiI6dHJ1ZSwiYm9keV9hbW91bnQiOjAsInlhd19hcHBseSI6ZmFsc2UsInlhd19zcGluX3NwZWVkIjozMywiYm9keSI6IkRlZmF1bHQiLCJ2YWx1ZSI6dHJ1ZSwieWF3X29mZnNldDIiOjE2OX0sInNhZmVfbGMiOnsidmFsdWUiOlsiRG91YmxldGFwIiwiSGlkZXNob3QiLCJ+Il19LCJqaXR0ZXIiOnsicmFuZG9taXplZCI6MCwib2Zmc2V0IjowLCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJEaXNhYmxlZCIsIndheSI6MywiaG9sZCI6MSwic3dpdGNoX29mZnNldCI6MCwic3dpdGNoIjoxfSwieWF3Ijp7InJpZ2h0IjoxMCwibGVmdCI6LTEyLCJ2YWx1ZSI6dHJ1ZSwiYnJva2VuIjotNDUsInJhbmRvbWl6ZWQiOjEwfSwiYm9keSI6eyJhbW91bnQiOi0xLCJkZWxheSI6NCwiZHluYW1pYyI6dHJ1ZSwidmFsdWUiOiJKaXR0ZXIifX0sIkNUIjp7ImhpZGRlbiI6eyJwaXRjaF9zcGluX3NwZWVkIjotOSwicGl0Y2giOiJTcGluIiwieWF3X21haW4iOjIwLCJ5YXdfb2Zmc2V0IjotOTcsInlhdyI6IlNwaW4iLCJwaXRjaF9vZmZzZXQyIjo3MCwicGl0Y2hfb2Zmc2V0IjotNjcsImJvZHlfZGVsYXkiOjcsImJvZHlfZGVsYXkyIjp0cnVlLCJib2R5X2Ftb3VudCI6MCwieWF3X2FwcGx5IjpmYWxzZSwieWF3X3NwaW5fc3BlZWQiOjQ4LCJib2R5IjoiSml0dGVyIiwidmFsdWUiOnRydWUsInlhd19vZmZzZXQyIjoxNjl9LCJzYWZlX2xjIjp7InZhbHVlIjpbIkRvdWJsZXRhcCIsIkhpZGVzaG90IiwifiJdfSwiaml0dGVyIjp7InJhbmRvbWl6ZWQiOjAsIm9mZnNldCI6MCwiZHluYW1pYyI6ZmFsc2UsInZhbHVlIjoiRGlzYWJsZWQiLCJ3YXkiOjMsImhvbGQiOjEsInN3aXRjaF9vZmZzZXQiOjAsInN3aXRjaCI6MX0sInlhdyI6eyJyaWdodCI6MTUsImxlZnQiOi0xMiwidmFsdWUiOnRydWUsImJyb2tlbiI6LTQ1LCJyYW5kb21pemVkIjoxMH0sImJvZHkiOnsiYW1vdW50IjotMSwiZGVsYXkiOjMsImR5bmFtaWMiOnRydWUsInZhbHVlIjoiSml0dGVyIn19fSwiRHVjayBtb3ZlIjp7IlQiOnsiaGlkZGVuIjp7InBpdGNoX3NwaW5fc3BlZWQiOi01MCwicGl0Y2giOiJDdXN0b20iLCJ5YXdfbWFpbiI6MzMsInlhd19vZmZzZXQiOi04NywieWF3IjoiU3BpbiIsInBpdGNoX29mZnNldDIiOi01MSwicGl0Y2hfb2Zmc2V0Ijo4OSwiYm9keV9kZWxheSI6MSwiYm9keV9kZWxheTIiOnRydWUsImJvZHlfYW1vdW50IjowLCJ5YXdfYXBwbHkiOnRydWUsInlhd19zcGluX3NwZWVkIjozNywiYm9keSI6IkppdHRlciIsInZhbHVlIjp0cnVlLCJ5YXdfb2Zmc2V0MiI6ODR9LCJzYWZlX2xjIjp7InZhbHVlIjpbIkRvdWJsZXRhcCIsIkhpZGVzaG90IiwifiJdfSwiaml0dGVyIjp7InJhbmRvbWl6ZWQiOjIxLCJvZmZzZXQiOi03LCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJIb2xkIiwid2F5IjozLCJob2xkIjoxLCJzd2l0Y2hfb2Zmc2V0Ijo5LCJzd2l0Y2giOjR9LCJ5YXciOnsicmlnaHQiOjQzLCJsZWZ0IjotMjMsInZhbHVlIjp0cnVlLCJicm9rZW4iOjAsInJhbmRvbWl6ZWQiOjE1fSwiYm9keSI6eyJhbW91bnQiOjAsImRlbGF5IjozLCJkeW5hbWljIjp0cnVlLCJ2YWx1ZSI6IkppdHRlciJ9fSwiQ1QiOnsiaGlkZGVuIjp7InBpdGNoX3NwaW5fc3BlZWQiOi01MCwicGl0Y2giOiJKaXR0ZXIiLCJ5YXdfbWFpbiI6MjksInlhd19vZmZzZXQiOjEwOCwieWF3IjoiUmFuZG9taXplZCIsInBpdGNoX29mZnNldDIiOjg5LCJwaXRjaF9vZmZzZXQiOjg4LCJib2R5X2RlbGF5IjozLCJib2R5X2RlbGF5MiI6ZmFsc2UsImJvZHlfYW1vdW50IjowLCJ5YXdfYXBwbHkiOnRydWUsInlhd19zcGluX3NwZWVkIjozNCwiYm9keSI6IkppdHRlciIsInZhbHVlIjp0cnVlLCJ5YXdfb2Zmc2V0MiI6LTg0fSwic2FmZV9sYyI6eyJ2YWx1ZSI6WyJEb3VibGV0YXAiLCJIaWRlc2hvdCIsIn4iXX0sImppdHRlciI6eyJyYW5kb21pemVkIjoyMSwib2Zmc2V0IjotNywiZHluYW1pYyI6ZmFsc2UsInZhbHVlIjoiSG9sZCIsIndheSI6MywiaG9sZCI6Miwic3dpdGNoX29mZnNldCI6Nywic3dpdGNoIjo0fSwieWF3Ijp7InJpZ2h0IjozNiwibGVmdCI6LTMwLCJ2YWx1ZSI6dHJ1ZSwiYnJva2VuIjowLCJyYW5kb21pemVkIjoxNX0sImJvZHkiOnsiYW1vdW50IjowLCJkZWxheSI6MywiZHluYW1pYyI6dHJ1ZSwidmFsdWUiOiJKaXR0ZXIifX19LCJTdGFuZCI6eyJUIjp7ImhpZGRlbiI6eyJwaXRjaF9zcGluX3NwZWVkIjo3LCJwaXRjaCI6IlJhbmRvbSBzdGF0aWMiLCJ5YXdfbWFpbiI6MCwieWF3X29mZnNldCI6LTE1OCwieWF3IjoiTGVmdFwvUmlnaHQiLCJwaXRjaF9vZmZzZXQyIjozMiwicGl0Y2hfb2Zmc2V0IjotNDAsImJvZHlfZGVsYXkiOjIsImJvZHlfZGVsYXkyIjpmYWxzZSwiYm9keV9hbW91bnQiOjEsInlhd19hcHBseSI6dHJ1ZSwieWF3X3NwaW5fc3BlZWQiOjUsImJvZHkiOiJKaXR0ZXIiLCJ2YWx1ZSI6dHJ1ZSwieWF3X29mZnNldDIiOjE1MX0sInNhZmVfbGMiOnsidmFsdWUiOlsiRG91YmxldGFwIiwiSGlkZXNob3QiLCJ+Il19LCJqaXR0ZXIiOnsicmFuZG9taXplZCI6MzAsIm9mZnNldCI6LTcsImR5bmFtaWMiOmZhbHNlLCJ2YWx1ZSI6IkhvbGQiLCJ3YXkiOjMsImhvbGQiOjIsInN3aXRjaF9vZmZzZXQiOjcsInN3aXRjaCI6N30sInlhdyI6eyJyaWdodCI6OSwibGVmdCI6LTcsInZhbHVlIjp0cnVlLCJicm9rZW4iOjIxLCJyYW5kb21pemVkIjoyMH0sImJvZHkiOnsiYW1vdW50IjoxLCJkZWxheSI6MywiZHluYW1pYyI6ZmFsc2UsInZhbHVlIjoiSml0dGVyIn19LCJDVCI6eyJoaWRkZW4iOnsicGl0Y2hfc3Bpbl9zcGVlZCI6NywicGl0Y2giOiJSYW5kb20gc3RhdGljIiwieWF3X21haW4iOjAsInlhd19vZmZzZXQiOi0xMzUsInlhdyI6IkxlZnRcL1JpZ2h0IiwicGl0Y2hfb2Zmc2V0MiI6MzIsInBpdGNoX29mZnNldCI6LTQwLCJib2R5X2RlbGF5IjoyLCJib2R5X2RlbGF5MiI6ZmFsc2UsImJvZHlfYW1vdW50IjoxLCJ5YXdfYXBwbHkiOnRydWUsInlhd19zcGluX3NwZWVkIjo1LCJib2R5IjoiSml0dGVyIiwidmFsdWUiOnRydWUsInlhd19vZmZzZXQyIjoxMzN9LCJzYWZlX2xjIjp7InZhbHVlIjpbIkRvdWJsZXRhcCIsIkhpZGVzaG90IiwifiJdfSwiaml0dGVyIjp7InJhbmRvbWl6ZWQiOjMwLCJvZmZzZXQiOi03LCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJIb2xkIiwid2F5IjozLCJob2xkIjoyLCJzd2l0Y2hfb2Zmc2V0Ijo3LCJzd2l0Y2giOjd9LCJ5YXciOnsicmlnaHQiOjksImxlZnQiOi03LCJ2YWx1ZSI6dHJ1ZSwiYnJva2VuIjoyMSwicmFuZG9taXplZCI6MjB9LCJib2R5Ijp7ImFtb3VudCI6MSwiZGVsYXkiOjMsImR5bmFtaWMiOmZhbHNlLCJ2YWx1ZSI6IkppdHRlciJ9fX0sIkR1Y2siOnsiVCI6eyJoaWRkZW4iOnsicGl0Y2hfc3Bpbl9zcGVlZCI6MTcsInBpdGNoIjoiUmFuZG9tIHN0YXRpYyIsInlhd19tYWluIjo1LCJ5YXdfb2Zmc2V0IjotMTEwLCJ5YXciOiJTcGluIiwicGl0Y2hfb2Zmc2V0MiI6NjUsInBpdGNoX29mZnNldCI6LTY0LCJib2R5X2RlbGF5IjoxMCwiYm9keV9kZWxheTIiOmZhbHNlLCJib2R5X2Ftb3VudCI6MCwieWF3X2FwcGx5IjpmYWxzZSwieWF3X3NwaW5fc3BlZWQiOjQwLCJib2R5IjoiSml0dGVyIiwidmFsdWUiOnRydWUsInlhd19vZmZzZXQyIjoxMTd9LCJzYWZlX2xjIjp7InZhbHVlIjpbIkRvdWJsZXRhcCIsIkhpZGVzaG90IiwifiJdfSwiaml0dGVyIjp7InJhbmRvbWl6ZWQiOjIzLCJvZmZzZXQiOi03LCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJIb2xkIiwid2F5IjozLCJob2xkIjoyLCJzd2l0Y2hfb2Zmc2V0IjoxNiwic3dpdGNoIjo1fSwieWF3Ijp7InJpZ2h0Ijo0NiwibGVmdCI6LTIzLCJ2YWx1ZSI6dHJ1ZSwiYnJva2VuIjotMzksInJhbmRvbWl6ZWQiOjEzfSwiYm9keSI6eyJhbW91bnQiOi0xLCJkZWxheSI6OCwiZHluYW1pYyI6dHJ1ZSwidmFsdWUiOiJKaXR0ZXIifX0sIkNUIjp7ImhpZGRlbiI6eyJwaXRjaF9zcGluX3NwZWVkIjotMzAsInBpdGNoIjoiU3BpbiIsInlhd19tYWluIjoxLCJ5YXdfb2Zmc2V0IjotMTI2LCJ5YXciOiJTcGluIiwicGl0Y2hfb2Zmc2V0MiI6NTUsInBpdGNoX29mZnNldCI6LTg5LCJib2R5X2RlbGF5Ijo5LCJib2R5X2RlbGF5MiI6ZmFsc2UsImJvZHlfYW1vdW50IjowLCJ5YXdfYXBwbHkiOmZhbHNlLCJ5YXdfc3Bpbl9zcGVlZCI6MTMsImJvZHkiOiJKaXR0ZXIiLCJ2YWx1ZSI6dHJ1ZSwieWF3X29mZnNldDIiOjE0NH0sInNhZmVfbGMiOnsidmFsdWUiOlsiRG91YmxldGFwIiwiSGlkZXNob3QiLCJ+Il19LCJqaXR0ZXIiOnsicmFuZG9taXplZCI6MjMsIm9mZnNldCI6LTcsImR5bmFtaWMiOmZhbHNlLCJ2YWx1ZSI6IkhvbGQiLCJ3YXkiOjMsImhvbGQiOjIsInN3aXRjaF9vZmZzZXQiOjE2LCJzd2l0Y2giOjV9LCJ5YXciOnsicmlnaHQiOjMxLCJsZWZ0IjotMjMsInZhbHVlIjp0cnVlLCJicm9rZW4iOi0zOSwicmFuZG9taXplZCI6MTN9LCJib2R5Ijp7ImFtb3VudCI6LTEsImRlbGF5IjozLCJkeW5hbWljIjp0cnVlLCJ2YWx1ZSI6IkppdHRlciJ9fX0sIkFpciBkdWNrIjp7IlQiOnsiaGlkZGVuIjp7InBpdGNoX3NwaW5fc3BlZWQiOi0zLCJwaXRjaCI6IkppdHRlciIsInlhd19tYWluIjotMTE3LCJ5YXdfb2Zmc2V0IjoxNDksInlhdyI6IlNwaW4iLCJwaXRjaF9vZmZzZXQyIjotNywicGl0Y2hfb2Zmc2V0IjotNzAsImJvZHlfZGVsYXkiOjQsImJvZHlfZGVsYXkyIjp0cnVlLCJib2R5X2Ftb3VudCI6MCwieWF3X2FwcGx5IjpmYWxzZSwieWF3X3NwaW5fc3BlZWQiOjM0LCJib2R5IjoiRGVmYXVsdCIsInZhbHVlIjp0cnVlLCJ5YXdfb2Zmc2V0MiI6MH0sInNhZmVfbGMiOnsidmFsdWUiOlsiRG91YmxldGFwIiwiSGlkZXNob3QiLCJ+Il19LCJqaXR0ZXIiOnsicmFuZG9taXplZCI6MCwib2Zmc2V0IjowLCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJEaXNhYmxlZCIsIndheSI6MywiaG9sZCI6MSwic3dpdGNoX29mZnNldCI6MCwic3dpdGNoIjoxfSwieWF3Ijp7InJpZ2h0IjoxMiwibGVmdCI6LTE4LCJ2YWx1ZSI6dHJ1ZSwiYnJva2VuIjozNiwicmFuZG9taXplZCI6MzB9LCJib2R5Ijp7ImFtb3VudCI6MSwiZGVsYXkiOjIsImR5bmFtaWMiOnRydWUsInZhbHVlIjoiSml0dGVyIn19LCJDVCI6eyJoaWRkZW4iOnsicGl0Y2hfc3Bpbl9zcGVlZCI6MzQsInBpdGNoIjoiUmFuZG9tIHN0YXRpYyIsInlhd19tYWluIjotOCwieWF3X29mZnNldCI6LTE2MywieWF3IjoiUmFuZG9tIHN0YXRpYyIsInBpdGNoX29mZnNldDIiOjQwLCJwaXRjaF9vZmZzZXQiOi00MCwiYm9keV9kZWxheSI6NSwiYm9keV9kZWxheTIiOmZhbHNlLCJib2R5X2Ftb3VudCI6LTEsInlhd19hcHBseSI6ZmFsc2UsInlhd19zcGluX3NwZWVkIjotMjEsImJvZHkiOiJEZWZhdWx0IiwidmFsdWUiOnRydWUsInlhd19vZmZzZXQyIjoxNTh9LCJzYWZlX2xjIjp7InZhbHVlIjpbIkRvdWJsZXRhcCIsIkhpZGVzaG90IiwifiJdfSwiaml0dGVyIjp7InJhbmRvbWl6ZWQiOjAsIm9mZnNldCI6MCwiZHluYW1pYyI6ZmFsc2UsInZhbHVlIjoiRGlzYWJsZWQiLCJ3YXkiOjMsImhvbGQiOjEsInN3aXRjaF9vZmZzZXQiOjAsInN3aXRjaCI6MX0sInlhdyI6eyJyaWdodCI6NywibGVmdCI6LTgsInZhbHVlIjp0cnVlLCJicm9rZW4iOjQyLCJyYW5kb21pemVkIjoyNn0sImJvZHkiOnsiYW1vdW50IjoxLCJkZWxheSI6OSwiZHluYW1pYyI6ZmFsc2UsInZhbHVlIjoiSml0dGVyIn19fSwiTW92ZSI6eyJUIjp7ImhpZGRlbiI6eyJwaXRjaF9zcGluX3NwZWVkIjowLCJwaXRjaCI6Ikdsb2JhbCIsInlhd19tYWluIjowLCJ5YXdfb2Zmc2V0IjowLCJ5YXciOiJHbG9iYWwiLCJwaXRjaF9vZmZzZXQyIjowLCJwaXRjaF9vZmZzZXQiOjAsImJvZHlfZGVsYXkiOjAsImJvZHlfZGVsYXkyIjpmYWxzZSwiYm9keV9hbW91bnQiOjAsInlhd19hcHBseSI6ZmFsc2UsInlhd19zcGluX3NwZWVkIjowLCJib2R5IjoiR2xvYmFsIiwidmFsdWUiOmZhbHNlLCJ5YXdfb2Zmc2V0MiI6MH0sInNhZmVfbGMiOnsidmFsdWUiOlsifiJdfSwiaml0dGVyIjp7InJhbmRvbWl6ZWQiOjMxLCJvZmZzZXQiOjYwLCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJDZW50ZXIiLCJ3YXkiOjMsImhvbGQiOjEsInN3aXRjaF9vZmZzZXQiOi0yNiwic3dpdGNoIjozfSwieWF3Ijp7InJpZ2h0IjozLCJsZWZ0IjotNSwidmFsdWUiOnRydWUsImJyb2tlbiI6MjgsInJhbmRvbWl6ZWQiOjIzfSwiYm9keSI6eyJhbW91bnQiOjEsImRlbGF5IjoxLCJkeW5hbWljIjpmYWxzZSwidmFsdWUiOiJKaXR0ZXIifX0sIkNUIjp7ImhpZGRlbiI6eyJwaXRjaF9zcGluX3NwZWVkIjozNSwicGl0Y2giOiJTcGluIiwieWF3X21haW4iOjE0LCJ5YXdfb2Zmc2V0IjotMTM4LCJ5YXciOiJSYW5kb21pemVkIiwicGl0Y2hfb2Zmc2V0MiI6MCwicGl0Y2hfb2Zmc2V0IjotNzUsImJvZHlfZGVsYXkiOjQsImJvZHlfZGVsYXkyIjpmYWxzZSwiYm9keV9hbW91bnQiOjAsInlhd19hcHBseSI6ZmFsc2UsInlhd19zcGluX3NwZWVkIjozMCwiYm9keSI6IkppdHRlciIsInZhbHVlIjpmYWxzZSwieWF3X29mZnNldDIiOjE0NX0sInNhZmVfbGMiOnsidmFsdWUiOlsiRG91YmxldGFwIiwiSGlkZXNob3QiLCJ+Il19LCJqaXR0ZXIiOnsicmFuZG9taXplZCI6NzUsIm9mZnNldCI6OCwiZHluYW1pYyI6ZmFsc2UsInZhbHVlIjoiQ2VudGVyIiwid2F5IjozLCJob2xkIjoxLCJzd2l0Y2hfb2Zmc2V0IjotMjYsInN3aXRjaCI6M30sInlhdyI6eyJyaWdodCI6NDAsImxlZnQiOi0zMSwidmFsdWUiOnRydWUsImJyb2tlbiI6NzUsInJhbmRvbWl6ZWQiOjI1fSwiYm9keSI6eyJhbW91bnQiOjEsImRlbGF5Ijo1LCJkeW5hbWljIjp0cnVlLCJ2YWx1ZSI6IkppdHRlciJ9fX19XX0=::avirossystem"
        
        local function load_default_config()
            if not default_config then
                return
            end

            configs:import(default_config)
            print('Default config loaded successfully')
        end

        local function save_config()
            local valid, name = validate_config_name()
            if not valid then
                return
            end

            local code = configs:export(name)
            local current_config = configs:get(config_information.id)

            if not current_config or name ~= current_config.name then
                configs:create(name, code)
                print('Config created successfully')
            else
                configs:save(config_information.id, code)
                print('Config saved successfully')
            end
        end

        local function remove_config()
            local valid, config = validate_config_exists(config_information.id)
            if not valid or not config then
                return
            end

            configs:delete(config_information.id)
            print('Config removed successfully: ' .. config.name)
        end

        local function export_config()
            local valid, name = validate_config_name()
            if not valid then
                return
            end

            clipboard.set(configs:export(name))
            print('Copied to clipboard')
        end

        local function import_config()
            local code = clipboard.get()
            if not code then
                print('Clipboard is empty')
                return
            end

            local ok = pcall(configs.create_from_encoded_data, configs, code)
            print(ok and 'Config imported successfully' or 'Invalid config data')
        end

        tab_aa:button('Load AA', load_aa_config):depend({menu.home.main_tab, "Home"})
        tab_aa:button('Save config', save_config):depend({menu.home.main_tab, "Home"})
        tab_aa:button('Delete config', remove_config):depend({menu.home.main_tab, "Home"})
        tab_aa:button('Load default config', load_default_config):depend({menu.home.main_tab, "Home"})
        tab_aa:button('Export config to clipboard', export_config):depend({menu.home.main_tab, "Home"})
        tab_aa:button('Import config from clipboard', import_config):depend({menu.home.main_tab, "Home"})
    end

    tabs()
    aimbot()
    antiaim()
    misc()
    visual()
    
    menu.config = pui.setup({menu.antiaim, menu.presets})
    config_system()
end

local helpers = new_class()
helpers:struct("core")({
    normalize_yaw = (function(self, a, b)
        while a > b do a = a - b*2 end
        while a < -b do a = a + b*2 end
        return a
    end),
    calc_angle = (function(self, a, b)
        local x_delta = b.x - a.x
        local y_delta = b.y - a.y
        local z_delta = b.z - a.z 
        local hyp = math.sqrt(x_delta^2 + y_delta^2)
        local x = math.atan2(z_delta, hyp) * 57.295779513082
        local y = math.atan2(y_delta , x_delta) * 180 / 3.14159265358979323846
        return { x = self:normalize_yaw(x, 90), y = self:normalize_yaw(y, 180), z = 0 }
    end),
    get_velocity = (function(self, a)
        local velocity = vector(entity.get_prop(a, "m_vecVelocity"))
        if not velocity then return end
        return math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    end),
    is_crouching = (function(self, a)
        if not a then return end
        local flags = entity.get_prop(a, "m_fFlags")
        if not flags then return end
        if bit.band(flags, 4) == 4 then
            return true
        end
        return false
    end),
    in_air = (function(self, a)
        if not a then return end
        local flags = entity.get_prop(a, "m_fFlags")
        if not flags then return end
        if bit.band(flags, 1) == 0 then
            return true
        end
        return false
    end),
    get_state = (function(self, cmd, a)
        local player = entity.get_local_player()
        local velocity = self:get_velocity(player)
        local in_jump = self:in_air(player) or cmd.in_jump == 1
        local in_duck = self:is_crouching(player) or cmd.in_duck == 1 or lua.refs.exploits.fd:get()
        local in_walk = (lua.refs.other.sw.value and lua.refs.other.sw.hotkey:get()) or cmd.in_speed == 1
        
        local cnds
        if velocity < 5 and not (in_jump or in_duck) then
            cnds = 1
        elseif in_jump and not in_duck then
            cnds = 4
        elseif in_jump and in_duck then
            cnds = 5
        elseif in_duck and not in_jump then
            cnds = velocity < 5 and 6 or 7
        else
            cnds = in_walk and 3 or 2
        end
        
        if a then
            return lua.vars.state_list[cnds]
        else
            return cnds
        end
    end),
    get_fakelag = (function(self, cmd, a)
        local chokedcommands = math.min(cmd.chokedcommands, lua.refs.exploits.fl:get())
        if chokedcommands ~= 0 then
            last_choke_packet = chokedcommands
        else
            last_send_packet = last_choke_packet
        end
        if a then
            if not last_send_packet then
                return false
            else
                return (last_send_packet ~= 1) or (chokedcommands > 1)
            end
        else
            if not last_send_packet then
                return 1
            else
                return last_send_packet
            end
        end
    end),
    get_entities = (function(self, enemy_only, alive_only)
        local enemy_only = enemy_only ~= nil and enemy_only or false
        local alive_only = alive_only ~= nil and alive_only or true
        local result = {}
        local me = entity.get_local_player()
        local player_resource = entity.get_player_resource()
        for player = 1, globals.maxplayers() do
            local is_enemy, is_alive = true, true
    
            if enemy_only and not entity.is_enemy(player) then is_enemy = false end
            if is_enemy then
                if alive_only and entity.get_prop(player_resource, 'm_bAlive', player) ~= 1 then is_alive = false end
                if is_alive then table.insert(result, player) end
            end
        end
        return result
    end),
    client_is_hittable = (function(self)
        local players = self:get_entities(true, true)
        for _, player in pairs(players) do
            if entity.is_dormant(player) then goto skip end
            if entity.have_flag(player, "Hit") then
                return true
            end
            ::skip::
        end
        return false
    end),
    get_exploit_charge = (function(self)
        local doubletap_ref = lua.refs.exploits.dt[1].value and lua.refs.exploits.dt[1]:get()
        local osaa_ref = lua.refs.exploits.hs.value and lua.refs.exploits.hs.hotkey:get()
        local tickbase = globals.tickcount() - globals.estimated_tickbase()
        local is_exploiting = osaa_ref or (doubletap_ref and tickbase > 0)
        return is_exploiting
    end),
    
    get_defensive = (function(self, vars, a, b)
        if b then
            if a then
                if self:get_exploit_charge() then
                    return vars.defensive_data.tick
                else
                    return 1
                end
            else
                return vars.defensive_data.tick
            end
        else
            if a then
                if self:get_exploit_charge() then
                    return (vars.defensive_data.tick > 1)
                else
                    return false
                end
            else
                return (vars.defensive_data.tick > 1)
            end
        end
    end),
    get_freestanding = (function(self, p, a)
        if not p then return false end
        if not a then return false end
        if not lua.refs.aa.fs:get() then return false end
        local is_dynamic = lua.refs.aa.yaw_base:get() == "At targets"
        local player_origin = vector(entity.get_origin(p))
        local ent_origin = vector(entity.get_origin(a))
        local yaw_base = is_dynamic and self:calc_angle(player_origin, ent_origin).y or vector(client.camera_angles()).y
        local yaw = yaw_base + lua.refs.aa.yaw[2]:get()
        local fs_yaw = self:normalize_yaw(entity.get_prop(p, "m_angEyeAngles[1]") - 180, 180)
        local diff = math.abs(yaw - fs_yaw)
        local is_fs = diff > 60 and diff < 300
        
        return is_fs
    end),
    get_freestand_direction = (function(self, p)
        local data = {
            side = 1,
            last_side = 0,
            last_hit = 0,
            hit_side = 0
        }
    
        if not p or entity.get_prop(p, "m_lifeState") ~= 0 then
            return
        end
    
        if data.hit_side ~= 0 and globals.curtime() - data.last_hit > 5 then
            data.last_side = 0
            data.last_hit = 0
            data.hit_side = 0
        end
    
        local eye = vector(client.eye_position())
        local ang = vector(client.camera_angles())
        local trace_data = {left = 0, right = 0}
    
        for i = ang.y - 120, ang.y + 120, 30 do
            if i ~= ang.y then
                local rad = math.rad(i)
                local px, py, pz = eye.x + 256 * math.cos(rad), eye.y + 256 * math.sin(rad), eye.z
                local fraction = client.trace_line(p, eye.x, eye.y, eye.z, px, py, pz)
                local side = i < ang.y and "left" or "right"
                trace_data[side] = trace_data[side] + fraction
            end
        end
    
        data.side = trace_data.left < trace_data.right and -1 or 1
    
        if data.side == data.last_side then
            return
        end
    
        data.last_side = data.side
    
        if data.hit_side ~= 0 then
            data.side = data.hit_side
        end
    
        return data.side
    end),
    safe_head = (function(self, p, a, cmd)
        if #menu.antiaim.safe_head.value:get() == 0 then return false end
        if not cmd.sidemove then return false end
        if not a then return false end
        if not p then return end
        if table.contains(menu.antiaim.safe_head.disabler:get(), "Lethal") then
            if entity.lethal(a, p) == true then return false end
        end
        local weapon = entity.get_player_weapon(p)
        if not weapon then return false end
        local weapon_c = entity.get_classname(weapon)
        if not weapon_c then return false end
        local is_taser = weapon_c == "CWeaponTaser"
        if is_taser then
            if not (table.contains(menu.antiaim.safe_head.value:get(), "Taser") or table.contains(menu.antiaim.safe_head.value:get(), "All")) then return false end
        end
        local is_knife = weapon_c == "CKnife"
        if is_knife then 
            if not (table.contains(menu.antiaim.safe_head.value:get(), "Knife") or table.contains(menu.antiaim.safe_head.value:get(), "All")) then return false end
        end
        if not table.contains(menu.antiaim.safe_head.value:get(), "All") then
            if not (is_knife or is_taser) then return false end
        end
        local state = self:get_state(cmd, true)
        if not table.contains(menu.antiaim.safe_head.trigger:get(), state) then return false end
        local m = -22.0676
        local b = 1949.0164

        local state = self:get_state(cmd, false)
        local velocity = self:get_velocity(p)
        local me = {
            vec = vector(entity.get_origin(p)) + vector(0, 0, entity.get_prop(p, "m_vecViewOffset[2]")),
        }
        local ent = {
            vec = vector(entity.get_origin(a)) + vector(0, 0, entity.get_prop(a, "m_vecViewOffset[2]")),
        }
        local dist_z = me.vec.z - ent.vec.z

        local weapon_model_mod = math.max(0, 20 - math.abs(vector(entity.get_prop(weapon, "m_vecMins")).z + vector(entity.get_prop(weapon, "m_vecMaxs")).z))
        local pitch_mod = is_knife and 0 or weapon_model_mod
        local pitch = 89 - pitch_mod

        local minimal_dist_z = math.min(75, m * pitch + b)
        if (minimal_dist_z <= dist_z) and (dist_z >= -75) then
            local m_yaw = is_knife and -13 or 0
            local s_yaw = (cmd.sidemove == 0) and 0 or ((cmd.sidemove > 0) and 2 or -3)
            local c_yaw = (cmd.sidemove == 0) and 12 or (12 + s_yaw)
            local yaw_state = { [1] = 1, [5] = 10, [6] = 10, [7] = c_yaw }
            local yaw = yaw_state[state] + m_yaw
            return true, yaw
        else
            return false
        end
    end),
    avoid_backstab = (function(self, a)
        if not menu.antiaim.avoid_backstab.value:get() then return false end
        if not a then return false end
        if not self:client_is_hittable() then return end
    
        local players = self:get_entities(true, true)
        local is_dangerous = false
    
        if menu.antiaim.avoid_backstab.disabler:get() then
            for _, player in pairs(players) do
                if not player then goto skip end
                if entity.is_dormant(player) then goto skip end
                local weapon_ent = entity.get_player_weapon(player)
                if weapon_ent == nil then goto skip end
                local weapon_idx = entity.get_prop(weapon_ent, "m_iItemDefinitionIndex")
                if weapon_idx == nil then goto skip end
                local weapon = csgo_weapons[weapon_idx]
                if weapon == nil then goto skip end
                if weapon.type == "knife" or weapon.type == "taser" then goto skip end
                if not entity.have_flag(player, "Hit") then goto skip end
                is_dangerous = true
                ::skip::
            end
        end
    
        local client_origin = vector(entity.get_origin(entity.get_local_player()))
        local target_origin = vector(entity.get_origin(a))
        local distance = client_origin:dist(target_origin)
    
        if distance > 250 or is_dangerous then return false end
    
        local weapon_ent = entity.get_player_weapon(a)
        if not weapon_ent then return false end
    
        local weapon_idx = entity.get_prop(weapon_ent, "m_iItemDefinitionIndex")
        if not weapon_idx then return false end
    
        local weapon = csgo_weapons[weapon_idx]
        if not weapon then return false end

        return (weapon.type == "knife")
    end),
    manual_yaw_handler = (function(self, vars)
        if not menu.antiaim.manual_yaw.value:get() then return true, false, false, false, 0 end
        local realtime = globals.realtime()
    
        if menu.antiaim.manual_yaw.back:get() or back_dir == nil then
            back_dir, right_dir, left_dir, forward_dir, yaw = true, false, false, false, 0
            vars.manual_yaw.last_press = realtime
        elseif menu.antiaim.manual_yaw.right:get() then
            if right_dir and vars.manual_yaw.last_press + 0.07 < realtime then
                back_dir, right_dir, left_dir, forward_dir, yaw = true, false, false, false, 0
            elseif not right_dir and vars.manual_yaw.last_press + 0.07 < realtime then
                right_dir, back_dir, left_dir, forward_dir, yaw = true, false, false, false, 90
            end
            vars.manual_yaw.last_press = realtime
        elseif menu.antiaim.manual_yaw.left:get() then
            if left_dir and vars.manual_yaw.last_press + 0.07 < realtime then
                back_dir, right_dir, left_dir, forward_dir, yaw = true, false, false, false, 0
            elseif not left_dir and vars.manual_yaw.last_press + 0.07 < realtime then
                left_dir, back_dir, right_dir, forward_dir, yaw = true, false, false, false, -90
            end
            vars.manual_yaw.last_press = realtime
        elseif menu.antiaim.manual_yaw.forward:get() then
            if forward_dir and vars.manual_yaw.last_press + 0.07 < realtime then
                back_dir, right_dir, left_dir, forward_dir, yaw = true, false, false, false, 0
            elseif not forward_dir and vars.manual_yaw.last_press + 0.07 < realtime then
                left_dir, back_dir, right_dir, forward_dir, yaw = false, false, false, true, 180
            end
            vars.manual_yaw.last_press = realtime
        end
    
        return back_dir, right_dir, left_dir, forward_dir, yaw
    end),
    create_way = (function(self, jitter, way, dynamic)
        local j = jitter* 0.5
        local wayh2 = (way%2 == 0) and way* 0.5 or (way-1)* 0.5

        local cycle = { }
        local store = { }

        for a = 1, wayh2 do
            local j2 = j/wayh2
            local i = wayh2-a+1
            local mod = (a%2 == 0) and -1 or 1

            local value = j2*i*mod
            table.insert(cycle, value)
            table.insert(cycle, value)
            table.insert(store, value)
            table.insert(store, value)
        end

        if way%2 ~= 0 then
            table.insert(cycle, 0)
        end

        if not dynamic then
            return cycle
        end

        local angles = {
            positive = { },
            negative = { },
        }

        for k, v in pairs(store) do
            if v > 0 then
                table.insert(angles.positive, v)
            elseif v < 0 then
                table.insert(angles.negative, v)
            end
        end

        local dynamic_cycle = { }

        if #angles.positive ~= 0 then
            for p = 1, (#angles.positive) * 0.5 do
                if #angles.positive == #angles.negative then
                    local frand = math.random(1, 2)
                    local ftbl = { angles.positive, angles.negative }
                    local stbl = { angles.negative, angles.positive }

                    local f_tbl = ftbl[frand]
                    local s_tbl = stbl[frand]
                    for l=1, 2 do
                        local rand = math.random(1, #f_tbl)
                        local v = f_tbl[rand]
                        table.insert(dynamic_cycle, v)
                        table.remove_id(f_tbl, v)
                    end
                    for l=1, 2 do
                        local rand = math.random(1, #s_tbl)
                        local v = s_tbl[rand]
                        table.insert(dynamic_cycle, v)
                        table.remove_id(s_tbl, v)
                    end
                else
                    for l=1, 2 do
                        local rand = math.random(1, #angles.positive)
                        local v = angles.positive[rand]
                        table.insert(dynamic_cycle, v)
                        table.remove_id(angles.positive, v)
                    end
                    if #angles.negative ~= 0 then
                        for l=1, 2 do
                            local rand = math.random(1, #angles.negative)
                            local v = angles.negative[rand]
                            table.insert(dynamic_cycle, v)
                            table.remove_id(angles.negative, v)
                        end
                    end
                end
            end
        end
        
        if way%2 ~= 0 then
            local rand = math.random(1, (#dynamic_cycle+1))
            if rand == #dynamic_cycle+1 then
                table.insert(dynamic_cycle, 0)
            else
                for d = #dynamic_cycle, rand, -1 do
                    dynamic_cycle[d + 1] = dynamic_cycle[d]
                end

                dynamic_cycle[rand] = 0
            end
        end

        return dynamic_cycle
    end),
})

client.set_event_callback("run_command", function(cmd)
    local vars = lua.vars

    vars.defensive_data.cmd = cmd.command_number
end)

client.set_event_callback("predict_command", function(cmd)
    local vars = lua.vars

    if cmd.command_number == vars.defensive_data.cmd then
        local tickbase = globals.estimated_tickbase()

        vars.defensive_data.check = math.max(tickbase, vars.defensive_data.check)
        vars.defensive_data.tick = math.min(14, math.max(1, vars.defensive_data.check-tickbase-3))
        vars.defensive_data.cmd = 0
    end
end)

client.set_event_callback("level_init", function()
    local vars = lua.vars

    vars.defensive_data.check = 0
    vars.defensive_data.tick = 0
    vars.defensive_data.cmd = 0
end)

local setup_command = new_class()
setup_command:struct("core", helpers.core)({
    declare_data = (function(self, cmd)
        local vars = lua.vars
        local player = entity.get_local_player()
        local state = self:get_state(cmd, true)
        local team = vars.team_list[entity.get_prop(player, "m_iTeamNum")]

        local preset = menu.presets[state][team]
        local defensive = self:get_defensive(vars, true, false) and preset.hidden.value:get()
        local freestand_dir = self:get_freestand_direction(player)

        if entity.get_prop(entity.get_all("CCSGameRulesProxy")[1], "m_bWarmupPeriod") == 1 and table.contains(menu.antiaim.warmup_preset:get(), "Warmup") then
            lua.refs.aa.yaw[1]:set("Spin")
            lua.refs.aa.pitch[1]:set('Off')
            lua.refs.aa.yaw_base:set("At targets")
            lua.refs.aa.pitch[2]:set(0)
            lua.refs.aa.byaw[1]:set('Off')
            lua.refs.aa.byaw[2]:set(0)
            lua.refs.aa.jyaw[1]:set("Off")
            lua.refs.aa.jyaw[2]:set(0)
            lua.refs.aa.yaw[2]:set(25)
        end

        local body_data = {
            value = (defensive and ((preset.hidden.body:get() == "Global") and preset.body.value:get() or preset.hidden.body:get()) or preset.body.value:get()),
            amount = (defensive and preset.hidden.body_amount:get() or preset.body.amount:get()),
            delay = (defensive and preset.hidden.body_delay:get() or preset.body.delay:get()),
            dynamic_delay = (defensive and preset.hidden.body_delay2:get() or preset.body.dynamic:get()),
        }
        legit_class = {}
        legit_class.__index = legit_class

        function legit_class:new()
            local instance = setmetatable({}, legit_class)
            return instance
        end

        function legit_class:entity_has_c4(ent)
            local bomb = entity.get_all("CC4")[1]
            if bomb then
                local owner = entity.get_prop(bomb, "m_hOwnerEntity")
                return owner == ent
            else
                return false 
            end
        end
        function legit_class:distance3d(x1, y1, z1, x2, y2, z2)
            return math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) + (z2 - z1) * (z2 - z1))
        end
        function legit_class:aa_on_use(cmd)
            local distance = 100
            local bomb = entity.get_all("CPlantedC4")[1]
            local classnames = { "CWorld", "CCSPlayer", "CFuncBrush" }

            if bomb then
                local bomb_vec = vector(entity.get_origin(bomb))
                if bomb_vec then
                    local player_vec = vector(entity.get_origin(entity.get_local_player()))
                    distance = self:distance3d(bomb_vec.x, bomb_vec.y, bomb_vec.z, player_vec.x, player_vec.y, player_vec.z)
                end
            end
            
            local team_num = entity.get_prop(entity.get_local_player(), "m_iTeamNum")
            local defusing = team_num == 3 and distance < 62
            local on_bombsite = entity.get_prop(entity.get_local_player(), "m_bInBombZone")
            local has_bomb = self:entity_has_c4(entity.get_local_player())
            
            local px, py, pz = client.eye_position()
            local pitch, yaw = client.camera_angles()
            
            local sin_pitch = math.sin(math.rad(pitch))
            local cos_pitch = math.cos(math.rad(pitch))
            local sin_yaw = math.sin(math.rad(yaw))
            local cos_yaw = math.cos(math.rad(yaw))
            local dir_vec = { cos_pitch * cos_yaw, cos_pitch * sin_yaw, -sin_pitch }
            
            local fraction, entindex = client.trace_line(entity.get_local_player(), px, py, pz, px + (dir_vec[1] * 8192), py + (dir_vec[2] * 8192), pz + (dir_vec[3] * 8192))
            
            local using = true
            
            if entindex then
                if classnames then
                    for i = 1, #classnames do
                        if entity.get_classname(entindex) == classnames[i] then
                            using = false
                            break
                        end
                    end
                end
            end
            
            if not using and not defusing then
                cmd.in_use = 0
            end
        end
        local my_instance = legit_class:new()
        if menu.antiaim.legit_antiaim:get() then
            lua.refs.aa.pitch[1]:override("Custom")
            lua.refs.aa.pitch[2]:override(0)
            lua.refs.aa.yaw[1]:override("180")
            lua.refs.aa.yaw[2]:override("180")
            my_instance:aa_on_use(cmd)
            if (right_dir or left_dir) then
                if lua.refs.aa.byaw[1] and lua.refs.aa.byaw[1].override then
                    lua.refs.aa.byaw[1]:override("Static", left_dir and 1 or right_dir and -1, cmd)
                end
            end
        end
        if cmd.chokedcommands == 0 then
            if (vars.anti_aim_data.delay.ticks >= vars.anti_aim_data.delay.value) or (defensive ~= vars.anti_aim_data.defensive.last) then
                if (vars.anti_aim_data.delay.ticks >= vars.anti_aim_data.delay.value) then
                    if body_data.value == "Jitter" then
                        if vars.anti_aim_data.aa.side == 0 then
                            vars.anti_aim_data.aa.side = 1
                        end
                        vars.anti_aim_data.aa.side = vars.anti_aim_data.aa.side*-1
                    elseif body_data.value == "Dynamic" then
                        vars.anti_aim_data.aa.side = (math.random(0, 1) == 0) and -1 or 1
                    elseif body_data.value == "Default" then
                        vars.anti_aim_data.aa.side = freestand_dir
                    elseif body_data.value == "Reversed" then
                        vars.anti_aim_data.aa.side = -freestand_dir
                    else
                        vars.anti_aim_data.aa.side = body_data.amount
                    end

                    if vars.anti_aim_data.hold.ticks >= (preset.jitter.hold:get() + preset.jitter.switch:get())*2 then
                        vars.anti_aim_data.hold.ticks = 1
                    else
                        vars.anti_aim_data.hold.ticks = vars.anti_aim_data.hold.ticks + 1
                    end

                    if vars.anti_aim_data.way.ticks >= preset.jitter.way:get() then
                        vars.anti_aim_data.way.cycle = self:create_way(vars.anti_aim_data.way.jitter, preset.jitter.way:get(), preset.jitter.dynamic:get())
                        vars.anti_aim_data.way.ticks = 1
                    else
                        vars.anti_aim_data.way.ticks = vars.anti_aim_data.way.ticks + 1
                    end
                    vars.anti_aim_data.delay.ticks = 0
                end

                if (body_data.value ~= "Jitter") and (body_data.value ~= "Dynamic") then
                    vars.anti_aim_data.delay.value = 0
                else
                    if body_data.dynamic_delay then
                        vars.anti_aim_data.delay.value = math.random(math.random(0, body_data.delay))
                    else
                        vars.anti_aim_data.delay.value = body_data.delay
                    end
                    local last_randomization_time = 0
                    local last_randomization_time_non_dynamic = 0
                    
                    if menu.antiaim.dodge_bruteforce:get() and is_can_emulate() then
                        if not body_data.dynamic_delay then
                            if body_data.delay == 0 then
                                if globals.realtime() - last_randomization_time_non_dynamic >= 1 then
                                    last_randomization_time_non_dynamic = globals.realtime()
                                    body_data.delay = math.random(0, 5)
                                    -- print("[dodge] delay is 0, switching delay to:", body_data.delay)
                                end

                                if math.random() < 0.7 then
                                    vars.anti_aim_data.delay.value = math.random(0, 2)
                                    -- print("[dodge] delay is 0, anti_aim_data.delay set to (0-2):", vars.anti_aim_data.delay.value)
                                else
                                    vars.anti_aim_data.delay.value = math.random(0, 5)
                                    -- print("[dodge] delay is 0, anti_aim_data.delay set to (0-5):", vars.anti_aim_data.delay.value)
                                end
                    
                            else
                                if globals.realtime() - last_randomization_time_non_dynamic >= 1.5 then
                                    last_randomization_time_non_dynamic = globals.realtime()
                                    vars.anti_aim_data.delay.value = math.random(0, body_data.delay)
                                    -- print("[dodge] delay is", body_data.delay, ", switching anti_aim_data.delay to:", vars.anti_aim_data.delay.value)
                                end
                            end
                    
                        else
                            if globals.realtime() - last_randomization_time >= 1 then
                                last_randomization_time = globals.realtime()
                                body_data.delay = math.random(0, 5)
                                -- print("[dodge] switch, delay updated to:", body_data.delay)
                            end
                            
                            if body_data.delay == 0 then
                                vars.anti_aim_data.delay.value = math.random(0, 3)
                                -- print("[dodge] delay is 0, setting anti_aim_data.delay to (0-3):", vars.anti_aim_data.delay.value)
                            else
                                if math.random() < 0.5 then
                                    vars.anti_aim_data.delay.value = math.random(0, 2)
                                    -- print("[dodge] delay is", body_data.delay, ", setting anti_aim_data.delay to (0-2):", vars.anti_aim_data.delay.value)
                                elseif is_can_emulate() then
                                    vars.anti_aim_data.delay.value = math.random(0, body_data.delay)
                                    -- print("[dodge] delay is", body_data.delay, ", setting anti_aim_data.delay to:", vars.anti_aim_data.delay.value)
                                end
                            end
                        end
                    end
                end
                vars.anti_aim_data.defensive.last = defensive
            else
                vars.anti_aim_data.delay.ticks = vars.anti_aim_data.delay.ticks + 1
            end

            if (body_data.value == "Jitter") or (body_data.value == "Dynamic") then
                vars.anti_aim_data.aa.jside = vars.anti_aim_data.aa.side
            else
                vars.anti_aim_data.aa.jside = vars.anti_aim_data.aa.jside*-1
            end
        end

        local side = vars.anti_aim_data.aa.side
        local jside = vars.anti_aim_data.aa.jside

        local yaw_data = { 
            [1] = {
                offset = preset.yaw.right:get(),
                v = preset.yaw.right:get()*(1-preset.yaw.randomized:get()/100),
            },
            [-1] = {
                offset = preset.yaw.left:get(),
                v = preset.yaw.left:get()*(1-preset.yaw.randomized:get()/100),
            }
        }
        if side ~= 0 then
            vars.anti_aim_data.aa.yaw = math.random(yaw_data[side].v, yaw_data[side].offset)
        else
            vars.anti_aim_data.aa.yaw = math.random(yaw_data[jside].v, yaw_data[jside].offset)
        end
        
        if preset.jitter.value:get() == "Center" then
            local v = preset.jitter.offset:get() * (1 - preset.jitter.randomized:get() / 100)
            vars.anti_aim_data.aa.jitter = math.random(v, preset.jitter.offset:get())* 0.5*jside
        elseif preset.jitter.value:get() == "Between" then
            local v = preset.jitter.offset:get() * (1 - preset.jitter.randomized:get() / 100)
            vars.anti_aim_data.hold.jitter = math.random(v, preset.jitter.offset:get())

            if preset.jitter.hold:get() * 2 >= vars.anti_aim_data.hold.ticks then
                vars.anti_aim_data.aa.jitter = (vars.anti_aim_data.hold.jitter * 0.5) * jside
            else
                vars.anti_aim_data.aa.jitter = (preset.jitter.switch_offset:get() * 0.5) * jside
            end
        elseif preset.jitter.value:get() == "Static Way" then
            if preset.jitter.offset:get() == 0 then
                vars.anti_aim_data.aa.jitter = 0
            else
                local v = preset.jitter.offset:get() * (1 - preset.jitter.randomized:get() / 100)
                if preset.jitter.offset:get() > 0 then
                    local jit = math.random(v, preset.jitter.offset:get()) * 0.5
                    local val = jit - (cmd.command_number * 3 % jit)
                    vars.anti_aim_data.aa.jitter = val * jside
                else
                    local jit = math.random(v, preset.jitter.offset:get()) * 0.5
                    local val = cmd.command_number * 3 % jit
                    vars.anti_aim_data.aa.jitter = val * jside
                end
            end
        elseif preset.jitter.value:get() == "Dynamic Way" then
            local v = preset.jitter.offset:get() * (1 - preset.jitter.randomized:get() / 100)
            vars.anti_aim_data.way.jitter = math.random(v, preset.jitter.offset:get())
            if vars.anti_aim_data.way.cycle[vars.anti_aim_data.way.ticks] then
                vars.anti_aim_data.aa.jitter = vars.anti_aim_data.way.cycle[vars.anti_aim_data.way.ticks] * jside
            else
                vars.anti_aim_data.aa.jitter = vars.anti_aim_data.way.jitter * jside
            end
        else
            vars.anti_aim_data.aa.jitter = 0
        end

        if preset.hidden.value:get() and (preset.hidden.pitch:get() ~= "Global") then
            if preset.hidden.pitch:get() == "Random" then
                vars.anti_aim_data.defensive.pitch = math.random(preset.hidden.pitch_offset:get(), preset.hidden.pitch_offset2:get())
            elseif preset.hidden.pitch:get() == "Jitter" then
                if cmd.command_number % 4 > 1 then
                    vars.anti_aim_data.defensive.pitch = preset.hidden.pitch_offset:get()
                else
                    vars.anti_aim_data.defensive.pitch = preset.hidden.pitch_offset2:get()
                end
            elseif preset.hidden.pitch:get() == "Spin" then
                local speed = preset.hidden.pitch_spin_speed:get() * 0.1
                local time = globals.realtime() * speed
                local absolutetime = time % 1
                vars.anti_aim_data.defensive.pitch = round(lerp(preset.hidden.pitch_offset:get(), preset.hidden.pitch_offset2:get(), absolutetime))
            elseif preset.hidden.pitch:get() == "Random static" then
                if vars.defensive_data.tick == 11 then
                    vars.anti_aim_data.defensive.random_pitch = math.random(preset.hidden.pitch_offset:get(), preset.hidden.pitch_offset2:get())
                end

                vars.anti_aim_data.defensive.pitch = vars.anti_aim_data.defensive.random_pitch
            else
                vars.anti_aim_data.defensive.pitch = preset.hidden.pitch_offset:get()
            end
        else
            vars.anti_aim_data.defensive.pitch = 89
        end

        if preset.hidden.value:get() and (preset.hidden.yaw:get() ~= "Global") then
            local v = preset.hidden.yaw_apply:get() and self:normalize_yaw(vars.anti_aim_data.aa.yaw + vars.anti_aim_data.aa.jitter, 180) or 0
            if preset.hidden.yaw:get() == "Random" then
                vars.anti_aim_data.defensive.yaw_mod = math.random(preset.hidden.yaw_offset:get(), preset.hidden.yaw_offset2:get())
            elseif preset.hidden.yaw:get() == "Jitter" then
                if cmd.command_number % 4 > 1 then
                    vars.anti_aim_data.defensive.yaw_mod = preset.hidden.yaw_offset:get()
                else
                    vars.anti_aim_data.defensive.yaw_mod = preset.hidden.yaw_offset2:get()
                end
            elseif preset.hidden.yaw:get() == "Left/Right" then
                local d_yaw_data = {
                    [1] = preset.hidden.yaw_offset2:get(),
                    [-1] = preset.hidden.yaw_offset:get()
                }
                if side ~= 0 then
                    vars.anti_aim_data.defensive.yaw_mod = d_yaw_data[side]
                else
                    vars.anti_aim_data.defensive.yaw_mod = d_yaw_data[jside]
                end
            elseif preset.hidden.yaw:get() == 'Spin' then
                vars.anti_aim_data.defensive.yaw_mod = (preset.hidden.yaw_offset:get() * globals.realtime() * (preset.hidden.yaw_spin_speed:get() * 0.1) * 2)
            elseif preset.hidden.yaw:get() == 'Random static' then
                if vars.defensive_data.tick == 11 then
                    vars.anti_aim_data.defensive.random_yaw = math.random(preset.hidden.yaw_offset:get(), preset.hidden.yaw_offset2:get())
                end

                vars.anti_aim_data.defensive.yaw_mod = vars.anti_aim_data.defensive.random_yaw
            elseif preset.hidden.yaw:get() == "Flick" then
                local d_yaw_data = {
                    [1] = preset.hidden.yaw_offset2:get(),
                    [-1] = preset.hidden.yaw_offset:get()
                }
                   
                if vars.defensive_data.tick < 6 then
                    vars.anti_aim_data.defensive.yaw_mod = d_yaw_data[1]
                    vars.anti_aim_data.aa.side = 1
                elseif vars.defensive_data.tick > 10 then
                    vars.anti_aim_data.defensive.yaw_mod = d_yaw_data[-1]
                    vars.anti_aim_data.aa.side = -1
                end
            else
                vars.anti_aim_data.defensive.yaw_mod = 0
            end
            vars.anti_aim_data.defensive.yaw = self:normalize_yaw(preset.hidden.yaw_main:get() + vars.anti_aim_data.defensive.yaw_mod + v, 180)
        else
            vars.anti_aim_data.defensive.yaw = -self:normalize_yaw(vars.anti_aim_data.aa.yaw + vars.anti_aim_data.aa.jitter, 180)
        end

        vars.cmd = cmd

        local doubletap_ref = lua.refs.exploits.dt[1].value and lua.refs.exploits.dt[1]:get()
        local osaa_ref = lua.refs.exploits.hs.value and lua.refs.exploits.hs.hotkey:get()

        if table.contains(preset.safe_lc.value:get(), "Doubletap") and doubletap_ref then
            cmd.force_defensive = 1
        elseif table.contains(preset.safe_lc.value:get(), "Hideshot") and osaa_ref then
            cmd.force_defensive = 1
        end
    end),
    main = (function(self, cmd)
        local vars = lua.vars
        local player = entity.get_local_player()
        local target = client.current_threat()
        local state = self:get_state(cmd, true)
        local team = vars.team_list[entity.get_prop(player, "m_iTeamNum")]

        local preset = menu.presets[state][team]
        local is_fakelag = self:get_fakelag(cmd, true)
        local defensive = self:get_defensive(vars, true, false) and preset.hidden.value:get()

        local safe_head, safe_yaw = self:safe_head(player, target, cmd)
        local freestanding = menu.antiaim.freestanding.value:get() and menu.antiaim.freestanding.key:get() and not table.contains(menu.antiaim.freestanding.disabler:get(), state)
        local back_dir, right_dir, left_dir, forward_dir, manual_yaw = self:manual_yaw_handler(vars)

        local presets = {
            avoid_backstab = self:avoid_backstab(target),
            manual_yaw = menu.antiaim.manual_yaw.force:get() and not back_dir,
            freestanding = freestanding and menu.antiaim.freestanding.force:get() and back_dir and self:get_freestanding(player, target),
            safe_head = safe_head and back_dir and not self:get_freestanding(player, target),
            --fakelag = fakelag[menu.antiaim.fl_aa.trigger:get()] and menu.antiaim.fl_aa.value:get() and not (lua.refs.exploits.fd:get() and menu.antiaim.fl_aa.opt:get() == "disable"),
        }

        local dynamic_yaw = (table.contains(menu.antiaim.dynamic_yaw.disabler:get(), "Manual yaw") and not back_dir and not presets.avoid_backstab) and "Local view" or ((menu.antiaim.dynamic_yaw.value:get() or presets.avoid_backstab) and "At targets" or "Local view")

        lua.refs.aa.enabled:override(true)
        lua.refs.aa.yaw_base:override(dynamic_yaw)
        lua.refs.aa.yaw[1]:override("180")
        lua.refs.aa.fs_byaw:override(false)
        lua.refs.aa.jyaw[1]:override("Center")
        lua.refs.aa.byaw[1]:override("Static")
        lua.refs.aa.fs:set_hotkey("Always on")

        if presets.avoid_backstab then
            if cmd.chokedcommands ~= 1 then
                lua.refs.aa.pitch[1]:override("Minimal")
                lua.refs.aa.pitch[2]:override(0)

                lua.refs.aa.yaw[2]:override(180)
                lua.refs.aa.byaw[2]:override(vars.anti_aim_data.aa.side)
            end

            lua.refs.aa.jyaw[2]:override(0)
            lua.refs.aa.fs:override(false)
        elseif presets.safe_head then
            if cmd.chokedcommands ~= 1 then
                if defensive then 
                    lua.refs.aa.pitch[1]:override("Custom")
                    lua.refs.aa.pitch[2]:override(preset.hidden.pitch:get() == "Global" and 89 or 0)
    
                    lua.refs.aa.yaw[2]:override(preset.hidden.yaw:get() == "Global" and safe_yaw or 180)
                    lua.refs.aa.byaw[2]:override(0)
                else
                    lua.refs.aa.pitch[1]:override("Minimal")
                    lua.refs.aa.pitch[2]:override(0)
    
                    lua.refs.aa.yaw[2]:override(safe_yaw)
                    lua.refs.aa.byaw[2]:override(0)
                end
            end

            lua.refs.aa.jyaw[2]:override(0)
            lua.refs.aa.fs:override(false)
        else
            if defensive then 
                if cmd.chokedcommands ~= 1 then
                    lua.refs.aa.pitch[1]:override("Custom")
                    if presets.freestanding or presets.manual_yaw then
                        lua.refs.aa.pitch[2]:override(preset.hidden.pitch:get() == "Global" and 89 or 0)
                    else
                        lua.refs.aa.pitch[2]:override(self:normalize_yaw(vars.anti_aim_data.defensive.pitch, 89))
                    end

                    if presets.freestanding or presets.manual_yaw then
                        lua.refs.aa.yaw[2]:override(preset.hidden.yaw:get() == "Global" and manual_yaw or self:normalize_yaw(180 + manual_yaw, 180))
                        lua.refs.aa.byaw[2]:override(preset.hidden.body:get() == "Global" and 1 or 0)
                    else
                        lua.refs.aa.yaw[2]:override(self:normalize_yaw(vars.anti_aim_data.defensive.yaw + manual_yaw, 180))
                        lua.refs.aa.byaw[2]:override(vars.anti_aim_data.aa.side)
                    end
                end
    
                lua.refs.aa.jyaw[2]:override(0)
                lua.refs.aa.fs:override(freestanding and back_dir)
            else
                if cmd.chokedcommands ~= 1 then
                    lua.refs.aa.pitch[1]:override("Minimal")
                    lua.refs.aa.pitch[2]:override(0)

                    if presets.freestanding or presets.manual_yaw then
                        lua.refs.aa.yaw[2]:override(manual_yaw)
                        lua.refs.aa.byaw[2]:override(1)
                    else
                        lua.refs.aa.yaw[2]:override(self:normalize_yaw(vars.anti_aim_data.aa.yaw + vars.anti_aim_data.aa.jitter + manual_yaw, 180))
                        lua.refs.aa.byaw[2]:override(vars.anti_aim_data.aa.side)
                    end
                end
    
                lua.refs.aa.jyaw[2]:override((cmd.chokedcommands == 0 and not is_fakelag) and vars.anti_aim_data.aa.broken or 0)
                lua.refs.aa.fs:override(freestanding and back_dir)
            end
        end
    end),
}, {"declare_data", "main"})

-- Dodge Bruteforce


local E_POSE_PARAMETERS = {
    STRAFE_YAW = 0,
    STAND = 1,
    LEAN_YAW = 2,
    SPEED = 3,
    LADDER_YAW = 4,
    LADDER_SPEED = 5,
    JUMP_FALL = 6,
    MOVE_YAW = 7,
    MOVE_BLEND_CROUCH = 8,
    MOVE_BLEND_WALk = 9,
    MOVE_BLEND_RUN = 10,
    BODY_YAW = 11,
    BODY_PITCH = 12,
    AIM_BLEND_STAND_IDLE = 13,
    AIM_BLEND_STAND_WALK = 14,
    AIM_BLEND_STAND_RUN = 15,
    AIM_BLEND_CROUCH_IDLE = 16,
    AIM_BLEND_CROUCH_WALK = 17,
    DEATH_YAW = 18,
}
local is_on_ground = false

client.set_event_callback("setup_command", function(cmd)
    is_on_ground = cmd.in_jump == 0
    if (menu.misc.animmoving:get() == "Jitter") then
    lua.refs.other.leg_movement:set(cmd.command_number % 4 == 0 and "Off" or "Always slide")
    end
end)

MyNewClass = {}
MyNewClass.__index = MyNewClass

function MyNewClass:new()
    local instance = setmetatable({}, MyNewClass)
    return instance
end

MyNewClass = {}
MyNewClass.__index = MyNewClass

function MyNewClass:new()
    local instance = setmetatable({}, MyNewClass)
    return instance
end

local shiza_air = false
local pre_flags = 0
local post_flags = 0

client.set_event_callback("pre_predict_command", function(e)
    local me = entity.get_local_player();
    pre_flags = entity.get_prop(me, "m_fFlags");
end)

client.set_event_callback("predict_command", function(e)
    local me = entity.get_local_player();
    post_flags = entity.get_prop(me, "m_fFlags");
end)
function get_air() 
    shiza_air = bit.band(pre_flags, post_flags, bit.lshift(1, 0)) == 0
end
client.set_event_callback("net_update_end", get_air)
function MyNewClass:in_air(self)
    return shiza_air
end

function MyNewClass:get_states()
    local player = entity.get_local_player()
    if player == nil then return end

    local my_data = c_entity(player);
    if my_data == nil then return end

    local animstate = c_entity.get_anim_state(my_data);
    if animstate == nil then return end
    
    local velocity = animstate.m_velocity > 5
    local in_jump = self:in_air()
    local in_duck = entity.get_prop(player, "m_flDuckAmount");
    local in_walk = (lua.refs.other.sw.value and lua.refs.other.sw.hotkey:get())

    local states
    if not velocity and in_duck ~= 1 and not in_jump then
        states = 1 -- Standing
    elseif in_jump then
        states = in_duck == 1 and 5 or 4 -- Air
    elseif in_duck == 1 and not in_jump then
        states = velocity and 7 or 6 -- Duck + DuckMove
    else
        states = in_walk and 3 or 2 -- Walk + Move
    end

    return states
end

local myObject = MyNewClass:new()

client.set_event_callback("pre_render", function()
    local self = entity.get_local_player()
    local my_data = c_entity(self)
    if not my_data then
        return
    end

    local animstate = c_entity.get_anim_state(my_data)
    if not animstate then
        return
    end

    if (menu.misc.animmoving:get() == "Jitter") then
        entity.set_prop(self, "m_flPoseParameter", E_POSE_PARAMETERS.STAND, globals.tickcount() % 4 > 1 and 0.01 or 1)
    end
    if (menu.misc.animmoving:get() == "Static") then
        entity.set_prop(self, "m_flPoseParameter", 1, 0, E_POSE_PARAMETERS.MOVE_BLEND_RUN)
    end
    if (menu.misc.animair:get() == "Kangaroo") then
        entity.set_prop(self, "m_flPoseParameter", math.random(), 3)
        entity.set_prop(self, "m_flPoseParameter", math.random()*0.25, 7)
        entity.set_prop(self, "m_flPoseParameter", math.random()*0.5, 6)
        -- entity.set_prop(self, "m_flPoseParameter", math.random(0, 10)/10, 6)
        entity.set_prop(self, "m_flPoseParameter", math.random()*0.1, 9)
        -- entity.set_prop(self, "m_flPoseParameter", math.random(0, 10)/10, 9)
    end
    if (menu.misc.animair:get() == "Static") then
        entity.set_prop(self, "m_flPoseParameter", 0.5, E_POSE_PARAMETERS.JUMP_FALL)
    end

    if menu.misc.pitch_on_land:get() then
        if not shiza_air and animstate.hit_in_ground_animation then
            entity.set_prop(self, 'm_flPoseParameter', 0.5, 12)
        end
    end
end)
function movementfast_ladder(cmd)
    if not menu.misc.fastladder:get() then return end
    local me = entity.get_local_player()
    if not me then return end

    local move_type = entity.get_prop(me, 'm_MoveType')
    local weapon = entity.get_player_weapon(me)
    local throw = entity.get_prop(weapon, 'm_fThrowTime')

    if move_type ~= 9 then
        return
    end

    if weapon == nil then
        return
    end

    if throw ~= nil and throw ~= 0 then
        return
    end

    local view = client.camera_angles()
    if cmd.forwardmove > 0 then
        if cmd.pitch < 45 then
            cmd.pitch = 89
            cmd.in_moveright = 1
            cmd.in_moveleft = 0
            cmd.in_forward = 0
            cmd.in_back = 1

            if cmd.sidemove == 0 then
                cmd.yaw = cmd.yaw + 90
            end

            if cmd.sidemove < 0 then
                cmd.yaw = cmd.yaw + 150
            end

            if cmd.sidemove > 0 then
                cmd.yaw = cmd.yaw + 30
            end
        end
    elseif cmd.forwardmove < 0 then
        cmd.pitch = 89
        cmd.in_moveleft = 1
        cmd.in_moveright = 0
        cmd.in_forward = 1
        cmd.in_back = 0

        if cmd.sidemove == 0 then
            cmd.yaw = cmd.yaw + 90
        end

        if cmd.sidemove > 0 then
            cmd.yaw = cmd.yaw + 150
        end

        if cmd.sidemove < 0 then
            cmd.yaw = cmd.yaw + 30
        end
    end
end

client.set_event_callback("setup_command", movementfast_ladder)

local aspectratio = {} do
    local switch = menu.misc.aspectratio
    local default_aspect_ratio = screen.x / screen.y
    local r_aspectratio = cvar.r_aspectratio
    local default_ratio = tonumber(r_aspectratio:get_string())

    local function set_aspect_ratio(value)
        r_aspectratio:set_raw_float(value == 0 and default_ratio or value)
    end

    function aspectratio.render()
        local target = switch.on:get() and switch.slider:get() * 0.01 or default_aspect_ratio
        set_aspect_ratio(target == default_aspect_ratio and 0 or target)
    end

    client.set_event_callback('paint', function ()
        if not switch.on:get() then
            set_aspect_ratio(default_ratio)
            return
        end
        
        aspectratio.render()
    end)

    function aspectratio.shutdown()
        set_aspect_ratio(default_ratio)
    end

    defer(aspectratio.shutdown)
end

local ffi_to = {
    classptr = ffi.typeof('void***'), 
    client_entity = ffi.typeof('void*(__thiscall*)(void*, int)'),
    
    set_angles = (function()
        ffi.cdef('typedef struct { float x; float y; float z; } vmodel_vec3_t;')

        return ffi.typeof('void(__thiscall*)(void*, const vmodel_vec3_t&)')
    end)()
}

local rawelist = client.create_interface('client_panorama.dll', 'VClientEntityList003') or error('VClientEntityList003 is nil', 2)
local ientitylist = ffi.cast(ffi_to.classptr, rawelist) or error('ientitylist is nil', 2)
local get_client_entity = ffi.cast(ffi_to.client_entity, ientitylist[0][3]) or error('get_client_entity is nil', 2)

local set_angles = client.find_signature('client_panorama.dll', '\x55\x8B\xEC\x83\xE4\xF8\x83\xEC\x64\x53\x56\x57\x8B\xF1') or error('Couldn\'t find set_angles signature!')
local set_angles_fn = ffi.cast(ffi_to.set_angles, set_angles) or error('Couldn\'t cast set_angles_fn')

local get_original = function()
    return {
        fov = client.get_cvar('viewmodel_fov'),
        
        x = client.get_cvar('viewmodel_offset_x'),
        y = client.get_cvar('viewmodel_offset_y'),
        z = client.get_cvar('viewmodel_offset_z')
    }
end

local g_handler = function(...)
    local shutdown = #({...}) > 0 or not menu.misc.viewmodel:get()

    local multiplier = shutdown and 0 or 0.0025
    local original, data = get_original(), 
    {
        fov = menu.misc.viewmodel_fov:get() * multiplier,
        x = menu.misc.viewmodel_x:get() * multiplier,
        y = menu.misc.viewmodel_y:get() * multiplier,
        z = menu.misc.viewmodel_z:get() * multiplier,
        
    }

    cvar.viewmodel_fov:set_raw_float(original.fov + data.fov)
    cvar.viewmodel_offset_x:set_raw_float(original.x + data.x)
    cvar.viewmodel_offset_y:set_raw_float(original.y + data.y)
    cvar.viewmodel_offset_z:set_raw_float(original.z + data.z)
end

local g_override_view = function()

    local me = entity.get_local_player()
    local viewmodel = entity.get_prop(me, 'm_hViewModel[0]')

    if me == nil or viewmodel == nil then
        return
    end

    local viewmodel_ent = get_client_entity(ientitylist, viewmodel)

    if viewmodel_ent == nil then
        return
    end

    local camera_angles = { client.camera_angles() }
    local angles = ffi.cast('vmodel_vec3_t*', ffi.new('char[?]', ffi.sizeof('vmodel_vec3_t')))

    angles.x, angles.y = camera_angles[1], camera_angles[2]

    set_angles_fn(viewmodel_ent, angles)
end

client.set_event_callback('pre_render', g_handler)
client.set_event_callback('override_view', g_override_view)
client.set_event_callback('shutdown', function() g_handler(true) end)

menu.misc.thirdperson_dist:set_callback(function (item)
    if menu.misc.thirdperson:get() then
        local idealdist = cvar.cam_idealdist
        idealdist:set_int(menu.misc.thirdperson_dist:get())
    end
end, true)

local prefer_baim = {}; do
    local function extrapolate_pos(xpos, ypos, zpos, tick, player)
        local x, y, z = entity.get_prop(player, "m_vecVelocity")

        if not x or not y or not z then
            return xpos, ypos, zpos
        end

        for i = 0, tick do
            xpos = xpos + (x * globals.tickinterval() * (i + 1))
            ypos = ypos + (y * globals.tickinterval() * (i + 1))
            zpos = zpos + (z * globals.tickinterval() * (i + 1))
        end
    
        return xpos, ypos, zpos
    end

    function prefer_baim.shutdown()
        local players = entity.get_players(true)
        for i = 1, #players do
            plist.set(players[i], "Override prefer body aim", '-')
            plist.set(players[i], "Override safe point", '-')
            
            client.update_player_list()
            break
        end
    end

    function prefer_baim.run_command()
        local me = entity.get_local_player()
        local weapon = entity.get_player_weapon(me)
        local player = client.current_threat()
        if not table.contains(menu.aimbot.aimtools:get(), "Advanced aimlogic") then
            prefer_baim.shutdown()
            return
        end

        if not weapon then
            return
        end

        local eye_x, eye_y, eye_z = client.eye_position()
        local extrapolate_pos_x, extrapolate_pos_y, extrapolate_pos_z = extrapolate_pos(eye_x, eye_y, eye_z, 5, me)
        local enemy_health = entity.get_prop(player, "m_iHealth")
        if entity.is_dormant(player) then
            return
        end

        local head_x, head_y, head_z = entity.hitbox_position(player, 0)
        local stomach_x, stomach_y, stomach_z = entity.hitbox_position(player, 3)
        local chest_x, chest_y, chest_z = entity.hitbox_position(player, 5)

        local head_ent, head_trace_bullet_damage = client.trace_bullet(me, extrapolate_pos_x, extrapolate_pos_y, extrapolate_pos_z, head_x, head_y, head_z, false)
        local stomach_ent, stomach_trace_bullet_damage = client.trace_bullet(me, extrapolate_pos_x, extrapolate_pos_y, extrapolate_pos_z, stomach_x, stomach_y, stomach_z, false)
        local chest_ent, chest_trace_bullet_damage = client.trace_bullet(me, extrapolate_pos_x, extrapolate_pos_y, extrapolate_pos_z, chest_x, chest_y, chest_z, false)

        -- print(stomach_trace_bullet_damage .. ' ' .. head_trace_bullet_damage .. ' ' .. chest_trace_bullet_damage)

        local is_lethal, max_dmg = entity.lethal(me, player, false)
        local lethal = false
        if enemy_health <= math.max(stomach_trace_bullet_damage, chest_trace_bullet_damage) and is_lethal then
            lethal = true
        elseif enemy_health > math.max(stomach_trace_bullet_damage, chest_trace_bullet_damage) and head_trace_bullet_damage >= enemy_health and is_lethal then
            lethal = false
        end

        plist.set(player, "Override prefer body aim", lethal and "Force" or '-')
        plist.set(player, "Override safe point", lethal and "On" or '-')
        client.update_player_list()
    end

    client.set_event_callback("run_command", prefer_baim.run_command)
    client.set_event_callback("shutdown", prefer_baim.shutdown)
end

emulatepred = function(cmd)
    local lp = entity.get_local_player()
    if not lp then return end
    local gun = entity.get_player_weapon(lp)
    local skeetweapon = ui.get(lua.refs.other.weapon_type)
    local classname = entity.get_classname(gun)
    if gun == nil then
        return
    end
    if table.contains(menu.aimbot.aimtools:get(), "Emulation of Predict") then
        cvar.sv_maxunlag:set_float(0.200)
        cvar.sv_max_allowed_net_graph:set_int(1)
        cvar.cl_interp:set_float(0.01)
        cvar.cl_interp_ratio:set_int(1)
        cvar.cl_interpolate:set_int(1)
        cvar.cl_predict:set_int(1)
        cvar.cl_updaterate:set_int(128)
        cvar.cl_cmdrate:set_int(128)
    
        if classname == "CWeaponSSG08" then
            cvar.cl_interp:set_float(0.03125)
        elseif classname == "CWeaponAWP" then
            cvar.cl_interp:set_float(0.4)
        elseif classname == "CWeaponSCAR20" or classname == "CWeaponG3SG1" then
            cvar.cl_interp:set_float(0.051000)
        elseif classname == "CDEagle" then
            cvar.cl_interp:set_float(0.020000)
        end
    else
        cvar.sv_maxunlag:set_float(0.200)
        cvar.sv_max_allowed_net_graph:set_int(1)
        cvar.cl_interp:set_float(0.015625)
        cvar.cl_interp_ratio:set_int(2)
        cvar.cl_interpolate:set_int(1)
        cvar.cl_predict:set_int(1)
    end
end

local hitgroup_names = { "generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "?", "gear" }

local vars = {
    shots = 0,
    hits = 0,
}

local last_shot_data = {
    vector = vector(0, 0, 0),
    damage = nil,
    hgroup = nil,
    bt = nil,
    lc = nil,
    dt = nil,
    tp = nil,
    simtime = nil,
}

local players_shift_data = { }

local gram_create = (function(value, count) local gram = { }; for i=1, count do gram[i] = value; end return gram; end)
local gram_update = (function(tab, value, forced) local new_tab = tab; if forced or new_tab[#new_tab] ~= value then table.insert(new_tab, value); table.remove(new_tab, 1); end; tab = new_tab; end)
local get_average = (function(tab) local elements, sum = 0, 0; for k, v in pairs(tab) do sum = sum + v; elements = elements + 1; end return sum / elements; end)

local GetNetChannelInfo = vtable_bind("engine.dll", "VEngineClient014", 78, "void* (__thiscall*)(void* ecx)")
local GetLatency = vtable_thunk(9, "float(__thiscall*)(void*, int)")

local function lerp_time()
    if cvar.cl_interpolate:get_int() > 0 then
        local ratio = cvar.cl_interp_ratio:get_float();

        if cvar.sv_client_max_interp_ratio and cvar.sv_client_min_interp_ratio then
            local min = cvar.sv_client_min_interp_ratio:get_float();
            local max = cvar.sv_client_max_interp_ratio:get_float();

            ratio = math.clamp(ratio, min, max);
        end

        local update_rate = cvar.cl_updaterate:get_float();

        if cvar.sv_maxupdaterate and cvar.sv_minupdaterate then
            local min = cvar.sv_minupdaterate:get_float();
            local max = cvar.sv_maxupdaterate:get_float();

            update_rate = math.clamp(update_rate, min, max);
        end

        local interp = cvar.cl_interp:get_float();
        local final_interp = ratio / update_rate;

        return interp > final_interp and interp or final_interp;
    end

    return 0;
end

local function is_tick_valid(simtime)
    local nci = GetNetChannelInfo();

    local correct = GetLatency(nci, 0) + lerp_time();

    local deltatime = correct - (globals.curtime() - simtime);

    if math.abs(deltatime) >= 0.2 then
        return false;
    end

    return true;
end

local function get_entities(enemy_only, alive_only)
    local enemy_only = enemy_only ~= nil and enemy_only or false
    local alive_only = alive_only ~= nil and alive_only or true

    local result = {}

    local me = entity.get_local_player()
    local player_resource = entity.get_player_resource()

    for player = 1, globals.maxplayers() do
        local is_enemy, is_alive = true, true

        if enemy_only and not entity.is_enemy(player) then is_enemy = false end
        if is_enemy then
            if alive_only and entity.get_prop(player_resource, 'm_bAlive', player) ~= 1 then is_alive = false end
            if is_alive then table.insert(result, player) end
        end
    end

    return result
end

client.set_event_callback("net_update_end", function()
    local players = get_entities(true, true)
    for k, player in pairs(players) do
        if (player == nil) then goto skip end

        if players_shift_data[player] == nil then
            players_shift_data[player] = {
                shift = 0,
                old_simtime = 0,
                old_origin = vector(0, 0, 0),
                teleport_data = gram_create(0, 3),
                teleport = 0,
            }
        end
    
        if entity.is_alive(player) and not entity.is_dormant(player) then
            local simtime = entity.get_prop(player, "m_flSimulationTime")
            local origin = vector(entity.get_origin(player))
            if simtime ~= players_shift_data[player].old_simtime then
                players_shift_data[player].shift = ((simtime/globals.tickinterval()) - globals.tickcount())*-1
                players_shift_data[player].old_simtime = simtime
    
                if (players_shift_data[player].old_origin ~= nil) then
                    players_shift_data[player].teleport = (origin-players_shift_data[player].old_origin):length2dsqr()
        
                    gram_update(players_shift_data[player].teleport_data, players_shift_data[player].teleport, true)
                end
    
                players_shift_data[player].old_origin = origin
            end
        end
        ::skip::
    end
end)

client.set_event_callback("aim_fire", function(e)
    if not  menu.misc.eventlog:get() then return end
    vars.shots = vars.shots + 1
    local player = e.target

    if players_shift_data[player] == nil then return end

    last_shot_data.vector = vector(e.x, e.y, e.z)
    last_shot_data.damage = e.damage
    last_shot_data.hgroup = e.hitgroup
    last_shot_data.bt = (globals.tickcount() - e.tick)
    last_shot_data.lc = e.teleported
    last_shot_data.dt = (players_shift_data[player].shift >= 1)
    last_shot_data.tp = ((get_average(players_shift_data[player].teleport_data) > 3200) and (players_shift_data[player].shift <= 0)) or ((get_average(players_shift_data[player].teleport_data) > 115) and (players_shift_data[player].shift >= 1))
    last_shot_data.simtime = entity.get_prop(player, "m_flSimulationTime")
end)

local multicolor_console = function(...)
    local texts = {...}
    for i=1, #texts do
        local text = texts[i]
        client.color_log(text[1], text[2], text[3], i ~= #texts and (text[4] .. '\0') or text[4])
    end
end
renderer_rec_out = function(x, y, width, height, color_r, color_g, color_b, alpha, radius, border_height)
    radius = math.min(width / 2, height / 2, radius)
    if radius == 1 then
        renderer.rectangle(x, y, width, border_height, color_r, color_g, color_b, alpha)
        renderer.rectangle(x, y + height - border_height, width, border_height, color_r, color_g, color_b, alpha)
    else
        renderer.rectangle(x + radius, y, width - radius * 2, border_height, color_r, color_g, color_b, alpha)
        renderer.rectangle(x + radius, y + height - border_height, width - radius * 2, border_height, color_r, color_g, color_b, alpha)
        renderer.rectangle(x, y + radius, border_height, height - radius * 2, color_r, color_g, color_b, alpha)
        renderer.rectangle(x + width - border_height, y + radius, border_height, height - radius * 2, color_r, color_g, color_b, alpha)
        renderer.circle_outline(x + radius, y + radius, color_r, color_g, color_b, alpha, radius, 180, .25, border_height)
        renderer.circle_outline(x + radius, y + height - radius, color_r, color_g, color_b, alpha, radius, 90, .25, border_height)
        renderer.circle_outline(x + width - radius, y + radius, color_r, color_g, color_b, alpha, radius, -90, .25, border_height)
        renderer.circle_outline(x + width - radius, y + height - radius, color_r, color_g, color_b, alpha, radius, 0, .25, border_height)
    end
end
renderer_rec = function(x, y, width, height, color_r, color_g, color_b, alpha, radius)
    radius = math.min(radius, width / 2, height / 2)
    renderer.rectangle(x, y + radius, width, height - radius * 2, color_r, color_g, color_b, alpha)
    renderer.rectangle(x + radius, y, width - radius * 2, radius, color_r, color_g, color_b, alpha)
    renderer.rectangle(x + radius, y + height - radius, width - radius * 2, radius, color_r, color_g, color_b, alpha)
    renderer.circle(x + radius, y + radius, color_r, color_g, color_b, alpha, radius, 180, .25)
    renderer.circle(x + width - radius, y + radius, color_r, color_g, color_b, alpha, radius, 90, .25)
    renderer.circle(x + width - radius, y + height - radius, color_r, color_g, color_b, alpha, radius, 0, .25)
    renderer.circle(x + radius, y + height - radius, color_r, color_g, color_b, alpha, radius, -90, .25)
end
renderer_glow = function(x, y, width, height, glow_steps, glow_intensity, color_r, color_g, color_b, alpha, outline_color_r, outline_color_g, outline_color_b, outline_alpha, draw_background)
    local offset = 1
    local step_size = 1

    if draw_background then
        renderer_rec(x, y, width, height, color_r, color_g, color_b, alpha, glow_intensity)
    end

    for step = 0, glow_steps do
        local glow_radius = (outline_alpha / 2) * (step / glow_steps) ^ 3
        renderer_rec_out(x + (step - glow_steps - step_size) * offset,y + (step - glow_steps - step_size) * offset,width - (step - glow_steps - step_size) * offset * 2,height - (step - glow_steps - step_size) * offset * 2,outline_color_r,outline_color_g,outline_color_b,glow_radius / 1.5,glow_intensity + offset * (glow_steps - step + step_size),offset
        )
    end
end


local logs = {}
renderer.notify = function(text, size)
    if entity.get_local_player() == nil or not entity.is_alive(entity.get_local_player()) then return end
    table.insert(logs, { text, 0, globals.curtime(), size })
end
local function notify_render()
    if #logs <= 0 then
        return
    end
    local offset, x, y = 0, screen.x / 2, screen.y / 1.3

    for idx = #logs, 1, -1 do
        local data = logs[idx]
        if not data then
            table.remove(logs, idx)
            goto continue
        end
        local time_alive = globals.curtime() - data[3]
        
        if time_alive < 4.0 and not (#logs > 5 and idx < #logs - 5) then
            data[2] = lerp(data[2], 255, 0.15)
        else
            data[2] = lerp(data[2], 0, 0.15)
        end
        local target_height = math.max(0, math.floor(22 * (1 - (time_alive / 4.15))))
        data.height = data.height or target_height
        data.height = lerp(data.height, target_height, 0.5)
        local time_alive = globals.curtime() - data[3]
        if time_alive < 4.0 then
            data[2] = math.min(data[2] + globals.absoluteframetime() * 1200, 255)
        else
            data[2] = math.max(data[2] - globals.absoluteframetime() * 1200, 0)
        end

        if data[2] <= 0 then
            table.remove(logs, idx)
            goto continue
        end
        local text_size_x, text_size_y = renderer.measure_text("", data[1])
        local r6, g6, b6, a6 = menu.visuals.stylelogs:get_color()

        local missed_color = {255, 54, 80}
        local default_color = {r6, g6, b6}

        if string.find(data[1], "Missed") then
            r6, g6, b6 = unpack(missed_color)
        else
            r6, g6, b6 = unpack(default_color)
        end

        local alpha = math.floor(data[2])
        local pulse = math.abs(math.sin(globals.realtime() * 2))
        local pulse2 = math.floor(205 * pulse) 
        local rect_x = x - 22 - text_size_x / 2
        local rect_y = y - offset - 5
        if menu.visuals.second_style_logs:get() == "Aviros" then
            if (menu.visuals.second_style_logs:get() == "Aviros") and string.find(data[1], "Missed") then
                renderer.text(rect_x + 2, rect_y + (text_size_y / 2) - 3, r6, g6, b6, data[2], "", 0, "⛺")
            else
                renderer.text(rect_x + 2, rect_y + (text_size_y / 2) - 3, r6, g6, b6, data[2], "", 0, "⛺")
            end
            renderer.rectangle(x - 7 - text_size_x / 2, y - offset - 6, text_size_x + 13, 24, r6, g6, b6, data[2] / 4)
            renderer.rectangle(x - 25 - text_size_x / 2, y - offset - 6, 3, data.height * (data[2] / 255) + 1, r6, g6, b6, data[2])
            -- renderer.rectangle(rect_x, rect_y, text_size_x + 11, 22, 0, 0, 0, alpha / 2)
            renderer.rectangle(x - 6 - text_size_x / 2, y - offset - 5, text_size_x + 11, 22, 15, 15, 15, data[2] / 2)
            renderer.rectangle(rect_x - 2, rect_y - 1, 18, text_size_y + 12, r6, g6, b6, alpha / 2)
        elseif menu.visuals.second_style_logs:get() == "Rounded" then
            -- renderer_glow(rect_x - 1, rect_y + 1, text_size_x + 31, 20, 15, 90, r6, g6, b6, alpha, r6, g6, b6, pulse2, 0)
            renderer_rec(rect_x - 3, rect_y, text_size_x + 35, 22, 10, 10, 10, alpha, 12, 1)
            renderer_rec_out(rect_x - 3, rect_y, text_size_x + 35, 22, r6, g6, b6, alpha / 2.5, 12, 1)
            if (menu.visuals.second_style_logs:get() == "Rounded") and string.find(data[1], "Missed") then
                renderer.text(rect_x + 5, rect_y + (text_size_y / 2) - 3, r6, g6, b6, data[2], "", 0, "⛺")
            else
                renderer.text(rect_x + 5, rect_y + (text_size_y / 2) - 3, r6, g6, b6, data[2], "", 0, "⛺")
            end
        end
        renderer.text(x - 1 - text_size_x / 2, y - offset - 1, 225, 225, 225, alpha, "", 0, data[1])

        offset = offset - 35 * (data[2] / 255)
        while #logs > 6 do
            table.remove(logs, 1)
        end
        ::continue::
    end
end

local check_miss = 0

local function adaptive_safe(e)
    -- print("adaptive_safe called with reason:", e.reason)
    local target_id = e.target
    local player_name = entity.get_player_name(target_id)
    
    if e.reason == "?" then
        check_miss = check_miss + 1
        -- print("check_miss incremented to:", check_miss)
        -- print("Missed shot at:", player_name)
    end
    
    if check_miss > 1 then
        plist.set(target_id, "Override safe point", "On")
        renderer.notify("Correction error: "..player_name.." force safety")
        -- print("safety")
    end
end

local function adaptive_safe_reset(e)
    -- print("adaptive_safe_reset called with reason:", e.reason)
    local target_id = e.target
    -- print("target_id:", target_id)
    local player_name = entity.get_player_name(target_id)

    if e.reason and e.reason ~= "?" then
        check_miss = 0
        -- print("check_miss reset to 0")
    end

    if target_id then
        plist.set(target_id, "Override safe point", "-")
        -- print("Override safe point set for target_id:", target_id)
    else
        -- print("target_id is nil, cannot set Override safe point")
    end
end


client.set_event_callback("aim_miss", adaptive_safe)
client.set_event_callback("aim_fire", adaptive_safe_reset)
client.set_event_callback('round_start', function()
    check_miss = 0
    -- print("check_miss reset on round start")
    if entity.get_local_player() == nil or not entity.is_alive(entity.get_local_player()) then return end
    if table.contains(menu.aimbot.aimtools:get(), "Correction helper") then
        renderer.notify("Correction has been reseted due to round restart")
    end
end)

local function rgba_to_hex(r, g, b, a)
    return string.format("%02x%02x%02x%02x", r, g, b, a);
end

client.set_event_callback("paint", function()
    notify_render()
    
end)

client.set_event_callback("aim_miss", function(e)
    local func = lua.ui.func
    if not  menu.misc.eventlog:get() then return end
    local player = e.target
    local id = e.id

    local name = entity.get_player_name(player)

    local wanted_damage = last_shot_data.damage
    local wanted_hgroup = hitgroup_names[last_shot_data.hgroup + 1]

    local bt_str = last_shot_data.bt < 0 and "pred: "..math.abs(last_shot_data.bt) or "history: "..math.abs(last_shot_data.bt)..""
    local simtime_not_valid = (is_tick_valid(last_shot_data.simtime) == false) and (last_shot_data.bt > 0)
    local is_lc = last_shot_data.lc
    local is_tp = last_shot_data.tp

    local is_x_discharge = last_shot_data.dt and (players_shift_data[player].shift <= 0) and (get_average(players_shift_data[player].teleport_data) > 100)
    local is_lagcomp_broke = last_shot_data.lc and (get_average(players_shift_data[player].teleport_data) > 100)

    local lc_error = is_x_discharge or is_lagcomp_broke or simtime_not_valid
    local lag_error = is_tp or ((get_average(players_shift_data[player].teleport_data) > 3200) and (players_shift_data[player].shift <= 0)) or ((get_average(players_shift_data[player].teleport_data) > 115) and (players_shift_data[player].shift >= 1))

    local flag_str = lc_error and (is_x_discharge and " flags : (tp)" or (is_lagcomp_broke and " flags : (lc)" or " flags : (bt)")) or (lag_error and ((players_shift_data[player].shift >= 1) and " flags : (dt)" or " flags : (fl)") or "")
    local r_color, g_color, b_color = menu.visuals.stylelogs:get_color()
    local hex_to_color = rgba_to_hex(255, 54, 80, 255)
    local reset_color = rgba_to_hex(200, 200, 200, 255)
    local draw_output = ui.reference("Misc", "Miscellaneous", "Draw console output")
    local reason = (lc_error and e.reason == "?") and "lagcompensation error" or ((lag_error and e.reason == "?") and "player lag" or ((e.reason == "?") and "correction failure" or e.reason))
    if e.reason == "unregistered shot" then
        renderer.notify("Missed shot due to unregistered shot")
    elseif e.reason == "death" then
        renderer.notify("Missed shot due to death")
    else
        -- client.log("Missed shot due to \ahex_color"..reason.." at "..name.."'s "..wanted_hgroup.." for "..wanted_damage.." damage ("..bt_str.."t)"..flag_str)
        if menu.visuals.stylelogs:get() == "All" then
            ui.set(draw_output, true)
            renderer.notify("\a"..hex_to_color.."Missed \a"..reset_color.."shot due to \a"..hex_to_color..reason.." \a"..reset_color.."at \a"..hex_to_color..name.."\a"..reset_color.."'s \a"..hex_to_color..wanted_hgroup.." \a"..reset_color.."for \a"..hex_to_color..wanted_damage.." \a"..reset_color.."damage")
            multicolor_console({r_color, g_color, b_color, "aviros » "}, 
            {255, 54, 80, "missed "}, 
            {r_color, g_color, b_color, "shot due to "}, 
            {255, 54, 80, reason}, 
            {r_color, g_color, b_color, " at "}, 
            {255, 54, 80, name},
            {r_color, g_color, b_color, " in "},
            {255, 54, 80, wanted_hgroup},
            {r_color, g_color, b_color, " for "},
            {255, 54, 80, wanted_damage},
            {r_color, g_color, b_color, " damage "},
            {255, 54, 80, bt_str},
            {r_color, g_color, b_color, " ticks"})
            if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
                -- -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
            end
        elseif menu.visuals.stylelogs:get() == "Centered" then
            ui.set(draw_output, false)
            -- renderer.notify("Missed shot due to "..reason.." at "..name.."'s "..wanted_hgroup.." for "..wanted_damage.." damage")
            renderer.notify("\a"..hex_to_color.."Missed \a"..reset_color.."shot due to \a"..hex_to_color..reason.." \a"..reset_color.."at \a"..hex_to_color..name.."\a"..reset_color.."'s \a"..hex_to_color..wanted_hgroup.." \a"..reset_color.."for \a"..hex_to_color..wanted_damage.." \a"..reset_color.."damage")

            multicolor_console({r_color, g_color, b_color, "aviros » "}, 
            {255, 54, 80, "missed "}, 
            {r_color, g_color, b_color, "shot due to "}, 
            {255, 54, 80, reason}, 
            {r_color, g_color, b_color, " at "}, 
            {255, 54, 80, name},
            {r_color, g_color, b_color, " in "},
            {255, 54, 80, wanted_hgroup},
            {r_color, g_color, b_color, " for "},
            {255, 54, 80, wanted_damage},
            {r_color, g_color, b_color, " damage "},
            {255, 54, 80, bt_str},
            {r_color, g_color, b_color, " ticks"})
            if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
                -- -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
            end
        elseif menu.visuals.stylelogs:get() == "Default" then
            ui.set(draw_output, true)
            -- renderer.notify("Missed shot due to "..reason.." at "..name.."'s "..wanted_hgroup.." for "..wanted_damage.." damage")
            -- renderer.notify("\a"..hex_to_color.."Missed \a"..reset_color.."shot due to \a"..hex_to_color..reason.." \a"..reset_color.."at \a"..hex_to_color..name.."\a"..reset_color.."'s \a"..hex_to_color..wanted_hgroup.." \a"..reset_color.."for \a"..hex_to_color..wanted_damage.." \a"..reset_color.."damage")
            multicolor_console({r_color, g_color, b_color, "aviros » "}, 
            {255, 54, 80, "missed "}, 
            {r_color, g_color, b_color, "shot due to "}, 
            {255, 54, 80, reason}, 
            {r_color, g_color, b_color, " at "}, 
            {255, 54, 80, name},
            {r_color, g_color, b_color, " in "},
            {255, 54, 80, wanted_hgroup},
            {r_color, g_color, b_color, " for "},
            {255, 54, 80, wanted_damage},
            {r_color, g_color, b_color, " damage "},
            {255, 54, 80, bt_str},
            {r_color, g_color, b_color, " ticks"})
            if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
                -- -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
            end
        end
    end
end)

client.set_event_callback("aim_hit", function(e)
    local func = lua.ui.func
    local id = e.id
    if not  menu.misc.eventlog:get() then return end
    vars.hits = vars.hits + 1
    local player = e.target
    local r_color, g_color, b_color = menu.visuals.stylelogs:get_color()

    local name = entity.get_player_name(player)

    local wanted_damage = last_shot_data.damage
    local wanted_hgroup = hitgroup_names[last_shot_data.hgroup + 1]

    local damage = e.damage
    local hgroup = hitgroup_names[e.hitgroup + 1]
    local draw_output = ui.reference("Misc", "Miscellaneous", "Draw console output")
    local bt_str = last_shot_data.bt < 0 and "pred: "..math.abs(last_shot_data.bt) or "history: "..math.abs(last_shot_data.bt)
    local is_lc = last_shot_data.lc
    local is_tp = last_shot_data.tp
    local hex_to_color = rgba_to_hex(r_color, g_color, b_color, 255)
    local reset_color = rgba_to_hex(200, 200, 200, 255)
    local mismatch_color = rgba_to_hex(255, 54, 80, 255)
    local is_x_discharge = last_shot_data.dt and (players_shift_data[player].shift <= 0) and (get_average(players_shift_data[player].teleport_data) > 100)
    local is_lagcomp_broke = last_shot_data.lc and (get_average(players_shift_data[player].teleport_data) > 100)

    local lag_error = is_tp or ((get_average(players_shift_data[player].teleport_data) > 3200) and (players_shift_data[player].shift <= 0)) or ((get_average(players_shift_data[player].teleport_data) > 115) and (players_shift_data[player].shift >= 1))

    local flag_str = is_x_discharge and " flags: (tp)" or (is_lagcomp_broke and " flags: (lc)" or (lag_error and ((players_shift_data[player].shift >= 1) and " flags: (dt)" or " flags: (fl)") or ""))

    -- renderer.notify("Shot fired at "..name.."'s in "..hgroup.."("..wanted_hgroup..") for "..damage.."("..wanted_damage..") damage ("..bt_str.."t)")

    if wanted_damage == damage and wanted_hgroup == hgroup and (menu.visuals.stylelogs:get() == "All") then
        ui.set(draw_output, true)
        renderer.notify("\a"..reset_color.."Shot fired at \a"..hex_to_color..name.."\a"..reset_color.."'s in \a"..hex_to_color..hgroup.." \a"..reset_color.."for \a"..hex_to_color..damage.." \a"..reset_color.."damage (\a"..hex_to_color..bt_str.." ticks\a"..reset_color..")")
        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, bt_str},
        {225, 225, 225, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
    elseif wanted_damage == damage and wanted_hgroup == hgroup and not menu.visuals.stylelogs:get() == "Centered" then
        ui.set(draw_output, false)
        renderer.notify("\a"..reset_color.."Shot fired at \a"..hex_to_color..name.."\a"..reset_color.."'s in \a"..hex_to_color..hgroup.." \a"..reset_color.."for \a"..hex_to_color..damage.." \a"..reset_color.."damage (\a"..hex_to_color..bt_str.." ticks\a"..reset_color..")")
        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, bt_str},
        {225, 225, 225, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
    elseif menu.visuals.stylelogs:get() == "All" then
        ui.set(draw_output, true)
        renderer.notify("\a"..reset_color.."Shot fired at \a"..hex_to_color..name.."\a"..reset_color.."'s in \a"..hex_to_color..hgroup.."\a"..reset_color.."(\a"..mismatch_color..wanted_hgroup.."\a"..reset_color..") \a"..reset_color.."for \a"..hex_to_color..damage.."\a"..reset_color.."(\a"..mismatch_color..wanted_damage.."\a"..reset_color..") \a"..reset_color.."damage (\a"..hex_to_color..bt_str.." ticks\a"..reset_color..")")

        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, " mismatch: "},
        {255, 54, 80, wanted_damage},
        {225, 225, 225, " damage / aimed: "},
        {255, 54, 80, wanted_hgroup.." "},
        {225, 225, 225, bt_str},
        {r_color, g_color, b_color, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
    elseif menu.visuals.stylelogs:get() == "Default" then
        ui.set(draw_output, true)
        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, " mismatch: "},
        {255, 54, 80, wanted_damage},
        {225, 225, 225, " damage / aimed: "},
        {255, 54, 80, wanted_hgroup.." "},
        {225, 225, 225, bt_str},
        {r_color, g_color, b_color, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
    elseif wanted_damage == damage and wanted_hgroup == hgroup and menu.visuals.stylelogs:get() == "Centered" then
        ui.set(draw_output, false)
        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, bt_str},
        {225, 225, 225, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
        renderer.notify("\a"..reset_color.."Shot fired at \a"..hex_to_color..name.."\a"..reset_color.."'s in \a"..hex_to_color..hgroup.." \a"..reset_color.."for \a"..hex_to_color..damage.." \a"..reset_color.."damage (\a"..hex_to_color..bt_str.." ticks\a"..reset_color..")")
    elseif menu.visuals.stylelogs:get() == "Centered" then
        ui.set(draw_output, false)
        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, " mismatch: "},
        {255, 54, 80, wanted_damage},
        {225, 225, 225, " damage / aimed: "},
        {255, 54, 80, wanted_hgroup.." "},
        {225, 225, 225, bt_str},
        {r_color, g_color, b_color, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
        renderer.notify("\a"..reset_color.."Shot fired at \a"..hex_to_color..name.."\a"..reset_color.."'s in \a"..hex_to_color..hgroup.."\a"..reset_color.."(\a"..mismatch_color..wanted_hgroup.."\a"..reset_color..") \a"..reset_color.."for \a"..hex_to_color..damage.."\a"..reset_color.."(\a"..mismatch_color..wanted_damage.."\a"..reset_color..") \a"..reset_color.."damage (\a"..hex_to_color..bt_str.." ticks\a"..reset_color..")")
    elseif wanted_damage == damage and wanted_hgroup == hgroup and (menu.visuals.stylelogs:get() == "All") then
        ui.set(draw_output, true)
        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, bt_str},
        {225, 225, 225, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
        renderer.notify("\a"..reset_color.."Shot fired at \a"..hex_to_color..name.."\a"..reset_color.."'s in \a"..hex_to_color..hgroup.." \a"..reset_color.."for \a"..hex_to_color..damage.." \a"..reset_color.."damage (\a"..hex_to_color..bt_str.." ticks\a"..reset_color..")")
    elseif (menu.visuals.stylelogs:get() == "All") then
        ui.set(draw_output, true)
        multicolor_console({r_color, g_color, b_color, "aviros » "}, 
        {225, 225, 225, "fired at "}, 
        {r_color, g_color, b_color, name}, 
        {225, 225, 225, " in "},
        {r_color, g_color, b_color, hgroup},
        {225, 225, 225, " for "},
        {r_color, g_color, b_color, damage},
        {225, 225, 225, " damage "},
        {r_color, g_color, b_color, " mismatch: "},
        {255, 54, 80, wanted_damage},
        {225, 225, 225, " damage / aimed: "},
        {255, 54, 80, wanted_hgroup.." "},
        {225, 225, 225, bt_str},
        {r_color, g_color, b_color, " ticks"})
        if table.contains(menu.aimbot.aimtools:get(), "Auto Enemy Correction") and menu.aimbot.aimtools_debuglog:get() then
            -- multicolor_console({r_color, g_color, b_color, "resolver_shot_logged: [angle: ".. math.floor(self.records_rm[player].angle).."° jitter: ".. math.floor(self.records_rm[player].jitter).."°]"})
        end
        renderer.notify("\a"..reset_color.."Shot fired at \a"..hex_to_color..name.."\a"..reset_color.."'s in \a"..hex_to_color..hgroup.."\a"..reset_color.."(\a"..mismatch_color..wanted_hgroup.."\a"..reset_color..") \a"..reset_color.."for \a"..hex_to_color..damage.."\a"..reset_color.."(\a"..mismatch_color..wanted_damage.."\a"..reset_color..") \a"..reset_color.."damage (\a"..hex_to_color..bt_str.." ticks\a"..reset_color..")")

        -- client.log("Shot fired at "..name.."'s in "..hgroup.." for "..damage.." damage / (mismatch: "..wanted_damage.." dmg aimed: "..wanted_hgroup..") ("..bt_str.."t)"..flag_str)
    end
end)

menu.misc.consolefilter:set_callback(function(self)
    if menu.misc.consolefilter:get() then
        cvar.developer:set_int(0)
        cvar.con_filter_enable:set_int(1)
        cvar.con_filter_text:set_string("IrWL5106TZZKNFPz4P4Gl3pSN?J370f5hi373ZjPg%VOVh6lN")
        client.exec("con_filter_enable 1")
    else
        cvar.con_filter_enable:set_int(0)
        cvar.con_filter_text:set_string("")
        client.exec("con_filter_enable 0")
    end
end)

client.set_event_callback("shutdown", function()
    cvar.con_filter_enable:set_int(0)
    cvar.con_filter_text:set_string("")
    client.exec("con_filter_enable 0")
end)



client.set_event_callback("setup_command", function( cmd )
    if not table.contains(menu.aimbot.aimtools:get(), "Backtrack Breaker") then
        return
    end

	local dt = ui.get(pui_musor_refs.dt[1]) and ui.get(pui_musor_refs.dt[2])

    if not dt then
        return
    end

    if is_can_emulate() then
        cmd.force_defensive = 1
    end
end)

get_doubletap_state = (function()
    if lua.refs.exploits.fd:get() then return false end
    if not ui.get(pui_musor_refs.dt[1]) and ui.get(pui_musor_refs.dt[2]) then return false end
    if not entity.is_alive(entity.get_local_player()) or entity.get_local_player() == nil then return end
    local weapon = entity.get_prop(entity.get_local_player(), "m_hActiveWeapon")
    if weapon == nil then return false end
    local next_attack = entity.get_prop(entity.get_local_player(), "m_flNextAttack") + 0.01
    local checkcheck = entity.get_prop(weapon, "m_flNextPrimaryAttack")
    if checkcheck == nil then return end
    local next_primary_attack = checkcheck + 0.01
    if next_attack == nil or next_primary_attack == nil then return false end
    return next_attack - globals.curtime() < 0.2 and next_primary_attack - globals.curtime() < 0
end)
function math.normalize_yaw(yaw)
    while yaw > 180 do
        yaw = yaw - 360
    end

    while yaw < -180 do
        yaw = yaw + 360
    end
    
    return yaw
end  

local function renderer_animtext(x, y, speed, color1, color2, text, flag)
    local final_text = ''
    local curtime = globals.curtime()
    if (menu.visuals.inds:get() == "Unselected") then
        for i = 0, #text do
            local x = i * 2
            local wave = math.cos(3 * speed * curtime + x / 15)
            local color = rgba_to_hex(
                lerp(color1.r, color2.r, math.clamp(wave, 0, 1)),
                lerp(color1.g, color2.g, math.clamp(wave, 0, 1)),
                lerp(color1.b, color2.b, math.clamp(wave, 0, 1)),
                color1.a
            ) 
            final_text = final_text .. '\a' .. color .. text:sub(i, i)
        end
    elseif (menu.visuals.inds:get() == "Aviros [1]") then
        for i = 0, #text do
            local x = i * 10
            local wave = math.cos(4 * speed * curtime + x / 20)
            local color = rgba_to_hex(
                lerp(color1.r, color2.r, math.clamp(wave, 0, 1)),
                lerp(color1.g, color2.g, math.clamp(wave, 0, 1)),
                lerp(color1.b, color2.b, math.clamp(wave, 0, 1)),
                color1.a
            ) 
            final_text = final_text .. '\a' .. color .. text:sub(i, i) 
        end
    elseif (menu.visuals.inds:get() == "Aviros [2]") or (menu.visuals.inds:get() == "Aviros [3]") then
        for i = 0, #text do
            local x = i * 10
            local wave = math.cos(4 * speed * curtime + x / 20)
            local color = rgba_to_hex(
                lerp(color1.r, color2.r, math.clamp(wave, 0, 1)),
                lerp(color1.g, color2.g, math.clamp(wave, 0, 1)),
                lerp(color1.b, color2.b, math.clamp(wave, 0, 1)),
                color1.a
            ) 
            final_text = final_text .. '\a' .. color .. text:sub(i, i) 
        end
    elseif (menu.visuals.inds:get() == "Aviros [old]") then
        for i = 0, #text do
            local x = i * 1
            local wave = math.cos(2 * speed * curtime + x / 3)
            local color = rgba_to_hex(
                lerp(color1.r, color2.r, math.clamp(wave, 0, 1)),
                lerp(color1.g, color2.g, math.clamp(wave, 0, 1)),
                lerp(color1.b, color2.b, math.clamp(wave, 0, 1)),
                color1.a
            ) 
            final_text = final_text .. '\a' .. color .. text:sub(i, i) 
        end
    end
    
    renderer.text(x, y, color1.r, color1.g, color1.b, color1.a, flag, nil, final_text)
end

local function get_body_yaw(animstate)
    return math.normalize_yaw(animstate.eye_angles_y - animstate.goal_feet_yaw)
end
local anim_lerp = 0
myObject:get_states()
local anim_bind_lerp_emulate = 0
local anim_bind_lerp_dt = 0
local anim_bind_lerp_dt_with_charge = 0
local anim_bind_lerp_osaa = 0
local anim_bind_lerp_baim = 0
local anim_bind_lerp_freestand = 0
local anim_bind_lerp_forcesafe = 0

paint_indicator = (function()
    local x_pos, y_pos = client.screen_size()
    local doubletap_ref = ui.get(pui_musor_refs.dt[1]) and ui.get(pui_musor_refs.dt[2])
    local dt_state = get_doubletap_state()
    local osaa_ref = lua.refs.exploits.hs.value and lua.refs.exploits.hs.hotkey:get()
    local fs_ref = lua.refs.aa.fs:get()
    local fsb_ref = lua.refs.rage.forcebodyaim:get()
    local fsf_ref = lua.refs.rage.forcesafepoint:get()
    local side_value = lua.refs.aa.byaw[2]:get()
    local side_text = (side_value == -1) and "LEFT" or (side_value == 1) and "RIGHT" or (side_value == 0) and "SAFE" or tostring(side_value)
    local side_text2 = (side_value == -1) and "L-" or (side_value == 1) and " -R" or tostring(side_value)
    local player = entity.get_local_player()
    if player == nil then return end

    local my_data = c_entity(player)
    if my_data == nil then return end

    local animstate = c_entity.get_anim_state(my_data);
    if animstate == nil then return end
    
    local body_yaw = math.clamp(math.abs(math.floor(get_body_yaw(animstate))), 20, 58)
    local player = entity.get_local_player()
    local pulse = math.abs(math.sin(globals.realtime() * 2))
    local alpha = math.floor(205 * pulse) 
    local semi_alpha = math.floor(255 * pulse) 
    local states = MyNewClass:get_states()
    local inds_offset = menu.visuals.inds_offset:get()
    local username = panorama.open("CSGOHud").MyPersonaAPI.GetName()
    local username_width = renderer.measure_text(nil, username)
    local arrows_offset = menu.visuals.arrows_offset:get()
    local get_scope = entity.get_prop(player, "m_bIsScoped") == 1
    local measure_dt_x = renderer.measure_text("-c", "DT")
    local measure_os_x = renderer.measure_text("-c", "OS")
    local measure_fs_x = renderer.measure_text("-c", "FS")
    local accent_r, accent_g, accent_b, accent_a = menu.visuals.inds:get_color()
    local global_a = 105
    local r2, g2, b2, a2 = accent_r, accent_g, accent_b, accent_a
    if doubletap_ref then
        r2, g2, b2, a2 = 255, 0, 0, 255
        if dt_state then
            r2, g2, b2, a2 = accent_r, accent_g, accent_b, accent_a
        end
    else
        r2, g2, b2, a2 = accent_r, accent_g, accent_b, alpha
    end
    anim_bind_lerp_emulate = lerp(anim_bind_lerp_emulate, is_can_emulate() and 1 or 0, 20 * globals.absoluteframetime())
    anim_bind_lerp_dt = lerp(anim_bind_lerp_dt, doubletap_ref and 1 or 0, 20 * globals.absoluteframetime())
    anim_bind_lerp_dt_with_charge = lerp(anim_bind_lerp_dt_with_charge, dt_state and 1 or 0, 20 * globals.absoluteframetime())
    anim_bind_lerp_osaa = lerp(anim_bind_lerp_osaa, osaa_ref and not doubletap_ref and 1 or 0, 20 * globals.absoluteframetime())
    anim_bind_lerp_baim = lerp(anim_bind_lerp_baim, fsb_ref and 1 or 0, 20 * globals.absoluteframetime())
    anim_bind_lerp_forcesafe = lerp(anim_bind_lerp_forcesafe, fsf_ref and 1 or 0, 20 * globals.absoluteframetime())
    anim_bind_lerp_freestand = lerp(anim_bind_lerp_freestand, fs_ref and 1 or 0, 20 * globals.absoluteframetime())
    anim_lerp = lerp(anim_lerp, get_scope and 1 or 0, 8 * globals.absoluteframetime())
    anim_lerp = math.clamp(anim_lerp, 0, 1)
    
    if entity.get_local_player() == nil or not entity.is_alive(entity.get_local_player()) then return end

    local position = vector((x_pos * 0.5) + math.floor(anim_lerp * 30), y_pos * 0.5 + 35 + inds_offset)
    if (menu.visuals.inds:get() == "Unselected") then
        renderer_animtext(x_pos/2 - 930 + username_width, y_pos/2 - 35 + inds_offset, 1, {r=25, g=25, b=25, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, "Aviros Alpha ~ "..username, "cdb")
    end
    if (menu.visuals.inds:get() == "Aviros [1]") then
        renderer.text(x_pos/2 + 30 + arrows_offset, y_pos/2 - 16 , 255, 255, 255, 55, "b+", 0, ">")
        renderer.text(x_pos/2 - 40 - arrows_offset, y_pos/2 - 16, 255, 255, 255, 55, "b+", 0, "<")
        if not (ui.get(lua.refs.other.damageoverride[1] and lua.refs.other.damageoverride[2])) then
            renderer.text(x_pos/2 + 15, y_pos/2 - 25, 255, 255, 255, 255, nil, 0, tostring(lua.refs.other.damage:get()))
        else
            renderer.text(x_pos/2 + 15, y_pos/2 - 25, 255, 255, 255, 255, nil, 0, tostring(ui.get(lua.refs.other.damageoverride[3])))
        end

        if yaw == -90 then 
            renderer.text(x_pos/2 - 40 - arrows_offset, y_pos/2 - 16, accent_r, accent_g, accent_b, accent_a, "b+", 0, "<")
        elseif yaw == 90 then
            renderer.text(x_pos/2 + 30 + arrows_offset, y_pos/2 - 16, accent_r, accent_g, accent_b, accent_a, "b+", 0, ">")
        end
        renderer_animtext(position.x, y_pos/2 + 25 + inds_offset, 1, {r=75, g=75, b=75, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, "aviros", "cdb")
        if not menu.antiaim.legit_antiaim:get() then
            renderer_animtext(position.x - 2, y_pos/2 + 15 + inds_offset, 1, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, {r=85, g=85, b=85, a=15}, side_text2, "-c")
        else
            renderer_animtext(position.x, y_pos/2 + 15 + inds_offset, 1, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, {r=85, g=85, b=85, a=15}, "LEGIT", "-c")
        end
        if is_can_emulate() and doubletap_ref then
            renderer_animtext(position.x, y_pos/2 + 15 + inds_offset, 1, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, {r=85, g=85, b=85, a=15}, "SETUP", "-c")
        end

        renderer.gradient(position.x + 1, position.y - 1, math.floor(29 * (body_yaw / 58)), 2, accent_r, accent_g, accent_b, accent_a, accent_r, accent_g, accent_b, alpha / 2, true)
        renderer.gradient(position.x + 1, position.y - 1, -math.floor(28 * (body_yaw / 58)), 2, accent_r, accent_g, accent_b, accent_a, accent_r, accent_g, accent_b, alpha / 2, true)

        renderer.text(position.x, y_pos/2 + 45 + inds_offset, accent_r, accent_g, accent_b, accent_a, "-c", 0, "*"..lua.vars.state_list[states]:upper().."*")
        renderer.text(position.x - (measure_dt_x + measure_dt_x * 0.5 + 5), y_pos/2 + 53 + inds_offset, r2, g2, b2, a2, "-", 0, "DT")

        renderer.text(position.x + (measure_os_x * 0.5 - measure_dt_x + measure_os_x * 0.5 - 6), y_pos/2 + 53 + inds_offset, accent_r, accent_g, accent_b, osaa_ref and 255 or alpha, "-", 0, "OS")
        renderer.text(position.x + (measure_os_x + measure_dt_x - measure_fs_x), y_pos/2 + 53 + inds_offset, accent_r, accent_g, accent_b, fs_ref and 255 or alpha, "-", 0 , "FS")
    end

    if (menu.visuals.inds:get() == "Aviros [2]") then
        if entity.get_local_player() == nil or not entity.is_alive(entity.get_local_player()) then return end
        -- renderer.text(x_pos/2 - 40 - arrows_offset, y_pos/2 - 16, 225, 225, 225, alpha / 4, "b+", 0, "⯇")
        -- renderer.text(x_pos/2 + 21 + arrows_offset, y_pos/2 - 16, 225, 225, 225, alpha / 4, "b+", 0, "⯈")
        -- renderer_animtext(x_pos/2 - 40 - arrows_offset, y_pos/2 - 16, 1, {r=75, g=75, b=75, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, "<", "b+")
        -- renderer_animtext(x_pos/2 + 21 + arrows_offset, y_pos/2 - 16, 1, {r=75, g=75, b=75, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, ">", "b+")

        if not (ui.get(lua.refs.other.damageoverride[1] and lua.refs.other.damageoverride[2])) then
            renderer.text(x_pos/2 + 15, y_pos/2 - 25, 255, 255, 255, 255, nil, 0, tostring(lua.refs.other.damage:get()))
        else
            renderer.text(x_pos/2 + 15, y_pos/2 - 25, 255, 255, 255, 255, nil, 0, tostring(ui.get(lua.refs.other.damageoverride[3])))
        end

        if yaw == -90 then 
            renderer_animtext(x_pos/2 - 40 - arrows_offset, y_pos/2 - 16, 1, {r=120, g=120, b=120, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, "<", "b+")
            renderer_animtext(x_pos/2 + 30 + arrows_offset, y_pos/2 - 16, 1, {r=100, g=100, b=100, a=semi_alpha/2}, {r=80, g=80, b=80, a=255}, ">", "b+")
            -- renderer.text(x_pos/2 - 40 - arrows_offset, y_pos/2 - 16, accent_r, accent_g, accent_b, accent_a, "b+", 0, "⯇")
        elseif yaw == 90 then
            renderer_animtext(x_pos/2 + 30 + arrows_offset, y_pos/2 - 16, 1, {r=120, g=120, b=120, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, ">", "b+")
            renderer_animtext(x_pos/2 - 40 - arrows_offset, y_pos/2 - 16, 1, {r=100, g=100, b=100, a=semi_alpha/2}, {r=80, g=80, b=80, a=255}, "<", "b+")

            -- renderer.text(x_pos/2 + 21 + arrows_offset, y_pos/2 - 16, accent_r, accent_g, accent_b, accent_a, "b+", 0, "⯈")
        end
        renderer_animtext(position.x, y_pos/2 + 15 + inds_offset, 1, {r=accent_r, g=accent_g, b=accent_b, a=alpha}, {r=55, g=55, b=55, a=15}, "ALPHA", "-c")
        
        renderer_animtext(position.x, y_pos/2 + 25 + inds_offset, 1, {r=75, g=75, b=75, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, "aviros", "cdb")
        if anim_bind_lerp_emulate > 0 and doubletap_ref then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 25 + 6), y_pos/2 + 30 + inds_offset, 255, 255, 255, alpha * anim_bind_lerp_emulate, "-с", 0, "EMULATE")
            y_pos = y_pos + (15 * anim_bind_lerp_emulate)
        end
        if doubletap_ref then
            anim_bind_lerp_dt = lerp(anim_bind_lerp_dt, 1, 20 * globals.absoluteframetime())
        else
            anim_bind_lerp_dt = lerp(anim_bind_lerp_dt, 0, 20 * globals.absoluteframetime())
        end
        
        if anim_bind_lerp_dt < 1e-1 then
            anim_bind_lerp_dt = 0
        end

        if anim_bind_lerp_dt > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 25 - 2), y_pos / 2 + 32 + inds_offset, 55, 55, 55, accent_a * anim_bind_lerp_dt, "-с", 0, "DT")
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 25 - 2), y_pos / 2 + 32 + inds_offset, accent_r, accent_g, accent_b, accent_a * anim_bind_lerp_dt_with_charge, "-с", 0, "DT")
            renderer.circle_outline(position.x - (measure_dt_x + measure_dt_x / 25 - 17), y_pos / 2 + 38 + inds_offset, accent_r, accent_g, accent_b, accent_a * anim_bind_lerp_dt, 3, 1, 1 * anim_bind_lerp_dt_with_charge, 1)
            y_pos = y_pos + (15 * anim_bind_lerp_dt)
        end
        if anim_bind_lerp_osaa > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 25 ), y_pos/2 + 32 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_osaa, "-с", 0, "OSAA")
            y_pos = y_pos + (15 * anim_bind_lerp_osaa)
        end
        if anim_bind_lerp_baim > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 25 - 1 ), y_pos/2 + 34 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_baim, "-с", 0, "BAIM")
            y_pos = y_pos + (15 * anim_bind_lerp_baim)
        end
        if anim_bind_lerp_forcesafe > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 25 - 1 ), y_pos/2 + 34 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_forcesafe, "-с", 0, "SAFE")
            y_pos = y_pos + (15 * anim_bind_lerp_forcesafe)
        end
        if anim_bind_lerp_freestand > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 25 - 5 ), y_pos/2 + 34 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_freestand, "-с", 0, "FS")
            y_pos = y_pos + (15 * anim_bind_lerp_freestand)
        end
    end
    if (menu.visuals.inds:get() == "Aviros [3]") then
        if entity.get_local_player() == nil or not entity.is_alive(entity.get_local_player()) then return end
        renderer.text(position.x - 13, y_pos/2 + 15 + inds_offset, accent_r, accent_g, accent_b, 255, "-c", 0, "AVIROS")
        renderer.text(position.x + 13, y_pos/2 + 15 + inds_offset, accent_r, accent_g, accent_b, alpha / 2, "-c", 0, "ALPHA")
        renderer.text(position.x, y_pos/2 + 25 + inds_offset, accent_r, accent_g, accent_b, 225, "-c", 0, "*"..lua.vars.state_list[states]:upper().."*")
        if anim_bind_lerp_dt < 1e-1 then
            anim_bind_lerp_dt = 0
        end

        if anim_bind_lerp_dt > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 2 - 9), y_pos / 2 + 30 + inds_offset, 55, 55, 55, accent_a * anim_bind_lerp_dt, "-с", 0, "DT")
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 2 - 9), y_pos / 2 + 30 + inds_offset, accent_r, accent_g, accent_b, accent_a * anim_bind_lerp_dt_with_charge * anim_bind_lerp_dt, "-с", 0, "DT")
            y_pos = y_pos + (18 * anim_bind_lerp_dt)
        end
        if anim_bind_lerp_osaa > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 2 - 4), y_pos/2 + 30 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_osaa, "-с", 0, "OSAA")
            y_pos = y_pos + (18 * anim_bind_lerp_osaa)
        end
        if anim_bind_lerp_baim > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 2 - 5 ), y_pos/2 + 30 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_baim, "-с", 0, "BAIM")
            y_pos = y_pos + (15 * anim_bind_lerp_baim)
        end
        if anim_bind_lerp_forcesafe > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 2 - 5 ), y_pos/2 + 30 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_forcesafe, "-с", 0, "SAFE")
            y_pos = y_pos + (15 * anim_bind_lerp_forcesafe)
        end
        if anim_bind_lerp_freestand > 0 then
            renderer.text(position.x - (measure_dt_x + measure_dt_x / 2 - 9 ), y_pos/2 + 30 + inds_offset, accent_r, accent_g, accent_b, 255 * anim_bind_lerp_freestand, "-с", 0, "FS")
            y_pos = y_pos + (18 * anim_bind_lerp_freestand)
        end
    
    end

    if (menu.visuals.inds:get() == "Aviros [old]") then
        renderer_animtext(x_pos/2, y_pos/2 + 500 + inds_offset, 1, {r=25, g=25, b=25, a=255}, {r=accent_r, g=accent_g, b=accent_b, a=accent_a}, "aviros alpha", "cdb")
        if not (ui.get(lua.refs.other.damageoverride[1] and lua.refs.other.damageoverride[2])) then
            renderer.text(x_pos/2 + 15, y_pos/2 - 25, 255, 255, 255, 255, nil, 0, tostring(lua.refs.other.damage:get()))
        else
            renderer.text(x_pos/2 + 15, y_pos/2 - 25, 255, 255, 255, 255, nil, 0, tostring(ui.get(lua.refs.other.damageoverride[3])))
        end
        renderer.text(x_pos/2 + 25 + arrows_offset, y_pos/2 - 16, 255, 255, 255, accent_a / 1.5, "b+", 0, ">")
        renderer.text(x_pos/2 - 35 - arrows_offset, y_pos/2 - 16, 255, 255, 255, accent_a / 1.5, "b+", 0, "<")
        renderer.text(x_pos/2, y_pos/2 + 25 + arrows_offset, 255, 255, 255, accent_a / 1.5, "cb+", 0, "v")

        if yaw == -90 then 
            renderer.text(x_pos/2 - 35 - arrows_offset, y_pos/2 - 16, accent_r, accent_g, accent_b, 255, "b+", 0, "<")
        elseif yaw == 90 then
            renderer.text(x_pos/2 + 25 + arrows_offset, y_pos/2 - 16, accent_r, accent_g, accent_b, 255, "b+", 0, ">")
        else
            renderer.text(x_pos/2, y_pos/2 + 25 + arrows_offset, accent_r, accent_g, accent_b, 255, "cb+", 0, "v")
        end

    end
end)
client.set_event_callback("paint", paint_indicator)

client.set_event_callback("setup_command", function(cmd)
    emulatepred()
end)

client.set_event_callback("setup_command", function(cmd)
    local g = setup_command.core
    for k, v in pairs(g.callbacks) do
        v(g, cmd)
    end
end)

local paint_ui = new_class()
paint_ui:struct("core", helpers.core)({
    handle_menu = (function(self)
        for k, v in pairs(lua.refs.aa) do
            if not v.type then
                for a, b in pairs(v) do
                    b:set_visible(false)
                end
            else
                v:set_visible(false)
            end
        end

        for k, v in pairs(lua.refs.fakelag) do
            if not v.type then
                for a, b in pairs(v) do
                    b:set_visible(false)
                end
            else
                v:set_visible(false)
            end
        end

        lua.refs.other.hide_shots:set_visible(menu.home.sub_tab:get() == 'Other')
        lua.refs.other.sw:set_visible(menu.home.sub_tab:get() == 'Other')
        lua.refs.other.fake_peek:set_visible(false)
        lua.refs.other.leg_movement:set_visible(menu.home.sub_tab:get() == 'Other')
    end),
}, {"handle_menu"})

client.set_event_callback("paint_ui", function()
    local g = paint_ui.core
    for k, v in pairs(g.callbacks) do
        v(g)
    end
end)

local shutdown = new_class()
shutdown:struct("core", helpers.core)({
    handle_menu = (function(self)
        for k, v in pairs(lua.refs.aa) do
            if not v.type then
                for a, b in pairs(v) do
                    b:set_visible(true)
                end
            else
                v:set_visible(true)
            end
        end

        for k, v in pairs(lua.refs.fakelag) do
            if not v.type then
                for a, b in pairs(v) do
                    b:set_visible(true)
                end
            else
                v:set_visible(true)
            end
        end

        lua.refs.other.fake_peek:set_visible(true)
        lua.refs.other.leg_movement:set_visible(true)
    end),
}, {"handle_menu"})

client.set_event_callback("shutdown", function()
    local g = shutdown.core
    for k, v in pairs(g.callbacks) do
        v(g)
    end
end)
