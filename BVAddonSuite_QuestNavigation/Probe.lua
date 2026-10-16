local _,N=...
if not N.ready then return end
-- QuestieDB probe (Florian 2026-10-15, quest navigation step 0; read only,
-- for development): for every quest of the log, what QuestieDB knows to
-- lead you there: giver, turn-in, objectives with their spawn points per
-- zone, the zone's map and Routing's continent point of the first spawn.
-- "/bv questnav probe" writes the report to the saved settings
-- (questieProbe) and prints a summary. Nothing else changes.
local ns=N.ns
local P={}
N.Probe=P

local function lib() return rawget(_G,"LibQuestieDB") end
local function clock() local t=rawget(_G,"debugprofilestop");return type(t)=="function" and t() or 0 end
-- Questie's own zone table (AreaID -> UiMapID), when Questie is loaded.
local function zoneDB()
    local loader=rawget(_G,"QuestieLoader")
    if type(loader)~="table" or type(loader.ImportModule)~="function" then return nil end
    local ok,zone=pcall(loader.ImportModule,loader,"ZoneDB")
    if ok and type(zone)=="table" and type(zone.GetUiMapIdByAreaId)=="function" then return zone end
    return nil
end
local function uiMap(zone,areaID)
    if not zone then return nil end
    local ok,id=pcall(zone.GetUiMapIdByAreaId,zone,areaID)
    return ok and type(id)=="number" and id or nil
end
-- Spawns {[areaID]={{x,y},...}}: count per zone, its map, the first point on its continent.
local function spawns(list,zone,report)
    local out,total={},0
    if type(list)~="table" then return out,0 end
    for areaID,points in pairs(list) do
        local count=type(points)=="table" and #points or 0
        total=total+count
        local row={area=areaID,count=count,map=uiMap(zone,areaID)}
        local first=type(points)=="table" and points[1]
        if type(first)=="table" and type(first[1])=="number" then
            row.x,row.y=first[1],first[2]
            local R=ns.Routing
            if row.map and R and R.OnContinent and first[1]>=0 then
                local ok,cont,cx,cy=pcall(R.OnContinent,R,row.map,first[1]/100,first[2]/100)
                if ok and cont then row.cont,row.cx,row.cy=cont,cx,cy else report.noContinent=(report.noContinent or 0)+1 end
            end
        end
        if not row.map then report.noMap=(report.noMap or 0)+1 end
        out[#out+1]=row
    end
    return out,total
end
local function get(entity,id,key)
    local ok,value=pcall(entity.Get,id,key)
    return ok and value or nil
end
-- NPCs and objects of a list of ids, each with its spawns.
local function places(L,kind,ids,zone,report,limit)
    local entity=kind=="npc" and L.Npc or L.Object
    local out={}
    for i,id in ipairs(type(ids)=="table" and ids or {}) do
        if i>(limit or 8) then out.more=#ids-(limit or 8);break end
        local id2=type(id)=="table" and id[1] or id
        if type(id2)=="number" and entity then
            local list,total=spawns(get(entity,id2,"spawns"),zone,report)
            local row={id=id2,name=get(entity,id2,"name"),spawns=total,zones=list}
            if kind=="npc" then row.friendly=get(entity,id2,"friendlyToFaction");row.moves=get(entity,id2,"waypoints")~=nil end
            out[#out+1]=row
        end
    end
    return out
end
local function quest(L,q,zone,report)
    local id=q.id
    local row={id=id,title=q.title,ready=q.ready==true}
    local okE,exists=pcall(L.Quest.Exists,id)
    row.known=okE and exists==true
    if not row.known then report.unknown=(report.unknown or 0)+1;return row end
    local started,finished=get(L.Quest,id,"startedBy"),get(L.Quest,id,"finishedBy")
    row.giver={npcs=places(L,"npc",started and started[1],zone,report,4),objects=places(L,"object",started and started[2],zone,report,4)}
    row.turnin={npcs=places(L,"npc",finished and finished[1],zone,report,4),objects=places(L,"object",finished and finished[2],zone,report,4)}
    local o=get(L.Quest,id,"objectives") or {}
    row.creatures=places(L,"npc",o[1],zone,report)
    row.objects=places(L,"object",o[2],zone,report)
    row.items={}
    for i,item in ipairs(type(o[3])=="table" and o[3] or {}) do
        local itemID=type(item)=="table" and item[1] or item
        if type(itemID)=="number" and L.Item and i<=6 then
            row.items[#row.items+1]={id=itemID,name=get(L.Item,itemID,"name"),
                npcs=places(L,"npc",get(L.Item,itemID,"npcDrops"),zone,report,6),
                objects=places(L,"object",get(L.Item,itemID,"objectDrops"),zone,report,6),
                vendors=places(L,"npc",get(L.Item,itemID,"vendors"),zone,report,3)}
        end
    end
    local trigger=get(L.Quest,id,"triggerEnd")
    if type(trigger)=="table" then row.trigger={text=trigger[1],zones=(spawns(trigger[2],zone,report))} end
    return row
end

function P:Run()
    local L=lib()
    local report={time=date and date("%Y-%m-%d %H:%M:%S") or "",quests={}}
    if type(L)~="table" then
        report.error="LibQuestieDB missing (QuestieDB not loaded)"
    else
        local okC,contract=pcall(L.RequireContract,4)
        report.contract=okC and contract==true
        report.readMode=L.readMode
        report.flavor=type(L.flavor)=="table" and (L.flavor.name or L.flavor.expansion) or tostring(L.flavor)
        local zone=zoneDB()
        report.zoneDB=zone~=nil
        local start=clock()
        local data=ns.Quest and ns.Quest.Data
        if data and #data.quests==0 and data.Read then data:Read() end
        for _,q in ipairs(data and data.quests or {}) do
            local t=clock()
            local okQ,row=pcall(quest,L,q,zone,report)
            if not okQ then row={id=q.id,title=q.title,error=tostring(row)} end
            row.ms=math.floor((clock()-t)*10+.5)/10
            report.quests[#report.quests+1]=row
        end
        report.ms=math.floor((clock()-start)*10+.5)/10
    end
    ns.Settings:Module("questnav").questieProbe=report
    if report.error then N:Print("Probe: "..report.error);return report end
    N:Print(string.format("Probe: %d quests, %d unknown to QuestieDB, contract 4 %s, %s, zone table %s, %d zones without a map, %d points off a continent, %.1f ms. /reload writes the report.",
        #report.quests,report.unknown or 0,report.contract and "ok" or "MISSING",tostring(report.readMode),report.zoneDB and "ok" or "missing",
        report.noMap or 0,report.noContinent or 0,report.ms or 0))
    return report
end
