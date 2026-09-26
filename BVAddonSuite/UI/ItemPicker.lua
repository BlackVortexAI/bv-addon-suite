-- Item-specific wording over the shared bounded lookup selection component.
local _,ns=...
function ns.UI:ItemPicker(parent,width)
 local view=self:LookupPicker(parent,width)
 view.blockTitle:SetText("Preparing carried items")
 local open=view.Open
 function view:Open(session,choose,dismiss)
  open(self,session,choose,dismiss)
  self.metadataStatus:SetText("Names and icons load for visible items. Item IDs stay selectable.")
 end
 return view
end
