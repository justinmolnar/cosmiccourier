-- views/components/ClientsPanelView.lua
local ClientsPanelView = {}

function ClientsPanelView.draw(game, ui_manager)
    local state = game.state
    love.graphics.setFont(game.fonts.ui)
    
    for i, l in ipairs(ui_manager.layout_cache.clients) do
        love.graphics.setColor(1,1,1)
        love.graphics.print("Client #"..i, l.x+5, l.y)
    end
    
    local btn = ui_manager.layout_cache.buttons.buy_client
    if btn then 
        love.graphics.setColor(1,1,1)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h)
        love.graphics.printf("Market for New Client ($"..state.costs.client..")", btn.x, btn.y+8, btn.w, "center") 
    end
end

return ClientsPanelView