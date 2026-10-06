-- Guide for Core's guide window (Core 0.8.94+, Core/Tutorial.lua): the
-- Cooldown Manager (a step shared with other packages, shown once) and the
-- wiki. Optional: with an older Core there is no guide and nothing changes.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local T=ns.Tutorial
if not (T and T.Register and T.RegisterShared) then return end

T:Register({
    id="aurastudio",
    title="AuraStudio",
    version=1,
    module="aura_studio",
    steps={
        {title="Welcome",icon="Interface\\Icons\\Spell_Holy_MagicalSentry",
         text="AuraStudio builds your own displays from nodes: icons, bars, texts and sounds that react to your buffs, cooldowns, resources and more.\n\n"
            .."Open it with /bv aura. Each node shows what it needs and what it gives; the wiki explains every node.\n\n"
            .."The next steps show what AuraStudio needs from the game and where to find help."},
        {shared="cooldownmanager"},
        {title="The wiki",icon="Interface\\Icons\\INV_Misc_Book_11",
         text="The wiki explains AuraStudio step by step: first displays, every node with its inputs and outputs, and what works in combat on WoW Forever.\n\n"
            .."Open it with the button below, or with the Wiki button in the editor. A node's own page: its \"i\" button, or right-click its heading and choose Wiki.\n\n"
            .."Done: you can open this guide again with /bv guide aurastudio.",
         action={label="Open the wiki",run=function() if ns.AuraStudio and ns.AuraStudio.OpenWiki then ns.AuraStudio:OpenWiki("page:start") end end}},
    },
})
