--[[
  NIGHTMARE BOSS  |  5-phase client-side boss fight  |  Delta / mobile executors
  Everything is local (only you see it). Re-executing the script cleans up the old run first.

  Mobile buttons (ContextActionService): SLASH (Purifying Sword) and DASH (1s cooldown, i-frames)
  PC keys: E / left click = slash, Q = dash
  Tweak positions/damage/HP in CFG below.
]]

local genv = (getgenv and getgenv()) or _G
if genv.NB_CLEANUP then pcall(genv.NB_CLEANUP) end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CAS = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local Hum = Char:WaitForChild("Humanoid")
local Root = Char:WaitForChild("HumanoidRootPart")
local Cam = Workspace.CurrentCamera

local CFG = {
	BOSS_USERID = nil, -- set a UserId (number) to build the boss from that avatar instead of yours
	PLAYER_HP = 100,
	SWORD_DAMAGE = 35,
	SWORD_COOLDOWN = 0.45,
	BOSS_HP = { 400, 500, 550, 600, 800 },
	HOVER_HEIGHT = 45,
	DASH_COOLDOWN = 1,
	DASH_IFRAMES = 0.35,
	DASH_SPEED = 85,
	GEMS_NEEDED = 3,
	STUN_TIME = 4,
	INVERT_TIME = 2.0,
	SWORD_BTN_POS = UDim2.new(0.45, 0, 0.05, 0),
	DASH_BTN_POS = UDim2.new(0.45, 0, 0.55, 0),
}

local PHASE_NAMES = { "ARACHNID DUEL", "FLESH GARDEN", "GLITCHED REALITY", "LEGGED NIGHTMARES", "TOTAL CLIMAX" }
local LEG = 8.5
local BODY_H = 9

---------------------------------------------------------------- STATE
local running, dead, cleaned = true, false, false
local rng = Random.new()
local conns = {}
local folder = Instance.new("Folder")
folder.Name = "NB_" .. math.random(1000, 9999)
folder.Parent = Workspace

local playerHP = CFG.PLAYER_HP
local invulnUntil, invertUntil = 0, 0
local phase, gemCount = 0, 0
local tentacles, monsters, gems, corrupted, hiddenModels = {}, {}, {}, {}, {}
local legs = {}
local B = {
	hp = 1, maxhp = 1, pos = Root.Position, gy = Root.Position.Y - 3, yaw = 0,
	height = -8, heightTarget = BODY_H, hRate = 6, mode = "idle", speed = 0, orbit = 0,
	shielded = false, stunned = false, paused = true, dead = false,
	cf = CFrame.new(Root.Position),
}

local RAYP = RaycastParams.new()
RAYP.FilterType = Enum.RaycastFilterType.Exclude
RAYP.FilterDescendantsInstances = { folder, Char }
RAYP.RespectCanCollide = true

local startPhase, nextPhase, victory, breakShield, launchGems, onPlayerDeath, cleanup

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

---------------------------------------------------------------- UI
local gui = mk("ScreenGui", { Name = "NB_UI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999 }, LP:WaitForChild("PlayerGui"))

local bossFrame = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.06, 0), Size = UDim2.new(0.55, 0, 0.03, 0), BackgroundColor3 = Color3.fromRGB(20, 0, 0), BorderSizePixel = 0 }, gui)
mk("UIStroke", { Color = Color3.fromRGB(170, 0, 40), Thickness = 2 }, bossFrame)
local bossFill = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(200, 20, 50), BorderSizePixel = 0 }, bossFrame)
local bossLabel = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(255, 220, 220), Text = "" }, bossFrame)

local playerFrame = mk("Frame", { Position = UDim2.new(0.03, 0, 0.13, 0), Size = UDim2.new(0.28, 0, 0.025, 0), BackgroundColor3 = Color3.fromRGB(0, 20, 0), BorderSizePixel = 0 }, gui)
mk("UIStroke", { Color = Color3.fromRGB(0, 160, 60), Thickness = 2 }, playerFrame)
local playerFill = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 220, 90), BorderSizePixel = 0 }, playerFrame)
local gemLabel = mk("TextLabel", { Position = UDim2.new(0.03, 0, 0.16, 0), Size = UDim2.new(0.28, 0, 0.03, 0), BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(110, 255, 255), Text = "" }, gui)

local banner = mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.25, 0), Size = UDim2.new(0.9, 0, 0.07, 0), BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(255, 60, 90), TextStrokeTransparency = 0.3, TextTransparency = 1, Text = "", ZIndex = 8 }, gui)

local invertFrame = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 0, 170), BackgroundTransparency = 0.6, BorderSizePixel = 0, Visible = false, ZIndex = 6 }, gui)
mk("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0), Size = UDim2.new(0.8, 0, 0.1, 0), BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(235, 190, 255), Text = "~ C0NTR0LS R3V3RS3D ~", ZIndex = 6 }, invertFrame)
local flashFrame = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, gui)
local hurtFrame = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(200, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 7 }, gui)

local bannerToken = 0
local function say(text, dur)
	bannerToken += 1
	local my = bannerToken
	banner.Text = text
	banner.TextTransparency = 0
	task.delay(dur or 3, function()
		if my == bannerToken and banner.Parent then
			TweenService:Create(banner, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
	end)
end

local function flash(col, a, dur)
	flashFrame.BackgroundColor3 = col
	flashFrame.BackgroundTransparency = a
	TweenService:Create(flashFrame, TweenInfo.new(dur), { BackgroundTransparency = 1 }):Play()
end

local function shake(mag, dur)
	task.spawn(function()
		local t0 = os.clock()
		while running and os.clock() - t0 < dur do
			local k = 1 - (os.clock() - t0) / dur
			Hum.CameraOffset = Vector3.new((math.random() - 0.5) * mag * k, (math.random() - 0.5) * mag * k, 0)
			RunService.Heartbeat:Wait()
		end
		Hum.CameraOffset = Vector3.zero
	end)
end

local function updateUI()
	bossFill.Size = UDim2.new(math.clamp(B.hp / B.maxhp, 0, 1), 0, 1, 0)
	local tag = B.shielded and "  [SHIELDED]" or (B.stunned and "  [STUNNED]" or "")
	bossLabel.Text = string.format("THE NIGHTMARE - PHASE %d/5: %s%s", math.max(phase, 1), PHASE_NAMES[math.max(phase, 1)], tag)
	playerFill.Size = UDim2.new(math.clamp(playerHP / CFG.PLAYER_HP, 0, 1), 0, 1, 0)
	gemLabel.Text = string.format("GEMS %d/%d", gemCount, CFG.GEMS_NEEDED)
end

local lastHurtFx = 0
local function hurt(n)
	if dead or not running or os.clock() < invulnUntil then return end
	playerHP -= n
	if os.clock() - lastHurtFx > 0.15 then
		lastHurtFx = os.clock()
		hurtFrame.BackgroundTransparency = 0.6
		TweenService:Create(hurtFrame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	end
	updateUI()
	if playerHP <= 0 then onPlayerDeath() end
end

---------------------------------------------------------------- WORLD HELPERS
local function groundAt(x, z, ref)
	local r = Workspace:Raycast(Vector3.new(x, ref + 8, z), Vector3.new(0, -150, 0), RAYP)
	return r and r.Position.Y or ref
end

local cache, cacheT, refreshing = {}, -100, false
local function refreshCache()
	if refreshing or os.clock() - cacheT < 10 then return end
	refreshing = true
	task.spawn(function()
		local out, n = {}, 0
		for _, m in ipairs(Workspace:GetDescendants()) do
			n += 1
			if n % 500 == 0 then task.wait() end
			if m:IsA("Model") and m ~= Char and not m:IsDescendantOf(folder) and not m:IsDescendantOf(Char)
				and not m:IsDescendantOf(Cam) and not m:FindFirstChildWhichIsA("Humanoid")
				and m:FindFirstChildWhichIsA("BasePart") and not m.Name:lower():find("baseplate") then
				out[#out + 1] = m
			end
		end
		cache, cacheT, refreshing = out, os.clock(), false
	end)
end

-- Only Model instances in Workspace; never the player character, never anything under the player's feet
local function pickModel(maxExt)
	refreshCache()
	if #cache == 0 then return nil end
	local fr = Workspace:Raycast(Root.Position, Vector3.new(0, -15, 0), RAYP)
	local floorPart = fr and fr.Instance
	for _ = 1, 12 do
		local m = cache[rng:NextInteger(1, #cache)]
		if m and m.Parent and not hiddenModels[m] and not (floorPart and floorPart:IsDescendantOf(m)) then
			local ok, sz = pcall(function() return m:GetExtentsSize() end)
			if ok and math.max(sz.X, sz.Y, sz.Z) <= maxExt then return m end
		end
	end
	return nil
end

local function setHidden(m, v)
	hiddenModels[m] = v or nil
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = v and 1 or 0 end
	end
end

local function ring(center, radius, dur, color)
	local p = mk("Part", {
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 1, 1), Color = color, Material = Enum.Material.Neon, Transparency = 0.5,
		CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	}, folder)
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Size = Vector3.new(0.4, radius * 2, radius * 2) }):Play()
	Debris:AddItem(p, dur + 0.15)
end

---------------------------------------------------------------- GEMS + SHIELD
local function spawnGem(pos)
	local g = mk("Part", {
		Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), Color = Color3.fromRGB(80, 255, 255),
		Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Position = pos,
	}, folder)
	mk("PointLight", { Color = g.Color, Range = 10 }, g)
	gems[#gems + 1] = { part = g, base = Vector3.new(pos.X, groundAt(pos.X, pos.Z, pos.Y) + 2, pos.Z), born = os.clock() }
end

local function makeShield()
	if B.shield then B.shield:Destroy() end
	B.shield = mk("Part", {
		Shape = Enum.PartType.Ball, Size = Vector3.new(42, 42, 42), Color = Color3.fromRGB(150, 60, 255),
		Material = Enum.Material.ForceField, Transparency = 0.35, Anchored = true, CanCollide = false,
		CanTouch = false, CanQuery = false, CFrame = B.cf,
	}, folder)
end

function breakShield()
	if not running or B.dead or B.paused or not B.shielded then return end
	B.shielded, B.stunned = false, true
	B.heightTarget, B.hRate, B.mode = BODY_H, 5, "idle"
	local sh = B.shield
	B.shield = nil
	if sh then
		TweenService:Create(sh, TweenInfo.new(0.4), { Transparency = 1, Size = sh.Size * 1.4 }):Play()
		Debris:AddItem(sh, 0.5)
	end
	flash(Color3.fromRGB(120, 255, 255), 0.3, 0.5)
	shake(2, 0.6)
	say("SHIELD BROKEN - SLASH HIM!", CFG.STUN_TIME)
	updateUI()
	local myPhase = phase
	task.delay(CFG.STUN_TIME, function()
		if not running or B.dead or phase ~= myPhase or B.paused then return end
		B.stunned, B.shielded = false, true
		B.heightTarget, B.hRate, B.mode = CFG.HOVER_HEIGHT, 2, "orbit"
		makeShield()
		updateUI()
	end)
end

function launchGems()
	gemCount = 0
	updateUI()
	local arrived = 0
	for i = 1, CFG.GEMS_NEEDED do
		local g = mk("Part", {
			Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(80, 255, 255),
			Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
			Position = Root.Position + Vector3.new(0, 2, 0),
		}, folder)
		local ang = i * 2 * math.pi / CFG.GEMS_NEEDED
		local side = Vector3.new(math.cos(ang), 1, math.sin(ang)).Unit
		task.spawn(function()
			local t0 = os.clock()
			while running and g.Parent do
				local dt = RunService.Heartbeat:Wait()
				local el = os.clock() - t0
				local v = B.cf.Position - g.Position
				if v.Magnitude < 14 or el > 4 then break end
				if el < 0.3 then
					g.Position += side * 30 * dt
				else
					g.Position += v.Unit * math.min(v.Magnitude, 110 * dt)
				end
			end
			g:Destroy()
			arrived += 1
			if arrived >= CFG.GEMS_NEEDED then breakShield() end
		end)
	end
end

local function collectGem()
	if phase >= 3 and B.shielded and not B.stunned and gemCount < CFG.GEMS_NEEDED then
		gemCount += 1
		updateUI()
		if gemCount >= CFG.GEMS_NEEDED then launchGems() end
	else
		playerHP = math.min(CFG.PLAYER_HP, playerHP + 6) -- spare gems heal a little
		updateUI()
	end
end

---------------------------------------------------------------- BOSS BUILD
local function buildBoss()
	local model
	if CFG.BOSS_USERID then
		local ok, m = pcall(function() return Players:CreateHumanoidModelFromUserId(CFG.BOSS_USERID) end)
		if ok and m then model = m end
	end
	if not model then
		Char.Archivable = true
		local ok, m = pcall(function() return Char:Clone() end)
		if ok and m then model = m end
	end
	if not model then -- blocky placeholder
		model = Instance.new("Model")
		local function blk(n, sz, off)
			return mk("Part", { Name = n, Size = sz, Color = Color3.fromRGB(40, 0, 60), Material = Enum.Material.SmoothPlastic, Anchored = true, CanCollide = false, CFrame = CFrame.new(off) }, model)
		end
		blk("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
		blk("Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0))
		blk("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0))
		blk("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0))
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("Sound") or d:IsA("BillboardGui") then d:Destroy() end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
	model.PrimaryPart = hrp
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
			if d.Name:find("Leg") or d.Name:find("Foot") then d.Transparency = 1 end -- spider legs replace them
		end
	end
	model.Name = "NightmareBoss"
	model.Parent = folder
	pcall(function() model:ScaleTo(3) end)
	B.hl = mk("Highlight", {
		FillColor = Color3.fromRGB(90, 0, 140), OutlineColor = Color3.fromRGB(255, 0, 60),
		FillTransparency = 0.6, Adornee = model,
	}, model)
	B.model = model

	for i = 1, 8 do
		local function seg()
			return mk("Part", {
				Size = Vector3.new(0.9, 0.9, LEG), Color = Color3.fromRGB(18, 6, 24), Material = Enum.Material.Metal,
				Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
			}, folder)
		end
		legs[i] = { a = (i - 1) * math.pi / 4 + math.pi / 8, s1 = seg(), s2 = seg(), stepping = false, t = 0, from = Vector3.zero, to = Vector3.zero }
	end
end

---------------------------------------------------------------- SPIDER LEG IK (procedural)
local function solve(H, F)
	local v = F - H
	local m = v.Magnitude
	local dir = m > 0.01 and v / m or Vector3.new(0, -1, 0)
	local d = math.clamp(m, 0.5, LEG * 2 - 0.1)
	local a = d / 2
	local h = math.sqrt(math.max(LEG * LEG - a * a, 0))
	local pole = Vector3.yAxis - dir * dir.Y
	if pole.Magnitude < 0.05 then pole = Vector3.xAxis end
	return H + dir * a + pole.Unit * h, H + dir * d
end

local function place(p, a, b)
	if (b - a).Magnitude < 0.05 then return end
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
end

local function updateLegs(dt, body, yawCF)
	local dangle = B.height > 28
	local stepping = 0
	for _, L in ipairs(legs) do if L.stepping then stepping += 1 end end
	for _, L in ipairs(legs) do
		local d = (yawCF * CFrame.Angles(0, L.a, 0)).LookVector
		local hip = body + Vector3.new(0, -1.5, 0) + d * 2
		local tgt
		if dangle then
			tgt = body + d * 8 + Vector3.new(0, -11, 0)
		else
			local w = Workspace:Raycast(body + d * 2, d * 12, RAYP) -- walls: legs cling to them
			if w and math.abs(w.Normal.Y) < 0.5 then
				tgt = w.Position + w.Normal * 0.4
			else
				local tx = body + d * 10
				local g = Workspace:Raycast(Vector3.new(tx.X, body.Y + 4, tx.Z), Vector3.new(0, -70, 0), RAYP)
				tgt = g and g.Position or Vector3.new(tx.X, B.gy, tx.Z)
			end
		end
		if not L.foot then L.foot = tgt end
		if dangle then
			L.foot = L.foot:Lerp(tgt, math.min(1, dt * 6))
			L.stepping = false
		elseif L.stepping then
			L.t += dt / 0.16
			if L.t >= 1 then L.t, L.stepping = 1, false end
			L.foot = L.from:Lerp(L.to, L.t) + Vector3.new(0, math.sin(L.t * math.pi) * 2.5, 0)
		elseif (L.foot - tgt).Magnitude > 5.5 and stepping < 4 then
			L.stepping, L.t, L.from, L.to = true, 0, L.foot, tgt
			stepping += 1
		end
		local knee, foot = solve(hip, L.foot)
		place(L.s1, hip, knee)
		place(L.s2, knee, foot)
	end
end

local function bossStep(dt)
	if B.dead or not B.model then return end
	local pp = Root.Position
	if not B.paused and not B.stunned then
		local target
		if B.mode == "chase" then
			target = pp
		elseif B.mode == "orbit" then
			B.orbit += dt * 0.5
			target = Vector3.new(pp.X + math.cos(B.orbit) * 26, 0, pp.Z + math.sin(B.orbit) * 26)
		end
		if target then
			local v = Vector3.new(target.X - B.pos.X, 0, target.Z - B.pos.Z)
			local m = v.Magnitude
			if m > (B.mode == "chase" and 12 or 1) then
				B.pos += v.Unit * math.min(m, B.speed * dt)
			end
		end
	end
	B.gy = groundAt(B.pos.X, B.pos.Z, B.gy)
	B.height += (B.heightTarget - B.height) * math.min(1, dt * B.hRate)
	local flat = Vector3.new(pp.X - B.pos.X, 0, pp.Z - B.pos.Z)
	if flat.Magnitude > 0.5 then
		local goal = math.atan2(-flat.X, -flat.Z)
		local diff = (goal - B.yaw + math.pi) % (2 * math.pi) - math.pi
		B.yaw += diff * math.min(1, dt * 6)
	end
	local body = Vector3.new(B.pos.X, B.gy + B.height + math.sin(os.clock() * 3) * 0.4, B.pos.Z)
	local yawCF = CFrame.Angles(0, B.yaw, 0)
	B.cf = CFrame.new(body) * yawCF
	B.model:PivotTo(B.cf)
	if B.shield then B.shield.CFrame = B.cf end
	updateLegs(dt, body, yawCF)
end

---------------------------------------------------------------- BOSS ATTACKS
local function slam()
	B.mode, B.heightTarget, B.hRate = "idle", 16, 3
	local center = Vector3.new(B.pos.X, B.gy, B.pos.Z)
	local R = 24
	local warnDisc = mk("Part", {
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, R * 2, R * 2), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon,
		Transparency = 0.8, CFrame = CFrame.new(center + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	}, folder)
	Debris:AddItem(warnDisc, 1.6)
	ring(center, R, 1.4, Color3.fromRGB(255, 40, 40))
	task.wait(1.4)
	if not running or B.dead then return end
	B.hRate, B.heightTarget = 30, BODY_H
	task.wait(0.12)
	shake(1.2, 0.5)
	ring(center, R + 6, 0.5, Color3.fromRGB(255, 150, 40))
	local pp = Root.Position
	local flat = Vector3.new(pp.X - center.X, 0, pp.Z - center.Z).Magnitude
	if flat < R and pp.Y - center.Y < 6.5 then hurt(30) end -- jump or dash to dodge
	B.hRate = 6
	task.wait(1.1)
end

local function fireOrb(spread)
	local start = B.cf.Position
	local dir = (Root.Position - start).Unit
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, spread, 0)).LookVector
	local p = mk("Part", {
		Shape = Enum.PartType.Ball, Size = Vector3.new(3.5, 3.5, 3.5), Color = Color3.fromRGB(190, 60, 255),
		Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Position = start,
	}, folder)
	task.spawn(function()
		local t0 = os.clock()
		while running and p.Parent and os.clock() - t0 < 6 do
			local dt = RunService.Heartbeat:Wait()
			p.Position += dir * 55 * dt
			if (p.Position - Root.Position).Magnitude < 4 then hurt(14) break end
		end
		p:Destroy()
	end)
end

local function groundCycle()
	B.mode, B.speed = "chase", (phase == 1) and 22 or 18
	local t0 = os.clock()
	while running and not B.dead and os.clock() - t0 < 4 do
		local pp = Root.Position
		if Vector3.new(pp.X - B.pos.X, 0, pp.Z - B.pos.Z).Magnitude < 20 and os.clock() - t0 > 1.2 then break end
		task.wait(0.1)
	end
	if B.paused or B.stunned or B.dead then return end
	slam()
end

local function floatCycle()
	B.mode, B.speed = "orbit", 30
	task.wait(rng:NextNumber(2.5, 4))
	if B.stunned or B.paused or B.dead or not running then return end
	if phase == 5 then
		for _, s in ipairs({ -0.25, 0, 0.25 }) do fireOrb(s) end
	else
		fireOrb(0)
	end
end

---------------------------------------------------------------- HAZARDS
local function spawnTentacle()
	local ang, dist = rng:NextNumber(0, math.pi * 2), rng:NextNumber(10, 28)
	local pp = Root.Position
	local x, z = pp.X + math.cos(ang) * dist, pp.Z + math.sin(ang) * dist
	local part = mk("Part", { Anchored = true, CanCollide = false, CanTouch = false, Color = Color3.fromRGB(150, 40, 60), Material = Enum.Material.Fabric, Size = Vector3.new(2.5, 0.2, 2.5) }, folder)
	local tip = mk("Part", { Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanTouch = false, Color = Color3.fromRGB(200, 30, 60), Material = Enum.Material.Neon, Size = Vector3.new(4, 4, 4) }, folder)
	tentacles[#tentacles + 1] = { part = part, tip = tip, base = Vector3.new(x, groundAt(x, z, B.gy), z), h = 0.2, seed = rng:NextNumber(0, 10) }
end

local function killTentacle(i)
	local t = table.remove(tentacles, i)
	spawnGem(t.base + Vector3.new(0, 3, 0))
	t.part:Destroy()
	t.tip:Destroy()
end

local function spawnMonster()
	local src = pickModel(60)
	if not src then return end
	local ok, m = pcall(function() return src:Clone() end)
	if not ok or not m then return end
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then d:Destroy()
		elseif d:IsA("BasePart") then parts[#parts + 1] = d end
	end
	if #parts == 0 or #parts > 80 then m:Destroy() return end
	m.Parent = folder
	local ext = m:GetExtentsSize()
	local mx = math.max(ext.X, ext.Y, ext.Z)
	pcall(function() m:ScaleTo(m:GetScale() * (mx > 10 and 10 / mx or (mx < 3 and 3 / mx or 1))) end)

	local ang, dist = rng:NextNumber(0, math.pi * 2), rng:NextNumber(35, 50)
	local pp = Root.Position
	local x, z = pp.X + math.cos(ang) * dist, pp.Z + math.sin(ang) * dist
	m:PivotTo(CFrame.new(x, groundAt(x, z, B.gy) + 10, z))

	local pr = m.PrimaryPart or parts[1]
	local cf, size = m:GetBoundingBox()
	for _, p in ipairs(parts) do
		p.Anchored, p.CanCollide, p.Massless, p.CanTouch = false, p == pr, p ~= pr, false
		if p ~= pr then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1, w.Parent = pr, p, p
		end
	end
	local att = mk("Attachment", {}, pr)
	mk("AlignOrientation", { Mode = Enum.OrientationAlignmentMode.OneAttachment, Attachment0 = att, MaxTorque = 1e7, Responsiveness = 40, CFrame = pr.CFrame.Rotation }, pr)

	local legLen = math.clamp(size.Y * 0.6, 2.5, 6)
	local lw = {}
	for i = 1, 4 do
		local sx, sz = (i % 2 == 0) and 1 or -1, (i <= 2) and 1 or -1
		local leg = Instance.new("Part")
		leg.Size, leg.Color, leg.Material = Vector3.new(0.7, legLen, 0.7), Color3.fromRGB(25, 10, 30), Enum.Material.Metal
		leg.CanCollide, leg.CanTouch, leg.Massless = true, false, false
		local worldAttach = cf.Position + Vector3.new(sx * size.X * 0.35, -size.Y / 2 + 0.3, sz * size.Z * 0.35)
		local c0 = pr.CFrame:ToObjectSpace(CFrame.new(worldAttach))
		local w = Instance.new("Weld")
		w.Part0, w.Part1, w.C0, w.C1 = pr, leg, c0, CFrame.new(0, legLen / 2, 0)
		leg.Parent = m
		w.Parent = leg
		lw[i] = { w = w, c0 = c0, ph = i * 1.7 }
	end
	setHidden(src, true) -- the original model "becomes" the monster
	monsters[#monsters + 1] = { m = m, pr = pr, welds = lw, hits = 0, src = src, hitCd = 0, radius = math.max(size.X, size.Z) / 2 }
end

local function killMonster(i, giveGem)
	local mo = table.remove(monsters, i)
	if giveGem then
		local pos = mo.pr.Parent and mo.pr.Position or (Root.Position + Vector3.new(6, 0, 0))
		if pos.Y < B.gy - 50 then pos = Root.Position + Vector3.new(6, 0, 0) end
		spawnGem(pos + Vector3.new(0, 2, 0))
	end
	pcall(setHidden, mo.src, false)
	mo.m:Destroy()
end

local function corruptRandom()
	local m = pickModel(150)
	if not m then return end
	local parts = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and not corrupted[p] and not p:IsDescendantOf(folder) and not p.Name:lower():find("baseplate") and p.Size.Magnitude < 150 then
			parts[#parts + 1] = p
			if #parts >= 25 then break end
		end
	end
	if #parts == 0 then return end
	local mode = rng:NextInteger(1, 2)
	for _, p in ipairs(parts) do
		corrupted[p] = { Size = p.Size, Transparency = p.Transparency, CanCollide = p.CanCollide }
		if mode == 1 then -- stretch
			local s = p.Size
			p.CanCollide = false
			TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = Vector3.new(s.X * rng:NextNumber(0.5, 1.6), s.Y * rng:NextNumber(2, 4), s.Z * rng:NextNumber(0.5, 1.6)),
			}):Play()
		else -- dissolve
			TweenService:Create(p, TweenInfo.new(4, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
		end
	end
end

local function restoreCorruption(instant)
	local snap = corrupted
	corrupted = {}
	for p, d in pairs(snap) do
		if p.Parent then
			if instant then
				p.Size, p.Transparency, p.CanCollide = d.Size, d.Transparency, d.CanCollide
			else
				TweenService:Create(p, TweenInfo.new(1.5), { Size = d.Size, Transparency = d.Transparency }):Play()
				task.delay(1.6, function()
					if p.Parent then p.Size, p.Transparency, p.CanCollide = d.Size, d.Transparency, d.CanCollide end
				end)
			end
		end
	end
end

local function clearHazards()
	for i = #tentacles, 1, -1 do
		local t = table.remove(tentacles, i)
		t.part:Destroy()
		t.tip:Destroy()
	end
	for i = #monsters, 1, -1 do
		local mo = table.remove(monsters, i)
		pcall(setHidden, mo.src, false)
		mo.m:Destroy()
	end
	for i = #gems, 1, -1 do
		table.remove(gems, i).part:Destroy()
	end
end

local function hazardStep(dt)
	local now = os.clock()
	local pp = Root.Position
	for _, t in ipairs(tentacles) do
		t.h = math.min(14, t.h + 22 * dt)
		local sway = CFrame.Angles(math.sin(now * 2 + t.seed) * 0.15, 0, math.cos(now * 1.7 + t.seed) * 0.15)
		local cf = CFrame.new(t.base) * sway * CFrame.new(0, t.h / 2, 0)
		t.part.Size = Vector3.new(2.5, t.h, 2.5)
		t.part.CFrame = cf
		t.tip.CFrame = cf * CFrame.new(0, t.h / 2, 0)
		local d = Vector3.new(pp.X - t.base.X, 0, pp.Z - t.base.Z).Magnitude
		if t.h > 5 and d < 7 and pp.Y - t.base.Y < t.h then hurt(14 * dt) end -- continuous proximity damage
	end
	for i = #monsters, 1, -1 do
		local mo = monsters[i]
		if not mo.pr.Parent then
			killMonster(i, false)
		else
			local mp = mo.pr.Position
			local v = Vector3.new(pp.X - mp.X, 0, pp.Z - mp.Z)
			local mag = v.Magnitude
			local dir = mag > 0.1 and v.Unit or Vector3.zero
			local vel = mo.pr.AssemblyLinearVelocity
			if now > mo.hitCd - 0.5 then
				mo.pr.AssemblyLinearVelocity = Vector3.new(dir.X * 13, vel.Y, dir.Z * 13)
			end
			for _, l in ipairs(mo.welds) do
				l.w.C0 = l.c0 * CFrame.Angles(math.sin(now * 9 + l.ph) * 0.6, 0, 0)
			end
			if mag < mo.radius + 4 and now > mo.hitCd and math.abs(pp.Y - mp.Y) < 10 then
				mo.hitCd = now + 1
				hurt(10)
			end
			if mp.Y < B.gy - 100 then killMonster(i, true) end
		end
	end
	for i = #gems, 1, -1 do
		local g = gems[i]
		if not g.part.Parent or now - g.born > 45 then
			g.part:Destroy()
			table.remove(gems, i)
		else
			g.part.CFrame = CFrame.new(g.base + Vector3.new(0, math.sin(now * 3 + i) * 0.4, 0)) * CFrame.Angles(0, now * 2, 0)
			if (g.part.Position - pp).Magnitude < 5 and not B.paused then
				g.part:Destroy()
				table.remove(gems, i)
				collectGem()
			end
		end
	end
end

---------------------------------------------------------------- PLAYER: DASH / SWORD / INVERSION
local dashReady, swingReady = 0, 0

local function doDash()
	if dead or not running or os.clock() < dashReady then return end
	dashReady = os.clock() + CFG.DASH_COOLDOWN
	invulnUntil = os.clock() + CFG.DASH_IFRAMES
	local dir = Hum.MoveDirection
	if dir.Magnitude < 0.1 then dir = Root.CFrame.LookVector end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	task.spawn(function()
		local t0 = os.clock()
		while running and os.clock() - t0 < 0.2 do
			local v = Root.AssemblyLinearVelocity
			Root.AssemblyLinearVelocity = Vector3.new(dir.X * CFG.DASH_SPEED, v.Y, dir.Z * CFG.DASH_SPEED)
			RunService.Heartbeat:Wait()
		end
	end)
	task.spawn(function()
		while running and os.clock() < dashReady do
			pcall(function() CAS:SetTitle("NB_Dash", string.format("%.1f", dashReady - os.clock())) end)
			task.wait(0.1)
		end
		pcall(function() CAS:SetTitle("NB_Dash", "DASH") end)
	end)
end

-- Purifying Sword visual (welded to your hand, local only)
local swordWeld, swordBase
do
	local hand = Char:FindFirstChild("RightHand") or Char:FindFirstChild("Right Arm")
	if hand then
		local handle = mk("Part", { Name = "NB_Handle", Size = Vector3.new(0.4, 1.4, 0.4), Color = Color3.fromRGB(70, 45, 10), Material = Enum.Material.Metal, CanCollide = false, CanTouch = false, CanQuery = false, Massless = true }, folder)
		local blade = mk("Part", { Name = "NB_Blade", Size = Vector3.new(0.3, 5.5, 1), Color = Color3.fromRGB(255, 255, 215), Material = Enum.Material.Neon, CanCollide = false, CanTouch = false, CanQuery = false, Massless = true }, folder)
		mk("PointLight", { Color = Color3.fromRGB(255, 240, 180), Range = 14 }, blade)
		swordBase = CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		swordWeld = mk("Weld", { Part0 = hand, Part1 = handle, C0 = swordBase }, handle)
		mk("Weld", { Part0 = handle, Part1 = blade, C0 = CFrame.new(0, 3.4, 0) }, blade)
	end
end

local function damageBoss(n)
	if B.shielded or B.paused or B.dead then return end
	B.hp -= n
	if B.hl then
		B.hl.FillTransparency = 0
		TweenService:Create(B.hl, TweenInfo.new(0.25), { FillTransparency = 0.6 }):Play()
	end
	if B.hp <= 0 then
		B.hp = 0
		updateUI()
		if phase >= 5 then victory() else nextPhase() end
		return
	end
	updateUI()
end

local function swordHit()
	local pp, look = Root.Position, Root.CFrame.LookVector
	-- boss (only when his shield is down)
	if not B.shielded and not B.paused and not B.dead then
		if Vector3.new(B.pos.X - pp.X, 0, B.pos.Z - pp.Z).Magnitude < 22 then damageBoss(CFG.SWORD_DAMAGE) end
	end
	-- tentacles: one slice deletes them
	for i = #tentacles, 1, -1 do
		local t = tentacles[i]
		local v = Vector3.new(t.base.X - pp.X, 0, t.base.Z - pp.Z)
		local m = v.Magnitude
		if m < 15 and (m < 4 or v.Unit:Dot(look) > -0.2) then killTentacle(i) end
	end
	-- legged monsters: exactly 2 hits
	for i = #monsters, 1, -1 do
		local mo = monsters[i]
		local mp = mo.pr.Position
		local v = Vector3.new(mp.X - pp.X, 0, mp.Z - pp.Z)
		local m = v.Magnitude
		if m < mo.radius + 11 and (m < 5 or v.Unit:Dot(look) > -0.2) then
			mo.hits += 1
			if mo.hits >= 2 then
				killMonster(i, true)
			else
				local away = m > 0.1 and v.Unit or look
				mo.pr.AssemblyLinearVelocity = away * 40 + Vector3.new(0, 25, 0)
				mo.hitCd = os.clock() + 0.5
			end
		end
	end
end

local function swing()
	if dead or not running or os.clock() < swingReady then return end
	swingReady = os.clock() + CFG.SWORD_COOLDOWN
	task.spawn(function()
		local t0, hit = os.clock(), false
		while running and os.clock() - t0 < 0.28 do
			local a = (os.clock() - t0) / 0.28
			if swordWeld then swordWeld.C0 = swordBase * CFrame.Angles(math.rad(-80 + 160 * a), 0, 0) end
			if not hit and a > 0.35 then hit = true swordHit() end
			RunService.Heartbeat:Wait()
		end
		if swordWeld then swordWeld.C0 = swordBase end
	end)
end

local function invert()
	if not running or dead then return end
	invertUntil = os.clock() + CFG.INVERT_TIME
	flash(Color3.fromRGB(200, 80, 255), 0, 0.6)
	say("REVERSED", CFG.INVERT_TIME)
end

local ctrlMod
pcall(function()
	ctrlMod = require(LP:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 3)):GetControls()
end)

-- Runs right after the default control script, so we can flip the joystick vector for exactly INVERT_TIME seconds
RunService:BindToRenderStep("NB_Invert", Enum.RenderPriority.Input.Value + 2, function()
	local on = os.clock() < invertUntil
	if invertFrame.Visible ~= on then invertFrame.Visible = on end
	if on and not dead then
		local mv
		if ctrlMod then
			local ok, v = pcall(function() return ctrlMod:GetMoveVector() end)
			if ok then mv = v end
		end
		if mv then
			if mv.Magnitude > 0 then Hum:Move(-mv, true) end
		else
			Hum:Move(-Hum.MoveDirection, false)
		end
	end
end)

CAS:BindAction("NB_Sword", function(_, state)
	if state == Enum.UserInputState.Begin then swing() end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.E, Enum.UserInputType.MouseButton1)
CAS:BindAction("NB_Dash", function(_, state)
	if state == Enum.UserInputState.Begin then doDash() end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.Q)
pcall(function()
	CAS:SetTitle("NB_Sword", "SLASH")
	CAS:SetTitle("NB_Dash", "DASH")
	CAS:SetPosition("NB_Sword", CFG.SWORD_BTN_POS)
	CAS:SetPosition("NB_Dash", CFG.DASH_BTN_POS)
end)

---------------------------------------------------------------- PHASE FLOW
function startPhase(n)
	phase = n
	B.paused, B.stunned = false, false
	B.hp = CFG.BOSS_HP[n]
	B.maxhp = B.hp
	gemCount = 0
	if B.shield then B.shield:Destroy() B.shield = nil end
	if n >= 3 then
		B.shielded = true
		makeShield()
		B.heightTarget, B.hRate, B.mode, B.speed = CFG.HOVER_HEIGHT, 1.5, "orbit", 30
	else
		B.shielded = false
		B.heightTarget, B.hRate, B.mode = BODY_H, 6, "chase"
	end
	if n ~= 3 and n ~= 5 then restoreCorruption(false) end
	flash(Color3.fromRGB(255, 0, 60), 0.4, 1)
	shake(2, 0.8)
	say(string.format("PHASE %d - %s", n, PHASE_NAMES[n]), 3.5)
	updateUI()
	if n >= 2 then -- one 2s control inversion per phase
		task.delay(rng:NextNumber(5, 12), function()
			if running and phase == n and not dead and not B.dead then invert() end
		end)
	end
end

function nextPhase()
	B.paused, B.stunned, B.shielded = true, false, false
	B.mode = "idle"
	B.heightTarget, B.hRate = BODY_H, 3
	clearHazards()
	if B.shield then B.shield:Destroy() B.shield = nil end
	say(string.format("PHASE %d CLEARED", phase), 2.5)
	flash(Color3.new(1, 1, 1), 0.2, 1)
	local n = phase + 1
	task.delay(3, function()
		if running and not dead then startPhase(n) end
	end)
end

function victory()
	B.dead, B.paused = true, true
	clearHazards()
	restoreCorruption(false)
	if B.shield then B.shield:Destroy() B.shield = nil end
	say("THE NIGHTMARE IS PURIFIED", 6)
	flash(Color3.new(1, 1, 1), 0, 2)
	for _, d in ipairs(B.model:GetDescendants()) do
		if d:IsA("BasePart") then TweenService:Create(d, TweenInfo.new(2.5), { Transparency = 1 }):Play() end
	end
	for _, L in ipairs(legs) do
		TweenService:Create(L.s1, TweenInfo.new(2.5), { Transparency = 1 }):Play()
		TweenService:Create(L.s2, TweenInfo.new(2.5), { Transparency = 1 }):Play()
	end
	task.delay(6, cleanup)
end

function onPlayerDeath()
	if dead then return end
	dead, invertUntil = true, 0
	say("YOU DIED", 4)
	flash(Color3.fromRGB(120, 0, 0), 0.2, 2)
	pcall(function() Hum.Health = 0 end)
	task.delay(4, cleanup)
end

function cleanup()
	if cleaned then return end
	cleaned, running = true, false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() RunService:UnbindFromRenderStep("NB_Invert") end)
	pcall(function() CAS:UnbindAction("NB_Sword") end)
	pcall(function() CAS:UnbindAction("NB_Dash") end)
	restoreCorruption(true)
	for _, mo in ipairs(monsters) do pcall(setHidden, mo.src, false) end
	pcall(function() Hum.CameraOffset = Vector3.zero end)
	pcall(function() gui:Destroy() end)
	pcall(function() folder:Destroy() end)
	if genv.NB_CLEANUP == cleanup then genv.NB_CLEANUP = nil end
end
genv.NB_CLEANUP = cleanup

---------------------------------------------------------------- GO
buildBoss()
B.pos = Root.Position + Root.CFrame.LookVector * 50
B.gy = groundAt(B.pos.X, B.pos.Z, Root.Position.Y - 3)
B.cf = CFrame.new(B.pos)
refreshCache()
updateUI()

local warned = false
conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
	if not running then return end
	local ok, err = pcall(function()
		bossStep(dt)
		hazardStep(dt)
	end)
	if not ok and not warned then warned = true warn("[NightmareBoss] " .. tostring(err)) end
end)

conns[#conns + 1] = Hum.Died:Connect(function()
	if not dead then
		dead = true
		task.delay(3, cleanup)
	end
end)

-- boss AI
task.spawn(function()
	while running and not dead and not B.dead do
		if B.paused or B.stunned then
			task.wait(0.1)
		elseif phase <= 2 then
			groundCycle()
		else
			floatCycle()
		end
	end
end)

-- hazard director
task.spawn(function()
	local tT, tM, tG = 0, 0, 0
	while running and not dead do
		task.wait(0.5)
		if B.paused or B.dead then continue end
		local now = os.clock()
		local maxT = (phase == 2 and 7) or (phase == 3 and 2) or (phase == 5 and 5) or 0 -- phase 3 sprouts a few as gem sources
		if #tentacles < maxT and now - tT > (phase == 2 and 2.5 or 5) then tT = now spawnTentacle() end
		local maxM = (phase == 4 and 3) or (phase == 5 and 3) or 0
		if #monsters < maxM and now - tM > (phase == 4 and 6 or 9) then tM = now spawnMonster() end
		if (phase == 3 or phase == 5) and now - tG > 2 then tG = now corruptRandom() end
	end
end)

-- intro, then Phase 1
say("A NIGHTMARE AWAKENS...", 3)
shake(1.5, 1.5)
task.delay(3, function()
	if running and not dead then startPhase(1) end
end)
