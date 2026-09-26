-- Explicit opt-in exception to the runtime's no-per-frame-work rule.
-- Constant bounded histogram work only; no rendering or source scans here.
local _,ns=...
function ns.UI:SetPerformanceSampling(enabled)
    local frame=self.performanceSampler
    if enabled then
        if not frame then frame=CreateFrame("Frame");self.performanceSampler=frame end
        frame:SetScript("OnUpdate",function(_,elapsed) ns.Performance:Frame(elapsed) end)
        frame:Show()
    elseif frame then frame:SetScript("OnUpdate",nil);frame:Hide() end
end
