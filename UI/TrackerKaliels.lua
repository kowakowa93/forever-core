---@type string, ForeverTrackerNamespace
local _, ns = ...

-- KT 8.11.1 keeps its outer frame at maxHeight when growing down. Background is the
-- visible content rectangle, updated by Tracker_SetSize, including scrolling caps.
-- Read that rectangle; never move KT or put our frames in its anchor family.
local TrackerKaliels = {}
ns.TrackerKaliels = TrackerKaliels
local observer = CreateFrame("Frame")
local enabled, onChange = false, nil

local function Frame()
	return rawget(_G, "!KalielsTrackerFrame")
end

local function Collapsed()
	local tracker = rawget(_G, "KT_ObjectiveTrackerFrame")
	return tracker and tracker.isCollapsed == true
end

-- The quest modules occupy KT_ObjectiveTrackerFrame inside the scroll child.
-- Read its actual horizontal bounds rather than hardcoding KT's border/inset sizes.
local function Content(edge)
	local content = rawget(_G, "KT_ObjectiveTrackerFrame")
	if content and content.GetLeft and content.GetRight then
		local left, right = content:GetLeft(), content:GetRight()
		if left and right and right > left then
			return content
		end
	end
	return edge
end

-- KT skins its section headers at fontSize + 1 and quest text at fontSize.
-- Read the live strings so font face/outline changes follow KT's active profile.
local function Fonts()
	local tracker = rawget(_G, "KT_QuestObjectiveTracker")
	local header = tracker and tracker.Header and tracker.Header.Text
	if not (header and header.GetFont) then return nil end
	local path, size, flags = header:GetFont()
	if not path or not size then return nil end
	local heading = { path, size, flags or "" }
	local body = { path, math.max(1, size - 1), flags or "" }
	for _, blocks in pairs(tracker.usedBlocks or {}) do
		for _, block in pairs(blocks) do
			if block.HeaderText and block.HeaderText.GetFont then
				local font, height, outline = block.HeaderText:GetFont()
				if font and height then
					return heading, { font, height, outline or "" }
				end
			end
		end
	end
	return heading, body
end

local function FontKey(heading, body)
	return heading and (table.concat(heading, "|") .. "/" .. table.concat(body, "|")) or "native"
end

-- KT hides the stock module button and draws its 16x16 module sprite at LEFT -6,2.
-- Keep our own clickable control there; never change KT or the shared mixins.
local function StyleCollapse(module, active)
	local header = module.Header
	local native = header and header.MinimizeButton
	if not (native and header.OnToggle and header.SetCollapsed) then return end
	local tracker = rawget(_G, "KT_QuestObjectiveTracker")
	local reference = tracker and tracker.Header and tracker.Header.Icon
	active = active and reference ~= nil
	local state = module.kalielsCollapse
	if not state and not active then return end
	if not state then
		local button = CreateFrame("Button", nil, header)
		button:SetSize(16, 16)
		button:SetPoint("LEFT", header, "LEFT", -6, 2)
		button:SetScript("OnClick", function() header:OnToggle() end)
		state = { button = button }
		module.kalielsCollapse = state
		local setCollapsed = header.SetCollapsed
		header.SetCollapsed = function(self, collapsed)
			setCollapsed(self, collapsed)
			if state.active then
				local texture = button:GetNormalTexture()
				-- KT Media.lua: 32x64 sheet, expand/collapse cells on its last row.
				texture:SetTexCoord(collapsed and 0 or 0.5, collapsed and 0.5 or 1, 0.75, 1)
			end
		end
	end
	if active then
		if not state.active then
			state.nativeShown = native:IsShown()
			state.textPoints = {}
			for index = 1, header.Text:GetNumPoints() do
				state.textPoints[index] = { header.Text:GetPoint(index) }
			end
		end
		state.active = true
		native:Hide()
		state.button:SetNormalTexture(reference:GetTexture())
		local texture = state.button:GetNormalTexture()
		texture:SetAllPoints(state.button)
		texture:SetVertexColor(reference:GetVertexColor())
		local collapsed = module:IsCollapsed()
		texture:SetTexCoord(collapsed and 0 or 0.5, collapsed and 0.5 or 1, 0.75, 1)
		header.Text:ClearAllPoints()
		header.Text:SetPoint("LEFT", header, "LEFT", 10, 1)
		state.button:Show()
	elseif state.active then
		state.active = false
		state.button:Hide()
		native:SetShown(state.nativeShown)
		header.Text:ClearAllPoints()
		for _, point in ipairs(state.textPoints) do
			header.Text:SetPoint(unpack(point))
		end
	end
end

-- Only our section and pooled block instances are wrapped. Apply before native
-- SetStringText measures row height, and retain each string's original font.
function TrackerKaliels.Style(module, active)
	StyleCollapse(module, active)
	local heading, body
	if active then heading, body = Fonts() end
	local state = module.kalielsFonts
	if not state then
		if not heading then return end
		state = { originals = setmetatable({}, { __mode = "k" }) }
		module.kalielsFonts = state
	end
	local key = FontKey(heading, body)
	local changed = state.key ~= key
	state.key, state.heading, state.body = key, heading, body
	local function Apply(text, font)
		if not (text and text.GetFont and text.SetFont) then return end
		local original = state.originals[text]
		if not original then
			local path, size, flags = text:GetFont()
			if not path or not size then return end
			original = { path, size, flags or "" }
			state.originals[text] = original
		end
		local wanted = font or original
		local path, size, flags = text:GetFont()
		if path ~= wanted[1] or size ~= wanted[2] or (flags or "") ~= wanted[3] then
			text:SetFont(unpack(wanted))
		end
	end
	if not state.wrapped and module.GetBlock then
		state.wrapped = true
		local getBlock = module.GetBlock
		module.GetBlock = function(self, ...)
			local block, wasActive = getBlock(self, ...)
			if not block.kalielsFontWrapped then
				block.kalielsFontWrapped = true
				local setString = block.SetStringText
				if setString then
					block.SetStringText = function(owner, text, ...)
						Apply(text, state.body)
						return setString(owner, text, ...)
					end
				end
				local getLine = block.GetLine
				if getLine then
					block.GetLine = function(owner, ...)
						local line = getLine(owner, ...)
						Apply(line.Text, state.body)
						Apply(line.Dash, state.body)
						return line
					end
				end
			end
			Apply(block.HeaderText, state.body)
			return block, wasActive
		end
	end
	if changed then
		for text in pairs(state.originals) do
			Apply(text, text == (module.Header and module.Header.Text) and heading or body)
		end
		Apply(module.Header and module.Header.Text, heading)
		if module.MarkDirty then module:MarkDirty() end
	end
end

-- KT has no public layout listener. Observe its completion methods and signals,
-- never replace them or anchor our frames to KT. No recurring timer is needed.
local watched = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local signalsRegistered = false
local function Changed()
	if enabled and onChange then onChange() end
end
local function Watch(frame)
	if not frame or watched[frame] then return end
	watched[frame] = true
	for _, script in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
		frame:HookScript(script, Changed)
	end
end
local function Observe()
	local frame = Frame()
	if not frame then return end
	Watch(frame)
	Watch(frame.Background)
	Watch(rawget(_G, "KT_ObjectiveTrackerFrame"))
	if not LibStub then return end
	local library = LibStub("MSA-AceAddon-3.0", true)
	local tracker = library and library:GetAddon("!KalielsTracker", true)
	if not tracker or hooked[tracker] then return end
	hooked[tracker] = true
	for _, method in ipairs({ "Tracker_SetSize", "Tracker_Move", "Tracker_SetScale",
		"Tracker_SetCollapsed", "Tracker_SetHidden", "Tracker_SetShown" }) do
		if type(tracker[method]) == "function" then
			hooksecurefunc(tracker, method, Changed)
		end
	end
end
function TrackerKaliels.SetEnabled(value)
	enabled = value
	if not value then return end
	if not signalsRegistered and EventRegistry then
		signalsRegistered = true
		for _, signal in ipairs({ "TRACKER_INITIALIZED", "OPTIONS_CHANGED", "ADDON_ENABLED" }) do
			EventRegistry:RegisterCallback("!KalielsTracker." .. signal, function()
				Observe()
				Changed()
			end, observer)
		end
	end
	Observe()
end
observer:RegisterEvent("ADDON_LOADED")
observer:RegisterEvent("PLAYER_ENTERING_WORLD")
observer:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_ENTERING_WORLD" or name == "!KalielsTracker" then
		if enabled then
			TrackerKaliels.SetEnabled(true)
			Changed()
		end
	end
end)

-- The second result keeps a hidden, collapsed or still-building KT from falling
-- back to the unrelated Blizzard slot. With KT absent, native behavior is unchanged.
function TrackerKaliels.List(host, changed)
	onChange = changed
	TrackerKaliels.SetEnabled(true)
	local frame = Frame()
	if not frame then
		return nil, false
	end
	local edge = frame.Background
	if not edge or not frame:IsVisible() or Collapsed() then
		return nil, true
	end
	local _, relativeTo = frame:GetPoint()
	if relativeTo == host then
		return nil, false
	end
	if not (edge:GetLeft() and edge:GetRight() and edge:GetTop() and edge:GetBottom()) then
		return nil, true
	end
	return edge, true
end

-- Keep vertical placement tied to the visible viewport, not the potentially taller
-- or scrolled content. Only the horizontal bounds come from the inner quest frame.
TrackerKaliels.Room = ns.TrackerQuestie.Room

function TrackerKaliels.Width(list, host)
	local content = Content(list)
	return (content:GetRight() - content:GetLeft()) * content:GetEffectiveScale() / host:GetEffectiveScale()
end

function TrackerKaliels.Places(list, host, besideX, screenWidth, screenHeight)
	local places = ns.TrackerQuestie.Places(list, host, besideX, screenWidth, screenHeight)
	local content = Content(list)
	local left = content:GetLeft() * content:GetEffectiveScale() / host:GetEffectiveScale()
	local x = math.max(0, math.min(left, math.max(0, screenWidth - host:GetWidth())))
	-- The last candidate is the side fallback; keep its outer-panel clearance.
	for index = 1, #places - 1 do
		places[index][2] = x
	end
	return places
end
