-- Generated dry ship walking endpoints; ride origins remain in Transports.lua.
-- Static ground evidence: routing-data/transports/boarding.json; not native boarding proof.
local _,Routing=...
if not Routing.ready then return end
local stops={
    ["Ship Booty Bay - Ratchet"]={a={1415,0.438,0.9266,"Booty Bay"},b={1414,0.5682,0.5627,"Ratchet"},boardingA={0.438361848,0.926699763,6.4565},boardingB={0.567818792,0.562360441,5.8258}},
    ["Ship Menethil Harbor - Theramore"]={a={1415,0.4712,0.4846,"Menethil Harbor"},b={1414,0.5926,0.6855,"Theramore"},boardingA={0.471582420,0.484271969,5.5087},boardingB={0.592279189,0.685034203,5.3943}},
    ["Ship Menethil Harbor - Auberdine"]={a={1415,0.4709,0.4763,"Menethil Harbor"},b={1414,0.4414,0.2606,"Auberdine"},boardingA={0.471141117,0.476761206,4.9197},boardingB={0.441550764,0.260055008,6.0347}},
    ["Ship Auberdine - Rut'theran Village"]={a={1414,0.4431,0.2529,"Auberdine"},b={1414,0.436,0.174,"Rut'theran Village"},boardingA={0.442980890,0.253538339,5.9369},boardingB={0.436037035,0.173338171,5.9239}},
    ["Ferry Forgotten Coast - Feathermoon"]={a={1414,0.3973,0.699,"Forgotten Coast"},b={1414,0.3745,0.6928,"Feathermoon Stronghold"},boardingA={0.397771772,0.698949428,5.9734},boardingB={0.374548264,0.693428474,6.0079}},
}
for _,t in ipairs(Routing.TRANSPORTS) do
    local b=stops[t.name]
    if b and t.kind=="ship" then
        local same=true
        for _,side in ipairs({"a","b"}) do for i=1,3 do if t[side][i]~=b[side][i] then same=false end end end
        if same then t.boardingA,t.boardingB=b.boardingA,b.boardingB end
    end
end
