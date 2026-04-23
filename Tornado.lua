-- ============================================================
--  CLOUD TORNADO  —  Roblox Studio  —  ServerScriptService
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- ── CONFIG ──────────────────────────────────────────────────
local CFG = {
	-- Позиция старта
	Position        = Vector3.new(0, 0, 0),

	-- ОБЛАЧНАЯ ФОРМА (вместо воронки)
	CloudHeight     = 100,
	CloudRadius     = 80,
	CloudLayers     = 5,           -- слои облака
	CloudThickness  = 20,          -- толщина облака
	CloudDensity    = 200,         -- кол-во частиц облака
	
	-- Внешний вид
	CloudColor1     = Color3.fromRGB(200, 200, 210),  -- светлый оттенок
	CloudColor2     = Color3.fromRGB(150, 150, 170),  -- средний оттенок
	CloudColor3     = Color3.fromRGB(100, 100, 120),  -- тёмный оттенок
	CloudOpacity    = 0.4,
	
	-- Скорость ветра (множитель мощности)
	WindSpeed       = 1.0,

	-- Захват объектов
	PullRadius      = 35,
	AttractionRadius= 65,
	OrbitSpeed      = 4.0,
	LiftSpeed       = 4.0,
	SpinSpeed       = 3.0,
	EjectHeight     = 50,          -- облако выбрасывает выше
	EjectForce      = 30,
	EjectCooldown   = 5.0,
	GrabAnchored    = true,
	GrabModels      = true,
	MaxPartMass     = 500,
	MaxModelMass    = 2000,

	-- Игрок
	PlayerDmgPerSec = 3,           -- облако менее опасно
	PlayerLiftSpeed = 3.0,

	-- Движение торнадо
	MoveMode        = "nearest",
	MoveSpeed       = 12,
	TrackSmooth     = 0.04,
	DashSpeed       = 50,
	DashDuration    = 0.6,
	DashCooldown    = 4.0,
	DashMinDist     = 10,
	RandDirMin      = 2.0,
	RandDirMax      = 5.0,
	WanderRadius    = 100,

	-- Анимация появления
	SpawnDuration   = 3.5,
	SpawnDropHeight = 50,

	SoundId         = "rbxassetid://9125417792",
	Duration        = 0,
}
-- ────────────────────────────────────────────────────────────

-- Текущая позиция центра
local PX = CFG.Position.X
local PY = CFG.Position.Y
local PZ = CFG.Position.Z
local START_X, START_Z = PX, PZ

-- Папка для всех FX-объектов
local folder = Instance.new("Folder")
folder.Name = "CloudTornadoFX"
folder.Parent = workspace
local fxSet = {}

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

local function cloudPart(size, color, transp)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Transparency = transp
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Parent = folder
	fxSet[p] = true
	return p
end

local function tw(obj, props, t, style, dir)
	return TweenService:Create(obj,
		TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props)
end

local function distance2D_unsafe(dx, dz)
	return dx * dx + dz * dz
end

-- ── Облачная структура ──────────────────────────────────────

local cloudParts = {}
local cloudRotation = 0

-- Создаём облако из сфер
for layer = 1, CFG.CloudLayers do
	local layerRadius = CFG.CloudRadius * (0.6 + (layer / CFG.CloudLayers) * 0.5)
	local layerHeight = PY + (CFG.CloudHeight / CFG.CloudLayers) * layer
	local particlesInLayer = math.floor(CFG.CloudDensity / CFG.CloudLayers)
	
	for i = 1, particlesInLayer do
		local angle = (i / particlesInLayer) * math.pi * 2 + math.random() * 0.5
		local randomR = layerRadius * (0.7 + math.random() * 0.6)
		local randomH = layerHeight + (math.random() - 0.5) * CFG.CloudThickness
		local size = 3 + math.random() * 4
		
		-- Выбираем цвет
		local colors = {CFG.CloudColor1, CFG.CloudColor2, CFG.CloudColor3}
		local color = colors[math.random(1, #colors)]
		
		local part = cloudPart(Vector3.new(size, size, size), color, CFG.CloudOpacity)
		part.CFrame = CFrame.new(
			PX + math.cos(angle) * randomR,
			randomH,
			PZ + math.sin(angle) * randomR
		)
		
		table.insert(cloudParts, {
			part = part,
			baseX = math.cos(angle) * randomR,
			baseZ = math.sin(angle) * randomR,
			baseY = randomH - PY,
			angle = angle,
			radius = randomR,
			wobble = math.random() * math.pi * 2,
			wobbleSpeed = 0.5 + math.random() * 1.0
		})
	end
end

-- ── Звук ────────────────────────────────────────────────────

local snd = Instance.new("Sound")
snd.SoundId = CFG.SoundId
snd.Looped = true
snd.Volume = 0
snd.RollOffMaxDistance = 300
snd.Parent = folder
snd:Play()

-- ── Анимация появления ──────────────────────────────────────

local spawnDone = false

local function playSpawn()
	local D = CFG.SpawnDuration
	tw(snd, {Volume = 1.5}, D * 0.8):Play()
	
	-- Облако поднимается и разворачивается
	for _, cloudInfo in ipairs(cloudParts) do
		local p = cloudInfo.part
		local targetY = PY + cloudInfo.baseY
		local delay = math.random() * D * 0.2
		local duration = D * 0.7
		
		task.delay(delay, function()
			if not folder.Parent then return end
			tw(p, {CFrame = CFrame.new(
				PX + cloudInfo.baseX,
				targetY,
				PZ + cloudInfo.baseZ
			)}, duration):Play()
			tw(p, {Transparency = CFG.CloudOpacity * 0.7}, duration):Play()
		end)
	end
	
	task.delay(D, function()
		spawnDone = true
		print("[Cloud Tornado] Готово!")
	end)
end

playSpawn()

-- ── Обновление облака (волнистое движение) ──────────────────

local function updateCloud(dt)
	cloudRotation = cloudRotation + dt * 0.3
	
	for _, cloudInfo in ipairs(cloudParts) do
		-- Волнистое движение
		cloudInfo.wobble = cloudInfo.wobble + dt * cloudInfo.wobbleSpeed
		local wobbleX = math.sin(cloudInfo.wobble) * 2
		local wobbleZ = math.cos(cloudInfo.wobble) * 2
		local wobbleY = math.sin(cloudInfo.wobble * 0.5) * 1
		
		-- Вращение облака
		local rotatedAngle = cloudInfo.angle + cloudRotation
		local x = PX + math.cos(rotatedAngle) * cloudInfo.radius + wobbleX
		local z = PZ + math.sin(rotatedAngle) * cloudInfo.radius + wobbleZ
		local y = PY + cloudInfo.baseY + wobbleY
		
		cloudInfo.part.CFrame = CFrame.new(x, y, z)
	end
end

-- ── Движение облака ─────────────────────────────────────────

local moveDX, moveDZ = 0, 0
local dashTimer = 0
local isDashing = false
local dashLeft = 0
local randTimer = 0
local randIntv = CFG.RandDirMin

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

local captured    = {}
local capturedSet = {}
local ejectCD     = {}
local objEjectCD  = {}
local attraced    = {}

-- ── Притяжение физикой ──────────────────────────────────────

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

-- ── Захват игрока ───────────────────────────────────────────

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
		radius = math.min(math.sqrt(dx * dx + dz * dz), CFG.CloudRadius * 0.8),
		vy = CFG.PlayerLiftSpeed * CFG.WindSpeed + math.random(),
		dmgAcc = 0,
	})
end

-- ── Захват объекта ──────────────────────────────────────────

local function capturePart(part)
	if capturedSet[part] then return end
	if fxSet[part] then return end
	if part.Locked then return end
	if CFG.MaxPartMass > 0 and part:GetMass() > CFG.MaxPartMass then return end
	if objEjectCD[part] and tick() < objEjectCD[part] then return end
	
	local bv = attraced[part]
	if bv and bv.Parent then bv:Destroy() end
	attraced[part] = nil
	
	local wasA = part.Anchored
	local wasC = part.CanCollide
	
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
		radius = math.min(math.sqrt(dx * dx + dz * dz), CFG.CloudRadius * 1.0),
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
		radius = math.min(math.sqrt(dx * dx + dz * dz), CFG.CloudRadius * 1.0),
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
			3,
			math.sin(entry.angle) * CFG.EjectForce * CFG.WindSpeed
		)
	end
	
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
		CFG.EjectForce * CFG.WindSpeed * 0.3,
		math.sin(entry.angle) * CFG.EjectForce * CFG.WindSpeed * 1.4
	)
	
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
			CFG.EjectForce * CFG.WindSpeed * 0.3,
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

-- ── Обновление захваченных ──────────────────────────────────

local function updateCaptured(entry, dt, elapsed)
	local orb = CFG.OrbitSpeed * CFG.WindSpeed
	entry.angle  = entry.angle  + dt * orb
	entry.height = entry.height + dt * entry.vy
	local tN = math.clamp(entry.height / CFG.CloudHeight, 0, 1)
	local tr = CFG.CloudRadius * (1 - tN * 0.5) + (CFG.CloudRadius * 0.3) * tN
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
		hrp.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, entry.angle + math.pi / 2, 0.1 * math.sin(elapsed * 2.5))
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

-- ── Сканирование ────────────────────────────────────────────

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

	-- Объекты
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

-- ── Очистка при выходе ──────────────────────────────────────

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

-- ── Основной цикл ───────────────────────────────────────────

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
	updateCloud(dt)
	updateAttraction(dt)

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

print(("[Cloud Tornado] OK | Mode=%s | Wind=%.1f | Pull=%d | Density=%d"):format(
	CFG.MoveMode, CFG.WindSpeed, CFG.PullRadius, CFG.CloudDensity))
