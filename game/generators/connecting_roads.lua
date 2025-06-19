-- game/generators/connecting_roads.lua
-- Connecting Roads Generation Module (Disabled for cleaner look)

local ConnectingRoads = {}

function ConnectingRoads.generateConnections(grid, districts, highway_points, map_w, map_h)
    -- DISABLED: These connecting roads create visual clutter
    -- Return empty connections array to keep highways clean
    local connections = {}
    return connections
end

function ConnectingRoads.findNearestHighwayPoint(start_x, start_y, highway_points)
    -- Not used when connections are disabled
    return nil
end

function ConnectingRoads.drawConnections(grid, connections)
    -- DISABLED: Don't draw any connecting roads
    -- This prevents the messy lines going to district centers
    -- The highways and ring roads provide sufficient connectivity
end

function ConnectingRoads.drawThickLine(grid, x1, y1, x2, y2, road_type, thickness)
    -- Not used when connections are disabled
end

function ConnectingRoads.inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

return ConnectingRoads