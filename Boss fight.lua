--[[
    CONSOLE_ROOT  //  BOSS FIGHT v2   (client-side LocalScript, run via Delta)
    - Boss = a clone of YOUR avatar
    - Phase 1 CALM    : runs, flees, walks to map parts, grabs them, throws them
    - Phase 2 ENRAGED : cutscene, flies up, telekinesis throws, rainbow spinning parts
    - Phase 3 MANIAC  : cutscene, glitch dialogue, command spam, neon-black clones (5 dmg/hit), SystemSword
    Everything is local (only you see it). Stop it any time with:  _G.CR_CLEANUP()
]]

local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local TS       = game:GetService("TweenService")
local Debris   = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

local LP  = Players.LocalPlayer
local Cam = workspace.CurrentCamera
local rnd = Random.new()

if _G.CR_CLEANUP then pcall(_G.CR_CLEANUP) end

----------------------------------------------------------------------
-- STATE / HELPERS
----------------------------------------------------------------------
local S = {
	phase = 0, hp = 100, running = true, busy = true, hover = false, over = false,
	conns = {}, objs = {}, restore = {}, hidden = {}, rb = {}, clones = {}, projs = {},
	lastCmd = 0, nextMove = 0, nextThrow = 0, dir = 1,
}
local Boss, BH, BR, R15
local BAnim = {}

local function track(o) S.objs[#S.objs + 1] = o return o end
local function on(sig, f) local c = sig:Connect(f) S.conns[#S.conns + 1] = c return c end
local function pHum() local c = LP.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function pRoot() local c = LP.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function mk(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end

local startHum = pHum()
if not startHum then warn("[CONSOLE_ROOT] spawn your character first") return end
S.ws, S.jp, S.jh = startHum.WalkSpeed, startHum.JumpPower, startHum.JumpHeight

S.folder = track(mk("Folder", {Name = "CR_FX"}, workspace))
S.cc = track(mk("ColorCorrectionEffect", {TintColor = Color3.new(1, 1, 1)}, Lighting))
track(mk("BloomEffect", {Intensity = 0.5, Size = 24, Threshold = 1}, Lighting))

----------------------------------------------------------------------
-- UI  (boss bar, CRT terminal banner, dialogue, black screen, flash)
----------------------------------------------------------------------
local gui = mk("ScreenGui", {Name = "CONSOLE_ROOT_UI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999}, nil)
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
track(gui)

local barBG = mk("Frame", {Size = UDim2.fromScale(0.5, 0.035), Position = UDim2.fromScale(0.25, 0.04), BackgroundColor3 = Color3.fromRGB(15, 0, 0), BorderSizePixel = 0}, gui)
mk("UIStroke", {Color = Color3.fromRGB(255, 40, 40), Thickness = 2}, barBG)
local barFill = mk("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(80, 255, 120), BorderSizePixel = 0}, barBG)
local barText = mk("TextLabel", {Size = UDim2.fromScale(1, 1.1), Position = UDim2.fromScale(0, -1.2), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.Code, TextScaled = true, Text = ""}, barBG)

local term = mk("Frame", {Size = UDim2.fromScale(0.62, 0.075), Position = UDim2.fromScale(0.19, 0.1), BackgroundColor3 = Color3.fromRGB(0, 14, 0), BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false}, gui)
mk("UIStroke", {Color = Color3.fromRGB(0, 255, 70), Thickness = 2}, term)
mk("UICorner", {CornerRadius = UDim.new(0, 6)}, term)
local termTxt = mk("TextLabel", {Size = UDim2.fromScale(0.97, 0.9), Position = UDim2.fromScale(0.015, 0.05), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(0, 255, 70), Font = Enum.Font.Code, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Text = ""}, term)
for i = 0, 7 do -- CRT scanlines
	mk("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, i / 8, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, BorderSizePixel = 0}, term)
end

local dlg = mk("TextLabel", {Size = UDim2.fromScale(0.8, 0.09), Position = UDim2.fromScale(0.1, 0.8), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(255, 60, 60), TextStrokeTransparency = 0, Font = Enum.Font.Code, TextScaled = true, Text = ""}, gui)
local blk = mk("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50}, gui)
local blkTxt = mk("TextLabel", {Size = UDim2.fromScale(0.6, 0.12), Position = UDim2.fromScale(0.2, 0.44), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(0, 255, 70), Font = Enum.Font.Code, TextScaled = true, Text = "", ZIndex = 51}, gui)
local flash = mk("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 40}, gui)

local termTok = 0
local function Term(txt) -- pops up instantly
	termTok += 1
	local my = termTok
	termTxt.Text = "root@console:~# " .. txt .. " █"
	term.Visible = true
	task.spawn(function()
		for _ = 1, 3 do termTxt.TextTransparency = 0.55 task.wait(0.03) termTxt.TextTransparency = 0 task.wait(0.03) end
	end)
	task.delay(2.6, function() if termTok == my then term.Visible = false end end)
end

local function Flash(a)
	flash.BackgroundTransparency = 1 - a
	TS:Create(flash, TweenInfo.new(0.45), {BackgroundTransparency = 1}):Play()
end

local function Bubble(txt)
	local head = Boss and Boss:FindFirstChild("Head")
	if not head then return end
	local old = head:FindFirstChild("CR_Bubble")
	if old then old:Destroy() end
	local b = mk("BillboardGui", {Name = "CR_Bubble", Size = UDim2.fromOffset(280, 46), StudsOffset = Vector3.new(0, 3.2, 0), AlwaysOnTop = true}, head)
	mk("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.2, TextColor3 = Color3.fromRGB(0, 255, 70), Font = Enum.Font.Code, TextScaled = true, Text = txt}, b)
	Debris:AddItem(b, 2.6)
end

local function Say(txt, hold, glitch)
	Bubble(txt)
	for i = 1, #txt do
		if not S.running then return end
		dlg.Text = txt:sub(1, i)
		task.wait(0.045)
	end
	local t0 = os.clock()
	while os.clock() - t0 < hold and S.running do
		if glitch then
			local o = {}
			for ch in txt:gmatch(".") do
				o[#o + 1] = (rnd:NextNumber() < 0.15) and string.char(rnd:NextInteger(33, 126)) or ch
			end
			dlg.Text = table.concat(o)
		end
		task.wait(0.06)
	end
	dlg.Text = ""
end

----------------------------------------------------------------------
-- CAMERA (cutscene camera + shake)
----------------------------------------------------------------------
local cine, shakeT, shakeI = nil, 0, 0
RS:BindToRenderStep("CR_CAM", Enum.RenderPriority.Camera.Value + 1, function()
	if cine then Cam.CFrame = cine() end
end)
RS:BindToRenderStep("CR_SHAKE", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if shakeT > 0 then
		shakeT -= dt
		local k = shakeI * math.clamp(shakeT * 2, 0, 1) * 0.25
		Cam.CFrame = Cam.CFrame * CFrame.new(rnd:NextNumber(-k, k), rnd:NextNumber(-k, k), 0) * CFrame.Angles(0, 0, math.rad(rnd:NextNumber(-k, k) * 2))
	end
end)
local function Shake(i, d)
	if shakeT <= 0 then shakeI = 0 end
	shakeI = math.max(shakeI, i)
	shakeT = math.max(shakeT, d)
end
local function StartCine(fn) Cam.CameraType = Enum.CameraType.Scriptable cine = fn end
local function EndCine()
	cine = nil
	Cam.CameraType = Enum.CameraType.Custom
	local h = pHum()
	if h then Cam.CameraSubject = h end
end
local function Lock(on_)
	local h = pHum()
	if not h then return end
	if on_ then h.WalkSpeed = 0 h.JumpPower = 0 h.JumpHeight = 0
	else h.WalkSpeed = S.ws h.JumpPower = S.jp h.JumpHeight = S.jh end
end

----------------------------------------------------------------------
-- FX HELPERS
----------------------------------------------------------------------
local function Boom(pos, size)
	local e = Instance.new("Explosion")
	e.Position = pos e.BlastRadius = size or 6 e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0 e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = workspace
	Debris:AddItem(e, 3)
end
local function NewNeon(color, tr)
	return mk("Part", {Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.Neon, Color = color, Transparency = tr or 0, Size = Vector3.one}, S.folder)
end
local function Seg(part, a, b, w)
	part.Size = Vector3.new(w, w, math.max((b - a).Magnitude, 0.1))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end
local function Hurt(n)
	if S.over then return end
	local h = pHum()
	if h and h.Health > 0 then
		h:TakeDamage(n)
		Flash(0.45) Shake(1.2, 0.35)
	end
end

----------------------------------------------------------------------
-- BOSS (your own avatar)
----------------------------------------------------------------------
local function MakeBoss()
	local c = LP.Character
	c.Archivable = true
	Boss = c:Clone()
	for _, d in ipairs(Boss:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") then d:Destroy() end
	end
	Boss.Name = "CONSOLE_ROOT"
	BH = Boss:FindFirstChildOfClass("Humanoid")
	BR = Boss:FindFirstChild("HumanoidRootPart")
	R15 = BH.RigType == Enum.HumanoidRigType.R15
	BH.DisplayName = "CONSOLE_ROOT"
	BH.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	BH.MaxHealth = 1e9 BH.Health = 1e9
	BH.WalkSpeed = 22 BH.UseJumpPower = true BH.JumpPower = 55
	local pr = pRoot()
	Boss.Parent = workspace
	Boss:PivotTo(CFrame.new(pr.Position + pr.CFrame.LookVector * 45 + Vector3.new(0, 3, 0)))
	track(Boss)
	S.hl = mk("Highlight", {FillColor = Color3.new(0, 0, 0), OutlineColor = Color3.fromRGB(255, 0, 0), FillTransparency = 0.55, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop}, Boss)
	local an = BH:FindFirstChildOfClass("Animator") or mk("Animator", {}, BH)
	local function load(id)
		local t = an:LoadAnimation(mk("Animation", {AnimationId = "rbxassetid://" .. id}))
		t.Looped = true
		return t
	end
	BAnim.idle = load(R15 and 507766666 or 180435571)
	BAnim.run = load(R15 and 507767714 or 180426354)
	BAnim.idle:Play()
end

local motorOrig = {}
local function Pose(active) -- hero / flying arm pose (tuned for R15)
	local ms = {}
	for _, m in ipairs(Boss:GetDescendants()) do if m:IsA("Motor6D") then ms[m.Name] = m end end
	local function setm(n, delta)
		local m = ms[n]
		if m then
			motorOrig[m] = motorOrig[m] or m.C0
			m.C0 = active and (motorOrig[m] * delta) or motorOrig[m]
		end
	end
	setm(R15 and "RightShoulder" or "Right Shoulder", CFrame.Angles(0, 0, math.rad(70)))
	setm(R15 and "LeftShoulder" or "Left Shoulder", CFrame.Angles(0, 0, math.rad(-70)))
end

local function WalkTo(pos, timeout, stopDist)
	local t0 = os.clock()
	while S.running and not S.busy and os.clock() - t0 < timeout do
		if flat(BR.Position - pos).Magnitude < stopDist then return true end
		BH:MoveTo(pos)
		if os.clock() - t0 > 0.6 and flat(BR.AssemblyLinearVelocity).Magnitude < 1 then BH.Jump = true end
		task.wait(0.15)
	end
	return false
end

local function Flee(dur)
	local t0 = os.clock()
	BH.WalkSpeed = 27
	while S.running and not S.busy and os.clock() - t0 < dur do
		local pr = pRoot()
		if not pr then break end
		local away = flat(BR.Position - pr.Position)
		if away.Magnitude < 1 then away = Vector3.new(1, 0, 0) end
		local side = Vector3.new(-away.Z, 0, away.X).Unit * rnd:NextNumber(-20, 20)
		BH:MoveTo(BR.Position + away.Unit * 30 + side)
		if flat(BR.AssemblyLinearVelocity).Magnitude < 2 then BH.Jump = true end
		if away.Magnitude > 50 then break end
		task.wait(0.2)
	end
	BH.WalkSpeed = 22
end

----------------------------------------------------------------------
-- MAP PARTS / PROJECTILES
----------------------------------------------------------------------
local partCache, cacheT = {}, 0
local function isCharPart(p)
	local m = p:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then return true end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return false
end
local function Parts()
	if os.clock() - cacheT < 8 and #partCache > 0 then return partCache end
	cacheT = os.clock()
	partCache = {}
	local pr = pRoot()
	if not pr then return partCache end
	for _, p in ipairs(workspace:GetDescendants()) do
		if p:IsA("BasePart") and not p:IsA("Terrain") and p.Transparency < 0.9 and (p.Position - pr.Position).Magnitude < 140 then
			local m = p.Size.Magnitude
			if m > 1.5 and m < 16 and not p:IsDescendantOf(S.folder) and not p:IsDescendantOf(Boss) and not isCharPart(p) then
				partCache[#partCache + 1] = p
			end
		end
	end
	return partCache
end

local function PickPart(maxBoss)
	local pr = pRoot()
	local list = {}
	for _, p in ipairs(Parts()) do
		if p.Parent and p.LocalTransparencyModifier < 1 and (p.Position - BR.Position).Magnitude < maxBoss
			and (not pr or (p.Position - pr.Position).Magnitude > 12) then
			list[#list + 1] = p
		end
	end
	if #list == 0 then return nil end
	return list[rnd:NextInteger(1, #list)]
end

local function NewProj(src)
	local sz = src.Size
	local p = mk("Part", {
		Size = Vector3.new(math.clamp(sz.X, 1, 7), math.clamp(sz.Y, 1, 7), math.clamp(sz.Z, 1, 7)),
		Color = src.Color, Material = src.Material, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CFrame = src.CFrame,
	}, S.folder)
	S.hidden[src] = true
	src.LocalTransparencyModifier = 1
	task.delay(6, function() if src.Parent then src.LocalTransparencyModifier = 0 S.hidden[src] = nil end end)
	mk("Highlight", {FillTransparency = 1, OutlineColor = Color3.fromRGB(255, 60, 60)}, p)
	return p
end

-- forward declarations
local Advance, UpdateBar, DamageBoss

local function GiveProp()
	local bp = LP:FindFirstChildOfClass("Backpack")
	if not bp then return end
	local tool = mk("Tool", {Name = "Prop", RequiresHandle = true, CanBeDropped = false, ToolTip = "Throw at CONSOLE_ROOT (15 dmg)"})
	mk("Part", {Name = "Handle", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 170, 0)}, tool)
	tool.Parent = bp
	tool.Activated:Connect(function()
		if S.busy or S.over or not Boss then return end
		local h = tool:FindFirstChild("Handle")
		local pr = pRoot()
		local startPos = h and h.Position or (pr and pr.Position) or BR.Position
		tool:Destroy()
		local p = mk("Part", {Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 170, 0), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Position = startPos}, S.folder)
		task.spawn(function()
			local t0 = os.clock()
			while S.running and p.Parent and os.clock() - t0 < 5 do
				local dt = RS.Heartbeat:Wait()
				local d = BR.Position - p.Position
				if d.Magnitude < 5 then p:Destroy() DamageBoss(15) return end
				p.Position = p.Position + d.Unit * 85 * dt
			end
			p:Destroy()
		end)
	end)
end

local function PropHit(p)
	S.projs[p] = nil
	p:Destroy()
	if rnd:NextNumber() < 0.7 then
		Term("CATCH SUCCESS :: Prop acquired")
		GiveProp()
	else
		local d = 8 * S.phase
		Term("CATCH FAILED :: -" .. d .. " HP")
		Hurt(d)
	end
end

local function ThrowAtPlayer(p)
	local pr = pRoot()
	if not pr then p:Destroy() return end
	local speed = 45 + S.phase * 15
	local d0 = (pr.Position - p.Position).Magnitude
	local aim = pr.Position + pr.AssemblyLinearVelocity * (d0 / speed) * 0.7 -- predicts your movement
	local dir = (aim - p.Position).Unit
	S.projs[p] = true
	task.spawn(function()
		local t0 = os.clock()
		while S.running and p.Parent and os.clock() - t0 < 4 do
			local dt = RS.Heartbeat:Wait()
			p.CFrame = p.CFrame * CFrame.Angles(dt * 6, dt * 5, 0) + dir * speed * dt
			local r = pRoot()
			if r and (r.Position - p.Position).Magnitude < p.Size.Magnitude / 2 + 3 then
				PropHit(p)
				return
			end
		end
		S.projs[p] = nil
		if p.Parent then p:Destroy() end
	end)
end

----------------------------------------------------------------------
-- BOSS HEALTH
----------------------------------------------------------------------
local PH_COL = {Color3.fromRGB(80, 255, 120), Color3.fromRGB(255, 170, 0), Color3.fromRGB(255, 40, 40)}
local PH_NAME = {"CALM", "ENRAGED", "MANIAC"}
UpdateBar = function()
	TS:Create(barFill, TweenInfo.new(0.2), {Size = UDim2.fromScale(math.clamp(S.hp / 100, 0, 1), 1), BackgroundColor3 = PH_COL[S.phase] or PH_COL[1]}):Play()
	barText.Text = ("CONSOLE_ROOT // PHASE %d/3 :: %s  [%d/100]"):format(math.max(S.phase, 1), PH_NAME[S.phase] or "BOOTING", math.max(0, math.floor(S.hp)))
end
DamageBoss = function(n)
	if S.busy or S.over or S.hp <= 0 then return end
	S.hp -= n
	Boom(BR.Position, 4) Shake(0.6, 0.3)
	S.hl.FillTransparency = 0
	task.delay(0.1, function() if S.hl.Parent then S.hl.FillTransparency = 0.55 end end)
	UpdateBar()
	if S.hp <= 0 then S.busy = true task.spawn(Advance) end
end

----------------------------------------------------------------------
-- CLONES (phase 3)  +  SYSTEM SWORD
----------------------------------------------------------------------
local function SpawnClone(pos)
	if #S.clones >= 9 or S.over then return end
	local c = LP.Character
	if not c then return end
	c.Archivable = true
	local m = c:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("Accessory") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") or d:IsA("CharacterMesh") then
			d:Destroy()
		end
	end
	m.Name = "CR_CLONE"
	local h = m:FindFirstChildOfClass("Humanoid")
	local r = m:FindFirstChild("HumanoidRootPart")
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Material = Enum.Material.Neon d.Color = Color3.new(0, 0, 0) end
	end
	h.MaxHealth = 1000 h.Health = 1000 h.WalkSpeed = 18
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	mk("Highlight", {FillColor = Color3.new(0, 0, 0), OutlineColor = Color3.fromRGB(0, 255, 255), FillTransparency = 0}, m)
	m.Parent = S.folder
	m:PivotTo(CFrame.new(pos))
	local an = h:FindFirstChildOfClass("Animator") or mk("Animator", {}, h)
	local run = an:LoadAnimation(mk("Animation", {AnimationId = "rbxassetid://" .. (h.RigType == Enum.HumanoidRigType.R15 and 507767714 or 180426354)}))
	run.Looped = true
	run:Play()
	S.clones[#S.clones + 1] = {m = m, h = h, r = r, hp = 100, cd = 0}
	Boom(pos, 4) Shake(0.5, 0.25)
end

local function SpawnClones(n)
	local pr = pRoot()
	if not pr then return end
	for i = 1, n do
		local a = rnd:NextNumber(0, math.pi * 2)
		SpawnClone(pr.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * rnd:NextNumber(22, 32) + Vector3.new(0, 4, 0))
	end
end

local function GiveSword()
	local bp = LP:FindFirstChildOfClass("Backpack")
	if not bp then return end
	local tool = mk("Tool", {
		Name = "SystemSword", RequiresHandle = true, CanBeDropped = false, ToolTip = "25 dmg per slash",
		GripPos = Vector3.new(0, 0, -1.5), GripForward = Vector3.new(-1, 0, 0), GripRight = Vector3.new(0, 1, 0), GripUp = Vector3.new(0, 0, 1),
	})
	mk("Part", {Name = "Handle", Size = Vector3.new(1, 0.8, 4), Material = Enum.Material.Neon, Color = Color3.fromRGB(0, 255, 255)}, tool)
	tool.Parent = bp
	local last = 0
	tool.Activated:Connect(function()
		if os.clock() - last < 0.45 then return end
		last = os.clock()
		local pr = pRoot()
		if not pr then return end
		for _, ang in ipairs({50, -50}) do
			local fx = NewNeon(Color3.fromRGB(0, 255, 255), 0.25)
			fx.Size = Vector3.new(10, 0.3, 0.3)
			fx.CFrame = pr.CFrame * CFrame.Angles(0, math.rad(ang), 0) * CFrame.new(0, 0.5, -5)
			TS:Create(fx, TweenInfo.new(0.2), {Transparency = 1}):Play()
			Debris:AddItem(fx, 0.25)
			task.wait(0.07)
		end
		for _, c in ipairs(S.clones) do
			local v = c.r.Position - pr.Position
			if v.Magnitude < 10 and v.Magnitude > 0.1 and v.Unit:Dot(pr.CFrame.LookVector) > 0.1 then
				c.hp -= 25
				Shake(0.4, 0.15)
				if c.hp <= 0 then
					Boom(c.r.Position, 3)
					c.m:Destroy()
				end
			end
		end
	end)
end

task.spawn(function() -- clone brain (one loop for all clones = cheap)
	while S.running do
		task.wait(0.15)
		local pr = pRoot()
		if pr then
			for i = #S.clones, 1, -1 do
				local c = S.clones[i]
				if not c.m.Parent or c.hp <= 0 then
					table.remove(S.clones, i)
				else
					c.h:MoveTo(pr.Position)
					local d = (c.r.Position - pr.Position).Magnitude
					if d < 5 and os.clock() > c.cd and not S.busy then
						c.cd = os.clock() + 1.2
						Hurt(5)
					end
					if c.r.AssemblyLinearVelocity.Magnitude < 1 then c.h.Jump = true end
					if d > 220 then c.m:PivotTo(CFrame.new(pr.Position + Vector3.new(20, 4, 0))) end
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- BOSS COMMANDS
----------------------------------------------------------------------
local Cmd = {}

function Cmd.laser()
	local pr = pRoot()
	if not pr or not Boss then return end
	Term(";laser " .. LP.Name)
	local head = Boss.Head
	local line = NewNeon(Color3.fromRGB(255, 0, 0), 0.4)
	local aim = pr.Position
	for i = 1, 12 do -- tracks you, then locks
		if not S.running then line:Destroy() return end
		local r = pRoot()
		if r then aim = aim:Lerp(r.Position, 0.35) end
		Seg(line, head.Position, head.Position + (aim - head.Position).Unit * 150, 0.25)
		line.Transparency = (i % 2 == 0) and 0.6 or 0.2
		task.wait(0.06)
	end
	local origin = head.Position
	local dir = (aim - origin).Unit
	line.Color = Color3.new(1, 1, 1) line.Transparency = 0
	Seg(line, origin, origin + dir * 150, 2.2)
	Shake(1.5, 0.4) Boom(aim, 5)
	local r = pRoot()
	if r then
		local rel = r.Position - origin
		local proj = rel:Dot(dir)
		if proj > 0 and (rel - dir * proj).Magnitude < 3.5 then Hurt(8 + 4 * S.phase) end
	end
	TS:Create(line, TweenInfo.new(0.35), {Transparency = 1}):Play()
	Debris:AddItem(line, 0.4)
end

function Cmd.slip()
	local pr, h = pRoot(), pHum()
	if not pr or not h then return end
	Term(";slip " .. LP.Name)
	h.PlatformStand = true
	local dir = flat(pr.AssemblyLinearVelocity)
	if dir.Magnitude < 1 then dir = flat(pr.CFrame.LookVector) end
	pr.AssemblyLinearVelocity = dir.Unit * 45 + Vector3.new(0, 12, 0)
	pr.AssemblyAngularVelocity = Vector3.new(rnd:NextNumber(-8, 8), rnd:NextNumber(-8, 8), rnd:NextNumber(-8, 8))
	Shake(0.8, 0.4)
	task.wait(1.4 + S.phase * 0.2)
	if h.Parent then h.PlatformStand = false h:ChangeState(Enum.HumanoidStateType.GettingUp) end
end

function Cmd.fling()
	local pr, h = pRoot(), pHum()
	if not pr or not h then return end
	Term(";fling " .. LP.Name)
	local dir = flat(pr.Position - BR.Position)
	if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, -1) end
	local v = dir.Unit * (80 + S.phase * 35) + Vector3.new(0, 55 + S.phase * 10, 0)
	h.PlatformStand = true
	Boom(pr.Position, 5) Shake(1.3, 0.5)
	for _ = 1, 8 do
		if not pr.Parent then break end
		pr.AssemblyLinearVelocity = v
		pr.AssemblyAngularVelocity = Vector3.new(20, 20, 20)
		task.wait(0.03)
	end
	Hurt(3 * S.phase)
	task.wait(1)
	if h.Parent then h.PlatformStand = false end
end

function Cmd.blackscreen()
	if S.black then return end
	S.black = true
	Term(";blackscreen " .. LP.Name)
	blk.BackgroundTransparency = 0
	blkTxt.Text = "SIGNAL LOST"
	local t0 = os.clock()
	while S.running and os.clock() - t0 < 2 + S.phase do
		blkTxt.Visible = rnd:NextNumber() < 0.7
		task.wait(0.1)
	end
	blkTxt.Text = "" blkTxt.Visible = true
	TS:Create(blk, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
	S.black = false
end

function Cmd.thaw()
	Term(";thaw " .. LP.Name)
	if S.jailParts then
		for _, p in ipairs(S.jailParts) do
			TS:Create(p, TweenInfo.new(0.3), {Transparency = 1}):Play()
			Debris:AddItem(p, 0.35)
		end
		S.jailParts = nil
	end
	if S.ice then S.ice:Destroy() S.ice = nil end
	local pr = pRoot()
	if pr then pr.Anchored = false end
	S.jailed = false S.frozen = false
end

function Cmd.freeze()
	local pr = pRoot()
	if not pr or S.frozen or S.jailed then return end
	S.frozen = true
	Term(";freeze " .. LP.Name)
	pr.Anchored = true
	local ice = NewNeon(Color3.fromRGB(150, 230, 255), 0.4)
	ice.Size = Vector3.new(5, 7, 5) ice.CFrame = pr.CFrame
	S.ice = ice
	task.wait(2.5)
	if S.frozen then Cmd.thaw() end
end

function Cmd.jail()
	local pr = pRoot()
	if not pr or S.jailed or S.frozen then return end
	S.jailed = true
	Term(";jail " .. LP.Name .. " 5")
	local c = pr.Position
	local parts = {}
	local function wall(off, size)
		local p = NewNeon(Color3.fromRGB(0, 255, 255), 0.35)
		p.Size = size p.Position = c + off
		p.CanCollide = true p.CanQuery = true
		parts[#parts + 1] = p
	end
	wall(Vector3.new(5, 2, 0), Vector3.new(0.6, 10, 10))
	wall(Vector3.new(-5, 2, 0), Vector3.new(0.6, 10, 10))
	wall(Vector3.new(0, 2, 5), Vector3.new(10, 10, 0.6))
	wall(Vector3.new(0, 2, -5), Vector3.new(10, 10, 0.6))
	wall(Vector3.new(0, 7, 0), Vector3.new(10, 0.6, 10))
	S.jailParts = parts
	Shake(0.8, 0.4) Boom(c, 4)
	if S.phase == 3 then -- maniac: clones swarm the cage, lasers into it
		task.delay(1, function() SpawnClones(3) end)
		task.delay(2.2, function() if S.jailed then Cmd.laser() end end)
	end
	task.wait(5)
	if S.jailed then Cmd.thaw() end
end

local TAUNTS = {"nowhere to hide", "i see you", "sudo kill player", "segfault.", "you can't catch me", "run."}
local function holdingProp() local c = LP.Character return c and c:FindFirstChild("Prop") ~= nil end

local function PickCmd()
	local pr = pRoot()
	if not pr or not Boss then return nil end
	if S.jailed or S.frozen then
		if S.phase >= 2 then return "laser" end -- hits you while you're stuck
		return nil
	end
	local d = (pr.Position - BR.Position).Magnitude
	local pool = {}
	local function add(n, w) for _ = 1, w do pool[#pool + 1] = n end end
	add("laser", 3) add("blackscreen", 1) add("fling", 2) add("slip", 2) add("jail", 2) add("freeze", 1)
	if d < 22 then add("slip", 3) add("fling", 3) add("jail", 2) end   -- you're close: punish
	if holdingProp() then add("blackscreen", 3) add("laser", 2) end   -- you're armed: blind/shoot you
	if S.black then
		for i = #pool, 1, -1 do if pool[i] == "blackscreen" then table.remove(pool, i) end end
	end
	return pool[rnd:NextInteger(1, #pool)]
end

local function RunCmd(name)
	if rnd:NextNumber() < 0.4 then Bubble(TAUNTS[rnd:NextInteger(1, #TAUNTS)]) end
	if name == "laser" and S.phase == 3 then
		task.spawn(Cmd.laser)
		task.delay(0.35, Cmd.laser)
	else
		task.spawn(Cmd[name])
	end
end

task.spawn(function()
	while S.running and not S.over do
		task.wait(0.25)
		if not S.busy and S.phase > 0 then
			local cd = ({7, 4.2, 1.6})[S.phase]
			if os.clock() - S.lastCmd > cd then
				S.lastCmd = os.clock()
				local n = PickCmd()
				if n then RunCmd(n) end
				if S.phase == 3 and rnd:NextNumber() < 0.35 then -- spam
					local n2 = PickCmd()
					if n2 then RunCmd(n2) end
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- RAINBOW / NEON MAP PARTS (phase 2 & 3)
----------------------------------------------------------------------
local function Rainbow(count, glow)
	local pr = pRoot()
	if not pr then return end
	local list = {}
	for _, p in ipairs(Parts()) do list[#list + 1] = p end
	for i = #list, 2, -1 do local j = rnd:NextInteger(1, i) list[i], list[j] = list[j], list[i] end
	local n = 0
	for _, p in ipairs(list) do
		if n >= count then break end
		if p.Parent and not S.restore[p] and p.Size.Magnitude < 24 then
			local below = p.Position.Y < pr.Position.Y - 2 and flat(p.Position - pr.Position).Magnitude < (p.Size.X + p.Size.Z) / 2 + 4
			if not below then
				S.restore[p] = {Color = p.Color, Material = p.Material, Anchored = p.Anchored, CFrame = p.CFrame}
				p.Anchored = true p.Material = Enum.Material.Neon
				S.rb[#S.rb + 1] = p
				n += 1
			end
		end
	end
	if glow then
		for _, p in ipairs(S.rb) do
			if p.Parent and not p:FindFirstChild("CR_Light") then
				track(mk("PointLight", {Name = "CR_Light", Range = 16, Brightness = 3, Color = Color3.fromRGB(255, 40, 80)}, p))
			end
		end
	end
end

on(RS.Heartbeat, function(dt)
	local t = os.clock()
	local k = S.phase == 3 and 3 or 1.2
	for i, p in ipairs(S.rb) do
		if p.Parent then
			if S.phase == 3 then
				p.Color = Color3.fromHSV(0.93 + 0.07 * math.sin(t * 6 + i), 1, 0.6 + 0.4 * math.sin(t * 9 + i))
			else
				p.Color = Color3.fromHSV((t * 0.4 + i * 0.07) % 1, 1, 1)
			end
			p.CFrame = p.CFrame * CFrame.Angles(0, dt * k * 2, 0)
		end
	end
end)

----------------------------------------------------------------------
-- HOVER MOVEMENT (phase 2 & 3)  +  TELEKINESIS
----------------------------------------------------------------------
local hoverAng, hoverR, hoverH = 0, 38, 24
local function StartHover()
	local pr = pRoot()
	if pr then hoverAng = math.atan2(BR.Position.Z - pr.Position.Z, BR.Position.X - pr.Position.X) end
	BR.Anchored = true
	BAnim.idle:Stop() BAnim.run:Stop()
	S.hover = true
end

on(RS.Heartbeat, function(dt)
	if not S.hover or S.busy or not BR or not BR.Parent then return end
	local pr = pRoot()
	if not pr then return end
	hoverAng += dt * (S.phase == 3 and 1.1 or 0.6) * S.dir
	local tgt = pr.Position + Vector3.new(math.cos(hoverAng) * hoverR, hoverH + math.sin(os.clock() * 2) * 2, math.sin(hoverAng) * hoverR)
	local pos = BR.Position:Lerp(tgt, math.clamp(dt * (S.phase == 3 and 3.5 or 2), 0, 1))
	BR.CFrame = CFrame.lookAt(pos, Vector3.new(pr.Position.X, pos.Y, pr.Position.Z))
end)

on(RS.Heartbeat, function() -- run / idle animation switching
	if not BR or not BR.Parent or S.hover or S.busy then return end
	local moving = flat(BR.AssemblyLinearVelocity).Magnitude > 3
	if moving and not BAnim.run.IsPlaying then BAnim.idle:Stop(0.1) BAnim.run:Play(0.1)
	elseif not moving and not BAnim.idle.IsPlaying then BAnim.run:Stop(0.1) BAnim.idle:Play(0.1) end
end)

local function Telekinesis(src)
	if not src or not src.Parent then return end
	local p = NewProj(src)
	mk("Highlight", {FillColor = Color3.fromRGB(190, 60, 255), OutlineColor = Color3.new(1, 1, 1), FillTransparency = 0.3}, p)
	local a0 = mk("Attachment", {}, BR)
	local a1 = mk("Attachment", {}, p)
	local beam = mk("Beam", {Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(Color3.fromRGB(190, 60, 255)), Width0 = 0.4, Width1 = 0.4, LightEmission = 1, FaceCamera = true}, p)
	local startCF = src.CFrame
	local liftT = S.phase == 3 and 0.5 or 0.9
	local t0 = os.clock()
	while S.running and not S.busy and os.clock() - t0 < liftT do -- levitate
		local a = (os.clock() - t0) / liftT
		p.CFrame = (startCF + Vector3.new(0, a * 8, 0)) * CFrame.Angles(a * 6, a * 7, 0)
		task.wait()
	end
	local fromPos = p.Position
	local t1, pullT = os.clock(), 0.45
	while S.running and not S.busy and os.clock() - t1 < pullT do -- pull to boss
		local a = (os.clock() - t1) / pullT
		local hand = (BR.CFrame * CFrame.new(1.5, 1, -3)).Position
		p.CFrame = CFrame.new(fromPos:Lerp(hand, a)) * CFrame.Angles(os.clock() * 6, os.clock() * 7, 0)
		task.wait()
	end
	beam:Destroy() a0:Destroy()
	if S.busy or not p.Parent then p:Destroy() return end
	task.wait(0.2)
	ThrowAtPlayer(p)
end

task.spawn(function() -- air brain: repositions + telekinesis throws
	while S.running and not S.over do
		task.wait(0.1)
		if S.phase >= 2 and S.hover and not S.busy then
			if os.clock() > S.nextMove then
				S.nextMove = os.clock() + rnd:NextNumber(2, 4)
				S.dir = -S.dir
				if S.phase == 3 then hoverR = rnd:NextNumber(20, 34) hoverH = rnd:NextNumber(10, 22)
				else hoverR = rnd:NextNumber(26, 42) hoverH = rnd:NextNumber(14, 28) end
			end
			if os.clock() > S.nextThrow then
				if S.phase == 3 then
					task.spawn(Telekinesis, PickPart(140))
					Telekinesis(PickPart(140))
					S.nextThrow = os.clock() + rnd:NextNumber(1.2, 2.2)
				else
					Telekinesis(PickPart(140))
					S.nextThrow = os.clock() + rnd:NextNumber(2.5, 4)
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- PHASE 1 BRAIN (grab a part -> throw it)
----------------------------------------------------------------------
local function GrabAndThrow(src)
	Bubble("mine.")
	if not WalkTo(src.Position, 7, 6) then return end
	if S.busy or not src.Parent or src.LocalTransparencyModifier >= 1 then return end
	BH:MoveTo(BR.Position)
	local p = NewProj(src)
	local hold
	hold = RS.Heartbeat:Connect(function()
		if not BR.Parent or not p.Parent then hold:Disconnect() return end
		local pr = pRoot()
		if pr then BR.CFrame = CFrame.lookAt(BR.Position, Vector3.new(pr.Position.X, BR.Position.Y, pr.Position.Z)) end
		p.CFrame = BR.CFrame * CFrame.new(0, 4.6, -0.5) * CFrame.Angles(0, os.clock() * 3, 0)
	end)
	task.wait(0.55)
	hold:Disconnect()
	if S.busy or not p.Parent then p:Destroy() return end
	ThrowAtPlayer(p)
	task.wait(0.7)
end

local function Phase1Think()
	local pr = pRoot()
	if not pr then task.wait(0.5) return end
	local d = flat(pr.Position - BR.Position).Magnitude
	if d < 16 then -- you're too close: he runs
		if rnd:NextNumber() < 0.5 then Bubble("back off") end
		Flee(2.5)
		return
	end
	if rnd:NextNumber() < 0.6 then
		local part = PickPart(80)
		if part then GrabAndThrow(part) return end
	end
	local a = rnd:NextNumber(0, math.pi * 2) -- kite around you
	WalkTo(pr.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * rnd:NextNumber(30, 45), 3, 4)
end

task.spawn(function()
	while S.running and not S.over do
		if S.busy or S.phase ~= 1 then task.wait(0.2) else Phase1Think() task.wait(0.05) end
	end
end)

----------------------------------------------------------------------
-- CUTSCENES
----------------------------------------------------------------------
local function CineOrbit(getFocus, radius, height, speed)
	local t0 = os.clock()
	return function()
		local f = getFocus()
		local a = (os.clock() - t0) * speed
		return CFrame.lookAt(f + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius), f)
	end
end

local function Prep()
	S.busy = true
	Lock(true)
	for p in pairs(S.projs) do p:Destroy() end
	S.projs = {}
	if S.jailed or S.frozen then Cmd.thaw() end
	blk.BackgroundTransparency = 1 S.black = false blkTxt.Text = ""
	local h = pHum()
	if h then h.PlatformStand = false end
	BH:MoveTo(BR.Position)
end

local function Intro()
	local pr = pRoot()
	BR.CFrame = CFrame.lookAt(BR.Position, Vector3.new(pr.Position.X, BR.Position.Y, pr.Position.Z))
	Lock(true)
	local t0 = os.clock()
	StartCine(function()
		local a = math.clamp((os.clock() - t0) / 7, 0, 1)
		local face = Boss.Head.Position
		return CFrame.lookAt(face + BR.CFrame.LookVector * (24 - 15 * a) + BR.CFrame.RightVector * (9 * (1 - a)) + Vector3.new(0, 3 - a, 0), face)
	end)
	Term("./console_root --boot")
	Say("> CONSOLE_ROOT.exe has awakened", 1.2)
	Say("So... you found the root console.", 2)
	Shake(0.8, 0.8)
	Say("Every admin command in this place answers to ME.", 2.4)
	Say("Let's play, player.", 1.6)
	Boom(BR.Position, 8) Shake(1.5, 0.8) Flash(0.5)
	EndCine()
	Lock(false)
end

local function Phase2Cut()
	Prep()
	Lock(true)
	BAnim.idle:Stop() BAnim.run:Stop()
	BR.Anchored = true
	local pr = pRoot()
	BR.CFrame = CFrame.lookAt(BR.Position, Vector3.new(pr.Position.X, BR.Position.Y, pr.Position.Z))
	StartCine(CineOrbit(function() return BR.Position end, 16, 4, 0.6))
	Term("sudo ./unleash --phase=2")
	Shake(1, 1) Boom(BR.Position, 8)
	Pose(true)
	local startCF = BR.CFrame
	local t0, dur = os.clock(), 2.8
	while S.running and os.clock() - t0 < dur do -- fly up
		local a = (os.clock() - t0) / dur
		a = a * a * (3 - 2 * a)
		BR.CFrame = startCF + Vector3.new(0, a * 28, 0)
		Shake(0.3, 0.1)
		task.wait()
	end
	StartCine(function() -- low hero angle (iron man pose)
		return CFrame.lookAt(BR.Position + BR.CFrame.LookVector * 24 + Vector3.new(0, -18, 0), BR.Position)
	end)
	Boom(BR.Position, 10) Shake(1.6, 1.2) Flash(0.6)
	TS:Create(S.cc, TweenInfo.new(1.5), {TintColor = Color3.fromRGB(255, 190, 220)}):Play()
	Say("YOU WILL REGRET DOING THAT PLAYER..", 1.8)
	Rainbow(30)
	Shake(2, 1)
	EndCine()
	Lock(false)
	S.phase = 2 S.hp = 100 UpdateBar()
	hoverR, hoverH = 38, 24
	S.nextThrow = os.clock() + 2
	StartHover()
	S.busy = false
end

local function Phase3Cut()
	Prep()
	Lock(true)
	local pr = pRoot()
	local from = BR.CFrame
	local dirv = flat(BR.Position - pr.Position)
	if dirv.Magnitude < 1 then dirv = Vector3.new(0, 0, 1) end
	local tpos = pr.Position + dirv.Unit * 16 + Vector3.new(0, 5, 0)
	local base = CFrame.lookAt(tpos, Vector3.new(pr.Position.X, tpos.Y, pr.Position.Z))
	StartCine(function() return CFrame.lookAt(BR.Position + BR.CFrame.LookVector * 14 + Vector3.new(0, 3, 0) + BR.CFrame.RightVector * 5, BR.Position) end)
	local t0 = os.clock()
	while S.running and os.clock() - t0 < 1.5 do -- descends toward you
		BR.CFrame = from:Lerp(base, (os.clock() - t0) / 1.5)
		task.wait()
	end
	BR.CFrame = base
	StartCine(function() return CFrame.lookAt(base.Position + base.LookVector * 7 + Vector3.new(0, 1, 0), Boss.Head.Position) end)
	local shaking, sh = true, 0
	task.spawn(function()
		while shaking and S.running do
			BR.CFrame = base * CFrame.new(rnd:NextNumber(-sh, sh), rnd:NextNumber(-sh, sh), 0)
			task.wait()
		end
		if BR.Parent then BR.CFrame = base end
	end)
	Term("ERROR 0xDEAD :: root integrity compromised")
	Say("...", 1.8)
	sh = 0.15 Shake(0.6, 3)
	TS:Create(S.cc, TweenInfo.new(2), {TintColor = Color3.fromRGB(255, 120, 120)}):Play()
	Say("How could you..", 2.2)
	sh = 0.5 Shake(1.8, 3)
	Say("Y7wua w1l1 p4y F0R ThI1S..", 2.4, true)
	shaking = false
	task.wait(0.1)
	Flash(1) Shake(3.5, 1.4) Boom(BR.Position, 12)
	for _, d in ipairs(Boss:GetDescendants()) do -- boss goes full neon-red maniac
		if d:IsA("BasePart") then d.Material = Enum.Material.Neon d.Color = Color3.fromRGB(40, 0, 0) end
	end
	S.hl.OutlineColor = Color3.new(1, 1, 1) S.hl.FillColor = Color3.fromRGB(255, 0, 0) S.hl.FillTransparency = 0.4
	TS:Create(S.cc, TweenInfo.new(1), {TintColor = Color3.fromRGB(255, 70, 70)}):Play()
	S.phase = 3
	Rainbow(25, true)
	SpawnClones(4)
	GiveSword()
	Term("spawn --clones --sword SystemSword")
	task.wait(0.8)
	EndCine()
	Lock(false)
	S.hp = 100 UpdateBar()
	hoverR, hoverH = 26, 14
	S.nextThrow = os.clock() + 1.5
	S.lastCmd = os.clock()
	StartHover()
	S.busy = false
end

local Cleanup

local function Victory()
	S.over = true
	Lock(true)
	for p in pairs(S.projs) do p:Destroy() end
	for _, c in ipairs(S.clones) do Boom(c.r.Position, 4) c.m:Destroy() end
	S.clones = {}
	if S.jailed or S.frozen then Cmd.thaw() end
	BR.Anchored = true
	StartCine(CineOrbit(function() return BR.Position end, 18, 4, 0.5))
	Term("rm -rf /CONSOLE_ROOT")
	Say("ERROR.. ROOT ACCESS LOST..", 1.6, true)
	for _ = 1, 4 do Boom(BR.Position + Vector3.new(rnd:NextNumber(-4, 4), rnd:NextNumber(-3, 5), rnd:NextNumber(-4, 4)), 6) Shake(1.5, 0.4) task.wait(0.35) end
	Flash(1)
	for _, d in ipairs(Boss:GetDescendants()) do
		if d:IsA("BasePart") then TS:Create(d, TweenInfo.new(1), {Transparency = 1}):Play() end
	end
	Say("CONSOLE_ROOT HAS BEEN TERMINATED", 3)
	EndCine()
	Cleanup()
end

Advance = function()
	S.busy = true
	if S.phase == 1 then S.phase = 2 Phase2Cut()
	elseif S.phase == 2 then Phase3Cut()
	else Victory() end
end

----------------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------------
Cleanup = function()
	if not S.running then return end
	S.running = false
	for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
	pcall(function() RS:UnbindFromRenderStep("CR_CAM") RS:UnbindFromRenderStep("CR_SHAKE") end)
	for p, o in pairs(S.restore) do
		if p.Parent then
			pcall(function() p.CFrame = o.CFrame p.Color = o.Color p.Material = o.Material p.Anchored = o.Anchored end)
		end
	end
	for p in pairs(S.hidden) do if p.Parent then p.LocalTransparencyModifier = 0 end end
	local pr, h = pRoot(), pHum()
	if pr then pr.Anchored = false end
	if h then
		h.PlatformStand = false
		h.WalkSpeed = S.ws h.JumpPower = S.jp h.JumpHeight = S.jh
		Cam.CameraType = Enum.CameraType.Custom
		Cam.CameraSubject = h
	end
	local bp = LP:FindFirstChildOfClass("Backpack")
	for _, holder in ipairs({bp, LP.Character}) do
		if holder then
			for _, n in ipairs({"Prop", "SystemSword"}) do
				local t = holder:FindFirstChild(n)
				if t then t:Destroy() end
			end
		end
	end
	for _, o in ipairs(S.objs) do pcall(function() o:Destroy() end) end
	_G.CR_CLEANUP = nil
end
_G.CR_CLEANUP = Cleanup

----------------------------------------------------------------------
-- MAIN
----------------------------------------------------------------------
task.spawn(function()
	MakeBoss()
	on(pHum().Died, function() -- you died
		if S.over then return end
		S.over = true S.busy = true
		Flash(1)
		dlg.Text = "YOU DIED."
		Term("kill -9 " .. LP.Name)
		task.delay(3, Cleanup)
	end)
	Intro()
	S.phase = 1 S.hp = 100
	UpdateBar()
	S.busy = false
	S.lastCmd = os.clock()
	warn("[CONSOLE_ROOT] fight started. Stop with _G.CR_CLEANUP()")
end)
