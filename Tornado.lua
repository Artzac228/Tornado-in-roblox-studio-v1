-- ============================================================
--  TORNADO  —  Roblox Studio  —  ServerScriptService
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris     = game:GetService("Debris")

-- ── CONFIG ──────────────────────────────────────────────────
local CFG = {
	-- Позиция старта
	Position        = Vector3.new(0, 0, 0),

	-- Воронка
	Height          = 80,
	BaseRadius      = 18,
	TopRadius       = 5,
	Segments        = 20,
	RotSpeed        = 4.0,       -- рад/с вращения воронки
	RotAccel        = 2.0,       -- плавность разгона
	FunnelShape     = "cone",    -- "cone" | "cylinder" | "hourglass"
	FunnelThickness = 1.0,
	FunnelOpacityLow  = 0.5,
	FunnelOpacityHigh = 0.85,
	FunnelColor     = Color3.fromRGB(85, 75, 70),

	-- Скорость ветра (множитель мощности)
	WindSpeed       = 1.0,

	-- Захват объектов
	PullRadius      = 30,
	AttractionRadius= 55,        -- притяжение физикой до захвата
	OrbitSpeed      = 5.0,       -- скорость вращения по орбите
	LiftSpeed       = 5.0,       -- скорость подъёма объектов
	SpinSpeed       = 4.0,       -- скорость вращения объектов вокруг себя
	EjectHeight     = 22,        -- высота выброса
	EjectForce      = 35,        -- сила горизонтального выброса
	EjectCooldown   = 5.0,       -- пауза после выброса
	GrabAnchored    = true,
	GrabModels      = true,
	MaxPartMass     = 500,
	MaxModelMass    = 2000,

	-- Игрок
	PlayerDmgPerSec = 5,
	PlayerLiftSpeed = 3.5,

	-- Движение торнадо
	-- "nearest" | "dash" | "random" | "static"
	MoveMode        = "nearest",
	MoveSpeed       = 14,
	TrackSmooth     = 0.04,
	DashSpeed       = 60,
	DashDuration    = 0.6,
	DashCooldown    = 4.0,
	DashMinDist     = 10,
	RandDirMin      = 2.0,
	RandDirMax      = 5.0,
	WanderRadius    = 80,

	-- Декоративный мусор вокруг воронки
	DebrisCount     = 35,
	DebrisRadius    = 20,
	DebrisColor     = Color3.fromRGB(105, 92, 78),

	-- Верхний диск-облако
	TopDiskEnabled    = true,
	TopDiskRadius     = 75,
	TopDiskThickness  = 7,
	TopDiskColor      = Color3.fromRGB(50, 46, 44),
	TopDiskTransp     = 0.3,
	TopDiskRings      = 2,
	TopDiskRingMult   = 1.7,
	TopDiskRingLift   = 5,

	-- Нижнее облако (дым)
	GroundSmokeCount    = 28,
	GroundSmokeRadius   = 26,
	GroundSmokeIntensity= 1.0,
	InnerSmokeCount     = 16,
	InnerSmokeRadius    = 10,
	InnerSmokeIntensity = 1.2,
	CloudCount          = 20,
	CloudRadius         = 42,
	CloudHeight         = 7,
	CloudIntensity      = 1.0,
	HazeCount           = 14,
	HazeRadius          = 62,
	HazeHeight          = 4,
	HazeIntensity       = 0.6,

	-- Анимация появления
	SpawnDuration   = 4.5,
	SpawnDropHeight = 130,

	SoundId         = "rbxassetid://9125417792",
	Duration        = 0,
}
-- ────────────────────────────────────────────────────────────

-- Текущая позиция центра (меняется при движении)
local PX = CFG.Position.X
local PY = CFG.Position.Y
local PZ = CFG.Position.Z
local START_X, START_Z = PX, PZ

-- Папка для всех FX-объектов
local folder = Instance.new("Folder")
folder.Name = "TornadoFX"
folder.Parent = workspace
local fxSet = {}   -- быстрая проверка "это FX-парт?"

-- Кэш персонажей
local charCache = {}
local function initCharacterCache()
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then charCache[pl.Character] = true end
	end
end

local function setupPlayerConnections(pl)
	pl.CharacterAdded:Connect(function(c) charCache[c] = true end)
	pl.CharacterRemoving:Connect(function(c) charCache[c] = nil end)
end

initCharacterCache()

Players.PlayerAdded:Connect(setupPlayerConnections)

for _, pl in ipairs(Players:GetPlayers()) do
	setupPlayerConnections(pl)
end

-- ── Утилиты ─────────────────────────────────────────────────

local function fx(size, color, transp, shape)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Transparency = transp
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = folder
	fxSet[p] = true
	return p
end

local function smoke(part, op, color, rise)
	local s = Instance.new("Smoke")
	s.Enabled = false
	s.Opacity = op or 0.4
	s.Size = 3
	s.RiseVelocity = rise or 4
	s.Color = color or Color3.fromRGB(90, 85, 80)
	s.Parent = part
	return s
end

local function particles(part, rate, speed, size, color, lifetime)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = 0
	pe.Speed = NumberRange.new(speed * 0.2, speed)
	pe.Lifetime = NumberRange.new((lifetime or 5) * 0.6, lifetime or 5)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.15),
		NumberSequenceKeypoint.new(0.35, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.5),
		NumberSequenceKeypoint.new(0.8, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(color or Color3.fromRGB(80, 75, 70))
	pe.RotSpeed = NumberRange.new(-20, 20)
	pe.Rotation = NumberRange.new(0, 360)
	pe.SpreadAngle = Vector2.new(40, 40)
	pe.Parent = part
	return pe
end

local function tw(obj, props, t, style, dir)
	return TweenService:Create(obj,
		TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props)
end

local function distance2D(x1, z1, x2, z2)
	local dx = x1 - x2
	local dz = z1 - z2
	return dx * dx + dz * dz
end

local function distance2D_unsafe(dx, dz)
	return dx * dx + dz * dz
end

-- ── Воронка ─────────────────────────────────────────────────

local segments  = {}
local segAngles = {}
local rotSpeed  = 0

for i = 1, CFG.Segments do
	local t = (i - 1) / CFG.Segments
	local r
	if CFG.FunnelShape == "cylinder" then
		r = CFG.BaseRadius
	elseif CFG.FunnelShape == "hourglass" then
		r = CFG.TopRadius + (CFG.BaseRadius - CFG.TopRadius) * (1 - math.abs(t - 0.5) * 2)
	else
		r = CFG.BaseRadius + (CFG.TopRadius - CFG.BaseRadius) * t
	end
	r = r * CFG.FunnelThickness
	local segH  = CFG.Height / CFG.Segments + 0.5
	local finalY = PY + CFG.Height * t
	local transp = CFG.FunnelOpacityLow + (CFG.FunnelOpacityHigh - CFG.FunnelOpacityLow) * t
	local seg = fx(Vector3.new(segH, r * 2, r * 2), CFG.FunnelColor, 1, Enum.PartType.Cylinder)
	seg.CFrame = CFrame.new(PX, finalY + CFG.SpawnDropHeight, PZ) * CFrame.Angles(0, 0, math.pi / 2)
	if i <= 5 then smoke(seg, 0.2 - i * 0.03, CFG.FunnelColor, 5) end
	segAngles[i] = 0
	table.insert(segments, {part=seg, t=t, finalY=finalY, finalTransp=transp})
end

-- ── Верхний диск ────────────────────────────────────────────

local diskParts = {}
local diskAngle = 0

local function makeDisk(r, th, col, transp, yOff)
	local p = fx(Vector3.new(th, r * 2, r * 2), col, transp, Enum.PartType.Cylinder)
	p.CFrame = CFrame.new(PX, PY + CFG.Height + CFG.TopRadius + yOff + CFG.SpawnDropHeight, PZ)
		* CFrame.Angles(0, 0, math.pi / 2)
	return p
end

if CFG.TopDiskEnabled then
	local main = makeDisk(CFG.TopDiskRadius, CFG.TopDiskThickness, CFG.TopDiskColor, CFG.TopDiskTransp, 0)
	smoke(main, 0.25, Color3.fromRGB(70, 65, 62), 2)
	table.insert(diskParts, {part=main, yOff=0})
	for i = 1, CFG.TopDiskRings do
		local frac = i / CFG.TopDiskRings
		local r  = CFG.TopDiskRadius * (CFG.TopDiskRingMult ^ i)
		local th = math.max(2, CFG.TopDiskThickness * (1 - frac * 0.5))
		local tr = math.min(0.92, CFG.TopDiskTransp + frac * 0.3)
		local c  = CFG.TopDiskColor:Lerp(Color3.fromRGB(85, 78, 74), frac * 0.4)
		local yO = CFG.TopDiskRingLift * i
		local ring = makeDisk(r, th, c, tr, yO)
		table.insert(diskParts, {part=ring, yOff=yO})
	end
end

-- ── Нижнее облако — дымовые точки ───────────────────────────

local smokeEmitters = {}

local function addSmokePoint(ox, oy, oz, angle, radius, sz, op, clr, rate, rise)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.CFrame = CFrame.new(ox, oy, oz)
	p.Parent = folder
	fxSet[p] = true
	local s = smoke(p, op, clr, rise)
	local pe = particles(p, rate, 1.5, sz, clr, 7)
	table.insert(smokeEmitters, {part=p, smoke=s, pe=pe, angle=angle, radius=radius, baseY=oy-PY})
end

-- Слой 1 — тёмный ковёр у земли
for i = 1, CFG.GroundSmokeCount do
	local a = (i - 1) / CFG.GroundSmokeCount * math.pi * 2 + (math.random() - 0.5) * 0.5
	local r = CFG.GroundSmokeRadius * (0.6 + math.random() * 1.2)
	addSmokePoint(PX + math.cos(a) * r, PY + math.random() * 1.5, PZ + math.sin(a) * r,
		a, r, 14 + math.random() * 10, 0.55 + math.random() * 0.2,
		Color3.fromRGB(42, 38, 36), math.floor(12 * CFG.GroundSmokeIntensity), 1.2)
end

-- Слой 2 — вихрь под воронкой
for i = 1, CFG.InnerSmokeCount do
	local a = (i - 1) / CFG.InnerSmokeCount * math.pi * 2 + math.random() * 0.5
	local r = CFG.InnerSmokeRadius * (0.3 + math.random() * 0.9)
	addSmokePoint(PX + math.cos(a) * r, PY + math.random() * 2.5, PZ + math.sin(a) * r,
		a, r, 8 + math.random() * 6, 0.65 + math.random() * 0.2,
		Color3.fromRGB(28, 26, 25), math.floor(14 * CFG.InnerSmokeIntensity), 0.5)
end

-- Слой 3 — основное облако
do
	local rings = {
		{n=CFG.CloudCount//3, rm=0.95, h1=2, h2=6,  sz=20, op=0.5},
		{n=CFG.CloudCount//3, rm=1.3,  h1=4, h2=9,  sz=26, op=0.42},
		{n=CFG.CloudCount - CFG.CloudCount//3*2, rm=1.7, h1=6, h2=CFG.CloudHeight+6, sz=32, op=0.33},
	}
	for _, ring in ipairs(rings) do
		for i = 1, ring.n do
			local a = (i - 1) / ring.n * math.pi * 2 + math.random() * 0.7
			local r = CFG.BaseRadius * ring.rm * (0.82 + math.random() * 0.36)
			local h = PY + ring.h1 + math.random() * (ring.h2 - ring.h1)
			addSmokePoint(PX + math.cos(a) * r, h, PZ + math.sin(a) * r,
				a, r, ring.sz + (math.random() - 0.5) * 6,
				ring.op + (math.random() - 0.5) * 0.08,
				Color3.fromRGB(62, 57, 53), math.floor(9 * CFG.CloudIntensity), 1.8)
		end
	end
end

-- Слой 4 — дальняя дымка
for i = 1, CFG.HazeCount do
	local a = (i - 1) / CFG.HazeCount * math.pi * 2 + math.random() * 1.1
	local r = CFG.HazeRadius * (0.8 + math.random() * 0.4)
	addSmokePoint(PX + math.cos(a) * r, PY + CFG.HazeHeight + math.random() * 8, PZ + math.sin(a) * r,
		a, r, 26 + math.random() * 16, 0.14 + math.random() * 0.1,
		Color3.fromRGB(85, 78, 72), math.floor(4 * CFG.HazeIntensity), 2)
end

-- ── Декоративный мусор ───────────────────────────────────────

local debris = {}
for i = 1, CFG.DebrisCount do
	local a  = math.random() * math.pi * 2
	local r  = CFG.DebrisRadius * (0.3 + math.random() * 0.7)
	local h  = math.random() * CFG.Height * 0.7
	local sz = math.random() * 1.3 + 0.3
	local d  = fx(Vector3.new(sz, sz * 0.4, sz * 0.4), CFG.DebrisColor, 1)
	d.CFrame = CFrame.new(PX + math.cos(a) * r, PY + h, PZ + math.sin(a) * r)
	table.insert(debris, {part=d, angle=a, radius=r, height=h,
		speed=2+math.random()*3, vy=(math.random()-0.5)*1.5})
end

-- ── Звук ────────────────────────────────────────────────────

local snd = Instance.new("Sound")
snd.SoundId = CFG.SoundId
snd.Looped = true
snd.Volume = 0
snd.RollOffMaxDistance = 250
snd.Parent = smokeEmitters[1] and smokeEmitters[1].part or folder
snd:Play()

-- ── Анимация появления ──────────────────────────────────────

local spawnDone = false

local function playSpawn()
	local D = CFG.SpawnDuration
	tw(snd, {Volume=2.5}, D*0.8):Play()
	
	-- Сегменты слетают вниз с задержкой
	for i, seg in ipairs(segments) do
		local delay   = seg.t * D * 0.4
		local moveDur = D * 0.58
		local finalCF = CFrame.new(PX, seg.finalY, PZ) * CFrame.Angles(0, 0, math.pi / 2)
		task.delay(delay, function()
			if not folder.Parent then return end
			tw(seg.part, {Transparency=seg.finalTransp}, moveDur*0.45):Play()
			tw(seg.part, {CFrame=finalCF}, moveDur):Play()
		end)
	end
	
	-- Диск
	task.delay(0.1, function()
		for _, e in ipairs(diskParts) do
			if not folder.Parent then return end
			local y = PY + CFG.Height + CFG.TopRadius + e.yOff
			tw(e.part, {CFrame=CFrame.new(PX, y, PZ)*CFrame.Angles(0, 0, math.pi/2)}, D*0.65):Play()
		end
	end)
	
	-- Дым и облако
	task.delay(D*0.3, function()
		for i, e in ipairs(smokeEmitters) do
			task.delay((i-1)*0.04, function()
				if not folder.Parent then return end
				e.smoke.Enabled = true
				if e.pe then
					e.pe.Rate = 0
					task.delay(0.2, function()
						if e.pe then e.pe.Rate = 4 end
					end)
					task.delay(0.7, function()
						if e.pe then e.pe.Rate = 8 end
					end)
				end
			end)
		end
	end)
	
	-- Мусор
	for i, d in ipairs(debris) do
		task.delay(D*0.4 + (i/CFG.DebrisCount)*D*0.5, function()
			if d.part and d.part.Parent then
				tw(d.part, {Transparency=math.random()*0.3}, 0.4):Play()
			end
		end)
	end
	
	task.delay(D, function()
		spawnDone = true
		print("[Tornado] Готов!")
	end)
end

playSpawn()

-- ── Обновление воронки (вращение) ───────────────────────────

local function updateFunnel(dt)
	rotSpeed = rotSpeed + (CFG.RotSpeed * CFG.WindSpeed - rotSpeed) * math.min(1, CFG.RotAccel * dt)
	for i, seg in ipairs(segments) do
		local spd = rotSpeed * (1 + (1 - seg.t) * 0.4)
		segAngles[i] = segAngles[i] + dt * spd
		seg.part.CFrame = CFrame.new(PX, seg.finalY, PZ)
			* CFrame.Angles(0, segAngles[i], 0)
			* CFrame.Angles(0, 0, math.pi / 2)
	end
	diskAngle = diskAngle + dt * rotSpeed * 0.12
	for _, e in ipairs(diskParts) do
		e.part.CFrame = CFrame.new(PX, PY + CFG.Height + CFG.TopRadius + e.yOff, PZ)
			* CFrame.Angles(0, diskAngle, math.pi / 2)
	end
end

-- ── Движение торнадо ─────────────────────────────────────────

local moveDX, moveDZ = 0, 0
local dashTimer = 0
local isDashing = false
local dashLeft = 0
local randTimer = 0
local randIntv  = CFG.RandDirMin

local function nearestPlayer()
	local bd, bx, bz = math.huge, nil, nil
	for _, pl in ipairs(Players:GetPlayers()) do
		local c  = pl.Character
		local h  = c and c:FindFirstChild("HumanoidRootPart")
		local hm = c and c:FindFirstChild("Humanoid")
		if h and hm and hm.Health > 0 then
			local dx = h.Position.X - PX
			local dz = h.Position.Z - PZ
			local d  = math.sqrt(dx * dx + dz * dz)
			if d < bd then
				bd = d
				bx = h.Position.X
				bz = h.Position.Z
			end
		end
	end
	return bx, bz, bd
end

local function updateMovement(dt)
	if not spawnDone then return end
	local mode = CFG.MoveMode
	if mode == "static" then return end
	local spd = CFG.MoveSpeed * CFG.WindSpeed

	if mode == "nearest" then
		local tx, tz = nearestPlayer()
		if tx then
			local dx = tx - PX
			local dz = tz - PZ
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 0.1 then
				moveDX = moveDX + (dx / len - moveDX) * CFG.TrackSmooth
				moveDZ = moveDZ + (dz / len - moveDZ) * CFG.TrackSmooth
				local ml = math.sqrt(moveDX * moveDX + moveDZ * moveDZ)
				if ml > 0.01 then
					moveDX = moveDX / ml
					moveDZ = moveDZ / ml
				end
			end
		else
			moveDX = moveDX * 0.95
			moveDZ = moveDZ * 0.95
		end
		PX = PX + moveDX * spd * dt
		PZ = PZ + moveDZ * spd * dt

	elseif mode == "dash" then
		dashTimer = dashTimer + dt
		if isDashing then
			PX = PX + moveDX * (CFG.DashSpeed * CFG.WindSpeed) * dt
			PZ = PZ + moveDZ * (CFG.DashSpeed * CFG.WindSpeed) * dt
			dashLeft = dashLeft - dt
			if dashLeft <= 0 then
				isDashing = false
				moveDX = 0
				moveDZ = 0
				dashTimer = 0
			end
		elseif dashTimer >= CFG.DashCooldown then
			local tx, tz, dist = nearestPlayer()
			if tx and dist > CFG.DashMinDist then
				local dx = tx - PX
				local dz = tz - PZ
				local len = math.sqrt(dx * dx + dz * dz)
				moveDX = dx / len
				moveDZ = dz / len
				isDashing = true
				dashLeft = CFG.DashDuration
				dashTimer = 0
			else
				dashTimer = CFG.DashCooldown * 0.8
			end
		end

	elseif mode == "random" then
		randTimer = randTimer + dt
		if randTimer >= randIntv then
			randTimer = 0
			randIntv = CFG.RandDirMin + math.random() * (CFG.RandDirMax - CFG.RandDirMin)
			local fx2 = PX - START_X
			local fz2 = PZ - START_Z
			local dist = math.sqrt(fx2 * fx2 + fz2 * fz2)
			local a
			if dist > CFG.WanderRadius * 0.8 then
				a = math.atan2(-fz2, -fx2) + (math.random() - 0.5) * math.rad(60)
			else
				a = math.random() * math.pi * 2
			end
			moveDX = math.cos(a)
			moveDZ = math.sin(a)
		end
		PX = PX + moveDX * spd * dt
		PZ = PZ + moveDZ * spd * dt
	end
end

-- ── СИСТЕМА ЗАХВАТА ──────────────────────────────────────────
--
-- КЛЮЧЕВОЙ ПРИНЦИП:
-- Объекты НЕ анкорятся. Каждый кадр мы ставим им CFrame вручную.
-- Пока мы ставим CFrame — физика не работает.
-- При выбросе — перестаём ставить CFrame, объект падает естественно.
-- Никаких BodyVelocity, никаких Anchored=true.
-- Выброс = просто убрать из таблицы captured.
-- ────────────────────────────────────────���───────────────────

local captured    = {}   -- массив записей
local capturedSet = {}   -- быстрая проверка [obj]=true
local ejectCD     = {}   -- [player] = tick()
local objEjectCD  = {}   -- [part]   = tick()
local attraced    = {}   -- части с BodyVelocity притяжения

-- ── Притяжение физикой (до захвата) ─────────────────────────

local attrTimer = 0

local function updateAttraction(dt)
	if not spawnDone then return end
	attrTimer = attrTimer + dt
	if attrTimer < 0.2 then return end
	attrTimer = 0

	local ar2 = CFG.AttractionRadius ^ 2
	local pr2 = CFG.PullRadius ^ 2
	local newSet = {}

	for _, child in ipairs(workspace:GetChildren()) do
		if fxSet[child] or child:IsA("Terrain") or charCache[child] then continue end
		local parts = {}
		if child:IsA("BasePart") then
			parts = {child}
		elseif child:IsA("Model") then
			for _, p in ipairs(child:GetDescendants()) do
				if p:IsA("BasePart") then table.insert(parts, p) end
			end
		end
		
		for _, p in ipairs(parts) do
			if capturedSet[p] or capturedSet[p.Parent] then continue end
			if p.Anchored then continue end
			if p.Locked then continue end
			if objEjectCD[p] and tick() < objEjectCD[p] then continue end
			
			local dx = p.Position.X - PX
			local dz = p.Position.Z - PZ
			local d2 = distance2D_unsafe(dx, dz)
			
			if d2 > pr2 and d2 <= ar2 then
				local dist = math.sqrt(d2)
				local force = CFG.MoveSpeed * CFG.WindSpeed * (1 - (dist - CFG.PullRadius) / (CFG.AttractionRadius - CFG.PullRadius))
				force = math.max(3, force)
				local bv = attraced[p]
				if not bv or not bv.Parent then
					bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(2e4, 2e4, 2e4)
					bv.Parent = p
					attraced[p] = bv
				end
				bv.Velocity = Vector3.new(-dx / dist * force, force * 0.1, -dz / dist * force)
				newSet[p] = true
			end
		end
	end

	for p, bv in pairs(attraced) do
		if not newSet[p] then
			if bv and bv.Parent then bv:Destroy() end
			attraced[p] = nil
		end
	end
end

-- ── Захват игрока ────────────────────────────────────────────

local function capturePlayer(pl)
	if capturedSet[pl] then return end
	if ejectCD[pl] and tick() < ejectCD[pl] then return end
	local c = pl.Character
	if not c then return end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChild("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end
	
	hum.PlatformStand = true
	capturedSet[pl] = true
	local dx = hrp.Position.X - PX
	local dz = hrp.Position.Z - PZ
	
	table.insert(captured, {
		type = "player",
		obj = pl,
		angle = math.atan2(dz, dx),
		height = math.max(hrp.Position.Y - PY, 3),
		radius = math.min(math.sqrt(dx * dx + dz * dz), CFG.BaseRadius * 0.9),
		vy = CFG.PlayerLiftSpeed * CFG.WindSpeed + math.random(),
		dmgAcc = 0,
	})
end

-- ── Захват объекта ───────────────────────────────────────────

local function capturePart(part)
	if capturedSet[part] then return end
	if fxSet[part] then return end
	if part.Locked then return end
	if CFG.MaxPartMass > 0 and part:GetMass() > CFG.MaxPartMass then return end
	if objEjectCD[part] and tick() < objEjectCD[part] then return end
	
	-- Убираем BodyVelocity притяжения
	local bv = attraced[part]
	if bv and bv.Parent then bv:Destroy() end
	attraced[part] = nil
	
	-- Запоминаем исходные свойства
	local wasA = part.Anchored
	local wasC = part.CanCollide
	
	-- НЕ анкорим — просто обнуляем скорость
	part.Anchored = false
	part.CanCollide = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	capturedSet[part] = true
	
	local dx = part.Position.X - PX
	local dz = part.Position.Z - PZ
	
	table.insert(captured, {
		type = "part",
		obj = part,
		angle = math.atan2(dz, dx),
		height = math.max(part.Position.Y - PY, 2),
		radius = math.min(math.sqrt(dx * dx + dz * dz), CFG.BaseRadius * 1.1),
		vy = CFG.LiftSpeed * CFG.WindSpeed + math.random() * 2,
		wasA = wasA,
		wasC = wasC,
		spin = 0,
		spinSpd = CFG.SpinSpeed * CFG.WindSpeed * (0.6 + math.random() * 0.8) * (math.random() > 0.5 and 1 or -1),
		tiltX = (math.random() - 0.5) * 0.6,
		tiltZ = (math.random() - 0.5) * 0.6,
	})
end

local function captureModel(model)
	if capturedSet[model] then return end
	if CFG.MaxModelMass > 0 then
		local m = 0
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then m = m + p:GetMass() end
		end
		if m > CFG.MaxModelMass then return end
	end
	
	local anchor = model.PrimaryPart
	if not anchor then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				anchor = p
				break
			end
		end
	end
	if not anchor then return end
	
	local infos = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local bv = attraced[p]
			if bv and bv.Parent then bv:Destroy() end
			attraced[p] = nil
			
			table.insert(infos, {
				part = p,
				wasA = p.Anchored,
				wasC = p.CanCollide,
				off = anchor.CFrame:ToObjectSpace(p.CFrame)
			})
			p.Anchored = false
			p.CanCollide = false
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	
	capturedSet[model] = true
	local dx = anchor.Position.X - PX
	local dz = anchor.Position.Z - PZ
	
	table.insert(captured, {
		type = "model",
		obj = model,
		anchor = anchor,
		infos = infos,
		angle = math.atan2(dz, dx),
		height = math.max(anchor.Position.Y - PY, 2),
		radius = math.min(math.sqrt(dx * dx + dz * dz), CFG.BaseRadius * 1.1),
		vy = CFG.LiftSpeed * CFG.WindSpeed + math.random() * 2,
		spin = 0,
		spinSpd = CFG.SpinSpeed * CFG.WindSpeed * (0.5 + math.random() * 0.5) * (math.random() > 0.5 and 1 or -1),
		tiltX = (math.random() - 0.5) * 0.4,
		tiltZ = (math.random() - 0.5) * 0.4,
	})
end

-- ── Выброс ──────────────────────────────────────────────────

local function releasePlayer(entry)
	capturedSet[entry.obj] = nil
	ejectCD[entry.obj] = tick() + CFG.EjectCooldown
	local c = entry.obj.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChild("Humanoid")
	if hum then hum.PlatformStand = false end
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(
			math.cos(entry.angle) * CFG.EjectForce * CFG.WindSpeed,
			2,
			math.sin(entry.angle) * CFG.EjectForce * CFG.WindSpeed
		)
	end
	
	-- Запасной сброс PlatformStand
	task.delay(0.2, function()
		local c2 = entry.obj.Character
		local hm2 = c2 and c2:FindFirstChild("Humanoid")
		if hm2 then hm2.PlatformStand = false end
	end)
end

local function releasePart(entry)
	capturedSet[entry.obj] = nil
	local p = entry.obj
	if not (p and p.Parent) then return end
	objEjectCD[p] = tick() + 3
	p.CanCollide = entry.wasC
	p.AssemblyLinearVelocity = Vector3.new(
		math.cos(entry.angle) * CFG.EjectForce * CFG.WindSpeed * 1.4,
		CFG.EjectForce * CFG.WindSpeed * 0.25,
		math.sin(entry.angle) * CFG.EjectForce * CFG.WindSpeed * 1.4
	)
	
	-- Если изначально был Anchored — вернём через 5 секунд
	if entry.wasA then
		task.delay(5, function()
			if p and p.Parent and not capturedSet[p] then
				p.Anchored = true
				p.CanCollide = entry.wasC
			end
		end)
	end
end

local function releaseModel(entry)
	capturedSet[entry.obj] = nil
	for _, info in ipairs(entry.infos) do
		local p = info.part
		if not (p and p.Parent) then continue end
		objEjectCD[p] = tick() + 3
		p.CanCollide = info.wasC
		p.AssemblyLinearVelocity = Vector3.new(
			math.cos(entry.angle) * CFG.EjectForce * CFG.WindSpeed * 1.2,
			CFG.EjectForce * CFG.WindSpeed * 0.25,
			math.sin(entry.angle) * CFG.EjectForce * CFG.WindSpeed * 1.2
		)
		if info.wasA then
			task.delay(5, function()
				if p and p.Parent and not capturedSet[p] then
					p.Anchored = true
					p.CanCollide = info.wasC
				end
			end)
		end
	end
end

local function release(entry)
	if entry.type == "player" then
		releasePlayer(entry)
	elseif entry.type == "part" then
		releasePart(entry)
	elseif entry.type == "model" then
		releaseModel(entry)
	end
end

-- ── Обновление захваченных ───────────────────────────────────

local function updateCaptured(entry, dt, elapsed)
	local orb = CFG.OrbitSpeed * CFG.WindSpeed
	entry.angle  = entry.angle  + dt * orb
	entry.height = entry.height + dt * entry.vy
	local tN = math.clamp(entry.height / CFG.Height, 0, 1)
	local tr = CFG.BaseRadius * (1 - tN * 0.65) + CFG.TopRadius * tN
	entry.radius = entry.radius + (tr - entry.radius) * dt * 2

	if entry.height >= CFG.EjectHeight then
		release(entry)
		return true
	end

	local x = PX + math.cos(entry.angle) * entry.radius
	local z = PZ + math.sin(entry.angle) * entry.radius
	local y = PY + entry.height

	if entry.type == "player" then
		local c = entry.obj.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChild("Humanoid")
		if not hrp or not hum then
			capturedSet[entry.obj] = nil
			if hum then hum.PlatformStand = false end
			return true
		end
		hrp.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, entry.angle + math.pi / 2, 0.2 * math.sin(elapsed * 2.5))
		if CFG.PlayerDmgPerSec * CFG.WindSpeed > 0 then
			entry.dmgAcc = entry.dmgAcc + dt * CFG.PlayerDmgPerSec * CFG.WindSpeed
			if entry.dmgAcc >= 1 then
				local d = math.floor(entry.dmgAcc)
				entry.dmgAcc = entry.dmgAcc - d
				hum:TakeDamage(d)
				if hum.Health <= 0 then
					release(entry)
					return true
				end
			end
		end

	elseif entry.type == "part" then
		local p = entry.obj
		if not (p and p.Parent) then return true end
		entry.spin = entry.spin + dt * entry.spinSpd
		p.CFrame = CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(entry.tiltX, entry.spin, entry.tiltZ)

	elseif entry.type == "model" then
		local a = entry.anchor
		if not (entry.obj.Parent and a and a.Parent) then return true end
		entry.spin = entry.spin + dt * entry.spinSpd
		local cf = CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(entry.tiltX, entry.spin, entry.tiltZ)
		a.CFrame = cf
		for _, info in ipairs(entry.infos) do
			local p = info.part
			if p and p.Parent and p ~= a then p.CFrame = cf * info.off end
		end
	end
	return false
end

-- ── Сканирование ─────────────────────────────────────────────

local scanTimer = 0

local function scan()
	if not spawnDone then return end
	local pr2 = CFG.PullRadius ^ 2

	-- Игроки
	for _, pl in ipairs(Players:GetPlayers()) do
		if capturedSet[pl] then continue end
		local c = pl.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChild("Humanoid")
		if not (hrp and hum and hum.Health > 0) then continue end
		local dx = hrp.Position.X - PX
		local dz = hrp.Position.Z - PZ
		if distance2D_unsafe(dx, dz) <= pr2 then capturePlayer(pl) end
	end

	-- Объекты — только прямые потомки workspace
	for _, obj in ipairs(workspace:GetChildren()) do
		if fxSet[obj] then continue end
		if obj:IsA("Terrain") then continue end
		if charCache[obj] then continue end
		if capturedSet[obj] then continue end

		if obj:IsA("BasePart") then
			if objEjectCD[obj] and tick() < objEjectCD[obj] then continue end
			if obj.Locked then continue end
			if obj.Anchored and not CFG.GrabAnchored then continue end
			local dx = obj.Position.X - PX
			local dz = obj.Position.Z - PZ
			if distance2D_unsafe(dx, dz) <= pr2 then capturePart(obj) end

		elseif obj:IsA("Model") and CFG.GrabModels then
			local sumX, sumZ, n = 0, 0, 0
			for _, p in ipairs(obj:GetDescendants()) do
				if p:IsA("BasePart") then
					sumX = sumX + p.Position.X
					sumZ = sumZ + p.Position.Z
					n = n + 1
				end
			end
			if n == 0 then continue end
			local avgX = sumX / n
			local avgZ = sumZ / n
			local dx = avgX - PX
			local dz = avgZ - PZ
			if distance2D_unsafe(dx, dz) <= pr2 then captureModel(obj) end
		end
	end
end

-- ── Очистка при выходе ───────────────────────────────────────

Players.PlayerRemoving:Connect(function(pl)
	ejectCD[pl] = nil
	for i = #captured, 1, -1 do
		local e = captured[i]
		if e.type == "player" and e.obj == pl then
			capturedSet[pl] = nil
			pcall(function()
				local hum = pl.Character and pl.Character:FindFirstChild("Humanoid")
				if hum then hum.PlatformStand = false end
			end)
			table.remove(captured, i)
		end
	end
end)

-- ── Основной цикл ────────────────────────────────────────────

local elapsed = 0
local conn = RunService.Heartbeat:Connect(function(dt)
	elapsed = elapsed + dt
	scanTimer = scanTimer + dt

	if CFG.Duration > 0 and elapsed > CFG.Duration then
		for _, e in ipairs(captured) do pcall(release, e) end
		snd:Stop()
		folder:Destroy()
		return
	end

	updateMovement(dt)
	updateFunnel(dt)
	updateAttraction(dt)

	-- Дым вращается
	if spawnDone then
		local ring = elapsed * CFG.RotSpeed * 0.2
		for _, e in ipairs(smokeEmitters) do
			local a = e.angle + ring
			e.part.CFrame = CFrame.new(PX + math.cos(a) * e.radius, PY + e.baseY, PZ + math.sin(a) * e.radius)
		end
	end

	-- Декоративный мусор
	for _, d in ipairs(debris) do
		d.angle = d.angle + dt * d.speed
		d.height = d.height + dt * d.vy
		if d.height > CFG.Height * 0.8 then d.vy = -math.abs(d.vy) end
		if d.height < 2 then d.vy = math.abs(d.vy) end
		local tn = d.height / CFG.Height
		local r = math.min(d.radius, CFG.DebrisRadius * (1 - tn * 0.6))
		d.part.CFrame = CFrame.new(PX + math.cos(d.angle) * r, PY + d.height, PZ + math.sin(d.angle) * r)
			* CFrame.Angles(elapsed * d.speed * 0.5, d.angle, elapsed * d.speed * 0.3)
	end

	-- Сканирование
	if scanTimer >= 0.25 then
		scanTimer = 0
		scan()
	end

	-- Обновляем захваченных
	for i = #captured, 1, -1 do
		if updateCaptured(captured[i], dt, elapsed) then
			table.remove(captured, i)
		end
	end
end)

folder.AncestryChanged:Connect(function()
	if not folder.Parent then
		conn:Disconnect()
		for _, e in ipairs(captured) do pcall(release, e) end
	end
end)

if CFG.Duration > 0 then
	task.delay(CFG.Duration + 0.1, function() conn:Disconnect() end)
end

print(("[Tornado] OK | Mode=%s | Wind=%.1f | Pull=%d"):format(
	CFG.MoveMode, CFG.WindSpeed, CFG.PullRadius))
