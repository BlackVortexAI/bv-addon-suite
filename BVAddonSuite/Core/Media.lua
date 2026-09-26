local addonName, ns = ...
local root = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local Media = { fonts = {}, statusbars = {}, revision=0, listeners={}, optionCache={} }
ns.Media = Media

local fonts = {
    { "ysabeau", "Ysabeau", "Ysabeau-Regular.ttf" },
    { "ysabeauBold", "Ysabeau Bold", "Ysabeau-Bold.ttf", "BV Ysabeau Bold" },
    { "alegreyaSans", "Alegreya Sans", "AlegreyaSans-Regular.ttf" },
    { "alegreyaSansBold", "Alegreya Sans Bold", "AlegreyaSans-Bold.ttf", "BV Alegreya Sans Bold" },
    { "alegreya", "Alegreya", "Alegreya-Regular.ttf" },
    { "alegreyaBold", "Alegreya Bold", "Alegreya-Bold.ttf", "BV Alegreya Bold" },
}
local bars = {
    { "flat", "Alu One Flat", "alu-one-flat" },
    { "bevel", "Alu One Bevel", "alu-one-bevel" },
    { "gradient", "Alu One Gradient", "alu-one-gradient" },
    { "gradientBevel", "Alu One Gradient Bevel", "alu-one-gradient-bevel" },
    { "softLight", "Alu One Soft Light", "alu-one-soft-light" },
    { "softLightBevel", "Alu One Soft Light Bevel", "alu-one-soft-light-bevel" },
}

function Media:Initialize()
    local lsm = LibStub("LibSharedMedia-3.0")
    for _, entry in ipairs(fonts) do
        local path = root .. "Fonts\\" .. entry[3]
        self.fonts[entry[1]] = path
        -- These bundled families contain Latin and Cyrillic, not CJK glyph sets.
        -- Preserve existing Regular handles; new faces use the compact BV prefix.
        lsm:Register("font", entry[4] or ("BV Addon Suite - " .. entry[2]), path, lsm.LOCALE_BIT_western + lsm.LOCALE_BIT_ruRU)
    end
    for _, entry in ipairs(bars) do
        local path = root .. "StatusBars\\" .. entry[3] .. ".tga"
        self.statusbars[entry[1]] = path
        lsm:Register("statusbar", "BV " .. entry[2], path)
    end
    self.lsm=lsm
    if not self.registered then
        self.registered=true
        lsm.RegisterCallback(self,"LibSharedMedia_Registered",function(_,kind,key)
            if kind~="font" and kind~="statusbar" and kind~="sound" then return end
            self.revision=self.revision+1;self.optionCache[kind]=nil
            for owner,callback in pairs(self.listeners) do callback(owner,kind,key) end
        end)
    end
    self.revision=self.revision+1;self.optionCache={}
    -- Deliberately no SetDefault/SetGlobal: other addons own their own selection.
end

-- Persistent selections are exact identifiers, independent of another addon's
-- LSM global override. Availability is separate from reference validity.
function Media:Reference(kind,id)
    if kind~="font" and kind~="statusbar" and kind~="sound" then return false end
    if ns.GraphValues.IsSecret(id) or type(id)~="string" or #id<1 or #id>132 or id:find("[%c|]") then return false end
    if kind=="font" and id=="default" then return true end -- Historical plain-media fallback alias.
    if id:sub(1,4)=="lsm:" then return #id>4 end
    if kind=="sound" then return false end
    for _,entry in ipairs(kind=="font" and fonts or bars) do if entry[1]==id then return true end end
    return false
end
function Media:Resolve(kind,id)
    local builtin=kind=="font" and self.fonts or self.statusbars
    local valid=self:Reference(kind,id)
    local path=valid and builtin[id]
    if valid and kind=="font" and id=="default" then path=self.fonts.ysabeau end
    if not path and valid and id:sub(1,4)=="lsm:" and self.lsm then
        local entries=self.lsm:HashTable(kind)
        path=entries and entries[id:sub(5)]
    end
    if not ns.GraphValues.IsSecret(path) and (type(path)=="string" and path~="" or kind=="statusbar" and type(path)=="number" and path>0 and path<math.huge and path==math.floor(path)) then return path,"ready" end
    return builtin[kind=="font" and "ysabeau" or "flat"],"missing; bundled fallback"
end
function Media:Font(id) return self:Resolve("font",id) end
function Media:StatusBar(id) return self:Resolve("statusbar",id) end
function Media:Subscribe(owner,callback)
    assert(owner and type(callback)=="function","Invalid media listener")
    self.listeners[owner]=callback
    return function()if self.listeners[owner]==callback then self.listeners[owner]=nil end end
end
function Media:Unsubscribe(owner) self.listeners[owner]=nil end
function Media:Options(kind,inherit)
    local cached=self.optionCache[kind]
    if not cached then
        cached={};local builtins=kind=="sound" and {} or kind=="font" and fonts or bars
        for _,entry in ipairs(builtins) do
            cached[#cached+1]={value=entry[1],label=entry[2],font=kind=="font" and entry[1] or nil,texture=kind=="statusbar" and self.statusbars[entry[1]] or nil}
        end
        local names={}
        for name in pairs(self.lsm and self.lsm:HashTable(kind) or {}) do
            if self:Reference(kind,"lsm:"..name) then names[#names+1]=name end
        end
        table.sort(names)
        for _,name in ipairs(names) do
            local ref="lsm:"..name
            cached[#cached+1]={value=ref,label=name,font=kind=="font" and ref or nil,texture=kind=="statusbar" and self:StatusBar(ref) or nil}
        end
        self.optionCache[kind]=cached
    end
    local options=inherit and {{value="inherit",label=kind=="font" and "Use global font" or "Use global texture"}} or {}
    -- Callers may append a missing-reference row without mutating the catalog.
    for _,entry in ipairs(cached) do local row={};for k,v in pairs(entry)do row[k]=v end;options[#options+1]=row end
    return options
end
function Media:FontOptions(inherit) return self:Options("font",inherit) end
function Media:BarOptions(inherit) return self:Options("statusbar",inherit) end
function Media:SoundOptions() return self:Options("sound") end
function Media:Sound(id)
    if not self:Reference("sound",id) then return nil,"invalid sound reference" end
    local entries=self.lsm and self.lsm:HashTable("sound")
    local file=entries and entries[id:sub(5)]
    if ns.GraphValues.IsSecret(file) then return nil,"sound unavailable" end
    if file==1 then return nil,"no sound selected" end -- LSM's explicit None sentinel.
    if type(file)=="number" and file>1 and file<2147483648 and file==math.floor(file) then return file,"ready" end
    if type(file)=="string" and #file>0 and #file<=512 and not file:find("[%c|]") then return file,"ready" end
    return nil,"SharedMedia sound missing"
end
