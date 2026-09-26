local _, ns = ...
local Theme = {
    colors = {
        canvas = { 0.051, 0.043, 0.059, 1 },
        surface = { 0.082, 0.071, 0.086, 1 },
        raised = { 0.110, 0.094, 0.114, 1 },
        hover = { 0.150, 0.125, 0.153, 1 },
        edge = { 0.255, 0.224, 0.259, 1 },
        text = { 0.933, 0.902, 0.847, 1 },
        muted = { 0.620, 0.584, 0.580, 1 },
        ink = { 0.016, 0.075, 0.051, 1 },
        success = { .58,.77,.69,1 }, warning = { .89,.74,.49,1 },
        danger = { 0.741, 0.345, 0.376, 1 },
    },
    accents = {
        verdant = { 0.1255, 0.9412, 0.6275, 1 },
        violet = { 0.541, 0.471, 0.929, 1 },
        ember = { 0.816, 0.604, 0.271, 1 },
    },
    fontSize = { body = 13, small = 11, heading = 26, title = 18 },
}
ns.Theme = Theme

function Theme:BoldFont()
    local id = ns.Settings:Get("font")
    if id:sub(1,4)=="lsm:" then return id end
    return id:find("Bold$") and id or id .. "Bold"
end

local aliases={canvas="bg",surface="panel",hover="raised",ink="bg"}
function Theme:Color(key,alpha)
    local palette=ns.DesignSystem.palettes[ns.Settings:Get("themeKey")] or ns.DesignSystem.palettes.violet
    local color=palette[aliases[key] or key] or ns.DesignSystem.shared[key] or self.colors[key]
    assert(color,"Unknown theme color: "..tostring(key))
    return color[1],color[2],color[3],alpha or color[4] or 1
end

function Theme:Font(region, size, fontID)
    local path = ns.Media:Font(fontID or ns.Settings:Get("font"))
    local ok, loaded = pcall(region.SetFont, region, path, size or self.fontSize.body, "")
    if not ok or not loaded then
        region:SetFont("Fonts\\FRIZQT__.TTF", size or self.fontSize.body, "")
    end
end
