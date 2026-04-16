-- views/tabs/CityTab.lua
-- Operational cockpit tab. Composes existing datagrid sources into a scope-
-- filtered accordion view keyed on the player's selected city. Pure
-- composition — no drawing, no state.
--
-- Data: data/scope_tabs.lua declares the City tab's shape (ordered sections,
-- each pointing at a datagrid source + a scope_filter id).
-- Services: ScopeFilterService wraps the source's items_fn; ScopeSelectionService
-- tells us which city is selected.

local ScopeFilterService    = require("services.ScopeFilterService")
local ScopeSelectionService = require("services.ScopeSelectionService")
local ScopeSelector         = require("views.components.ScopeSelector")
local UIConfig              = require("services.UIConfigService")

local CityTab = {}

function CityTab.build(game)
    local tab_def = require("data.scope_tabs").city

    -- Prime accordion defaults on first view so collapsed_default sections
    -- come up collapsed until the player toggles them.
    for _, s in ipairs(tab_def.sections) do
        UIConfig.getAccordion(game, tab_def.id, s.id, s.collapsed_default)
    end

    local selected_city = ScopeSelectionService.getSelectedCity(game)

    local components = {}

    -- Header: scope selector ("City: <name> ▾")
    components[#components + 1] = {
        type     = "scope_selector",
        label    = "City:",
        value_fn = function(g) return ScopeSelector.selectedCityName(g) end,
    }
    components[#components + 1] = { type = "spacer", h = 4 }

    -- Each section becomes an accordion wrapping its (scope-filtered) datagrid.
    for _, section in ipairs(tab_def.sections) do
        local source = require(section.source_module)
        local wrapped
        if section.scope_filter then
            wrapped = ScopeFilterService.wrap(source, section.scope_filter,
                                              "city", selected_city)
        else
            wrapped = source
        end

        local badge_fn
        if wrapped and wrapped.items_fn then
            badge_fn = function(g)
                local items = wrapped.items_fn(g) or {}
                return #items
            end
        end

        components[#components + 1] = {
            type       = "accordion_section",
            tab_id     = tab_def.id,
            section_id = section.id,
            header     = section.label,
            badge      = badge_fn,
            children   = { { type = "datagrid", source = wrapped } },
        }
    end

    return components
end

return CityTab
