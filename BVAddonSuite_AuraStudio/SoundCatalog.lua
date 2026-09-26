local _,A=...
if A.blocked then return end
local ns,G=BVAddonSuiteCore,A.G
local base={label="Play Sound",sink=true,soundSink=true,inputs={
    event={label="Play",type="event",wire=true,required=true,order=1},
    stop={label="Stop",type="event",wire=true,required=false,order=2}},
    outputs={played={label="Played",type="event",order=1},status={label="Status",type="string",order=2}},
    defaults={source="soundkit",soundKit=8959,sound="lsm:None",channel="Master",volume=100},
    help="Play local audio on a new Play event. Stop takes precedence; a new play replaces this node's previous sound. SharedMedia uses registered file paths/FileDataIDs and the chosen channel's game volume. SoundKits support per-playback Volume (0..100%) on this client. No global audio settings are changed. Initial evaluation and Graph Test are silent; use Preview sound in node details. Mute, graph stop and profile changes stop owned playback. Secret triggers are unavailable."}
base.resolve=function(c)
    if not ns.Sound.Valid(c) then return nil,"Choose a valid sound, channel and volume" end
    local d=G.Copy(base);d.resolve=nil
    d.fields={{key="source",label="Source",choices={"soundkit","sharedmedia"},choiceLabels={soundkit="Game SoundKit",sharedmedia="SharedMedia"}}}
    if c.source=="soundkit" then
        d.fields[#d.fields+1]={key="soundKit",label="SoundKit",type="integer",picker="sound"}
        d.fields[#d.fields+1]={key="soundKit",label="Custom SoundKit ID",type="integer",advanced=true}
        d.fields[#d.fields+1]={key="volume",label="Volume (%)",type="float"}
    else d.fields[#d.fields+1]={key="sound",label="Sound",type="string",picker="sound"} end
    d.fields[#d.fields+1]={key="channel",label="Channel",choices={"Master","SFX","Music","Ambience","Dialog"}}
    return d
end
A.catalog.play_sound=base;A.order[#A.order+1]="play_sound"
