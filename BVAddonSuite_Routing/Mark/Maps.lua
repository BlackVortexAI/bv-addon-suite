local _,R=...
-- /bv route memory (Claude 2026-10-25, Florian: measure, do not guess): Lua memory when loading reached this point;
-- collected first when "/bv route memory marks on" is set (BV Core's saved table is loaded before Routing's files).
local db=rawget(_G,"BVAddonSuiteDB")
local exact=type(db)=="table" and db.routingMemoryMarks==true
if exact then collectgarbage("collect") end
R.memMarks=R.memMarks or {};R.memMarks[#R.memMarks+1]={"Transports, Maps (shipped maps)",collectgarbage("count"),exact}
