local _, ns = ...
local Options = {}
ns.ProgressOptions = Options
Options.points = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local function has(list, value) for _, item in ipairs(list) do if item == value then return true end end end
local function bounded(value, default, low, high)
    return ns.ProgressModel.Number(value) and math.max(low, math.min(high, value)) or default
end
local function hex(value, default)
    return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") and value or default
end
local function field(template, anchor, relative, x, y, width, enabled)
    return { template = template, anchor = anchor, relative = relative, x = x, y = y, width = width,
        enabled = enabled ~= false, font = "inherit", size = 13, color = "EEE6D8FF", align = anchor:find("LEFT") and "LEFT" or anchor:find("RIGHT") and "RIGHT" or "CENTER" }
end
Options.Field=field
function Options:DefaultFields(kind)
    return assert(ns.ProgressBars.definitions[kind],"Progress module not loaded").defaultFields()
end

function Options:Get(kind)
    local definition=assert(ns.ProgressBars.definitions[kind],"Progress module not loaded")
    local config = ns.Settings:Module(kind .. "_bar")
    config.width = bounded(config.width, 720, 160, 1600)
    config.height = bounded(config.height, 22, 6, 80)
    config.x = bounded(config.x, 0, -5000, 5000)
    config.y = bounded(config.y, definition.y, -5000, 5000)
    config.anchor = has(self.points, config.anchor) and config.anchor or "BOTTOM"
    config.segments = math.floor(bounded(config.segments, 20, 1, 40))
    config.opacity = bounded(config.opacity, 1, 0.1, 1)
    config.texture = ns.Media:Reference("statusbar",config.texture) and config.texture or "inherit"
    config.color = hex(config.color, definition.color)
    config.background = hex(config.background, "100E12E6")
    config.restedColor = hex(config.restedColor, "8A78ED99")
    if type(config.hideInactive) ~= "boolean" then config.hideInactive = true end
    config.hideBlizzard = config.hideBlizzard == true
    config.showRested = config.showRested ~= false
    if type(config.fields) ~= "table" or #config.fields == 0 then config.fields = self:DefaultFields(kind) end
    while #config.fields > 12 do table.remove(config.fields) end
    for index, entry in ipairs(config.fields) do
        if type(entry) ~= "table" then entry = field("{percent}%", "CENTER", "CENTER", 0, 0, 200); config.fields[index] = entry end
        entry.template = type(entry.template) == "string" and entry.template:sub(1, 160) or "{percent}%"
        entry.enabled = entry.enabled ~= false
        entry.anchor = has(self.points, entry.anchor) and entry.anchor or "CENTER"
        entry.relative = has(self.points, entry.relative) and entry.relative or "CENTER"
        entry.x = bounded(entry.x, 0, -2000, 2000); entry.y = bounded(entry.y, 0, -2000, 2000)
        entry.width = bounded(entry.width, 200, 20, 1400); entry.size = bounded(entry.size, 13, 8, 40)
        entry.font = ns.Media:Reference("font",entry.font) and entry.font or "inherit"
        entry.color = hex(entry.color, "EEE6D8FF")
        entry.align = has({ "LEFT", "CENTER", "RIGHT" }, entry.align) and entry.align or "CENTER"
    end
    return config
end
