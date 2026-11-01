local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local SOURCES = {
	{ esp = "Loot", folder = "Loot",           color = Color3.fromRGB(255, 215, 0), isNpc = false },
	{ esp = "AC",   folder = "Town.Buildings", itemName = "ACUnit", color = Color3.fromRGB(0, 255, 200), isNpc = false },
	{ esp = "NPC",  folder = "Npcs",           color = Color3.fromRGB(60, 230, 90),  isNpc = true },
	{ esp = "NPC",  folder = "Guards",         color = Color3.fromRGB(255, 60, 60),  isNpc = true }, 
	{ esp = "NPC",  folder = "Police",         color = Color3.fromRGB(70, 160, 255), isNpc = true }, 
}
local MAX_HIGHLIGHTS = 30
local TEXT_MAX = 12

local CFG = {
	Loot = { on = false, name = false, val = false, dist = false, range = 150 },
	AC   = { on = false, dist = false, range = 150 },
	NPC  = { on = false, dist = false, arrows = false, range = 150 },
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(90, 220, 90),
	Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 150, 30),
	Mythic = Color3.fromRGB(255, 60, 90),
}

local THEME = {
	win = Color3.fromRGB(0, 0, 0),
	panel = Color3.fromRGB(14, 14, 14),
	cyan = Color3.fromRGB(95, 228, 235),
	text = Color3.fromRGB(60, 255, 90),
	sub = Color3.fromRGB(40, 170, 65),
	dark = Color3.fromRGB(10, 10, 14),
	green = Color3.fromRGB(80, 255, 0),
	input = Color3.fromRGB(30, 30, 34),
}

local alive = true
local filterTerms = {}
local items = {}      
local connections = {} 

local function track(conn)
	table.insert(connections, conn)
	return conn
end

local function loop(interval, fn)
	task.spawn(function()
		while alive do
			local ok, err = pcall(fn)
			if not ok then warn("[ESP] " .. tostring(err)) end
			task.wait(interval)
		end
	end)
end

pcall(function()
	local old = game:GetService("CoreGui"):FindFirstChild("LootViewerGui")
	if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "LootViewerGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
local okParent = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not okParent or not gui.Parent then
	gui.Parent = player:WaitForChild("PlayerGui")
end

local arrowLayer = Instance.new("Frame")
arrowLayer.Size = UDim2.new(1, 0, 1, 0)
arrowLayer.BackgroundTransparency = 1
arrowLayer.BorderSizePixel = 0
arrowLayer.Active = false
arrowLayer.Parent = gui

local function getPart(model)
	if model:IsA("BasePart") then return model end
	return model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function textSizeFor(d, range)
	local k = math.clamp(d / math.max(range, 1), 0, 1)
	local minSize = math.max(6, math.floor(TEXT_MAX * 0.65 + 0.5))
	return math.floor(TEXT_MAX - (TEXT_MAX - minSize) * k + 0.5)
end

local function matches(name)
	if #filterTerms == 0 then return true end
	local l = name:lower()
	for _, term in ipairs(filterTerms) do
		if l:find(term, 1, true) then return true end
	end
	return false
end

local function getValue(inst)
	return inst:GetAttribute("Value") or inst:GetAttribute("BaseValue")
end

local function fmtNum(n)
	if type(n) ~= "number" then return tostring(n) end
	return tostring(math.floor(n + 0.5))
end

local function myRootPart()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function isDead(inst, src)
	if not src.isNpc then return false end
	local hum = inst:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health <= 0
end

local function findFolder(path)
	local cur = workspace
	for part in string.gmatch(path, "[^%.]+") do
		cur = cur and cur:FindFirstChild(part)
	end
	if cur and cur ~= workspace then return cur end
	local last = path:match("([^%.]+)$")
	return workspace:FindFirstChild(last, true)
end

local function isItem(inst, root, src)
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
	if src.itemName then
		return inst.Name == src.itemName
	end
	local p = inst.Parent
	while p and p ~= root do
		if p:IsA("Model") or p:IsA("BasePart") then return false end
		p = p.Parent
	end
	return p == root
end

local function removeItem(inst)
	local t = items[inst]
	if not t then return end
	if t.hl then t.hl:Destroy() end
	if t.bb then t.bb:Destroy() end
	if t.arrow then t.arrow.holder:Destroy() end
	items[inst] = nil
end

local function addItem(inst, src, root)
	if items[inst] then return end
	if not isItem(inst, root, src) then return end
	local part = getPart(inst)
	if not part then return end
	items[inst] = { part = part, kind = src, root = root }
end

local function ensureVisuals(inst, t)
	if t.hl then return end
	local hl = Instance.new("Highlight")
	hl.Adornee = inst
	hl.FillColor = t.kind.color
	hl.FillTransparency = 0.5
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = gui

	local bb = Instance.new("BillboardGui")
	bb.Adornee = t.part
	bb.Size = UDim2.new(0, 400, 0, 130)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = TEXT_MAX
	label.TextWrapped = true
	label.Parent = bb

	t.hl, t.bb, t.label = hl, bb, label
end

local function ensureArrow(t)
	if t.arrow then return t.arrow end
	local color = t.kind.color

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, 60, 0, 34)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = arrowLayer

	local tri = Instance.new("Frame")
	tri.Size = UDim2.new(0, 14, 0, 14)
	tri.AnchorPoint = Vector2.new(0.5, 0.5)
	tri.Position = UDim2.new(0.5, 0, 0, 8)
	tri.BackgroundColor3 = color
	tri.BorderSizePixel = 0
	tri.Parent = holder
	local g = Instance.new("UIGradient")
	g.Rotation = 45
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = tri

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 16)
	lbl.Position = UDim2.new(0, 0, 0, 17)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.3
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 14
	lbl.Text = ""
	lbl.Parent = holder

	t.arrow = { holder = holder, tri = tri, lbl = lbl }
	return t.arrow
end

local function hide(t)
	if t.hl then
		t.hl.Enabled = false
		t.bb.Enabled = false
	end
end

local function clearRoot(root)
	for inst, t in pairs(items) do
		if t.root == root then removeItem(inst) end
	end
end

for _, src in ipairs(SOURCES) do
	src.root = nil
	src.conns = {}
end

local function bindRoot(src, folder)
	for _, c in ipairs(src.conns) do c:Disconnect() end
	src.conns = {}
	if src.root then clearRoot(src.root) end
	src.root = folder
	if not folder then return end
	for _, d in ipairs(folder:GetDescendants()) do addItem(d, src, folder) end
	table.insert(src.conns, folder.DescendantAdded:Connect(function(d)
		if src.itemName and d.Name ~= src.itemName then return end
		task.wait(0.2)
		if alive and d.Parent then addItem(d, src, folder) end
	end))
	table.insert(src.conns, folder.DescendantRemoving:Connect(removeItem))
end

do
	local scanTick = 0
	loop(2, function()
		scanTick += 1
		for _, src in ipairs(SOURCES) do
			local root = src.root
			if not root or not root.Parent then
				bindRoot(src, findFolder(src.folder))
			elseif not src.itemName or scanTick % 2 == 0 then
				for _, d in ipairs(root:GetDescendants()) do addItem(d, src, root) end
			end
		end
	end)
end

local rainbowSeq = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
})
local gradients = {}

local function addRainbow(parent)
	local g = Instance.new("UIGradient")
	g.Color = rainbowSeq
	g.Parent = parent
	table.insert(gradients, g)
	return g
end

local function addRainbowStroke(obj, thickness)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = Color3.new(1, 1, 1)
	s.Parent = obj
	addRainbow(s)
	return s
end

track(RunService.Heartbeat:Connect(function()
	local rot = (os.clock() * 120) % 360
	for _, g in ipairs(gradients) do g.Rotation = rot end
end))

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 6)
	c.Parent = obj
	return c
end

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos
	track(handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = i.Position
			startPos = target.Position
		end
	end))
	track(UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	track(UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

local pageOrder = {}
local function order(page)
	pageOrder[page] = (pageOrder[page] or 0) + 1
	return pageOrder[page]
end

local function addHeader(page, text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -6, 0, 24)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = THEME.cyan
	l.Font = Enum.Font.SourceSansBold
	l.TextSize = 17
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = order(page)
	l.Parent = page
	return l
end

local function addToggle(page, text, getter, setter)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -6, 0, 30)
	row.BackgroundTransparency = 1
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = order(page)
	row.Parent = page

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -56, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = THEME.text
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 15
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local trackF = Instance.new("Frame")
	trackF.Size = UDim2.new(0, 44, 0, 22)
	trackF.Position = UDim2.new(1, -46, 0.5, -11)
	trackF.BorderSizePixel = 0
	trackF.Parent = row
	corner(trackF, UDim.new(1, 0))

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.BackgroundColor3 = Color3.new(0, 0, 0)
	knob.BorderSizePixel = 0
	knob.Parent = trackF
	corner(knob, UDim.new(1, 0))

	local function refresh()
		local on = getter()
		trackF.BackgroundColor3 = on and THEME.green or Color3.new(1, 1, 1)
		knob.Position = on and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
	end
	refresh()
	row.MouseButton1Click:Connect(function()
		setter(not getter())
		refresh()
	end)
	return refresh
end

local function addInput(page, text, default, placeholder)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 30)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order(page)
	row.Parent = page

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.5, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = THEME.text
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 14
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.5, -4, 0, 26)
	box.Position = UDim2.new(0.5, 0, 0, 2)
	box.BackgroundColor3 = THEME.input
	box.BorderSizePixel = 0
	box.Text = default
	box.PlaceholderText = placeholder or ""
	box.PlaceholderColor3 = THEME.sub
	box.TextColor3 = THEME.text
	box.Font = Enum.Font.SourceSans
	box.TextSize = 15
	box.ClearTextOnFocus = false
	box.Parent = row
	corner(box, UDim.new(0, 6))
	return box
end

local function addRange(page, key)
	local box = addInput(page, "Tầm xa (m):", tostring(CFG[key].range))
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n and n > 0 then CFG[key].range = n else box.Text = tostring(CFG[key].range) end
	end)
	return box
end

local function addButtonRow(page, specs)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 32)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order(page)
	row.Parent = page
	local n = #specs
	local btns = {}
	for i, s in ipairs(specs) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1 / n, -4, 1, 0)
		b.Position = UDim2.new((i - 1) / n, 2, 0, 0)
		b.BackgroundColor3 = s[2]
		b.BorderSizePixel = 0
		b.Text = s[1]
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.SourceSansBold
		b.TextSize = 15
		b.Parent = row
		corner(b, UDim.new(0, 6))
		btns[i] = b
	end
	return unpack(btns)
end

local WIN_W, WIN_H = 460, 330
local SIDE_W = 110

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, WIN_W, 0, WIN_H)
frame.Position = UDim2.new(0, 40, 0.12, 0)
frame.BackgroundColor3 = THEME.win
frame.BorderSizePixel = 0
frame.Parent = gui
corner(frame, UDim.new(0, 16))
addRainbowStroke(frame, 4)

local divider = Instance.new("Frame")
divider.Size = UDim2.new(0, 3, 1, -16)
divider.Position = UDim2.new(0, SIDE_W, 0, 8)
divider.BackgroundColor3 = THEME.cyan
divider.BorderSizePixel = 0
divider.Parent = frame

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, SIDE_W, 1, 0)
sidebar.BackgroundTransparency = 1
sidebar.Parent = frame
do
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 10)
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = sidebar
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.Parent = sidebar
end

local panel = Instance.new("Frame")
panel.Position = UDim2.new(0, SIDE_W + 10, 0, 8)
panel.Size = UDim2.new(1, -(SIDE_W + 18), 1, -16)
panel.BackgroundColor3 = THEME.panel
panel.BorderSizePixel = 0
panel.Parent = frame
corner(panel, UDim.new(0, 14))

local header = Instance.new("Frame")
header.Position = UDim2.new(0, 8, 0, 8)
header.Size = UDim2.new(1, -16, 0, 30)
header.BackgroundColor3 = THEME.cyan
header.BorderSizePixel = 0
header.Parent = panel
corner(header, UDim.new(1, 0))
makeDraggable(header, frame)

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -70, 1, 0)
headerTitle.Position = UDim2.new(0, 12, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Text = "ESP"
headerTitle.TextColor3 = THEME.dark
headerTitle.Font = Enum.Font.SourceSansBold
headerTitle.TextSize = 16
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 26, 0, 26)
minBtn.Position = UDim2.new(1, -56, 0, 2)
minBtn.BackgroundTransparency = 1
minBtn.Text = "_"
minBtn.TextColor3 = THEME.dark
minBtn.Font = Enum.Font.SourceSansBold
minBtn.TextSize = 18
minBtn.Parent = header

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 26, 0, 26)
close.Position = UDim2.new(1, -28, 0, 2)
close.BackgroundTransparency = 1
close.Text = "X"
close.TextColor3 = Color3.fromRGB(190, 30, 30)
close.Font = Enum.Font.SourceSansBold
close.TextSize = 16
close.Parent = header

local mini = Instance.new("TextButton")
mini.Size = UDim2.new(0, 44, 0, 44)
mini.Position = UDim2.new(0, 40, 0.12, 0)
mini.BackgroundColor3 = THEME.win
mini.Text = "+"
mini.TextColor3 = Color3.new(1, 1, 1)
mini.Font = Enum.Font.SourceSansBold
mini.TextSize = 26
mini.Visible = false
mini.Parent = gui
corner(mini, UDim.new(0, 12))
addRainbowStroke(mini, 3)
makeDraggable(mini, mini)

local function setWindowVisible(v)
	if v then
		frame.Position = mini.Position
	else
		mini.Position = frame.Position
	end
	frame.Visible = v
	mini.Visible = not v
end
minBtn.MouseButton1Click:Connect(function() setWindowVisible(false) end)
mini.MouseButton1Click:Connect(function() setWindowVisible(true) end)

local TABS = {
	{ id = "ESP", title = "ESP" },
	{ id = "Fly", title = "FLY" },
}
local pages, tabBtns = {}, {}

local function selectTab(id)
	for pid, p in pairs(pages) do p.Visible = (pid == id) end
	for pid, b in pairs(tabBtns) do b.stroke.Enabled = (pid == id) end
	for _, t in ipairs(TABS) do
		if t.id == id then headerTitle.Text = t.title end
	end
end

for i, t in ipairs(TABS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -20, 0, 30)
	b.BackgroundColor3 = THEME.cyan
	b.BorderSizePixel = 0
	b.Text = t.title
	b.TextColor3 = THEME.dark
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 14
	b.LayoutOrder = i
	b.Parent = sidebar
	corner(b, UDim.new(1, 0))
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.new(1, 1, 1)
	st.Enabled = false
	st.Parent = b
	tabBtns[t.id] = { stroke = st }
	b.MouseButton1Click:Connect(function() selectTab(t.id) end)

	local p = Instance.new("ScrollingFrame")
	p.Position = UDim2.new(0, 8, 0, 46)
	p.Size = UDim2.new(1, -16, 1, -54)
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	p.ScrollBarThickness = 3
	p.CanvasSize = UDim2.new(0, 0, 0, 0)
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.ScrollingDirection = Enum.ScrollingDirection.Y
	p.Visible = false
	p.Parent = panel
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 6)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = p
	pages[t.id] = p
end

local flyOn = false
local flySpeed = 50
local flyBoost = 120
local upHeld, downHeld = false, false
local flyState = nil
local refreshFlyBtn

local function stopFlyObjs()
	local s = flyState
	if not s then return end
	flyState = nil
	for _, p in ipairs(s.parts) do
		if p then p:Destroy() end
	end
	if s.humanoid.Parent and s.humanoid.Health > 0 then
		s.humanoid.PlatformStand = false
		s.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function startFlyObjs()
	if flyState then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end

	local att = Instance.new("Attachment")
	att.Name = "FlyAttachment"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "FlyVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "FlyTurn"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 60
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root

	hum.PlatformStand = true
	flyState = { root = root, humanoid = hum, parts = { att, lv, ao }, velocity = lv, turn = ao }
end

local function setFly(v)
	flyOn = v
	if v then startFlyObjs() else stopFlyObjs() end
	if refreshFlyBtn then refreshFlyBtn() end
end

local conRender = track(RunService.RenderStepped:Connect(function(dt)
	local s = flyState
	if not s then return end
	if not s.root.Parent or s.humanoid.Health <= 0 then
		stopFlyObjs()
		return
	end

	s.humanoid.PlatformStand = true
	local cam = workspace.CurrentCamera.CFrame
	local flat = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
	local fwd = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local right = fwd:Cross(Vector3.new(0, 1, 0))
	local move = s.humanoid.MoveDirection
	local dir = cam.LookVector * move:Dot(fwd) + cam.RightVector * move:Dot(right)

	if not UIS:GetFocusedTextBox() then
		if UIS:IsKeyDown(Enum.KeyCode.Space) or upHeld
			or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA) then
			dir += Vector3.new(0, 1, 0)
		end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or downHeld then
			dir -= Vector3.new(0, 1, 0)
		end
	end

	if dir.Magnitude > 1 then dir = dir.Unit end

	local fast = UIS:IsKeyDown(Enum.KeyCode.LeftShift)
		or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3)
	local spd = fast and flyBoost or flySpeed

	s.velocity.VectorVelocity = s.velocity.VectorVelocity:Lerp(dir * spd, math.min(1, dt * 8))
	local _, yaw = cam:ToOrientation()
	s.turn.CFrame = CFrame.Angles(0, yaw, 0)
end))

track(player.CharacterAdded:Connect(function(char)
	flyState = nil
	if not flyOn then return end
	char:WaitForChild("HumanoidRootPart", 10)
	char:WaitForChild("Humanoid", 10)
	if alive and flyOn then startFlyObjs() end
end))

track(RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local cfg = CFG.NPC
	local myRoot = myRootPart()
	local vp = cam.ViewportSize
	local cx, cy = vp.X / 2, vp.Y / 2
	local halfW, halfH = cx - 32, cy - 22

	for inst, t in pairs(items) do
		local src = t.kind
		if src.esp == "NPC" then
			local want = false
			if alive and cfg.on and cfg.arrows and myRoot and inst.Parent and t.part.Parent
				and not isDead(inst, src) then
				local pos = t.part.Position
				local d = (pos - myRoot.Position).Magnitude
				if d <= cfg.range then
					local _, onScreen = cam:WorldToViewportPoint(pos)
					if not onScreen then
						want = true
						local rel = cam.CFrame:PointToObjectSpace(pos)
						local dir = Vector2.new(rel.X, -rel.Y)
						if dir.Magnitude < 0.001 then dir = Vector2.new(0, 1) else dir = dir.Unit end
						local sx = math.abs(dir.X) > 1e-4 and halfW / math.abs(dir.X) or math.huge
						local sy = math.abs(dir.Y) > 1e-4 and halfH / math.abs(dir.Y) or math.huge
						local k = math.min(sx, sy)
						local a = ensureArrow(t)
						a.holder.Position = UDim2.fromOffset(cx + dir.X * k, cy + dir.Y * k)
						a.tri.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 135
						a.lbl.Text = string.format("%dm", math.floor(d))
						a.holder.Visible = true
					end
				end
			end
			if not want and t.arrow then t.arrow.holder.Visible = false end
		end
	end
end))

local espPage = pages.ESP

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -6, 0, 18)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Đang tìm folder..."
statusLabel.TextColor3 = THEME.text
statusLabel.Font = Enum.Font.SourceSansBold
statusLabel.TextSize = 13
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.LayoutOrder = order(espPage)
statusLabel.Parent = espPage

addHeader(espPage, "ESP LOOT")
do
	local c = CFG.Loot
	addToggle(espPage, "Bật ESP Loot", function() return c.on end, function(v) c.on = v end)
	addToggle(espPage, "Hiện tên", function() return c.name end, function(v) c.name = v end)
	addToggle(espPage, "Hiện giá trị", function() return c.val end, function(v) c.val = v end)
	addToggle(espPage, "Hiện khoảng cách", function() return c.dist end, function(v) c.dist = v end)
	local searchBox = addInput(espPage, "Tìm tên:", "", "gold, cash...")
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		filterTerms = {}
		for term in string.gmatch(searchBox.Text:lower(), "[^,]+") do
			local trimmed = term:match("^%s*(.-)%s*$")
			if trimmed ~= "" then table.insert(filterTerms, trimmed) end
		end
	end)
	addRange(espPage, "Loot")
end

addHeader(espPage, "ESP AC")
do
	local c = CFG.AC
	addToggle(espPage, "Bật ESP AC", function() return c.on end, function(v) c.on = v end)
	addToggle(espPage, "Hiện khoảng cách", function() return c.dist end, function(v) c.dist = v end)
	addRange(espPage, "AC")
end

addHeader(espPage, "ESP NPC")
do
	local c = CFG.NPC
	addToggle(espPage, "Bật ESP NPC", function() return c.on end, function(v) c.on = v end)
	addToggle(espPage, "Hiện khoảng cách", function() return c.dist end, function(v) c.dist = v end)
	addToggle(espPage, "Arrow", function() return c.arrows end, function(v) c.arrows = v end)
	addRange(espPage, "NPC")
end

addHeader(espPage, "CHUNG")
do
	local fontBox = addInput(espPage, "Cỡ chữ (8-40):", tostring(TEXT_MAX))
	fontBox.FocusLost:Connect(function()
		local n = tonumber(fontBox.Text)
		if n and n >= 8 and n <= 40 then TEXT_MAX = math.floor(n) end
		fontBox.Text = tostring(TEXT_MAX)
	end)
end

local flyPage = pages.Fly

refreshFlyBtn = addToggle(flyPage, "Fly (phím F)", function() return flyOn end, function(v) setFly(v) end)

local flySpeedBox = addInput(flyPage, "Tốc độ:", tostring(flySpeed))
flySpeedBox.FocusLost:Connect(function()
	local n = tonumber(flySpeedBox.Text)
	if n and n > 0 and n <= 500 then flySpeed = n end
	flySpeedBox.Text = tostring(flySpeed)
end)

local flyBoostBox = addInput(flyPage, "Tốc độ nhanh:", tostring(flyBoost))
flyBoostBox.FocusLost:Connect(function()
	local n = tonumber(flyBoostBox.Text)
	if n and n > 0 and n <= 500 then flyBoost = n end
	flyBoostBox.Text = tostring(flyBoost)
end)

local upBtn, downBtn = addButtonRow(flyPage, {
	{ "Lên (giữ)", Color3.fromRGB(60, 110, 200) },
	{ "Xuống (giữ)", Color3.fromRGB(60, 110, 200) },
})
local function holdBind(btn, setter)
	btn.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			setter(true)
		end
	end)
	btn.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			setter(false)
		end
	end)
end
holdBind(upBtn, function(v) upHeld = v end)
holdBind(downBtn, function(v) downHeld = v end)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -6, 0, 64)
hint.BackgroundTransparency = 1
hint.Text = "WASD: bay theo hướng camera\nSpace / Ctrl: lên / xuống\nShift: bay nhanh\nRightShift: ẩn / hiện bảng"
hint.TextColor3 = THEME.sub
hint.Font = Enum.Font.SourceSans
hint.TextSize = 14
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextYAlignment = Enum.TextYAlignment.Top
hint.LayoutOrder = order(flyPage)
hint.Parent = flyPage

track(UIS.InputBegan:Connect(function(i, gp)
	if gp or not alive or UIS:GetFocusedTextBox() then return end
	if i.KeyCode == Enum.KeyCode.F then
		setFly(not flyOn)
	elseif i.KeyCode == Enum.KeyCode.RightShift then
		setWindowVisible(not frame.Visible)
	end
end))

close.MouseButton1Click:Connect(function()
	alive = false
	setFly(false)
	for _, c in ipairs(connections) do c:Disconnect() end
	for _, src in ipairs(SOURCES) do
		for _, c in ipairs(src.conns) do c:Disconnect() end
	end
	for inst in pairs(items) do removeItem(inst) end
	gui:Destroy()
end)

selectTab("ESP")

loop(0.25, function()
	local myRoot = myRootPart()

	local visible = {}
	local counts = { Loot = 0, AC = 0, NPC = 0 }

	for inst, t in pairs(items) do
		if not inst.Parent or not t.part.Parent then
			removeItem(inst)
		else
			local src = t.kind
			local cfg = CFG[src.esp]
			counts[src.esp] += 1
			local d = myRoot and (t.part.Position - myRoot.Position).Magnitude or math.huge

			local show = cfg.on and myRoot ~= nil and d <= cfg.range
			if show and src.esp == "Loot" and not matches(inst.Name) then show = false end
			if show and isDead(inst, src) then show = false end

			if show then
				table.insert(visible, { inst = inst, t = t, d = d })
			else
				hide(t)
			end
		end
	end

	table.sort(visible, function(a, b) return a.d < b.d end)

	for i, v in ipairs(visible) do
		local inst, t, d = v.inst, v.t, v.d
		local src = t.kind
		local cfg = CFG[src.esp]
		ensureVisuals(inst, t)

		local col = src.color
		local txtCol = (src.esp == "Loot") and Color3.new(1, 1, 1) or src.color
		if src.esp == "Loot" and cfg.val then
			local rarity = inst:GetAttribute("Rarity")
			if rarity and RARITY_COLORS[rarity] then
				col = RARITY_COLORS[rarity]
				txtCol = col
			end
		end
		t.hl.FillColor = col
		t.label.TextColor3 = txtCol
		t.hl.Enabled = i <= MAX_HIGHLIGHTS

		local lines = {}
		if src.esp == "Loot" then
			local line1 = {}
			if cfg.name then table.insert(line1, inst.Name) end
			if cfg.dist then table.insert(line1, string.format("[%dm]", math.floor(d))) end
			if #line1 > 0 then table.insert(lines, table.concat(line1, " ")) end
			if cfg.val then
				local value = getValue(inst)
				if value then table.insert(lines, "$" .. fmtNum(value)) end
			end
		else
			if cfg.dist then table.insert(lines, string.format("[%dm]", math.floor(d))) end
		end

		t.label.Text = table.concat(lines, "\n")
		t.label.TextSize = textSizeFor(d, cfg.range)
		t.bb.Enabled = #lines > 0
	end

	local found = false
	for _, src in ipairs(SOURCES) do
		if src.root and src.root.Parent then found = true end
	end
	if found then
		statusLabel.Text = string.format("Loot %d | NPC %d | AC %d | hiện: %d",
			counts.Loot, counts.NPC, counts.AC, #visible)
		statusLabel.TextColor3 = THEME.text
	else
		statusLabel.Text = "Không thấy folder nào"
		statusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	end
end)