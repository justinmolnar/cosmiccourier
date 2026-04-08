-- tests/test_agnostic_call.lua
-- Verifies that the dispatch engine is agnostic and can handle new actions
-- added only to data/dispatch_actions.lua.

local function test_agnostic()
    print("Testing Action Registry Agnosticism...")
    
    local RE = require("services.DispatchRuleEngine")
    local ACTIONS = require("data.dispatch_actions")
    
    -- 1. Inject a "fake" action into the registry at runtime
    local action_executed = false
    local test_action = {
        id = "test_logic_gate",
        fn = function(block, ctx)
            print("  [SUCCESS] Test action executed with value: " .. tostring(block.slots.value))
            action_executed = true
            return "claimed" -- simulate a blocking action
        end,
        params = { { key="value", type="number", default=42 } },
        tags = {"test"}
    }
    table.insert(ACTIONS, test_action)
    print("  Inserted 'test_logic_gate' into data/dispatch_actions.lua registry.")

    -- 2. Create a rule that uses the generic 'block_call' to call our new action
    -- Schema: Call(action="test_logic_gate", value=99)
    local rule = {
        id = "test_rule",
        enabled = true,
        stack = {
            {
                def_id = "block_call",
                kind = "stack",
                slots = {
                    action = "test_logic_gate",
                    value = 99
                }
            }
        }
    }

    -- 3. Evaluate the rule
    local game = {
        state = {
            dispatch_rules = { rule },
            vars = {}
        },
        entities = {
            vehicles = {},
            trips = { pending = { { id = "trip1" } } }
        }
    }

    print("  Evaluating rule via DispatchRuleEngine...")
    RE.evaluate(game)

    if action_executed then
        print("RESULT: PASS - New action was found and executed via generic block_call.")
    else
        print("RESULT: FAIL - New action was not executed.")
    end
end

-- Mock require if needed for standalone run, but here we assume project context
local ok, err = pcall(test_agnostic)
if not ok then
    print("Test Error: " .. tostring(err))
end
