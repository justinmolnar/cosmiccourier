-- tests/repro_dropdown_error.lua
-- Simulates the Dropdown error: bad argument #1 to 'ipairs' (table expected, got string)

local function test_dropdown()
    print("Testing Dropdown with string options...")
    
    -- Mock love global if needed, but Dropdown might use it
    if not _G.love then
        _G.love = {
            graphics = {
                setColor = function() end,
                rectangle = function() end,
                print = function() end,
                setFont = function() end,
            }
        }
    end

    local Dropdown = require("views.components.Dropdown")
    
    -- This is what happens in the reported error
    local opts = "dynamic" -- DispatchTab passes the raw string from sd.options
    local val = "some_val"
    local callback = function(v) end
    local game = {
        fonts = {
            ui_small = {
                getHeight = function() return 12 end,
                getWidth = function() return 50 end,
            }
        }
    }

    local ok, dropdown = pcall(Dropdown.new, Dropdown, opts, val, callback, game)
    if not ok then
        print("Dropdown.new failed: " .. tostring(dropdown))
        return
    end

    print("Attempting to draw dropdown with string options...")
    local ok_draw, err = pcall(function()
        dropdown:draw()
    end)

    if not ok_draw then
        print("SUCCESS: Reproduced the error!")
        print("Error: " .. tostring(err))
    else
        print("FAILURE: Did not reproduce the error. Dropdown:draw() succeeded.")
    end
end

test_dropdown()
