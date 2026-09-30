local _,A=...
if A.blocked then return end
local ns,G=BVAddonSuiteCore,A.G
local S=ns.AuraStudio
-- Studio is published through the module below; capabilities are pure catalog data.
local T={};A.NodeTesting=T;S.nodeTesting=T
function T.Ports(def)
    local ports={}
    if def.sink or not (def.source or def.nativeEvent or def.auraSource or def.unitSource or def.dataSource or def.inputs.active and def.outputs.event) then return ports end
    for _,key in ipairs(G.Ordered(def.outputs)) do
        local p=def.outputs[key]
        if ({boolean=true,event=true,string=true,integer=true,float=true,timestamp=true})[p.type] then ports[#ports+1]={value=key,label=p.label or key,kind=p.type} end
    end
    return ports
end
function T.Start(studio,id,values,mode,fire)
    local rec=studio:Graph();local plan,why=G.Compile(rec.draft,A.catalog)
    if not plan then studio.message=G.DescribeError(rec.draft,A.catalog,why);studio.messageError=studio.message;studio:Changed();return false end
    local def=plan.definitions[id];if not def or #T.Ports(def)==0 then return false end
    if not studio.test or studio.test.draftRevision~=rec.draftRevision then
        studio:EndTest();studio.test=studio:MakeRun(rec,plan,true)
        studio.test.draftRevision=rec.draftRevision
        studio.test.nodeOverrides={}
        studio:Schedule(studio.test,studio:Sample("initial"),"initial")
    end
    local run=studio.test
    local captured={}
    for _,p in ipairs(T.Ports(def)) do
        local value=values[p.value]
        if not G.IsSecret(value) and (p.kind=="event" and type(value)=="boolean" or G.Accepts(p.kind,value)) then captured[p.value]=value end
    end
    run.nodeOverrides[id]={values=captured,mode=mode,fire=fire==true}
    studio:Schedule(run,{nodeTest={id=id,values=G.Copy(captured),fire=fire==true}},"node_test:"..id);studio:Changed();return true
end
function T.Freeze(studio,id)
    if studio.test and studio.test.nodeOverrides and studio.test.nodeOverrides[id] then
        studio.test.nodeOverrides[id]=nil
        if not next(studio.test.nodeOverrides) then studio:EndTest()
        else studio:Schedule(studio.test,studio:Sample("initial"),"test") end
        studio:Changed();return
    end
    local _,run=studio:Trace();local values=run and run.values[id]
    if not values then studio.message="No readable observation to freeze";studio:Changed();return end
    local node=studio:Draft().nodes[id];local observed=run.plan and run.plan.graph.nodes[id]
    if not observed or observed.type~=node.type or not ns.DisplayModel.Equal(observed.config,node.config) or not ns.DisplayModel.Equal(observed.values,node.values) then
        studio.message="Source configuration changed; collect a matching observation or use Test Mode";studio:Changed();return
    end
    local readable=false
    for _,p in ipairs(T.Ports(G.Definition(A.catalog[node.type],node))) do
        local value=values[p.value]
        if value~=nil and not G.IsSecret(value) and (p.kind=="event" and type(value)=="boolean" or G.Accepts(p.kind,value)) then readable=true;break end
    end
    if not readable then studio.message="No readable observation to freeze";studio:Changed();return end
    return T.Start(studio,id,values,"freeze",false)
end
function T.Dialog(editor,studio,id)
    local UI,D=ns.UI,ns.DesignSystem.Metrics
    if editor.nodeTestDialog then editor.nodeTestDialog:Hide() end
    local rec=studio:Graph();local node=rec.draft.nodes[id];local def=G.Definition(A.catalog[node.type],node)
    local ports=T.Ports(def);if #ports==0 then return end
    local dialog=UI:Dialog(nil,440,286,editor.window);editor.nodeTestDialog=dialog
    local _,run=studio:Trace();local values=G.Copy(run and run.values[id] or {})
    local chosen=ports[1]
    UI:Place(UI:Label(dialog,"Test Mode / "..def.label,17,"text",true),dialog,16,14)
    local note=UI:Place(UI:Label(dialog,"Set readable outputs for this node. Other outputs remain unavailable. Event outputs fire only with Trigger once.",12,"muted"),dialog,16,48);D.Size(note,408,42)
    local input=UI:Place(UI:Input(dialog,408),dialog,16,142);input:SetAutoFocus(false)
    local toggle=UI:Place(UI:Switch(dialog,false),dialog,16,146)
    local function show()
        local boolean=chosen.kind=="boolean" or chosen.kind=="event"
        input:SetShown(not boolean);toggle:SetShown(boolean)
        input:SetText(tostring(values[chosen.value] or ""));toggle:SetValue(values[chosen.value]==true)
    end
    local function commit()
        local value
        if chosen.kind=="boolean" or chosen.kind=="event" then value=toggle.value
        elseif chosen.kind=="string" then value=input:GetText() else value=tonumber(input:GetText()) end
        if chosen.kind~="event" and not G.Accepts(chosen.kind,value) then note:SetText("Enter a valid "..chosen.kind.." value.");return false end
        values[chosen.value]=value;return true
    end
    local select=UI:Place(UI:Dropdown(dialog,408,ports,function(key)commit();for _,p in ipairs(ports) do if p.value==key then chosen=p end end;show()end),dialog,16,98)
    select:SetValue(chosen.value);show()
    local function valid() return studio:Graph()==rec and rec.draft.nodes[id]==node and not studio.inspectApplied end
    UI:Place(UI:Button(dialog,"Set values",126,function()if valid() and commit() then T.Start(studio,id,values,"test",false) end end,true),dialog,16,204)
    UI:Place(UI:Button(dialog,"Trigger once",126,function()if valid() and commit() then T.Start(studio,id,values,"test",true) end end),dialog,156,204)
    UI:Place(UI:Button(dialog,"Close",126,function()dialog:Hide()end),dialog,296,204)
    UI:Place(UI:Label(dialog,"Temporary draft preview. Live graph is unchanged.",11,"muted"),dialog,16,256)
    dialog:Show()
end
