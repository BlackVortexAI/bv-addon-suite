local package=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.89 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.8.91","0.8.95",1) then return end
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


-- Level-up notification on Core's notification stage (0.8.90, Core 0.8.95).
ns.Stage:Register({id="levelup",label="Level up",priority=3,hold=5,
    description="Your new level and how long the last one took. Shown while the Experience Bar module is on.",
    sample={title="Level 35",subtitle="Level 34 took 1h 12m"}})

-- Blizzard's own level-up display came at the same time as ours (Florian
-- 2026-10-08). While our level-up type is on, Blizzard's is hidden for a
-- few seconds after a level-up: the classic LevelUpDisplay frame and, on
-- clients with the event toasts, the toast shown then.
local blizzard={quietUntil=0}
local function ours() return ns.Stage.types.levelup~=nil and ns.Stage:TypeConfig("levelup").enabled==true end
local function quiet() return GetTime()<blizzard.quietUntil and ours() end
local function hookBlizzard()
    if blizzard.hooked then return end
    blizzard.hooked=true
    local display=rawget(_G,"LevelUpDisplay")
    if display and display.HookScript then display:HookScript("OnShow",function(own) if quiet() then own:Hide() end end) end
    local toasts=rawget(_G,"EventToastManagerFrame")
    if toasts and type(toasts.DisplayToast)=="function" then
        hooksecurefunc(toasts,"DisplayToast",function(own)
            if not quiet() then return end
            if type(own.CloseActiveToasts)=="function" then pcall(own.CloseActiveToasts,own) else own:Hide() end
        end)
    end
end
ns.ExperienceLevelUp=blizzard

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
        -- The old level's time comes from the session before the next XP update.
        hookBlizzard()
        context:Subscribe("PLAYER_LEVEL_UP",function(_,level)
            if not number(level) then return end
            blizzard.quietUntil=GetTime()+6
            -- Already on screen (it can come first): gone.
            local display=rawget(_G,"LevelUpDisplay")
            if ours() and display and display.IsShown and display:IsShown() then display:Hide() end
            local subtitle
            local ok,values=pcall(ns.ProgressModel.Values,state.snapshot,state.session,GetTime())
            if ok and type(values)=="table" and values.levelTime and values.levelTime~="—" then
                subtitle="Level "..(level-1).." took "..values.levelTime
            end
            -- Never let the notification disturb the bar.
            pcall(ns.Stage.Show,ns.Stage,"levelup",{title="Level "..level,subtitle=subtitle or "A new level"})
        end)
        context:Subscribe("TIME_PLAYED_MSG",function(_,_,levelSeconds)
            if number(levelSeconds) then
                state.session.playedBase,state.session.playedAt=levelSeconds,GetTime()
                ns.ProgressBars:Render("experience")
            end
        end)
        if RequestTimePlayed then RequestTimePlayed(false) end
    end,
})
