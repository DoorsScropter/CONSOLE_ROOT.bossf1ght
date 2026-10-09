--[[
  NIGHTMARE BOSS v2  |  5-phase client-side boss fight  |  Delta / mobile executors
  Everything is local (only you see it). Re-executing the script cleans up the old run first.

  v2: segmented realistic tentacles EVERYWHERE, swarms of legged environment crawlers,
      PERMANENT map corruption (flesh / stretch / dissolve / levitate, breathing flesh, eyes),
      difficulty that climbs every phase, eruptions, bigger orb fans, rage as the boss gets hurt.

  Mobile buttons (ContextActionService): SLASH (Purifying Sword) and DASH (1s cooldown, i-frames)
  PC keys: E / left click = slash, Q = dash
  Tweak everything in CFG below (arrays are indexed by phase 1-5).
]]

local genv = (getgenv and getgenv()) or _G
if genv.NB_CLEANUP then pcall(genv.NB_CLEANUP) end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CAS = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local Hum = Char:WaitForChild("Humanoid")
local Root = Char:WaitForChild("HumanoidRootPart")
local Cam = Workspace.CurrentCamera

local CFG = {
	BOSS_USERID = nil, -- set a UserId (number) to build the boss from that avatar instead of yours
	PLAYER_HP = 100,
	HEAL_ON_CLEAR = 15, -- HP restored when a phase is cleared (set 0 for pure hell)
	SWORD_DAMAGE = 35,
	SWORD_COOLDOWN = 0.45,
	BOSS_HP = { 450, 600, 700, 850, 1100 },
	HOVER_HEIGHT = 45,
	DASH_COOLDOWN = 1,
	DASH_IFRAMES = 0.35,
	DASH_SPEED = 85,
	GEMS_NEEDED = { [3] = 3, [4] = 4, [5] = 5 },
	STUN_TIME = { [3] = 4.5, [4] = 4, [5] = 3.5 },
	INVERT_TIME = 2.0,
	INVERT_COUNT = { 0, 1, 2, 3, 4 }, -- how many 2s control inversions per phase

	-- boss movement / attacks (index = phase)
	CHASE_SPEED = { 24, 32 },
	ORBIT_SPEED = { [3] = 34, [4] = 40, [5] = 48 },
	FLOAT_WAIT = { [3] = 2.2, [4] = 1.7, [5] = 1.2 },

	-- tentacles (everywhere on the map)
	TENT_CAP = { 0, 16, 24, 32, 40 },
	TENT_INTERVAL = { 99, 0.5, 0.33, 0.2, 0.12 }, -- seconds between spawns
	TENT_RANGE = 260, -- max spawn distance from you
	TENT_DMG = { 0, 8, 10, 12, 14 }, -- touch damage per second
	TENT_STRIKE = { 0, 14, 18, 22, 26 }, -- lash damage
	TENT_GEM = { 0, 0.5, 1, 0.6, 0.4 }, -- gem drop chance when sliced

	-- legged environment crawlers (made from real map models)
	MON_CAP = { 0, 0, 6, 18, 28 },
	MON_INTERVAL = { 99, 99, 2.0, 0.8, 0.5 },
	MON_SPEED = { 0, 0, 11, 13, 16 },
	MON_DMG = { 0, 0, 8, 10, 13 },
	MON_GEM = { 0, 0, 0.8, 0.7, 0.55 },

	-- permanent environment corruption
	CORRUPT_INTERVAL = { 99, 3.0, 1.2, 0.7, 0.35 },
	CORRUPT_BATCH = { 0, 5, 10, 18, 28 },
	FLESH_CHANCE = { 0, 0.9, 0.3, 0.5, 0.65 },
	MAX_CORRUPT = 8000,

	SWORD_BTN_POS = UDim2.new(0.45, 0, 0.05, 0),
	DASH_BTN_POS = UDim2.new(0.45, 0, 0.55, 0),
}

local PHASE_NAMES = { "ARACHNID DUEL", "FLESH GARDEN", "GLITCHED REALITY", "LEGGED NIGHTMARES", "TOTAL CLIMAX" }
local LEG = 8.5
local BODY_H = 9
local TSEG = 6 -- tentacle segments

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
local corruptN, breathing, eyes, frameN, tentId = 0, 0, {}, 0, 0
local legs = {}
local B = {
	hp = 1, maxhp = 1, pos = Root.Position, gy = Root.Position.Y - 3, yaw = 0,
	height = -8, heightTarget = BODY_H, hRate = 6, mode = "idle", speed = 0, orbit = 0,
	shielded = false, stunned = false, paused = true, dead = false,
	cf = CFrame.new(Root.Position), rage = 1, cycle = 0,
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

local function needGems() return CFG.GEMS_NEEDED[phase] or 3 end

local warned2 = false
local function safe(f, ...)
	local ok, e = pcall(f, ...)
	if not ok and not warned2 then warned2 = true warn("[NightmareBoss] " .. tostring(e)) end
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
	gemLabel.Text = phase >= 3 and string.format("GEMS %d/%d", gemCount, needGems()) or ""
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

---------------------------------------------------------------- MOOD (lighting)
local cc = mk("ColorCorrectionEffect", { Name = "NB_CC" }, Lighting)
local origFog = { Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd }
local MOODS = {
	{ tint = Color3.fromRGB(255, 255, 255), sat = 0, con = 0 },
	{ tint = Color3.fromRGB(255, 235, 235), sat = -0.1, con = 0.05 },
	{ tint = Color3.fromRGB(255, 205, 215), sat = -0.2, con = 0.1, fog = 1200, fogCol = Color3.fromRGB(40, 0, 10) },
	{ tint = Color3.fromRGB(255, 170, 180), sat = -0.3, con = 0.15, fog = 700, fogCol = Color3.fromRGB(45, 0, 12) },
	{ tint = Color3.fromRGB(255, 130, 150), sat = -0.4, con = 0.2, fog = 450, fogCol = Color3.fromRGB(55, 0, 15) },
}
local function setMood(n)
	local m = MOODS[n]
	if not m then return end
	TweenService:Create(cc, TweenInfo.new(2), { TintColor = m.tint, Saturation = m.sat, Contrast = m.con }):Play()
	if m.fog then
		TweenService:Create(Lighting, TweenInfo.new(3), { FogColor = m.fogCol, FogStart = 0, FogEnd = m.fog }):Play()
	end
end

---------------------------------------------------------------- WORLD HELPERS
local function groundAt(x, z, ref)
	local r = Workspace:Raycast(Vector3.new(x, ref + 8, z), Vector3.new(0, -150, 0), RAYP)
	return r and r.Position.Y or ref
end

local function groundTop(x, z)
	local r = Workspace:Raycast(Vector3.new(x, Root.Position.Y + 120, z), Vector3.new(0, -400, 0), RAYP)
	return r and r.Position or nil
end

local cache, partCache, cacheT, refreshing = {}, {}, -100, false
local function refreshCache()
	if refreshing or os.clock() - cacheT < 10 then return end
	refreshing = true
	task.spawn(function()
		local out, parts, n = {}, {}, 0
		for _, m in ipairs(Workspace:GetDescendants()) do
			n += 1
			if n % 500 == 0 then task.wait() end
			if not running then break end
			if m:IsA("Model") then
				if m ~= Char and not m:IsDescendantOf(folder) and not m:IsDescendantOf(Char)
					and not m:IsDescendantOf(Cam) and not m:FindFirstChildWhichIsA("Humanoid")
					and m:FindFirstChildWhichIsA("BasePart") and not m.Name:lower():find("baseplate") then
					out[#out + 1] = m
				end
			elseif m:IsA("BasePart") and not m:IsA("Terrain") and #parts < 30000 then
				if not corrupted[m] and not m:IsDescendantOf(folder) and not m:IsDescendantOf(Char)
					and not m:IsDescendantOf(Cam) and not m.Name:lower():find("baseplate") and m.Size.Magnitude < 200 then
					parts[#parts + 1] = m
				end
			end
		end
		cache, partCache, cacheT, refreshing = out, parts, os.clock(), false
	end)
end

local function isGone(m)
	local a = m
	while a and a ~= Workspace do
		if hiddenModels[a] then return true end
		a = a.Parent
	end
	return false
end

-- Only Model instances in Workspace; never the player character, never anything under the player's feet
local function pickModel(maxExt, minD, maxD)
	refreshCache()
	if #cache == 0 then return nil end
	local fr = Workspace:Raycast(Root.Position, Vector3.new(0, -15, 0), RAYP)
	local floorPart = fr and fr.Instance
	local pp = Root.Position
	for _ = 1, 25 do
		local m = cache[rng:NextInteger(1, #cache)]
		if m and m.Parent and not isGone(m) and not (floorPart and floorPart:IsDescendantOf(m)) then
			local ok, sz = pcall(function() return m:GetExtentsSize() end)
			if ok and math.max(sz.X, sz.Y, sz.Z) <= maxExt then
				local okp, piv = pcall(function() return m:GetPivot().Position end)
				if okp then
					local d = (piv - pp).Magnitude
					if d >= (minD or 0) and d <= (maxD or 1e9) then return m, piv end
				end
			end
		end
	end
	return nil
end

-- PERMANENT: the original object is gone for good (no restore, no regeneration)
local function consume(m)
	hiddenModels[m] = true
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanTouch = false, false
			d.LocalTransparencyModifier = 1
		end
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

---------------------------------------------------------------- PERMANENT ENVIRONMENT CORRUPTION
local FLESH = {
	Color3.fromRGB(150, 45, 55), Color3.fromRGB(120, 30, 42), Color3.fromRGB(178, 82, 78),
	Color3.fromRGB(92, 22, 34), Color3.fromRGB(205, 120, 110), Color3.fromRGB(130, 20, 30),
}

local function stripLook(p)
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("SurfaceAppearance") or c:IsA("Texture") or c:IsA("Decal") then c:Destroy() end
	end
	if p:IsA("MeshPart") then pcall(function() p.TextureID = "" end) end
end

local function placeEye(p)
	if #eyes >= 36 then return end
	local ox = rng:NextNumber(-0.3, 0.3) * p.Size.X
	local oz = rng:NextNumber(-0.3, 0.3) * p.Size.Z
	local c = p.CFrame:PointToWorldSpace(Vector3.new(ox, p.Size.Y / 2, oz))
	local r = rng:NextNumber(1.2, 3)
	local white = mk("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2), Color = Color3.fromRGB(240, 232, 222), Material = Enum.Material.SmoothPlastic, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Position = c }, folder)
	local pupil = mk("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(r * 0.7, r * 0.7, r * 0.7), Color = Color3.fromRGB(12, 0, 0), Material = Enum.Material.SmoothPlastic, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Position = c }, folder)
	eyes[#eyes + 1] = { c = c, r = r, w = white, p = pupil }
end

local function fleshify(p, instant, extras)
	stripLook(p)
	local col = FLESH[rng:NextInteger(1, #FLESH)]
	if rng:NextNumber() < 0.7 then
		p.Material = Enum.Material.Fabric
	else
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.12
	end
	if instant then
		p.Color = col
	else
		TweenService:Create(p, TweenInfo.new(rng:NextNumber(0.8, 2)), { Color = col }):Play()
	end
	if extras then
		if breathing < 150 and rng:NextNumber() < 0.35 then -- living, breathing walls
			breathing += 1
			local s = p.Size
			TweenService:Create(p, TweenInfo.new(rng:NextNumber(0.9, 1.6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Size = s * rng:NextNumber(1.04, 1.1),
			}):Play()
		end
		if phase >= 4 and rng:NextNumber() < 0.1 then placeEye(p) end
	end
end

local function corruptPart(p, forceFlesh)
	corrupted[p] = true
	corruptN += 1
	local floorish = (p.Position.Y + p.Size.Y / 2) < B.gy + 4 or (p.Size.X > 80 and p.Size.Z > 80)
	local fc = CFG.FLESH_CHANCE[math.max(phase, 1)] or 0.4
	if forceFlesh or floorish or rng:NextNumber() < fc then -- floors only ever turn to flesh (never collapse under you)
		fleshify(p, false, true)
		return
	end
	local mode = rng:NextInteger(1, 3)
	if mode == 1 then -- stretch (permanent)
		local s = p.Size
		TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Size = Vector3.new(s.X * rng:NextNumber(0.5, 1.6), s.Y * rng:NextNumber(2, 4), s.Z * rng:NextNumber(0.5, 1.6)),
		}):Play()
	elseif mode == 2 then -- dissolve (permanent)
		TweenService:Create(p, TweenInfo.new(4, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
		task.delay(4, function() if p.Parent then p.CanCollide = false end end)
	elseif p.Anchored then -- levitate + twist (permanent)
		p.CanCollide = false
		TweenService:Create(p, TweenInfo.new(rng:NextNumber(2.5, 4), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			CFrame = p.CFrame * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5)) + Vector3.new(0, rng:NextNumber(6, 22), 0),
		}):Play()
	else
		fleshify(p, false, true)
	end
end

-- corrupt n random map parts (optionally only around `center` within `radius`); nothing is ever restored
local function corruptBatch(n, center, radius, forceFlesh)
	refreshCache()
	if #partCache == 0 or corruptN >= CFG.MAX_CORRUPT then return end
	local pp = Root.Position
	local c = center or pp
	local rad = radius or 320
	local done, tries, maxTries = 0, 0, n * (rad < 100 and 60 or 12)
	while done < n and tries < maxTries do
		tries += 1
		local p = partCache[rng:NextInteger(1, #partCache)]
		if p and p.Parent and not corrupted[p] and p.Transparency < 1 and p.LocalTransparencyModifier < 1
			and (p.Position - c).Magnitude <= rad and (p.Position - pp).Magnitude > 8 then
			local am = p:FindFirstAncestorOfClass("Model")
			if not (am and am:FindFirstChildOfClass("Humanoid")) and not p:IsDescendantOf(folder) then
				corruptPart(p, forceFlesh)
				done += 1
			end
		end
	end
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
	local stun = CFG.STUN_TIME[phase] or 4
	flash(Color3.fromRGB(120, 255, 255), 0.3, 0.5)
	shake(2, 0.6)
	say("SHIELD BROKEN - SLASH HIM!", stun)
	updateUI()
	local myPhase = phase
	task.delay(stun, function()
		if not running or B.dead or phase ~= myPhase or B.paused then return end
		B.stunned, B.shielded = false, true
		B.heightTarget, B.hRate, B.mode = CFG.HOVER_HEIGHT, 2, "orbit"
		makeShield()
		updateUI()
	end)
end

function launchGems()
	local need = needGems()
	gemCount = 0
	updateUI()
	local arrived = 0
	for i = 1, need do
		local g = mk("Part", {
			Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(80, 255, 255),
			Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
			Position = Root.Position + Vector3.new(0, 2, 0),
		}, folder)
		local ang = i * 2 * math.pi / need
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
			if arrived >= need then breakShield() end
		end)
	end
end

local function collectGem()
	if phase >= 3 and B.shielded and not B.stunned and gemCount < needGems() then
		gemCount += 1
		updateUI()
		if gemCount >= needGems() then launchGems() end
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
			B.orbit += dt * 0.5 * B.rage
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

---------------------------------------------------------------- HAZARDS: TENTACLES (realistic, segmented, everywhere)
local function segDia(i) return 3.4 - (i - 1) * (2.6 / (TSEG - 1)) end

local function spawnTentacle(atPos)
	local pos = atPos
	local quick = atPos ~= nil
	if not pos then
		local pp = Root.Position
		for _ = 1, 5 do
			local ang = rng:NextNumber(0, math.pi * 2)
			local dist = (rng:NextNumber() < 0.4) and rng:NextNumber(12, 45) or rng:NextNumber(45, CFG.TENT_RANGE)
			local x, z = pp.X + math.cos(ang) * dist, pp.Z + math.sin(ang) * dist
			local r = Workspace:Raycast(Vector3.new(x, pp.Y + 120, z), Vector3.new(0, -400, 0), RAYP)
			if r and r.Normal.Y > 0.4 then pos = r.Position break end
		end
	end
	if not pos then return end

	local col0 = Color3.fromRGB(rng:NextInteger(95, 130), rng:NextInteger(18, 32), rng:NextInteger(30, 45))
	local col1 = Color3.fromRGB(rng:NextInteger(190, 225), rng:NextInteger(70, 100), rng:NextInteger(80, 105))
	local segs = {}
	for i = 1, TSEG do
		segs[i] = mk("Part", {
			Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
			Material = Enum.Material.SmoothPlastic, Reflectance = 0.08, CastShadow = false,
			Color = col0:Lerp(col1, (i - 1) / (TSEG - 1)), Size = Vector3.new(1, 1, 1), Position = pos,
		}, folder)
	end
	local tip = mk("Part", {
		Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 70, 90), Size = Vector3.new(1.5, 1.5, 1.5), Position = pos,
	}, folder)
	local disc = mk("Part", {
		Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
		Material = Enum.Material.Fabric, Color = Color3.fromRGB(85, 14, 24), Size = Vector3.new(0.5, 9, 9),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	}, folder)
	ring(pos, 7, 0.7, Color3.fromRGB(255, 40, 60))

	local pts = {}
	for k = 1, TSEG + 1 do pts[k] = pos end
	tentId += 1
	local now = os.clock()
	tentacles[#tentacles + 1] = {
		segs = segs, tip = tip, disc = disc, base = pos, pts = pts, id = tentId,
		h = 0.6, target = rng:NextNumber(16, 30) + math.max(phase, 1) * 2, seed = rng:NextNumber(0, 10),
		growAt = now + (quick and 0.2 or 0.6), nextStrike = now + 1.8 + rng:NextNumber(0, 2),
		strikeAt = -10, hit = true, lastSeg = -1,
	}
end

local function destroyTentacle(t)
	for _, s in ipairs(t.segs) do s:Destroy() end
	t.tip:Destroy()
	t.disc:Destroy()
end

local function killTentacle(i)
	local t = table.remove(tentacles, i)
	if rng:NextNumber() < (CFG.TENT_GEM[math.max(phase, 1)] or 0.5) then
		spawnGem(t.base + Vector3.new(0, 3, 0))
	end
	ring(t.base, 6, 0.4, Color3.fromRGB(200, 40, 60))
	destroyTentacle(t)
end

local function pruneFarTentacle()
	local pp = Root.Position
	local worst, wi = 0, nil
	for i, t in ipairs(tentacles) do
		local d = (t.base - pp).Magnitude
		if d > worst then worst, wi = d, i end
	end
	if wi and worst > 190 then destroyTentacle(table.remove(tentacles, wi)) end
end

---------------------------------------------------------------- HAZARDS: LEGGED CRAWLERS (the environment comes alive)
local function buildCrawler()
	local mdl = Instance.new("Model")
	local sz = rng:NextNumber(3, 6)
	local body = mk("Part", {
		Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(sz, sz, sz),
		Color = FLESH[rng:NextInteger(1, #FLESH)], Material = Enum.Material.Fabric, CFrame = CFrame.new(0, 0, 0),
	}, mdl)
	for _, sx in ipairs({ -1, 1 }) do
		mk("Part", {
			Shape = Enum.PartType.Ball, Size = Vector3.new(sz * 0.3, sz * 0.3, sz * 0.3), Color = Color3.fromRGB(255, 255, 230),
			Material = Enum.Material.Neon, CFrame = body.CFrame * CFrame.new(sx * sz * 0.22, sz * 0.12, -sz * 0.42),
		}, mdl)
	end
	mdl.PrimaryPart = body
	return mdl
end

local function spawnMonster()
	local src, sp = pickModel(60, 12, 320)
	local m, pos
	if src then
		local ok, c = pcall(function() return src:Clone() end)
		if ok and c then m, pos = c, sp + Vector3.new(0, 4, 0) end
	end
	if not m then
		src = nil
		m = buildCrawler()
		local pp = Root.Position
		local ang, dist = rng:NextNumber(0, math.pi * 2), rng:NextNumber(40, 110)
		local gp = groundTop(pp.X + math.cos(ang) * dist, pp.Z + math.sin(ang) * dist)
		if not gp then m:Destroy() return end
		pos = gp + Vector3.new(0, 6, 0)
	end
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then d:Destroy()
		elseif d:IsA("BasePart") then parts[#parts + 1] = d end
	end
	if #parts == 0 or #parts > 60 then m:Destroy() return end
	m.Parent = folder
	local ext = m:GetExtentsSize()
	local mx = math.max(ext.X, ext.Y, ext.Z)
	pcall(function() m:ScaleTo(m:GetScale() * (mx > 10 and 10 / mx or (mx < 3 and 3 / mx or 1))) end)
	m:PivotTo(CFrame.new(pos))

	local pr = m.PrimaryPart or parts[1]
	local cf, size = m:GetBoundingBox()
	if src and phase >= 4 and rng:NextNumber() < 0.6 then -- some of them are already flesh
		for _, p in ipairs(parts) do fleshify(p, true, false) end
	end
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
	if src then consume(src) end -- the original object "becomes" the monster and never comes back
	monsters[#monsters + 1] = {
		m = m, pr = pr, welds = lw, hits = 0, src = src, hitCd = 0, jumpAt = 0,
		radius = math.max(size.X, size.Z) / 2, speed = (CFG.MON_SPEED[math.max(phase, 1)] or 12) * rng:NextNumber(0.85, 1.2),
	}
end

local function killMonster(i, giveGem)
	local mo = table.remove(monsters, i)
	if giveGem then
		local pos = mo.pr.Parent and mo.pr.Position or (Root.Position + Vector3.new(6, 0, 0))
		if pos.Y < B.gy - 50 then pos = Root.Position + Vector3.new(6, 0, 0) end
		spawnGem(pos + Vector3.new(0, 2, 0))
	end
	mo.m:Destroy() -- source stays gone: permanent
end

local function clearHazards()
	for i = #tentacles, 1, -1 do
		destroyTentacle(table.remove(tentacles, i))
	end
	for i = #monsters, 1, -1 do
		table.remove(monsters, i).m:Destroy()
	end
	for i = #gems, 1, -1 do
		table.remove(gems, i).part:Destroy()
	end
end

local tParts, tCFs = {}, {}
local function bulk(parts, cfs)
	local ok = pcall(Workspace.BulkMoveTo, Workspace, parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if not ok then
		for i, p in ipairs(parts) do p.CFrame = cfs[i] end
	end
end

local function hazardStep(dt)
	frameN += 1
	local now = os.clock()
	local pp = Root.Position
	local ph = math.max(phase, 1)
	local acc = 0

	-- tentacles
	table.clear(tParts)
	table.clear(tCFs)
	for _, t in ipairs(tentacles) do
		local base = t.base
		local flatV = Vector3.new(pp.X - base.X, 0, pp.Z - base.Z)
		local dflat = flatV.Magnitude
		local far = dflat > 180
		if far and (frameN + t.id) % 4 ~= 0 then continue end

		if now >= t.growAt and t.h < t.target then
			t.h = math.min(t.target, t.h + 24 * dt * (far and 4 or 1))
		end
		local seg = t.h / TSEG
		if math.abs(seg - t.lastSeg) > 0.01 then
			t.lastSeg = seg
			local gk = math.clamp(t.h / 8, 0.25, 1)
			for i = 1, TSEG do
				local dia = segDia(i) * gk
				t.segs[i].Size = Vector3.new(seg * 1.2, dia, dia)
			end
		end

		local toP = (pp - base)
		toP = toP.Magnitude > 0.1 and toP.Unit or Vector3.yAxis
		local aggr = math.clamp(1 - dflat / 60, 0, 1) * 0.9 + 0.1
		local striking = now - t.strikeAt < 0.5
		if not striking and now > t.nextStrike and t.h >= t.target * 0.9 and dflat < t.h * 1.3 + 8 then
			t.strikeAt, t.hit = now, false
			t.nextStrike = now + rng:NextNumber(1.8, 3.6) / (1 + ph * 0.1)
			striking = true
		end
		local lean = (striking and 2.2 or 0.55) * aggr

		local pts = t.pts
		pts[1] = base
		local dir = Vector3.yAxis
		local minHit = 1e9
		for i = 1, TSEG do
			local f = i / TSEG
			local wob = Vector3.new(
				math.sin(now * 1.7 + t.seed + i * 0.9),
				math.sin(now * 1.1 + t.seed * 2 + i * 0.5) * 0.3,
				math.cos(now * 1.4 + t.seed * 1.3 + i * 1.1)
			) * 0.45 * f
			dir = (dir + wob + toP * lean * f * 0.6 + Vector3.new(0, -0.12 * f, 0)).Unit
			local b2 = pts[i] + dir * seg
			pts[i + 1] = b2
			if not far then
				local a = pts[i]
				local ab = b2 - a
				local tt = math.clamp((pp - a):Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
				local d = (a + ab * tt - pp).Magnitude - (segDia(i) * 0.5 + 1.8)
				if d < minHit then minHit = d end
			end
			local part = t.segs[i]
			tParts[#tParts + 1] = part
			tCFs[#tCFs + 1] = CFrame.lookAt((pts[i] + b2) / 2, b2) * CFrame.Angles(0, math.pi / 2, 0)
		end
		tParts[#tParts + 1] = t.tip
		tCFs[#tCFs + 1] = CFrame.new(pts[TSEG + 1])

		if not far and t.h > 4 then
			if minHit < 0.4 then acc += (CFG.TENT_DMG[ph] or 8) * dt end -- continuous touch damage
			if striking and not t.hit and minHit < 1.2 then
				t.hit = true
				acc += CFG.TENT_STRIKE[ph] or 14 -- lash
			end
		end
	end
	if #tParts > 0 then bulk(tParts, tCFs) end

	-- crawlers
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
			local sp = mo.speed * (mag > 70 and 2.4 or 1)
			if now > mo.hitCd - 0.5 then
				mo.pr.AssemblyLinearVelocity = Vector3.new(dir.X * sp, vel.Y, dir.Z * sp)
				if now > mo.jumpAt and mag > 6 and Vector3.new(vel.X, 0, vel.Z).Magnitude < sp * 0.3 then
					mo.jumpAt = now + 1.2 -- stuck on something: hop
					mo.pr.AssemblyLinearVelocity = Vector3.new(dir.X * sp, 45, dir.Z * sp)
				end
			end
			for _, l in ipairs(mo.welds) do
				l.w.C0 = l.c0 * CFrame.Angles(math.sin(now * 9 + l.ph) * 0.6, 0, 0)
			end
			if mag < mo.radius + 4 and now > mo.hitCd and math.abs(pp.Y - mp.Y) < 10 then
				mo.hitCd = now + 1
				acc += CFG.MON_DMG[ph] or 10
			end
			if mp.Y < B.gy - 100 then killMonster(i, true) end
		end
	end

	-- gems
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

	if acc > 0 then hurt(acc) end
end

local function eyeStep()
	if frameN % 2 ~= 0 or #eyes == 0 then return end
	local pp = Root.Position
	local ps, cs = {}, {}
	for _, e in ipairs(eyes) do
		if e.p.Parent then
			local v = pp - e.c
			if v.Magnitude < 250 and v.Magnitude > 0.1 then
				ps[#ps + 1] = e.p
				cs[#cs + 1] = CFrame.new(e.c + v.Unit * e.r * 0.85)
			end
		end
	end
	if #ps > 0 then bulk(ps, cs) end
end

---------------------------------------------------------------- BOSS ATTACKS
local function slam()
	local ph = math.max(phase, 1)
	local R = ({ 24, 30 })[ph] or 26
	local wind = ({ 1.3, 1.0 })[ph] or 1.2
	local dmg = ({ 30, 40 })[ph] or 35
	B.mode, B.heightTarget, B.hRate = "idle", 16, 3
	local center = Vector3.new(B.pos.X, B.gy, B.pos.Z)
	local warnDisc = mk("Part", {
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, R * 2, R * 2), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon,
		Transparency = 0.8, CFrame = CFrame.new(center + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	}, folder)
	Debris:AddItem(warnDisc, wind + 0.2)
	ring(center, R, wind, Color3.fromRGB(255, 40, 40))
	task.wait(wind / B.rage)
	if not running or B.dead then return end
	B.hRate, B.heightTarget = 30, BODY_H
	task.wait(0.12)
	shake(1.2, 0.5)
	ring(center, R + 6, 0.5, Color3.fromRGB(255, 150, 40))
	local pp = Root.Position
	local flat = Vector3.new(pp.X - center.X, 0, pp.Z - center.Z).Magnitude
	if flat < R and pp.Y - center.Y < 6.5 then hurt(dmg) end -- jump or dash to dodge
	if ph >= 2 then -- the impact rots the ground and sprouts tentacles
		safe(corruptBatch, 14, center, R + 14, true)
		for _ = 1, 3 do
			local a = rng:NextNumber(0, math.pi * 2)
			local gp = groundTop(center.X + math.cos(a) * (R + 4), center.Z + math.sin(a) * (R + 4))
			if gp then safe(spawnTentacle, gp) end
		end
	end
	B.hRate = 6
	task.wait(1.1 / B.rage)
end

local function fireOrb(spread, speed, dmg)
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
			p.Position += dir * speed * dt
			if (p.Position - Root.Position).Magnitude < 4 then hurt(dmg) break end
		end
		p:Destroy()
	end)
end

-- boss marks the ground around you; after a beat it ERUPTS (damage + tentacle + rot)
local function eruption(count, radius, dmg)
	local spots = {}
	local pp = Root.Position
	local vel = Root.AssemblyLinearVelocity
	for i = 1, count do
		local off = (i == 1) and (Vector3.new(vel.X, 0, vel.Z) * 0.6) or Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30))
		local x, z = pp.X + off.X, pp.Z + off.Z
		local gp = groundTop(x, z)
		local spot = Vector3.new(x, gp and gp.Y or (pp.Y - 3), z)
		spots[#spots + 1] = spot
		local disc = mk("Part", {
			Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, radius * 2, radius * 2), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon,
			Transparency = 0.75, CFrame = CFrame.new(spot + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		}, folder)
		Debris:AddItem(disc, 1.3)
		ring(spot, radius, 1.1, Color3.fromRGB(255, 40, 40))
	end
	task.wait(1.1 / math.min(B.rage, 1.4))
	if not running or B.dead then return end
	shake(1.2, 0.5)
	for _, spot in ipairs(spots) do
		ring(spot, radius + 5, 0.4, Color3.fromRGB(255, 150, 40))
		local p2 = Root.Position
		if Vector3.new(p2.X - spot.X, 0, p2.Z - spot.Z).Magnitude < radius and p2.Y - spot.Y < 8 then hurt(dmg) end
		safe(spawnTentacle, spot)
		safe(corruptBatch, 6, spot, radius * 2.5, true)
	end
end

local function groundCycle()
	B.mode, B.speed = "chase", CFG.CHASE_SPEED[math.max(phase, 1)] or 26
	local t0 = os.clock()
	while running and not B.dead and os.clock() - t0 < 4 / B.rage do
		local pp = Root.Position
		if Vector3.new(pp.X - B.pos.X, 0, pp.Z - B.pos.Z).Magnitude < 20 and os.clock() - t0 > 1.0 then break end
		task.wait(0.1)
	end
	if B.paused or B.stunned or B.dead then return end
	slam()
	if phase == 2 and not B.dead and not B.paused and not B.stunned and running then
		for _, s in ipairs({ -0.3, 0, 0.3 }) do fireOrb(s, 52, 12) end
	end
end

local FANS = {
	[3] = { -0.22, 0, 0.22 },
	[4] = { -0.45, -0.22, 0, 0.22, 0.45 },
	[5] = { -0.6, -0.4, -0.2, 0, 0.2, 0.4, 0.6 },
}

local function floatCycle()
	local ph = phase
	B.mode, B.speed = "orbit", CFG.ORBIT_SPEED[ph] or 36
	local w = CFG.FLOAT_WAIT[ph] or 2
	task.wait(rng:NextNumber(w, w + 1) / B.rage)
	if B.stunned or B.paused or B.dead or not running then return end
	B.cycle += 1
	local speed, dmg = 45 + ph * 5, 12 + ph * 2
	if ph == 3 and B.cycle % 2 == 0 then
		eruption(3, 11, 22)
		return
	end
	for _, s in ipairs(FANS[ph] or FANS[3]) do fireOrb(s, speed, dmg) end
	if ph >= 4 then
		task.wait(0.4)
		if B.stunned or B.paused or B.dead or not running then return end
		eruption(ph == 4 and 4 or 7, 11, 24)
		if ph == 5 and not (B.stunned or B.paused or B.dead) then
			task.wait(0.3)
			for _, s in ipairs(FANS[5]) do fireOrb(s * 1.4, speed + 10, dmg) end -- second, wider volley
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
	B.rage = 1 + (1 - math.clamp(B.hp / B.maxhp, 0, 1)) * 0.6 -- the more you hurt him, the faster he gets
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
	-- tentacles: one slice deletes the ones in front of you (closest point of the body counts)
	for i = #tentacles, 1, -1 do
		local t = tentacles[i]
		local best, bv = 1e9, nil
		for k = 1, TSEG + 1 do
			local pt = t.pts[k]
			if pt then
				local v = Vector3.new(pt.X - pp.X, 0, pt.Z - pp.Z)
				local m = v.Magnitude
				if m < best then best, bv = m, v end
			end
		end
		if bv and best < 13 and (best < 5 or bv.Unit:Dot(look) > 0) then killTentacle(i) end
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
				killMonster(i, rng:NextNumber() < (CFG.MON_GEM[math.max(phase, 1)] or 0.5))
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
	B.rage, B.cycle = 1, 0
	gemCount = 0
	if B.shield then B.shield:Destroy() B.shield = nil end
	if n >= 3 then
		B.shielded = true
		makeShield()
		B.heightTarget, B.hRate, B.mode, B.speed = CFG.HOVER_HEIGHT, 1.5, "orbit", CFG.ORBIT_SPEED[n] or 36
	else
		B.shielded = false
		B.heightTarget, B.hRate, B.mode = BODY_H, 6, "chase"
	end
	setMood(n)
	flash(Color3.fromRGB(255, 0, 60), 0.4, 1)
	shake(2, 0.8)
	say(string.format("PHASE %d - %s", n, PHASE_NAMES[n]), 3.5)
	updateUI()
	-- control inversions (2s each), more of them every phase
	local at = rng:NextNumber(5, 9)
	for _ = 1, CFG.INVERT_COUNT[n] or 0 do
		local when = at
		at += rng:NextNumber(8, 12)
		task.delay(when, function()
			if running and phase == n and not dead and not B.dead and not B.paused then invert() end
		end)
	end
end

function nextPhase()
	B.paused, B.stunned, B.shielded = true, false, false
	B.mode = "idle"
	B.heightTarget, B.hRate = BODY_H, 3
	clearHazards() -- hazards go, but the corruption stays forever
	if B.shield then B.shield:Destroy() B.shield = nil end
	playerHP = math.min(CFG.PLAYER_HP, playerHP + CFG.HEAL_ON_CLEAR)
	updateUI()
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
	-- NOTE: corrupted / consumed map parts are intentionally NOT restored
	pcall(function() Hum.CameraOffset = Vector3.zero end)
	pcall(function() cc:Destroy() end)
	pcall(function()
		Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd = origFog[1], origFog[2], origFog[3]
	end)
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
		eyeStep()
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
			safe(groundCycle)
		else
			safe(floatCycle)
		end
	end
end)

-- hazard director: tentacles everywhere, crawler swarms, permanent corruption
task.spawn(function()
	local tT, tM, tC, tB = 0, 0, 0, 0
	while running and not dead do
		task.wait(0.1)
		if B.paused or B.dead or phase < 1 then continue end
		local now = os.clock()
		local ph = phase
		local rage = B.rage

		local tcap = CFG.TENT_CAP[ph] or 0
		if tcap > 0 and now - tT > (CFG.TENT_INTERVAL[ph] or 1) / rage then
			tT = now
			for _ = 1, (ph >= 4 and 2 or 1) do
				if #tentacles >= tcap then safe(pruneFarTentacle) end
				if #tentacles < tcap then safe(spawnTentacle) end
			end
		end

		local mcap = CFG.MON_CAP[ph] or 0
		if mcap > 0 and now - tM > (CFG.MON_INTERVAL[ph] or 1) / rage then
			tM = now
			for _ = 1, (ph >= 5 and 2 or 1) do
				if #monsters < mcap then safe(spawnMonster) end
			end
		end

		if ph >= 2 and now - tC > (CFG.CORRUPT_INTERVAL[ph] or 2) / rage then
			tC = now
			safe(corruptBatch, CFG.CORRUPT_BATCH[ph] or 5)
			if ph >= 4 and rng:NextNumber() < 0.25 then shake(0.6, 0.5) end -- the world rumbles
		end

		if ph >= 4 and now - tB > (ph == 4 and 14 or 9) then -- big reality wave
			tB = now
			say("REALITY IS BLEEDING", 2.5)
			flash(Color3.fromRGB(200, 0, 80), 0.6, 1)
			shake(2, 1)
			safe(corruptBatch, 60, nil, 200)
		end
	end
end)

-- intro, then Phase 1
say("A NIGHTMARE AWAKENS...", 3)
shake(1.5, 1.5)
task.delay(3, function()
	if running and not dead then startPhase(1) end
end)
