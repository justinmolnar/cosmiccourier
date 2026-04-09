-- data/dispatch_actions.lua
local E = require("services.DispatchEvaluators")

-- Schema:
-- id: unique string
-- fn: function(block, ctx) -> nil or "claimed" or "skipped" or "cancel" or "stop_all"
-- params: list of { key="name", type="number"|"string"|"enum"|"reporter", default=value, options={"a","b"} }
-- tags: list of strings for palette filtering

return {
    -- Trip mutation
    { id = "set_payout",       fn = E.set_payout,       params = { { key="value",  type="reporter", default=100 } }, tags = {"trip"} },
    { id = "add_bonus",        fn = E.add_bonus,        params = { { key="amount", type="reporter", default=50 } },  tags = {"trip"} },
    { id = "cancel_trip",      fn = E.cancel_trip,      params = {},                                     tags = {"trip"} },

    -- Economy
    { id = "add_money",        fn = E.add_money,        params = { { key="amount", type="reporter", default=100 } }, tags = {"game"} },
    { id = "subtract_money",   fn = E.subtract_money,   params = { { key="amount", type="reporter", default=100 } }, tags = {"game"} },

    -- Rush Hour
    { id = "trigger_rush_hour",fn = E.trigger_rush_hour,params = { { key="duration", type="reporter", default=30 } }, tags = {"game"} },
    { id = "end_rush_hour",    fn = E.end_rush_hour,    params = {},                                     tags = {"game"} },

    -- Trip Generation
    { id = "pause_trip_gen",   fn = E.pause_trip_gen,   params = {},                                     tags = {"game"} },
    { id = "resume_trip_gen",  fn = E.resume_trip_gen,  params = {},                                     tags = {"game"} },
    { id = "set_trip_gen_rate",fn = E.set_trip_gen_rate,params = { { key="multiplier", type="reporter", default=1.0 } }, tags = {"game"} },

    -- Queue Management
    { id = "prioritize_trip",  fn = E.prioritize_trip,  params = {},                                     tags = {"game"} },
    { id = "deprioritize_trip",fn = E.deprioritize_trip,params = {},                                     tags = {"game"} },
    { id = "sort_queue",       fn = E.sort_queue,       params = { { key="metric", type="enum", options={"payout","wait","bonus","scope","cargo"} } }, tags = {"game"} },
    { id = "cancel_all_scope", fn = E.cancel_all_scope, params = { { key="scope",  type="enum", options={"district","neighborhood","city"} } }, tags = {"game"} },
    { id = "cancel_all_wait",  fn = E.cancel_all_wait,  params = { { key="seconds",type="reporter", default=60 } }, tags = {"game"} },

    -- Counters & Flags
    { id = "counter_inc",      fn = E.counter_inc,      params = { { key="var", type="string", default="counter1" }, { key="amount", type="reporter", default=1 } }, tags = {"counter"} },
    { id = "counter_dec",      fn = E.counter_dec,      params = { { key="var", type="string", default="counter1" }, { key="amount", type="reporter", default=1 } }, tags = {"counter"} },
    { id = "counter_set",      fn = E.counter_set,      params = { { key="var", type="string", default="counter1" }, { key="value",  type="reporter", default=0 } }, tags = {"counter"} },
    { id = "counter_reset",    fn = E.counter_reset,    params = { { key="var", type="string", default="counter1" } }, tags = {"counter"} },
    { id = "reset_all_counters",fn = E.reset_all_counters,params = {},                                   tags = {"counter"} },
    { id = "set_flag",         fn = E.set_flag,         params = { { key="var", type="string", default="flag1" } }, tags = {"counter"} },
    { id = "clear_flag",       fn = E.clear_flag,       params = { { key="var", type="string", default="flag1" } }, tags = {"counter"} },
    { id = "toggle_flag",      fn = E.toggle_flag,      params = { { key="var", type="string", default="flag1" } }, tags = {"counter"} },
    { id = "swap_counters",    fn = E.swap_counters,    params = { { key="var1", type="string", default="c1" }, { key="var2", type="string", default="c2" } }, tags = {"counter"} },

    -- Vehicles
    { id = "unassign_vehicle", fn = E.unassign_vehicle, params = {},                                     tags = {"vehicle"} },
    { id = "send_to_depot",    fn = E.send_to_depot,    params = {},                                     tags = {"vehicle"} },
    { id = "set_speed_mult",   fn = E.set_speed_mult,   params = { { key="mult", type="reporter", default=1.2 } }, tags = {"vehicle"} },
    { id = "set_vehicle_color",fn = E.set_vehicle_color,params = { { key="r", type="number", default=1 }, { key="g", type="number", default=1 }, { key="b", type="number", default=1 } }, tags = {"vehicle"} },
    { id = "reset_vehicle_color",fn = E.reset_vehicle_color,params = {},                                 tags = {"vehicle"} },
    { id = "set_vehicle_icon", fn = E.set_vehicle_icon, params = { { key="icon", type="string", default="car" } }, tags = {"vehicle"} },
    { id = "show_speech_bubble",fn = E.show_speech_bubble,params = { { key="text", type="string", default="Hello!" }, { key="duration", type="number", default=3 } }, tags = {"vehicle"} },
    { id = "flash_vehicle",    fn = E.flash_vehicle,    params = { { key="duration", type="number", default=1 } }, tags = {"vehicle"} },
    { id = "show_vehicle_label",fn = E.show_vehicle_label,params = {},                                   tags = {"vehicle"} },
    { id = "hide_vehicle_label",fn = E.hide_vehicle_label,params = {},                                   tags = {"vehicle"} },
    { id = "show_vehicle",     fn = E.show_vehicle,     params = {},                                     tags = {"vehicle"} },
    { id = "hide_vehicle",     fn = E.hide_vehicle,     params = {},                                     tags = {"vehicle"} },

    -- Camera
    { id = "zoom_to_vehicle",  fn = E.zoom_to_vehicle,  params = {},                                     tags = {"ui"} },
    { id = "pan_to_depot",     fn = E.pan_to_depot,     params = { { key="depot_id", type="string", default="1" } }, tags = {"ui"} },
    { id = "set_zoom",         fn = E.set_zoom,         params = { { key="level", type="number", default=1.0 } }, tags = {"ui"} },

    -- Sounds
    { id = "play_sound",       fn = E.play_sound,       params = { { key="sound", type="string", default="alert" } }, tags = {"sound"} },
    { id = "stop_all_sounds",  fn = E.stop_all_sounds,  params = {},                                     tags = {"sound"} },
    { id = "set_volume",       fn = E.set_volume,       params = { { key="level", type="number", default=0.5 } }, tags = {"sound"} },

    -- UI & Logging
    { id = "show_alert",       fn = E.show_alert,       params = { { key="text", type="string", default="Alert!" }, { key="color", type="enum", options={"red","blue","green"} } }, tags = {"ui"} },
    { id = "add_to_log",       fn = E.add_to_log,       params = { { key="text", type="string", default="Entry" } }, tags = {"ui"} },
    { id = "action_comment",   fn = E.action_comment,   params = { { key="text", type="string", default="comment..." } }, tags = {"ui"} },

    -- Depot
    { id = "set_depot_capacity",fn = E.set_depot_capacity,params = { { key="cap", type="reporter", default=10 } }, tags = {"depot"} },
    { id = "send_vehicles_to_depot",fn = E.send_vehicles_to_depot,params = {},                           tags = {"depot"} },

    -- Clients
    { id = "pause_all_clients",fn = E.pause_all_clients,params = {},                                     tags = {"client"} },
    { id = "resume_all_clients",fn = E.resume_all_clients,params = {},                                   tags = {"client"} },
    { id = "set_client_freq",  fn = E.set_client_freq,  params = { { key="mult", type="reporter", default=1.0 } }, tags = {"client"} },
    { id = "add_client",       fn = E.add_client,       params = { { key="client_id", type="string", default="client1" } }, tags = {"client"} },
    { id = "remove_client",    fn = E.remove_client,    params = { { key="client_id", type="string", default="client1" } }, tags = {"client"} },

    -- System
    { id = "stop_rule",        fn = E.stop_rule,        params = {},                                     tags = {"logic"} },
    { id = "stop_all",         fn = E.stop_all,         params = {},                                     tags = {"logic"} },
    { id = "action_break",     fn = E.action_break,     params = {},                                     tags = {"logic"} },
    { id = "action_continue",  fn = E.action_continue,  params = {},                                     tags = {"logic"} },
    { id = "broadcast_message",fn = E.broadcast_message,params = { { key="msg", type="string", default="msg1" } }, tags = {"logic"} },
    { id = "set_rule_name",    fn = E.set_rule_name,    params = { { key="name", type="string", default="New Name" } }, tags = {"logic"} },
    { id = "benchmark",        fn = E.benchmark,        params = {},                                     tags = {"logic"} },
    { id = "assign_ctx",       fn = E.assign_ctx,       params = {},                                     tags = {"logic"} },

    -- Trip flow
    { id = "skip",             fn = E.skip,             params = {},                                     tags = {"trip"} },

    -- Text variables
    { id = "set_text_var",     fn = E.set_text_var,     params = { { key="key", type="string", default="my_text" }, { key="value", type="reporter", default="" } }, tags = {"counter"} },
    { id = "append_text_var",  fn = E.append_text_var,  params = { { key="key", type="string", default="my_text" }, { key="value", type="reporter", default="" } }, tags = {"counter"} },
    { id = "clear_text_var",   fn = E.clear_text_var,   params = { { key="key", type="string", default="my_text" } },                                               tags = {"counter"} },

    -- Screen effects
    { id = "shake_screen",     fn = E.shake_screen,     params = { { key="seconds", type="number", default=0.5 }, { key="magnitude", type="number", default=8 } },  tags = {"ui"} },

    -- Vehicles (additional)
    { id = "fire_vehicle",     fn = E.fire_vehicle,     params = {},                                     tags = {"vehicle"} },

    -- Depot
    { id = "open_depot",       fn = E.open_depot,       params = {},                                     tags = {"depot"} },
    { id = "close_depot",      fn = E.close_depot,      params = {},                                     tags = {"depot"} },
    { id = "rename_depot",     fn = E.rename_depot,     params = { { key="name", type="string", default="My Depot" } },                                             tags = {"depot"} },
}
