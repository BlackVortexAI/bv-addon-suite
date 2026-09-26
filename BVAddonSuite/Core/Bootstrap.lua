local addonName, ns = ...
local lifecycle = {}

local function login()
    ns.Modules:Reconcile()
    ns.UI.MinimapLauncher:Initialize()
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
