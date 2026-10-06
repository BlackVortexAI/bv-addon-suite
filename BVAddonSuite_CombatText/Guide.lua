local _,L=...
if not L.ready then return end
-- Guide for Core's guide window (Core 0.8.94+, Core/Tutorial.lua). Optional:
-- with an older Core there is no guide and nothing else changes.
local ns=L.ns
local T=ns.Tutorial
if not (T and T.Register) then return end
local G=L.Log

L.GUIDE_ID="combattext"
L.FILTER_GUIDE_ID="combattext_filter"
-- 0.7.2: the BV Combat Log filter (LogFilter.lua) and the status display
-- (UI/StatusDisplay.lua). In the main guide and, for players who finished
-- an older one, as a guide of their own (offered once on the next login).
local F=L.LogFilter
local FILTER_STEP={title="Combat Log filter",icon="Interface\\Icons\\INV_Misc_Spyglass_03",
    text="The filter selected on the Combat Log tab decides which actions the game reports. Best is Combat Text's own filter \"BV Combat Text\": "
        .."your actions and your pet's, your pet in its own colour. Then every Combat Log line tells whether it was you, your pet or someone else.\n\n"
        .."Setting it up reloads the interface (the game accepts a new filter only that way); you are asked first. Your other filters stay as they are.\n\n"
        .."Important: the filter must stay selected. The Start button and the status display select it again with one click. "
        .."If you choose another filter while playing, Combat Text can no longer tell your pet apart and falls back to the other filter or to estimates until you click one of them.",
    check=function()
        local saved=_G.Blizzard_CombatLog_Filters
        if type(saved)~="table" then return "open","Combat Log not loaded yet: open the Combat Log tab once" end
        if F:Selected() then return "done","\"BV Combat Text\" selected" end
        if F:Find() then return "open","Set up, but another filter is selected: click the Start button" end
        local s=G:Status()
        if G.USABLE[s.filter] then return "open",(s.filterName and "\""..s.filterName.."\" " or "").."fits too, but cannot tell your pet apart" end
        return "open","Not set up yet"
    end,
    action={label="Set up BV filter (reloads)",run=function() F:Confirm() end,hideWhenDone=true}}
local STATUS_STEP={title="Status display (optional)",icon="Interface\\Icons\\INV_Misc_PocketWatch_01",
    text="A small box with a symbol shows whether everything Combat Text needs is in order: the Combat Log opened since login, its filter selected, the line colours. "
        .."If something is off, it turns red; a click puts it right (it opens the Combat Log for a moment and selects the BV filter).\n\n"
        .."Hover over it for every detail; move it in the Layout Editor (top left by default).",
    check=function() local on=L:Config().statusDisplay;return on and "done" or "open",on and "Shown" or "Off (optional)" end,
    action={label="Show status display",run=function() L:Config().statusDisplay=true;L:Changed() end,hideWhenDone=true}}
T:Register({
    id=L.GUIDE_ID,
    title="Combat Text",
    -- 2: Blizzard's Cooldown Manager as a shared step (Core 0.8.94).
    version=2,
    module=L.ID,
    steps={
        {title="Welcome",icon="Interface\\Icons\\INV_Sword_04",
         text="Combat Text shows your damage, heals and avoidance as floating numbers, plus auras and messages.\n\n"
            .."WoW Forever does not tell addons who hit an enemy. Combat Text therefore collects evidence: the Combat Log reports your own actions, "
            .."and an enemy that fights you is a hint. From that it tells your hits from those of your pet, your group or a damage shield.\n\n"
            .."The next steps set this up. It takes a minute, and each step is checked live."},
        {title="Open the Combat Log",icon="Interface\\Icons\\INV_Misc_Note_01",
         text="The game reports your actions to addons only after the Combat Log tab in your chat was shown once since login or /reload "
            .."(that is when Blizzard loads its filter; addons cannot do it themselves).\n\n"
            .."Click the button below: it opens the Combat Log tab for a moment and switches back. After each login, the small Start button "
            .."at the top of the screen does the same, or click the Combat Log tab yourself.",
         check=function() if G.started then return "done","Opened since login" end;return "open","Not yet since login" end,
         secure={label="Open the Combat Log now",macro=function() return G:Macro() end,hideWhenDone=true}},
        FILTER_STEP,
        STATUS_STEP,
        {title="Whose numbers",icon="Interface\\Icons\\Ability_Hunter_Pet_Wolf",
         text="Per area (open world, dungeons, raids, battlegrounds) you choose under \"Whose numbers\":\n\n"
            .."Only mine: your hits.\n"
            .."Mine, others dimmed: also hits of others on enemies fighting you or your group (pet, group, Thorns), in grey and see-through.\n"
            .."All, full color: every number on enemies.\n\n"
            .."Without the Combat Log a hit counts as yours only with evidence of your own (your cast, a damage over time effect, your swing); others' hits in your fight are dimmed.",
         action={label="Open Combat Text settings",run=function() ns.Config:OpenPage("combattext") end}},
        {shared="cooldownmanager"},
        {title="Spell icons (optional)",icon="Interface\\Icons\\INV_Misc_QuestionMark",
         text="Under Experimental, Combat Text can guess which of your spells caused a hit and show its icon. It learns each spell's damage type and tick rhythm from your fights.\n\n"
            .."Damage over time is recognised by its tick rhythm, because auras on enemies cannot be read in combat.\n\n"
            .."Done: you can open this guide again in the Combat Text settings or with /bv guide combattext.",
         action={label="Open Combat Text settings",run=function() ns.Config:OpenPage("combattext") end}},
    },
})

-- The filter steps on their own, for players who finished an older guide.
T:Register({
    id=L.FILTER_GUIDE_ID,
    title="Combat Text: Combat Log filter",
    version=1,
    module=L.ID,
    steps={FILTER_STEP,STATUS_STEP},
})
-- Called as the module starts: a player who never finished the main guide
-- gets these steps there, so the extra guide counts as done.
function L.GuideSync()
    local db=ns.Settings and ns.Settings.db
    local seen=db and db.tutorials
    if type(seen)=="table" and seen[L.GUIDE_ID]==nil and not T:Seen(L.FILTER_GUIDE_ID) then T:Finish(L.FILTER_GUIDE_ID) end
end
