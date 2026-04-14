-- views/VehicleRenderer.lua
-- Rendering logic for Vehicle objects.
-- Extracted from models/vehicles/Vehicle.lua to keep the model free of love.* calls.

local DrawingUtils = require("utils.DrawingUtils")

local VehicleRenderer = {}

function VehicleRenderer.drawDebug(vehicle, game)
    local screen_x, screen_y = vehicle.px, vehicle.py
    local _pi = vehicle.path_i or 1
    if vehicle.path and _pi <= #vehicle.path then
        love.graphics.setColor(0, 0, 1, 0.7)
        love.graphics.setLineWidth(2 / game.camera.scale)
        local pixel_path = {}
        table.insert(pixel_path, vehicle.px)
        table.insert(pixel_path, vehicle.py)
        local path_map = game.maps[vehicle.operational_map_key]
        for i = _pi, #vehicle.path do
            local node = vehicle.path[i]
            local px, py = path_map:getNodePixel(node)
            table.insert(pixel_path, px)
            table.insert(pixel_path, py)
        end
        if #pixel_path >= 4 then
            love.graphics.line(pixel_path)
        end
        love.graphics.setLineWidth(1)
    end

    local scale  = 1 / game.camera.scale
    local line_h = 15 * scale
    local menu_x = screen_x + (20 * scale)
    local menu_y = screen_y - (20 * scale)

    local state_name  = vehicle.state and vehicle.state.name or "N/A"
    local pi          = vehicle.path_i or 1
    local path_count  = vehicle.path and math.max(0, #vehicle.path - pi + 1) or 0
    local target_text = "None"
    if vehicle.path and pi <= #vehicle.path then
        target_text = string.format("(%d, %d)", vehicle.path[pi].x, vehicle.path[pi].y)
    end
    local debug_lines = {
        string.format("ID: %d | Type: %s", vehicle.id, vehicle.type),
        string.format("State: %s", state_name),
        string.format("Path Nodes: %d", path_count),
        string.format("Target: %s", target_text),
        string.format("Cargo: %d | Queue: %d", #vehicle.cargo, #vehicle.trip_queue),
        string.format("Pos: %d, %d", math.floor(vehicle.px), math.floor(vehicle.py))
    }

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", menu_x - (5*scale), menu_y - (5*scale), (200*scale), #debug_lines * line_h + (10*scale))

    local old_font = love.graphics.getFont()
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.setColor(0, 1, 0)
    for i, line in ipairs(debug_lines) do
        love.graphics.push()
        love.graphics.translate(menu_x, menu_y + (i-1) * line_h)
        love.graphics.scale(scale, scale)
        love.graphics.print(line, 0, 0)
        love.graphics.pop()
    end
    love.graphics.setFont(old_font)
    love.graphics.setColor(1, 1, 1)
end

function VehicleRenderer.draw(vehicle, game)
    if not vehicle:shouldDrawAtCameraScale(game) then return end
    if not vehicle.visible then return end

    local draw_px, draw_py = vehicle.px, vehicle.py
    local g = love.graphics

    -- Selection ring
    if vehicle == game.entities.selected_vehicle then
        g.setColor(1, 1, 0, 0.8)
        local radius = 16 / game.camera.scale
        g.setLineWidth(2 / game.camera.scale)
        g.circle("line", draw_px, draw_py, radius)
        g.setLineWidth(1)
    end

    -- Color override disc
    local co = vehicle.color_override
    if co then
        g.setColor(co[1], co[2], co[3], 0.55)
        g.circle("fill", draw_px, draw_py, 11 / game.camera.scale)
    end

    -- Flash effect
    local fl = vehicle.flash
    if fl and fl.timer > 0 then
        local t  = fl.timer / fl.max_time
        local fc = fl.color or { 1, 1, 0 }
        g.setColor(fc[1], fc[2], fc[3], 0.75 * t)
        g.circle("fill", draw_px, draw_py, 13 / game.camera.scale)
    end

    DrawingUtils.drawWorldIcon(game, vehicle:getIcon(), draw_px, draw_py)

    -- Count badge (cargo the vehicle is actually carrying)
    DrawingUtils.drawCountBadge(game, #vehicle.cargo, draw_px, draw_py)

    -- Speech bubble (fades in last second)
    local sb = vehicle.speech_bubble
    if sb and sb.timer > 0 then
        local alpha = math.min(1, sb.timer)
        g.push()
        g.translate(draw_px, draw_py)
        g.scale(1 / game.camera.scale, 1 / game.camera.scale)
        local font = game.fonts.ui_small
        g.setFont(font)
        local fh   = font:getHeight()
        local fw   = font:getWidth(sb.text) + 10
        local bx, by = -fw / 2, -26 - fh
        g.setColor(0, 0, 0, 0.70 * alpha)
        g.rectangle("fill", bx, by, fw, fh + 6, 3, 3)
        g.setColor(1, 1, 1, alpha)
        g.print(sb.text, bx + 5, by + 3)
        g.pop()
    end

    -- Persistent label
    local lbl = vehicle.show_label
    if lbl and lbl ~= "" then
        g.push()
        g.translate(draw_px, draw_py)
        g.scale(1 / game.camera.scale, 1 / game.camera.scale)
        local font = game.fonts.ui_small
        g.setFont(font)
        local fh = font:getHeight()
        local fw = font:getWidth(lbl) + 8
        g.setColor(0, 0, 0, 0.60)
        g.rectangle("fill", -fw / 2, -(20 + fh), fw, fh + 4, 2, 2)
        g.setColor(1, 1, 0.6, 1)
        g.print(lbl, -fw / 2 + 4, -(20 + fh) + 2)
        g.pop()
    end
end

return VehicleRenderer
