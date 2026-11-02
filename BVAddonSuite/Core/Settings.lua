local _, ns = ...
local Settings = { profileListeners = {}, afterProfileListeners={} }
ns.Settings = Settings

local defaults = { font = "alegreyaSansBold", themeKey = "violet", accent = "verdant", scale = 1, tooltips = true, statusbar = "softLightBevel", inspectorGap = 100, gridSize = 16, snapToGrid = true, snapToElements = false,
    -- Gameplay family uses themeKey for its BV palette; tools use interfaceTheme.
    -- gameMatchUI: only read once to move an old switch to the family "match".
    gameFamily = "bv", gameMatchUI = false,
    interfaceTheme="clean", interfaceAccent="", interfaceSurface="atlas", interfaceSurfaceArea="full", interfaceSurfaceStrength=15 }
local choices = {
    themeKey = { violet=true, ember=true, tide=true },
    gameFamily = { bv=true, wow=true, clean=true, match=true },
    font = { ysabeau = true, ysabeauBold = true, alegreyaSans = true, alegreyaSansBold = true, alegreya = true, alegreyaBold = true },
    accent = { verdant = true, violet = true, ember = true },
    statusbar = { flat = true, bevel = true, gradient = true, gradientBevel = true, softLight = true, softLightBevel = true },
    gridSize = { [8]=true, [16]=true, [24]=true, [32]=true, [48]=true, [64]=true },
}

local function valid(key, value)
    if key=="interfaceTheme" then return type(value)=="string" and ns.ThemeTokens and ns.ThemeTokens.themes[value]~=nil end
    if key=="interfaceAccent" then return type(value)=="string" and (value=="" or value:match("^%x%x%x%x%x%x$")~=nil) end
    if key=="interfaceSurface" then return type(value)=="string" and ({none=true,relief=true,atlas=true,mist=true,patina=true,horde=true,alliance=true})[value]==true end
    if key=="interfaceSurfaceArea" then return value=="casing" or value=="full" end
    if key=="interfaceSurfaceStrength" then return type(value)=="number" and value>=0 and value<=50 and value%5==0 end
    if key == "font" or key == "statusbar" then return ns.Media:Reference(key, value) == true end
    if key == "inspectorGap" then return type(value)=="number" and value>=20 and value<=400 end
    if key == "gridSize" then return type(value)=="number" and choices.gridSize[value]==true end
    if choices[key] then return type(value) == "string" and choices[key][value] == true end
    if key == "scale" then return type(value) == "number" and value >= 0.5 and value <= 1.3 end
    if key == "tooltips" or key == "snapToGrid" or key == "snapToElements" or key == "gameMatchUI" then return type(value) == "boolean" end
    return false
end

-- Release cutover: only profiles that still use the former interface (including
-- pre-interface profiles) adopt the new bundle. Chosen families and all gameplay
-- preferences remain untouched; once clean is stored this operation is idempotent.
local function migrateInterface(profile)
    local ui=profile.ui
    if type(ui)~="table" then ui={};profile.ui=ui end
    if ui.interfaceTheme==nil or ui.interfaceTheme=="legacy" then
        ui.interfaceTheme=defaults.interfaceTheme
        ui.interfaceAccent=defaults.interfaceAccent
        ui.interfaceSurface=defaults.interfaceSurface
        ui.interfaceSurfaceArea=defaults.interfaceSurfaceArea
        ui.interfaceSurfaceStrength=defaults.interfaceSurfaceStrength
    end
    -- Former valid strengths above the new slider limit keep the closest
    -- available value. Invalid data still follows ordinary normalization.
    local strength=ui.interfaceSurfaceStrength
    if type(strength)=="number" and strength>50 and strength<=70 and strength%5==0 then
        ui.interfaceSurfaceStrength=50
    end
end

local function normalize(profile)
    if type(profile) ~= "table" then profile = {} end
    migrateInterface(profile)
    if type(profile.modules) ~= "table" then profile.modules = {} end
    for key, value in pairs(defaults) do
        if not valid(key, profile.ui[key]) then profile.ui[key] = value end
    end
    profile.ui.interfaceAccent=profile.ui.interfaceAccent:upper()
    return profile
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

function Settings:Initialize(db)
    if type(db) ~= "table" then db = {} end
    if db.schema ~= nil and db.schema ~= 1 then
        error("Unsupported settings schema; existing data was left untouched")
    end
    db.schema = 1
    if type(db.profiles) ~= "table" then db.profiles = {} end
    -- Migrate inactive selectable profiles too, without normalizing unrelated fields.
    for name,profile in pairs(db.profiles) do
        if type(name)=="string" and type(profile)=="table" then migrateInterface(profile) end
    end
    -- Only a missing default profile receives the curated shipping preset.
    -- Existing profiles (including intentional empty/disabled configurations)
    -- keep their choices. A new named profile still copies the active profile.
    if type(db.profiles.Default) ~= "table" then
        db.profiles.Default = copy(ns.FactoryDefaults.profile)
        if db.windowPositions == nil then
            db.windowPositions = copy(ns.FactoryDefaults.windowPositions)
        end
    end
    db.profiles.Default = normalize(db.profiles.Default)
    if type(db.activeProfile) ~= "string" or type(db.profiles[db.activeProfile]) ~= "table" then
        db.activeProfile = "Default"
    end
    db.profiles[db.activeProfile] = normalize(db.profiles[db.activeProfile])
    self.db = db
    if ns.Config then ns.Config:EnsureShellStyle() end
    return db
end

function Settings:Profile() return self.db.profiles[self.db.activeProfile] end
function Settings:Get(key) return self:Profile().ui[key] end

function Settings:ListProfiles()
    local result = {}
    for name, profile in pairs(self.db.profiles) do
        -- Keep unrecognized saved data intact, but never expose it as a selectable profile.
        if type(name) == "string" and type(profile) == "table" then
            result[#result + 1] = { value = name, label = name }
        end
    end
    table.sort(result, function(a, b) return a.label < b.label end)
    return result
end

function Settings:Changed()
    if ns.Config then ns.Config:SyncInterfaceSettings() end
    if ns.Layout then ns.Layout:Refresh() end
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end

function Settings:Set(key, value)
    if key=="interfaceAccent" and type(value)=="string" then value=value:upper() end
    assert(valid(key, value), "Invalid UI setting: " .. tostring(key))
    if self:Get(key) == value then return end
    self:Profile().ui[key] = value
    self:Changed()
end

function Settings:CreateProfile(name)
    assert(type(name) == "string", "Profile name must be text")
    name = name:match("^%s*(.-)%s*$")
    assert(#name > 0 and #name <= 48 and not name:find("[%c|]"), "Invalid profile name")
    assert(self.db.profiles[name] == nil, "Profile already exists")
    self.db.profiles[name] = copy(self:Profile())
    return name
end

function Settings:BeforeProfileChange(owner,callback)
    assert(owner and type(callback)=="function","Invalid profile listener")
    -- A registration token distinct even when the same owner/callback is reused.
    local registration=function(...)return callback(...)end
    self.profileListeners[owner]=registration
    return function()
        if self.profileListeners[owner]==registration then self.profileListeners[owner]=nil end
    end
end
function Settings:AfterProfileChange(owner,callback)
    assert(owner and type(callback)=="function","Invalid profile listener")
    self.afterProfileListeners[owner]=callback
end

local function activateProfile(self,name,profile)
    for _,callback in pairs(self.profileListeners) do ns:Call("profile/leave",callback) end
    -- Tear down old-profile resources before exposing the new profile.
    if ns.ProgressBars then ns.ProgressBars:ClosePreviews() end
    ns.Modules:StopAll()
    self.db.activeProfile = name
    self.db.profiles[name] = normalize(profile)
    ns.Modules:Reconcile()
    self:Changed()
    for _,callback in pairs(self.afterProfileListeners) do ns:Call("profile/enter",callback) end
end

function Settings:SelectProfile(name)
    assert(type(name) == "string" and type(self.db.profiles[name]) == "table", "Unknown profile")
    if name == self.db.activeProfile then return end
    assert(not (ns.Layout and ns.Layout.draft), "Save or discard the layout editor before switching profiles")
    activateProfile(self,name,self.db.profiles[name])
end

function Settings:CopyFromProfile(source)
    assert(type(source)=="string" and type(self.db.profiles[source])=="table", "Unknown source profile")
    assert(source~=self.db.activeProfile, "Choose another source profile")
    assert(not InCombatLockdown(), "Leave combat before copying a profile")
    assert(not (ns.Layout and ns.Layout.draft), "Save or discard the layout editor before copying a profile")
    -- Snapshot before teardown: listeners still see the old target while they
    -- release its resources. Neither profile shares nested configuration tables.
    local replacement=copy(self.db.profiles[source])
    activateProfile(self,self.db.activeProfile,replacement)
end

function Settings:ResetAppearance()
    self:Profile().ui = copy(defaults)
    self:Changed()
end

function Settings:Module(id)
    local modules = self:Profile().modules
    if type(modules[id]) ~= "table" then modules[id] = {} end
    return modules[id]
end

-- Client settings (CVars) a package turned off, with the values found before.
-- The client keeps CVars after an addon is disabled or deleted, so the package
-- reports them here; at login Core gives them back for every package that did
-- not load (GitHub issue 1: Blizzard's damage numbers stayed off). Only values
-- still at "0", the value the package set, are given back.
Settings.cvarClaims = {}
function Settings:HoldCVars(owner, values)
    local guard = type(self.db.cvarGuard) == "table" and self.db.cvarGuard or {}
    local kept = {}
    for name, value in pairs(type(values) == "table" and values or {}) do
        if type(name) == "string" and type(value) == "string" then kept[name] = value end
    end
    guard[owner] = next(kept) and kept or nil
    self.db.cvarGuard = next(guard) and guard or nil
end
-- A package that loaded handles its own values.
function Settings:ClaimCVars(owner) self.cvarClaims[owner] = true end
function Settings:RestoreUnclaimedCVars()
    local guard = self.db.cvarGuard
    if type(guard) ~= "table" then return end
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    for owner, values in pairs(guard) do
        if not self.cvarClaims[owner] then
            local restored = {}
            for name, value in pairs(type(values) == "table" and values or {}) do
                local ok, current = pcall(get, name)
                if ok and current == "0" and value ~= "0" and pcall(set, name, value) then restored[#restored + 1] = name end
            end
            guard[owner] = nil
            if #restored > 0 then
                table.sort(restored)
                ns:Print(tostring(owner) .. " is not loaded: restored the game settings it had turned off (" .. table.concat(restored, ", ") .. ").")
            end
        end
    end
    self.db.cvarGuard = next(guard) and guard or nil
end
