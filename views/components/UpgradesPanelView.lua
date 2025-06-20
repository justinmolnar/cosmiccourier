-- views/components/UpgradesPanelView.lua
local UpgradesPanelView = {}

function UpgradesPanelView.draw(game, ui_manager)
    love.graphics.setFont(game.fonts.ui)
    
    -- Draw category headers from layout data
    for id, layout_item in pairs(ui_manager.layout_cache.upgrades) do
        if layout_item.type == "header" then
            love.graphics.setColor(0.7, 0.7, 0.8)
            love.graphics.print(layout_item.text, layout_item.x + 5, layout_item.y)
            love.graphics.line(layout_item.x, layout_item.y + 20, layout_item.x + layout_item.w, layout_item.y + 20)
        end
    end
    
    -- Draw upgrade buttons from layout data
    for _, button_data in ipairs(ui_manager.layout_cache.upgrades.buttons) do
        -- Background
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", button_data.x, button_data.y, button_data.w, button_data.w)
        
        -- Border
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", button_data.x, button_data.y, button_data.w, button_data.w)
        
        -- Icon
        love.graphics.setFont(game.fonts.emoji_ui)
        love.graphics.printf(button_data.icon, button_data.x, button_data.y + 5, button_data.w, "center")
        
        -- Name
        love.graphics.setFont(game.fonts.ui_small)
        love.graphics.printf(button_data.name, button_data.x, button_data.y + button_data.w - 5, button_data.w, "center")
    end
end

return UpgradesPanelView