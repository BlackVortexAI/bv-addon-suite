local _,L=...
if not L.ready then return end
-- Guide for Core's guide window (Core 0.8.94+, Core/Tutorial.lua). Optional:
-- with an older Core there is no guide and nothing else changes.
local ns=L.ns
local T=ns.Tutorial
if not (T and T.Register) then return end
local G=L.Log

L.GUIDE_ID="combattext"
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
        {title="Combat Log filter",icon="Interface\\Icons\\INV_Misc_Spyglass_03",
         text="The filter selected on the Combat Log tab decides which actions are reported. Combat Text reads it and never changes it.\n\n"
            .."It fits when \"Done By\" has only \"Me\", as in WoW's default filter \"My actions\". Tick \"Pet\" as well if your pet's hits should count as yours. "
            .."Any other source (Friends, Enemy Units, ...) would make their hits look like yours, so Combat Text then does not use the Combat Log.\n\n"
            .."To change it: right-click the Combat Log tab, Settings, select the filter, Message Sources, set \"Done By\", Okay. Message types do not matter.",
         check=function()
            local s=G:Status()
            local name=s.filterName and "\""..s.filterName.."\" " or ""
            return G.USABLE[s.filter] and "done" or "open",name..G.FILTER_TEXT[s.filter]
         end},
        {title="Whose numbers",icon="Interface\\Icons\\Ability_Hunter_Pet_Wolf",
         text="Per area (open world, dungeons, raids, battlegrounds) you choose under \"Whose numbers\":\n\n"
            .."Only mine: your hits.\n"
            .."Mine, others dimmed: also hits of others on enemies fighting you or your group (pet, group, Thorns), in grey and see-through.\n"
            .."All, full color: every number on enemies.\n\n"
            .."Without the Combat Log every hit on an enemy that fights you counts as yours.",
         action={label="Open Combat Text settings",run=function() ns.Config:OpenPage("combattext") end}},
        {shared="cooldownmanager"},
        {title="Spell icons (optional)",icon="Interface\\Icons\\INV_Misc_QuestionMark",
         text="Under Experimental, Combat Text can guess which of your spells caused a hit and show its icon. It learns each spell's damage type and tick rhythm from your fights.\n\n"
            .."Damage over time is recognised by its tick rhythm, because auras on enemies cannot be read in combat.\n\n"
            .."Done: you can open this guide again in the Combat Text settings or with /bv guide combattext.",
         action={label="Open Combat Text settings",run=function() ns.Config:OpenPage("combattext") end}},
    },
})
