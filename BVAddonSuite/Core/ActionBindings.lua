-- Exact hardware bindings; every modifier combination is explicit.
local _,ns=...
local A,V=ns.Actions,ns.GraphValues
A.bindings={};A.bindingOrder={}
local buttons={{'left','LeftButton','Left Click',1},{'right','RightButton','Right Click',2},{'middle','MiddleButton','Middle Click',3},{'button4','Button4','Button 4',4},{'button5','Button5','Button 5',5}}
for mask=0,7 do for _,b in ipairs(buttons) do
    local alt=mask%2==1;local ctrl=math.floor(mask/2)%2==1;local shift=math.floor(mask/4)%2==1
    local prefix=(alt and 'alt-' or '')..(ctrl and 'ctrl-' or '')..(shift and 'shift-' or '')
    local key=prefix:gsub('-','_')..b[1]
    A.bindings[key]={key=key,button=b[2],number=b[4],prefix=prefix,
        label=(alt and 'Alt+' or '')..(ctrl and 'Ctrl+' or '')..(shift and 'Shift+' or '')..b[3]}
    A.bindingOrder[#A.bindingOrder+1]=key
end end
function A.HardwareKey(button)
    if V.IsSecret(button) then return end
    local mask=0
    for _,v in ipairs({{IsAltKeyDown,1},{IsControlKeyDown,2},{IsShiftKeyDown,4}}) do
        local value=v[1] and v[1]() or false;if V.IsSecret(value) then return end
        if value then mask=mask+v[2] end
    end
    for _,b in ipairs(buttons) do if b[2]==button then return A.bindingOrder[mask*5+b[4]] end end
end
function A.BindingMap(action)
    return action and action.kind=='bindings' and action.bindings or action and {left=action} or {}
end
function A.Mode(action)
    for _,a in pairs(A.BindingMap(action)) do if a.kind~='click' and a.kind~='ui' and a.kind~='group' then return 'secure' end end
    return 'local'
end
function A.HasMacro(action)
    for _,a in pairs(A.BindingMap(action)) do if a.kind=='macro' then return true end end
end
function A.BindingSame(a,b)
    local function identity(v)
        if not v then return end
        local out={};for key,action in pairs(A.BindingMap(v)) do
            out[key]={};for k,value in pairs(action) do if k~='payload' then out[key][k]=value end end
        end;return out
    end
    return ns.DisplayModel.Equal(identity(a),identity(b))
end
local prepare=A.Prepare
function A.Prepare(action)
    if not A.Valid(action) then return nil,'Invalid action' end
    if action.kind~='bindings' then
        local attrs,why,mode=prepare(action)
        if not attrs then return nil,why,mode end
        -- Empty type is deliberate: modified lookup must not reach *type1.
        for _,key in ipairs(A.bindingOrder) do local b=A.bindings[key]
            if key~='left' then attrs[b.prefix..'type'..b.number]='' end
        end
        return attrs,why,mode
    end
    local out={};local issues={}
    for _,key in ipairs(A.bindingOrder) do local b=A.bindings[key]
        out[b.prefix..'type'..b.number]=''
        local a=action.bindings[key]
        if a then
            local attrs,why,mode=prepare(a)
            if why then issues[#issues+1]=b.label..': '..why end
            if attrs and mode=='secure' then
                for k,value in pairs(attrs) do out[b.prefix..(k=='*type1' and 'type' or k)..b.number]=value end
            end
        end
    end
    return out,#issues>0 and table.concat(issues,'; ') or nil,A.Mode(action)
end
function A.ExecuteClick(action,owner,button)
    if not action or not owner or owner.test or owner.stopped then return false,'inactive' end
    if action.kind~='click' then return A.ExecuteLocal(action) end
    if not A.Valid(action) then return false,'Invalid click action' end
    local key=A.HardwareKey(button);local b=key and A.bindings[key]
    if not b then return false,'unsupported input' end
    local packet={key=action.key,button=button,payload=action.payload,
        alt=b.prefix:find('alt-',1,true)~=nil,control=b.prefix:find('ctrl-',1,true)~=nil,shift=b.prefix:find('shift-',1,true)~=nil}
    local accepted=ns.DisplayAnchors.inputHandler and ns.DisplayAnchors.inputHandler(owner,packet)
    return accepted~=false,'click event'
end
