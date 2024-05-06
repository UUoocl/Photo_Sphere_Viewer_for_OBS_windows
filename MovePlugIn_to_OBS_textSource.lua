--[[
      OBS Studio Lua script : Get USB Camera PTZ values from the Move Plugin Filter
      Author: Jonathan Wood
      Version: 0.1
      Released: 2024-05-05
      references: https://obsproject.com/forum/resources/hotkeyrotate.723/, https://obsproject.com/forum/threads/command-runner.127662/
      https://github.com/jtfrey/uvc-util
--]]

local obs = obslua
local ffi = require("ffi")
local obsffi

local ptz_source_name = ""
local text_source = ""
local interval

local cur_settings
local prev_settings

local hotkeys = {
    {id = "START_uvcUtil", description = "Start getting Camera 1 USB PTZ values", HK = '{"START_uvcUtil": [ { "key": "OBS_KEY_F1", "control": false, "alt": false, "shift": false, "command": true } ]}'},
	{id = "STOP_uvcUtil", description = "Stop getting Camera 1 USB PTZ values", HK = '{"STOP_uvcUtil": [ { "key": "OBS_KEY_F1", "control": false, "alt": false, "shift": false, "command": false  } ]}'},
}

ffi.cdef[[

struct obs_source;
struct obs_properties;
struct obs_property;
struct obs_data;
typedef struct obs_source obs_source_t;
typedef struct obs_properties obs_properties_t;
typedef struct obs_property obs_property_t;
typedef struct obs_data obs_data_t;

obs_source_t *obs_get_source_by_name(const char *name);
obs_source_t *obs_source_get_filter_by_name(obs_source_t *source, const char *name);
obs_properties_t *obs_source_properties(const obs_source_t *source);
obs_property_t *obs_properties_first(obs_properties_t *props);
bool obs_property_next(obs_property_t **p);
const char *obs_property_name(obs_property_t *p);
void obs_properties_destroy(obs_properties_t *props);
void obs_source_release(obs_source_t *source);
bool obs_property_button_clicked(obs_property_t *p, void *obj);
obs_data_t *obs_source_get_settings(const obs_source_t *source);
const char *obs_data_get_json(obs_data_t *data);

]]

    obsffi = ffi.load("obs")

local function getPTZdata()
    local source = obsffi.obs_get_source_by_name(ptz_source_name)
    if source then
        local fSource = obsffi.obs_source_get_filter_by_name(source, "mVideo")
        if fSource then
            local props = obsffi.obs_source_properties(fSource)
            if props then
                local prop = obsffi.obs_properties_first(props)
                local name = obsffi.obs_property_name(prop)
                if name then
                    local propCount = 1
                    --obs.script_log(obs.LOG_INFO, string.format("Property 1 = %s", ffi.string(name)))
                    local _p = ffi.new("obs_property_t *[1]", prop)
                    local foundProp = obsffi.obs_property_next(_p)
                    prop = ffi.new("obs_property_t *", _p[0])
                    while foundProp do
                        propCount = propCount + 1
                        name = obsffi.obs_property_name(prop)

                        if ffi.string(name) == "value_get" then
                            --obs.script_log(obs.LOG_INFO, string.format("Property %d = %s", propCount, ffi.string(name)))
                            obsffi.obs_property_button_clicked(prop, fSource)
                            cur_settings = obsffi.obs_source_get_settings(fSource)
                            --print(ffi.string(obsffi.obs_data_get_json(cur_settings)))
                            set_source_text()
                        end     
                        _p = ffi.new("obs_property_t *[1]", prop)
                        foundProp = obsffi.obs_property_next(_p)
                        prop = ffi.new("obs_property_t *", _p[0])
                    end
                end
                obsffi.obs_properties_destroy(props)
            end
            obsffi.obs_source_release(fSource)
        end
        obsffi.obs_source_release(source)
    end
end

function set_source_text()
    if ffi.string(obsffi.obs_data_get_json(cur_settings)) ~= prev_settings then
        local source = obs.obs_get_source_by_name(text_source)
        if source ~= nil then
            local settings = obs.obs_data_create()
            obs.obs_data_set_string(settings, "text", ffi.string(obsffi.obs_data_get_json(cur_settings)))
            obs.obs_source_update(source, settings)
            obs.obs_data_release(settings)
            obs.obs_source_release(source)
            prev_settings = ffi.string(obsffi.obs_data_get_json(cur_settings))
            --print("text source" .. ffi.string(obsffi.obs_data_get_json(cur_settings))) 
        end
    end
end

obs.timer_add(getPTZdata, interval);


----------------------------------------------------------
-- Script start up
----------------

function script_load(settings)
    obs.script_log(obs.LOG_INFO, OBS_KEY_2)
    --load hotkeys
	for _, v in pairs(hotkeys) do
        jsonHK = obs.obs_data_create_from_json(v.HK)
		hk = obs.obs_hotkey_register_frontend(v.id, v.description, function(pressed) if pressed then onHotKey(v.id) end end)
		local hotkeyArray = obs.obs_data_get_array(jsonHK, v.id)
		obs.obs_hotkey_load(hk, hotkeyArray)
		obs.obs_data_array_release(hotkeyArray)
        obs.obs_data_release(jsonHK)
	end
end

-- called when settings changed
function script_update(settings)
    ptz_source_name = obs.obs_data_get_string(settings, "ptz_source_name")
    text_source = obs.obs_data_get_string(settings, "text_source") 
	interval = obs.obs_data_get_int(settings, "interval")
end

-- return description shown to user
function script_description()
	return "Create a Video Capture Source and add a 'Move Video Capture Filter'. \n Rename the filter to 'mVideo' \n Create a Text Source to store the PTZ data."
end

-- define properties that user can change
function script_properties()
	local props = obs.obs_properties_create()
    --list of video sources
    obs.obs_properties_add_text(props, "ptz_source_name", "Name of PTZ video source", obs.OBS_TEXT_DEFAULT)
    --list of text sources
    local property_list = obs.obs_properties_add_list(props, "text_source", "Select a Text Source to store PTZ values", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
            source_id = obs.obs_source_get_id(source)
            --print(source_id)
			if source_id == "text_gdiplus" or source_id == "text_ft2_source" or source_id == "text_ft2_source_v2" or source_id == "text_gdiplus_v2" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(property_list, name, name)
			end
		end
	end
	obs.source_list_release(sources)

    --refresh interval
	obs.obs_properties_add_int(props, "interval", "Refresh Interval (ms)", 2, 1000, 1)
	--debug option
    --obs.obs_properties_add_bool(props, "debug", "Debug")
	return props
end

function script_defaults(settings)    
    obs.obs_data_set_default_string(settings, "ptz_source_name", "PTZcamera")
    obs.obs_data_set_default_string(settings, "source", "PTZdata")
	obs.obs_data_set_default_int(settings, "interval", 1000)
end