local _, ns = ...
local Settings = { profileListeners = {}, afterProfileListeners={} }
ns.Settings = Settings

local defaults = { font = "ysabeau", themeKey = "violet", accent = "verdant", scale = 1, tooltips = true, statusbar = "flat", inspectorGap = 100, gridSize = 16, snapToGrid = true, snapToElements = true }
local choices = {
    themeKey = { violet=true, ember=true, tide=true },
    font = { ysabeau = true, ysabeauBold = true, alegreyaSans = true, alegreyaSansBold = true, alegreya = true, alegreyaBold = true },
    accent = { verdant = true, violet = true, ember = true },
    statusbar = { flat = true, bevel = true, gradient = true, gradientBevel = true, softLight = true, softLightBevel = true },
    gridSize = { [8]=true, [16]=true, [24]=true, [32]=true, [48]=true, [64]=true },
}

local function valid(key, value)
    if key == "font" or key == "statusbar" then return ns.Media:Reference(key, value) == true end
    if key == "inspectorGap" then return type(value)=="number" and value>=20 and value<=400 end
    if key == "gridSize" then return type(value)=="number" and choices.gridSize[value]==true end
    if choices[key] then return type(value) == "string" and choices[key][value] == true end
    if key == "scale" then return type(value) == "number" and value >= 0.5 and value <= 1.3 end
    if key == "tooltips" or key == "snapToGrid" or key == "snapToElements" then return type(value) == "boolean" end
    return false
end

local function normalize(profile)
    if type(profile) ~= "table" then profile = {} end
    if type(profile.ui) ~= "table" then profile.ui = {} end
    if type(profile.modules) ~= "table" then profile.modules = {} end
    for key, value in pairs(defaults) do
        if not valid(key, profile.ui[key]) then profile.ui[key] = value end
    end
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
    db.profiles.Default = normalize(db.profiles.Default)
    if type(db.activeProfile) ~= "string" or type(db.profiles[db.activeProfile]) ~= "table" then
        db.activeProfile = "Default"
    end
    db.profiles[db.activeProfile] = normalize(db.profiles[db.activeProfile])
    self.db = db
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
    if ns.Layout then ns.Layout:Refresh() end
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end

function Settings:Set(key, value)
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
    self.profileListeners[owner]=callback
end
function Settings:AfterProfileChange(owner,callback)
    assert(owner and type(callback)=="function","Invalid profile listener")
    self.afterProfileListeners[owner]=callback
end

function Settings:SelectProfile(name)
    assert(type(name) == "string" and type(self.db.profiles[name]) == "table", "Unknown profile")
    if name == self.db.activeProfile then return end
    assert(not (ns.Layout and ns.Layout.draft), "Save or discard the layout editor before switching profiles")
    for _,callback in pairs(self.profileListeners) do ns:Call("profile/leave",callback) end
    -- Tear down old-profile resources before exposing the new profile.
    if ns.ProgressBars then ns.ProgressBars:ClosePreviews() end
    ns.Modules:StopAll()
    self.db.activeProfile = name
    self.db.profiles[name] = normalize(self.db.profiles[name])
    ns.Modules:Reconcile()
    self:Changed()
    for _,callback in pairs(self.afterProfileListeners) do ns:Call("profile/enter",callback) end
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
