local package=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireRelease then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BVAddonSuite Core 0.8.51. Update all BV packages together; saved data is preserved.") end
    return
end
if not ns:RequireRelease(package,"0.8.51") then return end
local Data,number=ns.ProgressData,ns.ProgressModel.Number
local field=ns.ProgressOptions.Field
function Data:Experience()
    local current, maximum, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if not number(current) or not number(maximum) or not number(level) then return nil end
    local capped = maximum <= 0
    if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
        capped = capped or GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
    elseif GetMaxLevelForPlayerExpansion then
        local maxLevel = GetMaxLevelForPlayerExpansion()
        capped = capped or (number(maxLevel) and level >= maxLevel)
    end
    local rested = GetXPExhaustion() or 0
    if not number(rested) then rested = 0 end
    return { current = math.max(0, current), maximum = math.max(0, maximum), level = level,
        rested = math.max(0, rested), capped = capped, disabled = IsXPUserDisabled and IsXPUserDisabled() or false }
end


ns.ProgressBars:Register({
    kind="experience", label="Experience Bar", description="Progress, pace and time to your next level.",
    aliases={"exp","xp","experience"}, y=180, color="20F0A0FF", supportsRested=true,
    defaultFields=function() return {
        field("Level {level}", "LEFT", "LEFT", 8, 0, 110),
        field("{current} / {max}  ({percent}%)", "CENTER", "CENTER", 0, 0, 280),
        field("Next: {eta}", "RIGHT", "RIGHT", -8, 0, 160),
        field("{rate} XP/h", "TOPLEFT", "BOTTOMLEFT", 0, -5, 230),
        field("On this level: {levelTime}", "TOPRIGHT", "BOTTOMRIGHT", 0, -5, 250),
        field("Rested: {rested}", "BOTTOMLEFT", "TOPLEFT", 0, 5, 230, false),
        field("Remaining: {remaining}", "BOTTOMRIGHT", "TOPRIGHT", 0, 5, 230, false),
    } end,
    snapshot=function() return Data:Experience() end,
    preview=function()
        return {level=34,current=42000,maximum=65000,rested=12000},
            {level="34",nextLevel="35",current="42000",max="65000",remaining="23000",percent="64.6",rested="12000",rate="38000",eta="36m",levelTime="1h 12m",sessionXP="24000",status="PREVIEW"}
    end,
    events={"PLAYER_XP_UPDATE","PLAYER_LEVEL_UP","UPDATE_EXHAUSTION","ENABLE_XP_GAIN","DISABLE_XP_GAIN"},
    newSession=ns.ProgressModel.NewSession, observe=ns.ProgressModel.Observe,
    clockTokens={"{eta}","{rate}","{levelTime}"},
    onEnable=function(context,state)
        context:Subscribe("TIME_PLAYED_MSG",function(_,_,levelSeconds)
            if number(levelSeconds) then
                state.session.playedBase,state.session.playedAt=levelSeconds,GetTime()
                ns.ProgressBars:Render("experience")
            end
        end)
        if RequestTimePlayed then RequestTimePlayed(false) end
    end,
})
