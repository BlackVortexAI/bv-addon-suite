-- Repeated unit contexts share scheduling, never mutable node state.
local _,A=...
if A.blocked then return end
local R,G=A.Runtime,A.G
local P=BVAddonSuiteCore.Performance
local I={};A.InstanceRuntime=I
local New=R.NewOne or R.New
local Begin=R.BeginOne or R.Begin
local Step=R.StepOne or R.Step
local NeedsClock=R.NeedsClockOne or R.NeedsClock
local function plain(v,t)return not G.IsSecret(v) and type(v)==t end
local function stack(plan,id)return plan.definitions[id].displayStack or plan.graph.nodes[id].type=="display_stack" end
local function subset(plan,selected)
 local p={graph=plan.graph,definitions=plan.definitions,incoming=plan.incoming,dependents=plan.dependents,active={},order={}}
 for _,id in ipairs(plan.order)do if selected[id]then p.active[id]=true;p.order[#p.order+1]=id end end
 return p
end
local function partition(plan)
 local repeated={}
 local function descend(id)
  if repeated[id]then return end;repeated[id]=true
  for child in pairs(plan.dependents[id] or {})do descend(child)end
 end
 for _,id in ipairs(plan.order)do if plan.repeated and plan.repeated[id] or plan.definitions[id].collectionSource then descend(id)end end
 if not next(repeated)then return end
 local child,base={},{}
 local function ancestors(id)
  if child[id]then return end;child[id]=true
  for _,edge in pairs(plan.incoming[id] or {})do ancestors(edge.from)end
 end
 for _,id in ipairs(plan.order)do if repeated[id]then ancestors(id)else base[id]=true end end
 return subset(plan,base),subset(plan,child),repeated
end
local function valid(token,b)
 return plain(token,"string") and A.UnitSource.ValidToken(token) and (token:match("^nameplate%d+$") or token:match("^party%d+$") or token:match("^raid%d+$"))
  and plain(b,"table") and not getmetatable(b)
  and plain(b.unit,"string") and b.unit==token and G.Number(b.generation)
  and b.generation>=0 and b.generation==math.floor(b.generation) and G.RuntimeAccepts("unitref",b.reference)
end
local function current(parent,child)
 if parent.stopped or child.stopped or parent.children[child.unitToken]~=child then return false end
 local b=parent.bindings and parent.bindings[child.unitToken]
 return valid(child.unitToken,b) and b.generation==child.instanceGeneration and rawequal(b.reference,child.instance)
end
local inherited={"nodeOverrides","draftRevision","dialogResume","test","graphId","appliedRevision","objectIcons","send","messageStatus","messageAccept","requestChat","sendChat","needs","messageTopics","interactionKeys","sectionMute","sectionBypass"}
local function inherit(parent,run)
 for _,key in ipairs(inherited)do run[key]=parent[key]end
 run.messageDriven=parent.messageDriven
end
local function sync(parent)
 local started=P.active and P:Begin()
 local base=parent.baseRun
 parent.values=G.RuntimeCopy(base.values);parent.signals=G.Copy(base.signals);parent.trace=G.TraceCopy(base.trace)
 parent.state=base.state;parent.auras=base.auras
 local representative
 for _,child in pairs(parent.children)do
  if not representative or child.instanceAppearance<representative.instanceAppearance
   or child.instanceAppearance==representative.instanceAppearance and child.unitToken<representative.unitToken then representative=child end
 end
 if representative then
  for id in pairs(parent.repeated)do
   parent.values[id]=G.RuntimeCopy(representative.values[id]);parent.signals[id]=G.Copy(representative.signals[id]);parent.trace[id]=G.TraceCopy(representative.trace[id])
  end
 end
 if P.active then P:Finish("instance_sync_ms",started)end
end
local function hide(parent,run)
 BVAddonSuiteCore.Sound:Release(run)
 run.pendingDisplay=nil
 if parent.instanceDisplay then for _,id in ipairs(run.plan.order)do if stack(run.plan,id)then
  pcall(parent.instanceDisplay,id,false,nil,nil,run.instance)
 end end end
end
local function purge(parent,token)
 for _,key in ipairs({"units","unitGenerations"})do if parent.latestSample[key]then parent.latestSample[key][token]=nil end end
 for _,key in ipairs({"unitQueries","auras"})do
  for id in pairs(parent.latestSample[key] or {})do
   local legacyPlayerAura=key=="auras" and token=="player" and plain(id,"string") and (id:match("^HELPFUL:") or id:match("^HARMFUL:"))
   if plain(id,"string") and (id==token or id:sub(1,#token+1)==token..":" or legacyPlayerAura)then parent.latestSample[key][id]=nil end
  end
 end
end
function R.InvalidateInstance(parent,token)
 if not parent or not parent.instanceRuntime or not plain(token,"string")then return end
 purge(parent,token)
 local child=parent.children[token];if not child then return end
 parent.children[token]=nil;child.stopped=true;hide(parent,child)
 child.values={};child.state={};child.signals={};child.trace={};child.auras={};child.instance=nil;child.memory=nil
 sync(parent)
end
function R.InvalidateInstances(parent)
 if not parent or not parent.instanceRuntime then return end
 local tokens={};for token in pairs(parent.children)do tokens[#tokens+1]=token end
 for _,token in ipairs(tokens)do R.InvalidateInstance(parent,token)end
 hide(parent,parent.baseRun);parent.latestSample={}
end
function R.InvalidateNodes(parent,affected)
 if not parent or not parent.instanceRuntime then return end
 parent.revision=parent.revision+1
 local runs={parent.baseRun};for _,child in pairs(parent.children)do runs[#runs+1]=child end
 for id in pairs(affected)do
  local def=parent.plan.definitions[id];local n=parent.plan.graph.nodes[id]
  if def and (def.unitSource or def.auraSource) and not def.collectionSource then
   for _,token in ipairs(A.UnitSource.PlanTokens(parent.plan,id,n)) do purge(parent,token) end
  end
  for _,run in ipairs(runs)do if run.plan.active[id]then
   if def and def.soundSink then BVAddonSuiteCore.Sound:Stop(run,id) end
   run.values[id]=nil;run.signals[id]=nil;run.trace[id]=nil
   local state=run.state[id];if state then state.time=nil;state.auraEstimate=nil end
   if run.pendingDisplay then run.pendingDisplay[id]=nil end
   if stack(run.plan,id) and parent.instanceDisplay then pcall(parent.instanceDisplay,id,false,nil,nil,run.instance)end
  end end
 end
 sync(parent)
end
local function displayed(parent,run,id,shown,media,payload)
 if stack(run.plan,id)then
  if run.pendingDisplay then run.pendingDisplay[id]={shown=shown==true,media=G.RuntimeCopy(media),payload=G.RuntimeCopy(payload)}end
 elseif parent.instanceDisplay then parent.instanceDisplay(id,shown,media,payload,run.instance)end
end
local function make(parent,plan)
 local run
 run=New(plan,parent.emit,parent.diagnose,function(id,shown,media,payload)displayed(parent,run,id,shown,media,payload)end)
 inherit(parent,run);return run
end
local function commit(parent,run,now)
 local pending=run.pendingDisplay;run.pendingDisplay=nil
 if not pending or parent.stopped or run.stopped or run.instance and not current(parent,run)then return end
 for _,id in ipairs(run.plan.order)do
  local value=pending[id]
  if value and parent.instanceDisplay then
   if parent.stopped or run.stopped or run.instance and not current(parent,run)then return end
   local ok,why=pcall(parent.instanceDisplay,id,value.shown,value.media,value.payload,run.instance)
   local state=run.state[id]
   if not ok then
    pcall(parent.instanceDisplay,id,false,nil,nil,run.instance)
    state=state or {};run.state[id]=state;state.renderFailures=(state.renderFailures or 0)+1
    state.time=nil;state.retryAt=now+math.min(30,2^(state.renderFailures-1));state.paused=state.renderFailures>=5
    run.values[id]=nil;run.signals[id]={};run.trace[id]={status="faulted",values={},at=now}
    if parent.diagnose then parent.diagnose(id,G.Error and G.Error(why) or "Display operation failed")end
   elseif value.shown and state then state.renderFailures=nil end
  end
 end
end
function R.New(plan,emit,diagnose,display)
 local base,child,repeated=partition(plan)
 if not base then return New(plan,emit,diagnose,display)end
 local parent=New(plan,emit,diagnose,display)
 parent.instanceRuntime=true;parent.instanceDisplay=display;parent.children={};parent.bindings={};parent.latestSample={};parent.allowedCollectionTokens={}
 for _,id in ipairs(plan.order) do
  for _,token in ipairs(A.CollectionTokens(plan.definitions[id],plan.graph.nodes[id].config)) do parent.allowedCollectionTokens[token]=true end
 end
 parent.collectionTokens=G.Copy(parent.allowedCollectionTokens)
 parent.childPlan=child;parent.repeated=repeated;parent.baseRun=make(parent,base)
 sync(parent);return parent
end
local maps={units=true,unitQueries=true,unitGenerations=true,sources=true,auras=true}
local transient={message=true,sourceEvent=true,interaction=true}
local function latest(parent,sample,owned)
 for key,value in pairs(sample)do if not transient[key]then
  if maps[key] and type(value)=="table"then
   local map=parent.latestSample[key] or {};parent.latestSample[key]=map
   -- The scheduler transfers an isolated, read-only sample. Keep our own map
   -- so lifecycle purge never edits a queued job; observation records can be
   -- retained because node evaluation copies them before exposing mutable state.
   for k,v in pairs(value)do if not owned then v=G.RuntimeCopy(v)end;map[k]=v end
  else if not owned then value=G.RuntimeCopy(value)end;parent.latestSample[key]=value end
 end end
end
-- Freeze map membership before yielding. Owned observation records are immutable;
-- only the small merge maps can change on lifecycle invalidation or later jobs.
local function freezeSample(sample)
 local frozen={}
 for key,value in pairs(sample)do
  if (maps[key] or key=="unitRefs") and plain(value,"table") then
   local map={};for k,v in pairs(value)do map[k]=v end;frozen[key]=map
  else frozen[key]=value end
 end
 return frozen
end
local function copyForContext(run,sample)
 local units,queries={},{}
 for _,id in ipairs(run.plan.order)do
  local node,def=run.plan.graph.nodes[id],run.plan.definitions[id]
  if def.unitSource or def.auraSource then
   for _,token in ipairs(A.UnitSource.PlanTokens(run.plan,id,node,run.instance)) do units[token]=true;queries[A.UnitSource.Key(token,node.config)]=true end
  end
 end
 local work={sample={},items={},index=1}
 local function add(target,key,value)work.items[#work.items+1]={target=target,key=key,value=value}end
 for key,value in pairs(sample)do
  if (maps[key] or key=="unitRefs") and plain(value,"table") then
   local out={};work.sample[key]=out
   local selected=key=="unitQueries" and queries or
    (key=="units" or key=="unitGenerations" or key=="unitRefs") and units
   if selected then
    for k in pairs(selected)do if value[k]~=nil then add(out,k,value[k])end end
   else for k,v in pairs(value)do add(out,k,v)end end
  else add(work.sample,key,value)end
 end
 return work
end
local function advanceCopy(work,budget)
 local started=debugprofilestop and debugprofilestop();local copied=0
 while work.index<=#work.items do
  local item=work.items[work.index];item.target[item.key]=G.RuntimeCopy(item.value)
  work.index=work.index+1;copied=copied+1
  if copied>=8 or started and debugprofilestop()-started>=budget then break end
 end
 return work.index>#work.items
end
local observations={initial=true,unit=true,aura=true,clock=true,hp=true,power=true,player_state=true,context=true,metadata=true}
function R.InputBoundary(job)
 return job and job.instanceJob and observations[job.reason] and job.boundary
  and not job.run.stopped and job.revision==job.run.revision and job.index<=#job.tasks
end
local function inputBinding(job,sample)
 local packet=sample and sample.interaction
 local info=packet and packet.instance and G.Object(packet.instance,"unitref")
 local binding=info and job.run.bindings[info.unit]
 if binding and valid(info.unit,binding) and binding.reference==packet.instance then return info.unit,binding end
end
local function inputReady(job,sample)
 if not R.InputBoundary(job)then return false end
 local token,binding=inputBinding(job,sample);if not token then return false end
 for i=job.index,#job.tasks do
  local task=job.tasks[i]
  if task.run==job.run.baseRun or task.token==token then return false end
 end
 local child=job.run.children[token]
 return child and child.instanceInitialized and current(job.run,child) and child.instance==binding.reference
end
function R.PrioritizeInput(job,sample)
 if not R.InputBoundary(job)then return false end
 local token=inputBinding(job,sample);if not token then return false end
 -- Complete older shared/target work before its input. Other contexts are
 -- independent, so the target may move forward without replaying any task.
 for i=job.index,#job.tasks do if job.tasks[i].run==job.run.baseRun then return false end end
 for i=job.index,#job.tasks do if job.tasks[i].token==token then
  if i>job.index then
   table.insert(job.tasks,job.index,table.remove(job.tasks,i))
   if P.active then P:Count("graph_input_promotions")end
  end
  return false
 end end
 return inputReady(job,sample)
end
function R.Begin(parent,sample,now,reason,owned,prepareBudget,suspended,instanceTokens)
 if not parent.instanceRuntime then return Begin(parent,sample,now,reason)end
 if parent.stopped then return end
 if suspended then
  assert(reason=="interaction" and suspended.run==parent and inputReady(suspended,sample),"Unsafe input interruption")
 else parent.revision=parent.revision+1 end
 local old={};for token in pairs(parent.children)do old[#old+1]=token end
 for _,token in ipairs(old)do if not current(parent,parent.children[token])then R.InvalidateInstance(parent,token)end end
 -- Only Studio.Pump may transfer ownership. Other callers retain the existing
 -- defensive copy contract; fresh contexts still receive private snapshots.
 if not suspended then latest(parent,sample,owned==true)end
 local packet=reason=="interaction" and sample.interaction
 local clicked=packet and packet.instance and G.Object(packet.instance,"unitref")
 local ordered={}
 for token,binding in pairs(parent.bindings or {})do if valid(token,binding) and parent.allowedCollectionTokens[token] and (not clicked or clicked.unit==token)
  and (not instanceTokens or instanceTokens[token])then ordered[#ordered+1]=token end end
 table.sort(ordered,function(a,b)
  local x,y=parent.bindings[a],parent.bindings[b]
  local ax,ay=G.Number(x.appearance) and x.appearance or 0,G.Number(y.appearance) and y.appearance or 0
  return ax<ay or ax==ay and a<b
 end)
 local sliced=owned==true and G.Number(prepareBudget) and prepareBudget>0
 local tasks={};local needsInitial=false
 if #parent.baseRun.plan.order>0 then
  needsInitial=not parent.baseRun.instanceInitialized
  tasks[#tasks+1]={run=parent.baseRun,fresh=needsInitial}
 end
 for index,token in ipairs(ordered)do if index<=84 then
  local binding=parent.bindings[token];local child=parent.children[token]
  if not child and not sliced then
   child=make(parent,parent.childPlan);child.instance=binding.reference;child.unitToken=token
   child.instanceGeneration=binding.generation;child.instanceAppearance=G.Number(binding.appearance) and binding.appearance or 0
   parent.children[token]=child
  end
  local fresh=not child or not child.instanceInitialized;needsInitial=needsInitial or fresh
  tasks[#tasks+1]={run=child,fresh=fresh,token=token,binding=binding}
 end end
 -- Only fresh tasks read the historical snapshot. Keep their private copy,
 -- but do not traverse all observations for already-initialized contexts.
 return {instanceJob=true,run=parent,revision=parent.revision,tasks=tasks,index=1,boundary=true,sample=sample,
  initialSample=needsInitial and (sliced and freezeSample(parent.latestSample) or G.RuntimeCopy(parent.latestSample)) or nil,
  prepareBudget=sliced and math.min(.5,prepareBudget) or nil,now=now,reason=reason}
end
local function nextTask(job)
 job.index=job.index+1;job.boundary=true;job.inputServed=nil
 return job.index>#job.tasks
end
function R.Step(job)
 if not job.instanceJob then return Step(job)end
 local parent=job.run
 local interaction=job.reason=="interaction" and job.sample.interaction
 if interaction and interaction.instance then
  local info=G.Object(interaction.instance,"unitref")
  local binding=info and parent.bindings[info.unit]
  if not binding or binding.reference~=interaction.instance then return true end
 end
 if parent.stopped or job.revision~=parent.revision then
  for _,task in ipairs(job.tasks)do if task.pending and task.run.pendingDisplay==task.pending then task.run.pendingDisplay=nil end end
  return true
 end
 local task=job.tasks[job.index];if not task then return true end
 job.boundary=false
 local run=task.run
 if not run then
  local binding=parent.bindings[task.token]
  local generation=job.sample.unitGenerations and job.sample.unitGenerations[task.token]
  if not valid(task.token,binding) or binding.reference~=task.binding.reference
   or generation~=nil and generation~=binding.generation then
   return nextTask(job)
  end
  run=make(parent,parent.childPlan);run.instance=binding.reference;run.unitToken=task.token
  run.instanceGeneration=binding.generation;run.instanceAppearance=G.Number(binding.appearance) and binding.appearance or 0
  parent.children[task.token]=run;task.run=run
  return false -- Let the pump check its budget after creating one context.
 end
 local generation=job.sample.unitGenerations and job.sample.unitGenerations[run.unitToken]
 if run.stopped or run.instance and (not current(parent,run) or generation~=nil and generation~=run.instanceGeneration)then
  run.pendingDisplay=nil;return nextTask(job)
 end
 if not task.job then
  if task.fresh and job.prepareBudget and not task.firstSample then
   local started=P.active and P:Begin()
   task.copy=task.copy or copyForContext(run,job.initialSample)
   if advanceCopy(task.copy,job.prepareBudget)then task.firstSample=task.copy.sample;task.copy=nil end
   if P.active then P:Finish("instance_snapshot_ms",started)end
   return false -- Observation copies are bounded separately from node work.
  end
  local started=P.active and P:Begin()
  inherit(parent,run);run.pendingDisplay={};task.pending=run.pendingDisplay
  local first=task.firstSample or (task.fresh and G.RuntimeCopy(job.initialSample) or job.sample)
  task.firstSample=nil
  local eventKey=({source_event="sourceEvent",interaction="interaction",message="message"})[job.reason]
  if task.fresh and eventKey then first[eventKey]=G.RuntimeCopy(job.sample[eventKey]) end
  task.job=Begin(run,first,job.now,task.fresh and "initial" or job.reason)
  -- Initialise every ancestor, but evaluate an event received by this exact
  -- job as an event. Transients never enter the cache for later contexts.
  if task.fresh and eventKey and task.job then task.job.reason=job.reason end
  if P.active then P:Finish("instance_prepare_ms",started)end
  if job.prepareBudget then return false end -- BeginOne has its own budget boundary.
 end
 local done=not task.job or Step(task.job)
 if done then
  run.instanceInitialized=true
  local started=P.active and P:Begin()
  commit(parent,run,job.now)
  if P.active then P:Finish("instance_commit_ms",started)end
  sync(parent);return nextTask(job)
 end
 return false
end
function R.NeedsClock(parent)
 if not parent or not parent.instanceRuntime then return NeedsClock(parent)end
 if parent.stopped then return false end
 if NeedsClock(parent.baseRun)then return true end
 for _,child in pairs(parent.children)do if current(parent,child) and NeedsClock(child)then return true end end
 return false
end
