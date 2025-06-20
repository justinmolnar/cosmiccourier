-- views/components/UpgradesPanelView.lua
local UpgradesPanelView = {}

function UpgradesPanelView.draw(game, ui_manager)
    love.graphics.setFont(game.fonts.ui)
    for id, l in pairs(ui_manager.layout_cache.upgrades) do
        if l.type == "header" then
            love.graphics.setColor(0.7, 0.7, 0.8)
            love.graphics.print(l.text, l.x + 5, l.y)
            love.graphics.line(l.x, l.y + 20, l.x + l.w, l.y + 20)
        end
    end
    for _, btn in ipairs(ui_manager.layout_cache.upgrades.buttons) do
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.w)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.w)
        love.graphics.setFont(game.fonts.emoji_ui)
        love.graphics.printf(btn.icon, btn.x, btn.y + 5, btn.w, "center")
        love.graphics.setFont(game.fonts.ui_small)
        love.graphics.printf(btn.name, btn.x, btn.y + btn.w - 5, btn.w, "center")
    end
end

return UpgradesPanelView