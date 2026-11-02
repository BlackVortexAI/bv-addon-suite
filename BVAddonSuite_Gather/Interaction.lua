local _,G=...
if not G.ready then return end
-- One real client-selected object, never a projected database spawn. All
-- queries may be absent/restricted on another client; unknown is not ready.
local I={owned={},declined={}}
G.Interaction=I
local UNIT="softinteract"
local function read(path,...)
    local value=G.Call(path,...)
    if not G.Secret(value) then return value end
end
I.Read=read
local CURSORS={Mine={kind="ore"},UnableMine={kind="ore",blocked=true},
    GatherHerbs={kind="herb"},UnableGatherHerbs={kind="herb",blocked=true}}
local function namedCursor(value)
    if G.Secret(value) or type(value)~="string" then return nil end
    local name=(value:gsub("/","\\"):match("([^\\]+)$") or ""):lower()
    name=name:gsub("%.[^%.]+$","")
    -- Native Forever GetTexture returns a single logical texture name such
    -- as "Cursor Crosshair_GatherHerbs_64"; GetAtlas may be nil. Strip the
    -- texture namespace before decoding the cursor action. An atlas region
    -- supplied separately on another client uses the same action naming.
    name=name:gsub("^cursor%s+","")
    name=name:match("^crosshair_(%a+)_%d+$") or name
    for key,item in pairs(CURSORS) do if name==key:lower() then return item end end
end
local CVARS={SoftTargetInteract="3",SoftTargetNameplateInteract="1",SoftTargetInteractRange="60",SoftTargetInteractArc="2",SoftTargetInteractOnlyInRange="0"}

function I:Supported()
    return type(SetUnitCursorTexture)=="function" and type(UnitIsGameObject)=="function"
end
function I:Wanted()
    local c=G:Config()
    return self.active and self:Supported() and (c.objectMark~="off" or c.interactHint)
end
function I:Cursor()
    if not self.probe then
        self.probe,self.texture=G.InteractionView:Probe()
        self.cursorIDs={}
        for name,data in pairs(CURSORS) do
            local path="Interface\\CURSOR\\"..name
            local id=read("GetFileIDFromPath",path)
            if not id or id==0 then self.texture:SetTexture(path);id=self.texture:GetTexture() end
            if id and not G.Secret(id) then self.cursorIDs[id]=data end
        end
    end
    self.texture:SetTexture(nil)
    local ok,result=pcall(SetUnitCursorTexture,self.texture,UNIT,nil,true)
    if not ok or G.Secret(result) or result==false then return end
    local value=self.texture:GetTexture()
    local data
    if not G.Secret(value) then data=self.cursorIDs[value] or namedCursor(value) end
    if not data and self.texture.GetAtlas then
        local atlasOK,atlas=pcall(self.texture.GetAtlas,self.texture)
        if atlasOK then data=namedCursor(atlas) end
    end
    return data
end
function I.State(inRange,blocked)
    if inRange==false then return "far" end
    if blocked then return "blocked" end
    return inRange==true and "ready" or "unknown"
end
function I:Binding()
    local key=read("GetBindingKey","INTERACTTARGET")
    if type(key)~="string" or key=="" then return nil end
    return read("GetBindingText",key,"KEY_") or key
end
-- First Gather start for the current native binding set, not every login
-- or profile switch. Never overwrite a key or undo a later user removal.
function I:DefaultBinding()
    if not self.active or self.bindingBusy or not self:Supported() or read("IsLoggedIn")~=true or read("InCombatLockdown")==true then return end
    for _,name in ipairs({"GetBindingKey","GetBindingAction","GetCurrentBindingSet","SetBinding","SaveBindings"}) do
        if type(_G[name])~="function" then return end
    end
    local set=read("GetCurrentBindingSet")
    if set~=1 and set~=2 then return end
    local scope=set==1 and "account" or read("UnitGUID","player")
    if type(scope)~="string" or scope=="" then return end
    local db=G.Data.db or G.Data:Init()
    if type(db.interactBindingChecked)~="table" then db.interactBindingChecked={} end
    local checked=db.interactBindingChecked
    if checked[scope] then return end
    local ok,first,second=pcall(GetBindingKey,"INTERACTTARGET")
    if not ok or G.Secret(first) or G.Secret(second) then return end
    if (type(first)=="string" and first~="") or (type(second)=="string" and second~="") then checked[scope]=true;return end
    local taken=read("GetBindingAction","CTRL-G")
    local effective=read("GetBindingAction","CTRL-G",true)
    if type(taken)~="string" or type(effective)~="string" then return end
    if taken~="" or effective~="" then
        checked[scope]=true
        G:Print("Ctrl+G is already in use. Assign Interact Target in Key Bindings to gather with a key.")
        return
    end
    self.bindingBusy=true
    local assigned=read("SetBinding","CTRL-G","INTERACTTARGET")
    if assigned and read("GetBindingAction","CTRL-G")=="INTERACTTARGET" then
        local saved,result=pcall(SaveBindings,set)
        if saved and not G.Secret(result) and result~=false then
            checked[scope]=true
            G:Print("Ctrl+G now uses Interact Target. You can change it in Key Bindings.")
        else
            -- Only this previously free key was changed. Undo the unsaved
            -- assignment so a later startup can retry without a false success.
            if read("GetBindingAction","CTRL-G")=="INTERACTTARGET" then read("SetBinding","CTRL-G") end
            G:Print("Could not save the Interact Target key. Assign it in Key Bindings.")
        end
    end
    self.bindingBusy=nil
end
function I:Plate()
    local plate=read("C_NamePlate.GetNamePlateForUnit",UNIT)
    if plate then return plate end
    -- Some clients expose the object plate only through its nameplate token.
    -- Match identity, never just a resource name shared by nearby deposits.
    local guid=read("UnitGUID",UNIT)
    local plates=read("C_NamePlate.GetNamePlates")
    if type(guid)~="string" or type(plates)~="table" then return nil end
    for _,candidate in ipairs(plates) do
        local token=candidate.namePlateUnitToken or (candidate.UnitFrame and candidate.UnitFrame.unit)
        if type(token)=="string" and not G.Secret(token) and read("UnitGUID",token)==guid then return candidate end
    end
end
function I:Snapshot()
    if read("UnitIsGameObject",UNIT)~=true then return nil end
    local cursor=self:Cursor()
    if not cursor then return nil end
    local c=G:Config()
    if (cursor.kind=="herb" and not c.objectHerbs) or (cursor.kind=="ore" and not c.objectOre) then return nil end
    local name=read("UnitName",UNIT)
    if type(name)~="string" then name=cursor.kind=="herb" and "Herb" or "Ore" end
    local inRange=read("UnitIsInInteractRange",UNIT)
    return {kind=cursor.kind,name=name,state=self.State(inRange,cursor.blocked),inRange=inRange,
        guid=read("UnitGUID",UNIT),plate=self:Plate(),binding=self:Binding()}
end
-- Perspective approximation, not model bounds or a range measurement.
-- Reference: 15-yard camera zoom, nearby object. Without fresh scanner
-- evidence only camera zoom changes geometry. Boolean interact range must
-- never manufacture a size/offset step at the interaction radius.
local function number(value)
    return not G.Secret(value) and type(value)=="number" and value==value and value>=0 and value<math.huge
end
function I.MarkerScale(zoom,distance)
    zoom=number(zoom) and zoom or 15
    local scale
    if number(distance) then scale=20/(zoom+math.max(5,distance))
    else scale=20/(zoom+5) end
    return math.max(.45,math.min(1.6,scale))
end
function I:Appearance(target)
    if not target or not target.plate or G:Config().objectMark=="off" then self.motion=nil;return end
    local now=GetTime()
    local distance
    if type(target.guid)=="string" and G.Scanner and G.Scanner.DistanceEstimate then
        distance=G.Scanner:DistanceEstimate(target.name,target.kind,now)
    end
    local scale=self.MarkerScale(read("GetCameraZoom"),distance)
    local motion=self.motion
    if not motion or motion.guid~=target.guid or motion.plate~=target.plate or motion.name~=target.name or motion.kind~=target.kind then
        motion={guid=target.guid,plate=target.plate,name=target.name,kind=target.kind,value=scale}
        self.motion=motion
    else
        local dt=math.max(0,math.min(1,now-motion.at))
        motion.value=motion.value+(scale-motion.value)*(1-math.exp(-dt/.2))
    end
    motion.at=now
    target.markerScale=motion.value
    target.distance=distance -- nil without fresh, unambiguous evidence
    target.scaleSource=distance and "minimap estimate" or "camera zoom"
end
-- Change targeting only while enabled. An external change revokes ownership:
-- never fight another addon, and never restore over the user's newer value.
function I:Targeting(on)
    if read("InCombatLockdown")==true then self.pending=true;return end
    self.pending=nil
    local external=read("C_AddOns.IsAddOnLoaded","ForeverLootSparkles") or read("IsAddOnLoaded","ForeverLootSparkles")
    -- A newly loaded targeting owner may have adopted these exact values.
    -- Hand them over without restoring underneath its just-run setup.
    if external then self.owned={};return end
    on=on and G:Config().interactTargeting
    for key,desired in pairs(CVARS) do
        local current=read("GetCVar",key)
        local own=self.owned[key]
        if own and current~=own.written then self.owned[key]=nil;self.declined[key]=true;own=nil end
        if on then
            if not own and not self.declined[key] and current~=nil and tostring(current)~=desired then
                read("SetCVar",key,desired)
                if read("GetCVar",key)==desired then self.owned[key]={before=current,written=desired} end
            end
        elseif own then read("SetCVar",key,own.before);self.owned[key]=nil end
    end
end
function I:Refresh()
    self.current=self:Wanted() and self:Snapshot() or nil
    self:Appearance(self.current)
    if G.InteractionView then G.InteractionView:Paint(self.current) end
end
function I:Update()
    local wanted=self:Wanted()
    self:Targeting(wanted)
    if wanted and not self.ticker then self.ticker=C_Timer.NewTicker(.2,function() I:Refresh() end)
    elseif not wanted and self.ticker then self.ticker:Cancel();self.ticker=nil end
    self:Refresh()
end
function I:Enable(context)
    self.active=true;self.declined={}
    context:Defer(function()
        I.active=false;I:Update()
        if I.restore and not I.pending then I.restore:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    end)
    if not self:Supported() then return end
    -- This tiny restore listener survives disabling in combat until it can
    -- return CVars. It is reused and otherwise has no registered events.
    if not self.restore then
        self.restore=G.InteractionView:RestoreListener(function()
            I:Targeting(I:Wanted())
            if not I.active then I.restore:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        end)
    end
    self.restore:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED"}) do
        context:Subscribe(event,function() I:DefaultBinding();I:Refresh() end)
    end
    for _,event in ipairs({"PLAYER_SOFT_INTERACT_CHANGED","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","UPDATE_BINDINGS"}) do
        context:Subscribe(event,function()
            if event=="PLAYER_SOFT_INTERACT_CHANGED" then I.motion=nil end
            I:Refresh()
        end)
    end
    context:Subscribe("ADDON_LOADED",function() I:Update() end)
    context:Subscribe("PLAYER_LOGOUT",function() I:Targeting(false) end)
    self:DefaultBinding()
    self:Update()
end
