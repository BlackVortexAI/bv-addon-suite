local addonName, ns = ...
local lifecycle = {}

local cvarGuard = {}
local function restoreCVars()
    if not (InCombatLockdown and InCombatLockdown()) then ns.Settings:RestoreUnclaimedCVars();return end
    ns.Events:Subscribe(cvarGuard, "PLAYER_REGEN_ENABLED", function()
        ns.Events:Release(cvarGuard)
        ns.Settings:RestoreUnclaimedCVars()
    end)
end

local function login()
    ns.Modules:Reconcile()
    ns.UI.MinimapLauncher:Initialize()
    -- Every package has loaded by now; game settings of missing ones go back.
    ns:Call("cvar-guard", restoreCVars)
    -- Guides of packages not finished yet (Core/Tutorial.lua).
    ns:Call("tutorial", function() ns.Tutorial:Offer() end)
end

local function initialize()
    BVAddonSuiteDB = ns.Settings:Initialize(BVAddonSuiteDB)
    ns.Media:Initialize()
    ns.IconSkins:Masque()
    ns.ready = true
    SLASH_BVADDONSUITE1 = "/bv"
    SLASH_BVADDONSUITE2 = "/bvs"
    SlashCmdList.BVADDONSUITE = function(message) ns:Call("command", ns.Commands.Run, ns.Commands, message) end
    if IsLoggedIn() then login()
    else
        ns.Events:Subscribe(lifecycle, "PLAYER_LOGIN", function()
            ns.Events:Release(lifecycle)
            login()
        end)
    end
end

ns.Events:Subscribe(lifecycle, "ADDON_LOADED", function(_, loadedName)
    if loadedName ~= addonName then return end
    ns.Events:Release(lifecycle)
    ns:Call("bootstrap", initialize)
end)
