local package,N=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.102 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.1.0","0.8.102",1) then return end
-- Quest Navigation (Florian 2026-10-15: its own package, so that Quest stays
-- free of Routing and every dependency here is a required one): where a
-- quest's objectives and turn-in are, from QuestieDB (installed with
-- Questie; read only, nothing of it is shipped), and BV Routing leads you
-- there spot by spot. Quest shows the buttons (its details ask
-- Quest.navigation). Files: this, Questie (the bridge, the spots, leading),
-- Probe (a report for development).
N.ns=ns
ns.QuestNavigation=N
N.ready=true
function N:Print(text) ns:Print(text,"Quest Navigation") end

-- Quest's details ask this for the targets of a quest and lead to them.
local Q=ns.Quest
if Q then Q.navigation=N end

ns.Commands:RegisterAction("questnav",function(action)
    action=type(action)=="string" and action or ""
    local command,rest=action:match("^(%S*)%s*(.-)%s*$")
    if command=="probe" then N.Probe:Run();return end
    if command=="test" then N.Guide:Test(rest);return end
    if N.Questie:Available() then N:Print("Ready: the quest details show a button beside each objective and the turn-in.")
    else N:Print(N.Questie:Missing()) end
end)
