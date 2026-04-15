-- data/names/pools/geography.lua
-- Descriptor words keyed by geography tag. Templates pull from here via
-- slots like {nearby_water}, {terrain_descriptor}, {highland_descriptor}.

return {
    coastal     = { "Coast", "Waterfront", "Harbor", "Bay", "Shore", "Pier", "Dockside" },
    near_lake   = { "Lake", "Lakeside", "Lakeshore", "Cove", "Bayside" },
    near_river  = { "River", "Riverside", "Creek", "Brook", "Ford" },
    highland    = { "Heights", "Ridge", "Summit", "Overlook", "Highland", "Peaks" },
    lowland     = { "Flats", "Basin", "Hollow", "Valley", "Plain" },
    mountainous = { "Mountain", "Peak", "Alpine", "Highland", "Ridge" },
    desert      = { "Desert", "Mesa", "Sands", "Dunes", "Badlands" },
    forest      = { "Woodland", "Forest", "Grove", "Timber", "Pine" },
    plains      = { "Plains", "Prairie", "Field", "Meadow" },

    -- Short adjectival forms used as prefix in e.g. "Waterfront {food}".
    coastal_adj    = { "Waterfront", "Harborside", "Coastal", "Dockside" },
    near_lake_adj  = { "Lakeside", "Lakeshore", "Lakefront" },
    near_river_adj = { "Riverside", "Creekside" },
}
