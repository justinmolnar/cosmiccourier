-- views/sandbox/panels/ActionsPanel.lua
-- Draws Generate, View Mode toggle buttons, and Send to Main Game button.
-- Button rects are owned and managed by SandboxSidebarManager.

local ActionsPanel = {}

function ActionsPanel.draw(gen_btn, view_btns, send_btn, sc, game)
    love.graphics.setFont(game.fonts.ui)

    -- Generate button
    love.graphics.setColor(0.15, 0.35, 0.15)
    love.graphics.rectangle("fill", gen_btn.x, gen_btn.y, gen_btn.w, gen_btn.h, 4)
    love.graphics.setColor(0.3, 0.8, 0.3)
    love.graphics.rectangle("line", gen_btn.x, gen_btn.y, gen_btn.w, gen_btn.h, 4)
    love.graphics.setColor(0.5, 1.0, 0.5)
    love.graphics.printf("Generate", gen_btn.x, gen_btn.y + 10, gen_btn.w, "center")

    -- View toggle buttons (4 buttons, 2x2 grid)
    love.graphics.setFont(game.fonts.ui_small)
    for _, vb in ipairs(view_btns) do
        local active = sc.view_mode == vb.mode
        if active then
            love.graphics.setColor(0.25, 0.35, 0.65)
        else
            love.graphics.setColor(0.12, 0.12, 0.22)
        end
        love.graphics.rectangle("fill", vb.x, vb.y, vb.w, vb.h, 3)
        if active then
            love.graphics.setColor(0.5, 0.6, 1.0)
        else
            love.graphics.setColor(0.3, 0.3, 0.55)
        end
        love.graphics.rectangle("line", vb.x, vb.y, vb.w, vb.h, 3)
        if active then
            love.graphics.setColor(0.9, 0.95, 1.0)
        else
            love.graphics.setColor(0.55, 0.55, 0.75)
        end
        love.graphics.printf(vb.label, vb.x, vb.y + 6, vb.w, "center")
    end

    -- Send to Main Game button
    love.graphics.setFont(game.fonts.ui)
    local can_send = sc.sandbox_map ~= nil
    love.graphics.setColor(can_send and 0.15 or 0.10, can_send and 0.25 or 0.12, can_send and 0.45 or 0.20)
    love.graphics.rectangle("fill", send_btn.x, send_btn.y, send_btn.w, send_btn.h, 4)
    love.graphics.setColor(can_send and 0.3 or 0.3, can_send and 0.5 or 0.3, can_send and 0.9 or 0.4)
    love.graphics.rectangle("line", send_btn.x, send_btn.y, send_btn.w, send_btn.h, 4)
    love.graphics.setColor(can_send and 0.5 or 0.4, can_send and 0.7 or 0.4, can_send and 1.0 or 0.5)
    love.graphics.printf("Send to Main Game", send_btn.x, send_btn.y + 10, send_btn.w, "center")

    -- Status text
    if sc.status_text and sc.status_text ~= "" then
        love.graphics.setFont(game.fonts.ui_small)
        love.graphics.setColor(0.7, 0.9, 0.7)
        love.graphics.printf(sc.status_text, send_btn.x, send_btn.y + send_btn.h + 6, send_btn.w, "center")
    end

    love.graphics.setColor(1, 1, 1)
end

return ActionsPanel
