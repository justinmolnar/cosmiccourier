-- data/entity_details/init.lua
-- Registry mapping entity kind → detail descriptor. Adding a new entity type
-- is one file + one line here; no view or controller changes.

return {
    vehicle = require("data.entity_details.vehicle"),
    depot   = require("data.entity_details.depot"),
    client  = require("data.entity_details.client"),
}
