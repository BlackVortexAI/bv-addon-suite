-- Small local inventory catalog. Never enumerates global item IDs or bank storage.
local _,ns=...
local Catalog={};Catalog.__index=Catalog;ns.ItemCatalogModel=Catalog
function Catalog.New(api)return setmetatable({api=api},Catalog)end
function Catalog:Secret(value)return (self.api.issecretvalue or ns.GraphValues.IsSecret)(value)end
function Catalog:Read(fn,...)
 if type(fn)~="function"then return end
 local ok,value=pcall(fn,...);if ok and not self:Secret(value)then return value end
end
function Catalog:ID(value)
 if self:Secret(value)or type(value)~="number"or value~=value or value<1 or value>2147483647 or value~=math.floor(value)then return end
 return value
end
function Catalog:Row(id,request,attempts)
 if not self:ID(id)then return end
 local api=self.api.C_Item or {};local name=self:Read(api.GetItemNameByID,id)
 if type(name)~="string"or #name==0 or #name>256 or name:find("%c")then name=nil end
 local icon=self:ID(self:Read(api.GetItemIconByID,id))
 if not name and request and not attempts[id]then attempts[id]=true;self:Read(api.RequestLoadItemDataByID,id)end
 return {value=id,name=name,label=(name and name:gsub("|","||")or "Item "..id).." ["..id.."]",icon=icon,
  origin="Carried or equipped item. Item ID "..id..". Selection changes this node's draft only.",textPending=not name}
end
function Catalog:Open(valid)
 local catalog=self;local session={entries={},byID={},attempts={}}
 function session:Valid()return not self.closed and (not valid or valid())end
 function session:Status()return {ready=true,state="ready"}end
 function session:Close()self.closed=true end
 function session:EnrichmentPaused()return catalog:Read(catalog.api.InCombatLockdown)==true end
 function session:Enrich(entry,request)
  if not self:Valid()or catalog:Secret(entry)or type(entry)~="table"or not catalog:ID(entry.value)or not self.byID[entry.value]then return entry end
  local row=catalog:Row(entry.value,request and not self:EnrichmentPaused(),self.attempts)
  self.byID[row.value]=row;return row
 end
 function session:Tooltip(entry,request)return self:Enrich(entry,request)end
 function session:Contains(id)return self:Valid()and catalog:ID(id)and self.byID[id]~=nil end
 function session:Search(query)
  if not self:Valid()then return {},"Selector context changed"end
  if catalog:Secret(query)or type(query)~="string"then return {},"Search a name or item ID"end
  query=query:sub(1,100):lower();local out={}
  for _,id in ipairs(self.entries)do
   local row=self.byID[id]
   if query==""or tostring(id):find(query,1,true)or (row.name and row.name:lower():find(query,1,true))then out[#out+1]=row end
  end
  return out,"Snapshot: bags 0–4 and equipment. Refresh after inventory changes."
 end
 local function add(value)
  local id=catalog:ID(value);if id and not session.byID[id]then session.entries[#session.entries+1]=id;session.byID[id]=catalog:Row(id,false,session.attempts)end
 end
 local container=self.api.C_Container or {}
 for bag=0,4 do
  local slots=self:Read(container.GetContainerNumSlots,bag)
  if type(slots)=="number"and slots==slots and slots>=0 and slots<=64 and slots==math.floor(slots)then
   for slot=1,slots do add(self:Read(container.GetContainerItemID,bag,slot))end
  end
 end
 for slot=1,19 do add(self:Read(self.api.GetInventoryItemID,"player",slot))end
 table.sort(session.entries);return session
end
ns.ItemCatalog=Catalog.New(_G)
