local package,P=...
-- BV Addon Suite - Gather Data. Licensed under the GNU General Public
-- License version 2 (LICENSE.txt): the data is derived from the vMaNGOS
-- world database (NOTICE.txt). It is a separate work read by BV Gather;
-- the rest of BV Addon Suite keeps its own license.
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.96 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.1.0","0.8.96",1) then return end
P.ready=true
