local package=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireRelease then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BVAddonSuite Core 0.8.51. Update all BV packages together; saved data is preserved.") end
    return
end
if not ns:RequireRelease(package,"0.8.51") then return end
local Data,number=ns.ProgressData,ns.ProgressModel.Number
local field=ns.ProgressOptions.Field
function Data:Reputation()
    local api = C_Reputation
    local data = api and api.GetWatchedFactionData and api.GetWatchedFactionData()
    if not data or not data.name then return nil end
    local low, high, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    local id, capped = data.factionID, false
    local standing = _G["FACTION_STANDING_LABEL" .. tostring(data.reaction)] or tostring(data.reaction or "")
    local status = ""
    if api.IsFactionParagonForCurrentPlayer and api.IsFactionParagonForCurrentPlayer(id) then
        local total, threshold, _, pending = api.GetFactionParagonInfo(id)
        if not number(total) or not number(threshold) or threshold <= 0 then return nil end
        low, high, value = 0, threshold, total % threshold
        standing, status = "Paragon", pending and "Reward ready" or ""
        if pending then value = threshold end
    elseif api.IsMajorFaction and api.IsMajorFaction(id) and C_MajorFactions then
        local info = C_MajorFactions.GetMajorFactionData(id)
        if not info then return nil end
        low, high, value = 0, info.renownLevelThreshold, info.renownReputationEarned
        standing = "Renown " .. tostring(info.renownLevel)
        capped = C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(id) or false
    else
        local friendship = C_GossipInfo and C_GossipInfo.GetFriendshipReputation and C_GossipInfo.GetFriendshipReputation(id)
        if friendship and number(friendship.friendshipFactionID) and friendship.friendshipFactionID > 0 then
            low, high, value = friendship.reactionThreshold, friendship.nextThreshold, friendship.standing
            standing = friendship.reaction or standing
            capped = not high
        else capped = data.reaction == 8 end
    end
    if capped then return { current = 1, maximum = 1, name = data.name, standing = standing, capped = true, factionID = id } end
    if not number(low) or not number(high) or not number(value) or high <= low then return nil end
    return { current = math.max(0, math.min(high - low, value - low)), maximum = high - low,
        name = data.name, standing = standing, factionID = id, status = status }
end

ns.ProgressBars:Register({
    kind="reputation", label="Reputation Bar", description="Your watched faction, with the information you choose.",
    aliases={"rep","reputation"}, y=130, color="4F96D1FF",
    defaultFields=function() return { field("{faction}", "LEFT", "LEFT", 8, 0, 200),
        field("{current} / {max}  ({percent}%)", "CENTER", "CENTER", 0, 0, 280),
        field("{standing}", "RIGHT", "RIGHT", -8, 0, 170),
        field("{remaining} to next rank  {status}", "TOP", "BOTTOM", 0, -5, 500) } end,
    snapshot=function() return Data:Reputation() end,
    preview=function()
        local snapshot={name="Example faction",standing="Honored",current=4200,maximum=12000}
        return snapshot,ns.ProgressModel.Values(snapshot,nil,0)
    end,
    missing={current=0,maximum=1,name="No watched faction",standing="Select one in Reputation"},
    events={"UPDATE_FACTION"},
})
