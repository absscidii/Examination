--[[
	Script v8 = v7 plus:
	* FUTURISTIC DARK TEAM SELECTOR: Cybernetic modal button opening team selection for RAID and MENLO
	  with full lore descriptions, auto-reset, and client-sided team state tracking.
	* RE-CALIBRATED THREAT SENSITIVITY: Adjusted threat tiers and enemy scaling so weak mobs no longer hit EXTREME.
	* BOOSTED STAMINA: Higher max stamina limits and instantaneous recovery.
	* ANIMATION OVERLAP FIX: Hardened zero-delay frame-1 silencing in Kit.swap and RenderStepped polling.
	* VISOR & CRT OVERHAUL: Enhanced retro aesthetics, phosphor glow, and tactical readouts.
	* RAPID-FIRE ABILITY STOP: Stops the replacement animation if triggered again in under 0.4 seconds.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local env = (getgenv and getgenv()) or _G
local Shared = env.Shared or rawget(_G, "Shared") or {}
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------- cleanup of previous run
local GUI_NAMES = {
	"ESPToggleGui", "ViralFistsGUI", "CombatControlsGui", "VictimAnimGui",
	"SinSwapGui", "ExecModeGui", "LayoutEditorGui", "DevicePromptGui", "ScriptStatusGui", "ScriptLogGui", "VisorToggleGui", "RifVisorGui", "MenloToggleGui", "MenloVisorGui", "HideHudGui", "TeamSelectGui",
}

if type(env.__ScriptCleanup) == "function" then
	pcall(env.__ScriptCleanup)
end

local statusLines, statusOrder, anyFailed = {}, {}, false
local statusGui = Instance.new("ScreenGui")
statusGui.Name = "ScriptStatusGui"
statusGui.ResetOnSpawn = false
statusGui.IgnoreGuiInset = true
statusGui.DisplayOrder = 2000
statusGui.Parent = PlayerGui
local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
statusLabel.BackgroundTransparency = 0.25
statusLabel.BorderSizePixel = 0
statusLabel.Position = UDim2.new(0, 8, 0, 8)
statusLabel.Size = UDim2.new(0, 420, 0, 130)
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 12
statusLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextWrapped = true
statusLabel.Text = "script v8: starting..."
statusGui.Enabled = false
statusLabel.Parent = statusGui

local SECTION_NAMES = {
	["1"] = "stamina", ["2"] = "esp", ["3"] = "fire button", ["4"] = "sprint/swap",
	["5"] = "victim anim", ["6"] = "sin", ["6b"] = "rif visor", ["6c"] = "menlo visor", ["6d"] = "hide game hud", ["7"] = "layout + device prompt", ["8"] = "team selector",
}

local function renderStatus()
	local out = { "script v8" }
	for _, k in ipairs(statusOrder) do table.insert(out, statusLines[k]) end
	statusLabel.Text = table.concat(out, "\n")
	local _, n = string.gsub(statusLabel.Text, "\n", "")
	statusLabel.Size = UDim2.new(0, 420, 0, 18 + 15 * (n + 1) + (anyFailed and 90 or 0))
end

local function runSection(name, fn)
	local label = SECTION_NAMES[name] or name
	table.insert(statusOrder, name)
	statusLines[name] = name .. " " .. label .. ": running"
	renderStatus()
	local ok, err = xpcall(fn, function(e) return tostring(e) .. " | " .. tostring(debug and debug.traceback and debug.traceback("", 2) or "") end)
	if ok then
		statusLines[name] = name .. " " .. label .. ": ok"
	else
		anyFailed = true
		statusGui.Enabled = true
		task.delay(8, function() if statusGui.Parent then statusGui.Enabled = false end end)
		statusLines[name] = name .. " " .. label .. ": FAILED " .. tostring(err)
		warn("[Script] section " .. name .. " (" .. label .. ") failed: " .. tostring(err))
	end
	renderStatus()
end

task.delay(12, function()
	if not anyFailed and statusGui.Parent then statusGui:Destroy() end
end)

local jobs = {}
local function bind(conn) table.insert(jobs, conn) return conn end
local function onCleanup(fn) table.insert(jobs, fn) return fn end

env.__ScriptCleanup = function()
	for _, j in ipairs(jobs) do
		if typeof(j) == "RBXScriptConnection" then
			pcall(function() j:Disconnect() end)
		elseif type(j) == "function" then
			pcall(j)
		end
	end
	table.clear(jobs)
	for _, n in ipairs(GUI_NAMES) do
		local o = PlayerGui:FindFirstChild(n)
		if o then o:Destroy() end
	end
end

for _, n in ipairs(GUI_NAMES) do
	for _, o in ipairs(PlayerGui:GetChildren()) do
		if o.Name == n and o ~= statusGui then o:Destroy() end
	end
end

---------------------------------------------------------------- helpers
local function tween(obj, time, props)
	local t = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local GREY_TEXT = Color3.fromRGB(130, 130, 150)

local function makeToggleCard(guiName, cardName, titleText, titleSize, accent, yOffset, onToggle)
	local OFF_BG, CARD_BG, STROKE_OFF = Color3.fromRGB(70, 70, 76), Color3.fromRGB(8, 8, 10), Color3.fromRGB(235, 235, 240)

	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.Parent = PlayerGui

	local card = Instance.new("TextButton")
	card.Name = cardName
	card.Size = UDim2.new(0, 156, 0, 46)
	card.Position = UDim2.new(0.02, 0, 0.45, yOffset)
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 0.3
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_OFF
	stroke.Thickness = 1
	stroke.Transparency = 0.55
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	local scale = Instance.new("UIScale")
	scale.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0, 90, 0, 18)
	title.Position = UDim2.new(0, 20, 0, 7)
	title.Font = Enum.Font.GothamMedium
	title.Text = titleText
	title.TextSize = titleSize
	title.TextColor3 = Color3.fromRGB(240, 240, 248)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(0, 70, 0, 14)
	status.Position = UDim2.new(0, 20, 0, 25)
	status.Font = Enum.Font.GothamMedium
	status.Text = "DISABLED"
	status.TextSize = 10
	status.TextColor3 = GREY_TEXT
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = card

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Size = UDim2.new(0, 38, 0, 20)
	track.Position = UDim2.new(1, -16, 0.5, 0)
	track.BackgroundColor3 = OFF_BG
	track.BorderSizePixel = 0
	track.Parent = card
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.Position = UDim2.new(0, 3, 0.5, -7)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local function setVisual(on)
		tween(track, 0.2, { BackgroundColor3 = on and accent or OFF_BG })
		tween(knob, 0.2, { Position = on and UDim2.new(0, 21, 0.5, -7) or UDim2.new(0, 3, 0.5, -7) })
		tween(stroke, 0.2, { Color = on and accent or STROKE_OFF, Transparency = on and 0.05 or 0.55 })
		status.Text = on and "ACTIVE" or "DISABLED"
		tween(status, 0.2, { TextColor3 = on and accent or GREY_TEXT })
	end

	card.MouseEnter:Connect(function() tween(scale, 0.12, { Scale = 1.05 }) end)
	card.MouseLeave:Connect(function() tween(scale, 0.12, { Scale = 1 }) end)
	card.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = 0.95 }) end)
	card.MouseButton1Up:Connect(function() tween(scale, 0.1, { Scale = 1.05 }) end)
	card.MouseButton1Click:Connect(function()
		setVisual(onToggle())
	end)

	return setVisual
end

local function makeCycleCard(guiName, cardName, titleText, modes, startIndex, yOffset, onChange)
	local CARD_BG, STROKE_OFF = Color3.fromRGB(8, 8, 10), Color3.fromRGB(235, 235, 240)
	local index = startIndex or 1

	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.Parent = PlayerGui

	local card = Instance.new("TextButton")
	card.Name = cardName
	card.Size = UDim2.new(0, 156, 0, 46)
	card.Position = UDim2.new(0.02, 0, 0.45, yOffset)
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 0.3
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_OFF
	stroke.Thickness = 1
	stroke.Transparency = 0.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	local scale = Instance.new("UIScale")
	scale.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0, 90, 0, 18)
	title.Position = UDim2.new(0, 20, 0, 7)
	title.Font = Enum.Font.GothamMedium
	title.Text = titleText
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(240, 240, 248)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(0, 130, 0, 14)
	status.Position = UDim2.new(0, 20, 0, 25)
	status.Font = Enum.Font.GothamMedium
	status.TextSize = 10
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = card

	local pips = {}
	for i = 1, #modes do
		local pip = Instance.new("Frame")
		pip.AnchorPoint = Vector2.new(1, 0.5)
		pip.Size = UDim2.fromOffset(8, 8)
		pip.Position = UDim2.new(1, -18 - (#modes - i) * 14, 0.5, 0)
		pip.BackgroundColor3 = Color3.fromRGB(58, 58, 70)
		pip.BorderSizePixel = 0
		pip.Parent = card
		Instance.new("UICorner", pip).CornerRadius = UDim.new(1, 0)
		pips[i] = pip
	end

	local function render()
		local m = modes[index]
		status.Text = m.label
		tween(status, 0.2, { TextColor3 = m.color })
		tween(stroke, 0.2, { Color = m.color })
		for i, pip in ipairs(pips) do
			tween(pip, 0.2, { BackgroundColor3 = (i == index) and m.color or Color3.fromRGB(58, 58, 70) })
		end
	end

	card.MouseEnter:Connect(function() tween(scale, 0.12, { Scale = 1.05 }) end)
	card.MouseLeave:Connect(function() tween(scale, 0.12, { Scale = 1 }) end)
	card.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = 0.95 }) end)
	card.MouseButton1Up:Connect(function() tween(scale, 0.1, { Scale = 1.05 }) end)
	card.MouseButton1Click:Connect(function()
		index = index % #modes + 1
		render()
		if onChange then onChange(index) end
	end)

	render()
	return function() return index end
end

---------------------------------------------------------------- animation kit
local Kit = {}
local trackCache = setmetatable({}, { __mode = "k" })
local idCache    = setmetatable({}, { __mode = "k" })
local setCache   = setmetatable({}, { __mode = "k" })
local nameCache  = setmetatable({}, { __mode = "k" })

local LOG_ENABLED = false
env.__ScriptRun = (env.__ScriptRun or 0) + 1
local RUN_ID = env.__ScriptRun
local logLines = {}
local logLabel

function Kit.log(msg)
	if not LOG_ENABLED then return end
	local line = string.format("r%d %.2f %s", RUN_ID, os.clock() % 1000, msg)
	table.insert(logLines, line)
	if #logLines > 15 then table.remove(logLines, 1) end
end

function Kit.describe(track)
	local ok, text = pcall(function()
		local id = nameCache[track] or (function()
			local a = track.Animation
			return a and string.match(tostring(a.AnimationId), "%d+") or "?"
		end)()
		return string.format("%s %s len=%.2f w=%.2f", id, track.Priority.Name, track.Length, track.WeightTarget)
	end)
	return ok and text or "?"
end

function Kit.digits(id)
	return string.match(tostring(id or ""), "%d+")
end

function Kit.idOf(track)
	local id = idCache[track]
	if id == nil then
		local anim = track.Animation
		local s = anim and tostring(anim.AnimationId) or ""
		id = string.match(s, "id=(%d+)") or string.match(s, "%d+") or false
		idCache[track] = id
	end
	return id or nil
end

function Kit.matches(track, ids)
	local set = setCache[ids]
	if not set then
		set = {}
		for _, target in ipairs(ids) do
			local d = Kit.digits(target)
			if d then set[d] = true end
		end
		setCache[ids] = set
	end
	local id = Kit.idOf(track)
	return id ~= nil and set[id] == true
end

function Kit.get(animator, id)
	local byId = trackCache[animator]
	if not byId then
		byId = {}
		trackCache[animator] = byId
	end
	if byId[id] then return byId[id] end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	anim:Destroy()
	if not ok or not track then return nil end
	byId[id] = track
	nameCache[track] = Kit.digits(id)
	return track
end

function Kit.warm(animator, id)
	task.spawn(function()
		local t = Kit.get(animator, id)
		if not t then return end
		local t0 = os.clock()
		while t.Length <= 0 and os.clock() - t0 < 8 do task.wait() end
		if t.Length <= 0 then return end
		if t.IsPlaying then return end
		t:Play(0, 0.001, 1)
		task.wait()
		if t.IsPlaying and t.WeightTarget <= 0.01 then t:Stop(0) end
	end)
end

function Kit.nearestVictim(myChar, range)
	local root = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local pool
	local folder = Workspace:FindFirstChild("Characters")
	if folder then
		pool = folder:GetChildren()
	else
		pool = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(pool, p.Character) end
		end
	end

	local best, bestDist = nil, range
	for _, c in ipairs(pool) do
		if c ~= myChar and c:IsA("Model") then
			local hrp = c:FindFirstChild("HumanoidRootPart")
			local hum = c:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local d = (hrp.Position - root.Position).Magnitude
				if d <= bestDist then best, bestDist = c, d end
			end
		end
	end
	return best
end

local demoted = setmetatable({}, { __mode = "k" })

function Kit.demote(track, owner)
	local info = demoted[track]
	if not info then
		info = { priority = track.Priority, owners = {} }
		demoted[track] = info
		pcall(function() track.Priority = Enum.AnimationPriority.Idle end)
	end
	info.owners[owner] = true
end

Kit.watching = setmetatable({}, { __mode = "k" })

function Kit.restore(owner)
	for track, info in pairs(demoted) do
		if info.owners[owner] then
			info.owners[owner] = nil
			if next(info.owners) == nil then
				pcall(function() track.Priority = info.priority end)
				demoted[track] = nil
			end
		end
	end
	for orig, w in pairs(Kit.watching) do
		if w.opt.owner == owner then Kit.watching[orig] = nil end
	end
end

function Kit.silence(track, owner)
	Kit.demote(track, owner)
	track:AdjustWeight(0, 0)
end

Kit.live = {}
Kit.lastStart = -1e9
Kit.lastEnd = -1e9
Kit.REFRACTORY = 0.8
Kit.HIT_LOCKOUT = 1.0

function Kit.claim(track, kind)
	for other in pairs(Kit.live) do
		if other ~= track and other.IsPlaying then other:Stop(0) end
	end
	Kit.live[track] = { t = os.clock(), kind = kind or "move" }
	Kit.lastStart = os.clock()
	track.Stopped:Once(function()
		if not track.IsPlaying then
			Kit.lastEnd = os.clock()
		end
	end)
end

function Kit.execPlaying()
	for track, info in pairs(Kit.live) do
		if info.kind == "exec" and track.IsPlaying then return true end
	end
	return false
end

function Kit.enforce()
	local newest, newestT, count = nil, -1e9, 0
	for track, info in pairs(Kit.live) do
		if track.IsPlaying then
			count += 1
			if info.t > newestT then newest, newestT = track, info.t end
		else
			Kit.live[track] = nil
		end
	end
	if count > 1 then
		for track in pairs(Kit.live) do
			if track ~= newest and track.IsPlaying then track:Stop(0) end
		end
	end
end

function Kit.tick()
	Kit.enforce()
	local now = os.clock()
	for orig, w in pairs(Kit.watching) do
		local elapsed = now - w.t
		local expected = (w.rep.Length - w.start) / math.max(w.speed, 0.01)
		if elapsed > 0.2 or elapsed > expected * 0.5 or not orig.IsPlaying then
			Kit.watching[orig] = nil
		elseif not w.rep.IsPlaying and w.tries < 1 then
			w.tries += 1
			w.rep:Play(0, w.opt.weight or 1, w.speed)
			w.rep.TimePosition = w.start
		end
	end
end

bind(RunService.RenderStepped:Connect(function() Kit.tick() end))

function Kit.swap(animator, original, repId, opt, lock)
	local now = os.clock()
	local window = 0.4 -- 0.4 second rapid-fire stop window

	-- If played again in under 0.4 seconds, stop the active replacement animation
	if lock.startedAt and (now - lock.startedAt) < window then
		if lock.rep and lock.rep.IsPlaying then
			lock.rep:Stop(0)
		end
		lock.rep = nil
		lock.startedAt = nil
		lock.origs = nil
		Kit.silence(original, opt.owner)
		return nil, "stopped"
	end

	local busy = nil
	if Kit.execPlaying() then busy = "execution playing"
	elseif lock.rep and lock.rep.IsPlaying then busy = "rep playing"
	elseif now - Kit.lastStart < Kit.HIT_LOCKOUT then busy = "other started"
	elseif now - Kit.lastEnd < Kit.REFRACTORY then busy = "just ended"
	end
	if not busy and lock.origs and now - (lock.startedAt or -1e9) < 1.5 then
		for o in pairs(lock.origs) do
			if o ~= original and o.IsPlaying then busy = "game move still running" break end
		end
	end
	if busy then
		Kit.silence(original, opt.owner)
		return nil, "lock"
	end

	local rep = Kit.get(animator, repId)
	if not rep or rep.Length <= 0 then
		return nil, "unloaded"
	end

	Kit.silence(original, opt.owner)

	rep.Priority = Enum.AnimationPriority.Action4
	rep.Looped = opt.loop or false
	if rep.IsPlaying then rep:Stop(0) end
	Kit.claim(rep, "move")

	local len = rep.Length
	local start = opt.start or 0
	local speed = opt.speed or 1
	start = math.clamp(start, 0, math.max(len - 0.05, 0))

	rep:Play(opt.fadeIn or 0, opt.weight or 1, speed)
	rep.TimePosition = start

	lock.rep = rep
	lock.startedAt = now
	lock.origs = { [original] = true }

	local trim = opt.trimEnd and opt.trimEnd[Kit.digits(repId)]
	lock.stopToken = nil
	if trim and trim > 0 then
		local playFor = (len - start - trim) / math.max(speed, 0.01)
		if playFor > 0.05 then
			local token = {}
			lock.stopToken = token
			task.delay(playFor, function()
				if lock.stopToken == token and lock.rep == rep and rep.IsPlaying then
					rep:Stop(opt.trimFade or 0)
				end
			end)
		end
	end
	if opt.owner ~= "sin" then
		Kit.watching[original] = { rep = rep, t = now, start = start, speed = speed, opt = opt, tries = 0 }
	else
		Kit.watching[original] = nil
	end
	return rep
end

local victimLast = setmetatable({}, { __mode = "k" })
local victimState = setmetatable({}, { __mode = "k" })
local victimActive = {}

local function victimFinish(state, token)
	if state.token ~= token or state.done then return end
	state.done = true
	victimActive[state] = nil
	for _, c in ipairs(state.conns) do c:Disconnect() end
	table.clear(state.conns)
	for t, info in pairs(state.muted) do
		if t.IsPlaying then
			if info.loop then t:AdjustWeight(info.w, 0.1) else t:Stop(0.1) end
		end
	end
	table.clear(state.muted)
end
onCleanup(function()
	for st in pairs(victimActive) do victimFinish(st, st.token) end
end)

function Kit.playOnVictim(victim, animId, opt)
	opt = opt or {}
	local hum = victim:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end

	local track = Kit.get(animator, animId)
	if not track then return end

	local fade = opt.fadeIn or 0.05

	if opt.dedupe then
		local last = victimLast[animator]
		if last and last.track.IsPlaying then
			if last.track == track and os.clock() - last.t < 0.3 then return end
			if last.track ~= track then last.track:Stop(0) end
		end
		victimLast[animator] = { track = track, t = os.clock() }
	end

	local state = victimState[animator]
	if state and not state.done then
		for _, c in ipairs(state.conns) do c:Disconnect() end
		table.clear(state.conns)
	else
		state = { muted = {}, conns = {}, done = false }
		victimState[animator] = state
	end
	local token = {}
	state.token = token
	state.t0 = os.clock()
	victimActive[state] = true

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	if track.IsPlaying then track:Stop(0) end

	local function muteOthers(f)
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			if t ~= track and t.WeightTarget > 0 then
				if state.muted[t] == nil then state.muted[t] = { w = t.WeightTarget, loop = t.Looped } end
				t:AdjustWeight(0, f)
			end
		end
	end
	muteOthers(fade)

	track:Play(fade, opt.weight or 1, opt.speed or 1)

	table.insert(state.conns, animator.AnimationPlayed:Connect(function()
		if state.token == token then muteOthers(0) end
	end))
	table.insert(state.conns, RunService.RenderStepped:Connect(function()
		if state.token ~= token then return end
		muteOthers(0)
		if not track.IsPlaying and os.clock() - state.t0 > 0.5 then victimFinish(state, token) end
	end))
	track.Stopped:Once(function()
		if state.token ~= token or track.IsPlaying then return end
		victimFinish(state, token)
	end)
end

---------------------------------------------------------------- 1) stamina (boosted & infinite)
runSection("1", function()
	local cachedStateObj = nil
	local cachedBar = nil

	local function isEnabled()
		local Toggles = env.Toggles or rawget(_G, "Toggles")
		local toggle = Toggles and Toggles.inf_stamina_toggle
		if toggle == nil then return true end
		return toggle.Value == true
	end

	local function getBar()
		if cachedBar and cachedBar:IsDescendantOf(PlayerGui) then return cachedBar end
		local gui = PlayerGui:FindFirstChild("Gui")
		local statusFrame = gui and gui:FindFirstChild("statusFrame")
		local stamina = statusFrame and statusFrame:FindFirstChild("stamina")
		cachedBar = stamina and stamina:FindFirstChild("bar") or nil
		return cachedBar
	end

	local function applyStamina()
		if not isEnabled() then return end

		local char = LocalPlayer.Character
		if not char then return end

		if not cachedStateObj then
			local clientHandler = char:FindFirstChild("ClientHandler") or char:FindFirstChild("Client")
			local stateMod = clientHandler and clientHandler:FindFirstChild("State")
			if stateMod then
				pcall(function() cachedStateObj = require(stateMod) end)
			end
		end

		if cachedStateObj and type(cachedStateObj.stamina) == "table" then
			cachedStateObj.stamina.max = 1000
			cachedStateObj.stamina.current = 1000
		end

		local bar = getBar()
		if bar then bar.Size = UDim2.new(1, 0, 1, 0) end
	end

	bind(LocalPlayer.CharacterAdded:Connect(function()
		cachedStateObj = nil
		cachedBar = nil
	end))
	bind(RunService.Heartbeat:Connect(applyStamina))
	bind(RunService.RenderStepped:Connect(applyStamina))
end)

---------------------------------------------------------------- 2) ESP
runSection("2", function()
	local CharactersFolder = Workspace:FindFirstChild("Characters") or Workspace:WaitForChild("Characters", 5)

	local espEnabled = false
	local activeESP = {}

	local COLOR_PLAYER = Color3.fromRGB(0, 255, 100)
	local COLOR_OTHER  = Color3.fromRGB(255, 50, 50)
	local MAX_TEXT_DISTANCE = 125

	local function isPlayerCharacter(char)
		return Players:GetPlayerFromCharacter(char) ~= nil or Players:FindFirstChild(char.Name) ~= nil
	end

	local function removeESP(char)
		local data = activeESP[char]
		if not data then return end
		for _, conn in ipairs(data.Connections) do conn:Disconnect() end
		if data.Highlight then data.Highlight:Destroy() end
		if data.Billboard then data.Billboard:Destroy() end
		activeESP[char] = nil
	end

	local function createESP(char)
		if not char:IsA("Model") then return end
		if char == LocalPlayer.Character or char.Name == LocalPlayer.Name then return end
		if activeESP[char] then return end

		task.spawn(function()
			local humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 3)
			local head = char:FindFirstChild("Head") or char:WaitForChild("Head", 3) or char.PrimaryPart

			if not humanoid or not head or not espEnabled or activeESP[char] then return end

			local mainColor = isPlayerCharacter(char) and COLOR_PLAYER or COLOR_OTHER

			local highlight = Instance.new("Highlight")
			highlight.Name = "ESPHighlight"
			highlight.FillColor = mainColor
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.FillTransparency = 0.5
			highlight.OutlineTransparency = 0.2
			highlight.Adornee = char
			highlight.Parent = char

			local billboard = Instance.new("BillboardGui")
			billboard.Name = "ESPBillboard"
			billboard.Size = UDim2.new(0, 180, 0, 40)
			billboard.StudsOffset = Vector3.new(0, 3.5, 0)
			billboard.AlwaysOnTop = true
			billboard.MaxDistance = MAX_TEXT_DISTANCE
			billboard.Adornee = head

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.TextColor3 = mainColor
			label.TextStrokeTransparency = 0.2
			label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			label.Font = Enum.Font.SourceSansBold
			label.TextSize = 14
			label.Parent = billboard

			local function updateHealthDisplay()
				local hp = math.floor(math.max(0, humanoid.Health))
				local maxHp = math.floor(humanoid.MaxHealth)
				label.Text = string.format("%s\n[%d / %d HP]", char.Name, hp, maxHp)
			end

			updateHealthDisplay()
			billboard.Parent = char

			local connections = {
				humanoid.HealthChanged:Connect(updateHealthDisplay),
				humanoid.Died:Connect(function() removeESP(char) end),
				char.AncestryChanged:Connect(function(_, newParent)
					if not newParent then removeESP(char) end
				end),
			}

			activeESP[char] = { Highlight = highlight, Billboard = billboard, Connections = connections }
		end)
	end

	local function disableAllESP()
		for char in pairs(activeESP) do removeESP(char) end
	end

	local function listCharacters()
		if CharactersFolder then return CharactersFolder:GetChildren() end
		local out = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character then table.insert(out, p.Character) end
		end
		return out
	end

	if CharactersFolder then
		bind(CharactersFolder.ChildAdded:Connect(function(child)
			if espEnabled then createESP(child) end
		end))
		bind(CharactersFolder.ChildRemoved:Connect(removeESP))
	else
		local function watchPlayer(p)
			if p == LocalPlayer then return end
			bind(p.CharacterAdded:Connect(function(c)
				if espEnabled then createESP(c) end
			end))
			bind(p.CharacterRemoving:Connect(removeESP))
		end
		for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
		bind(Players.PlayerAdded:Connect(watchPlayer))
	end
	onCleanup(disableAllESP)

	for _, c in ipairs(listCharacters()) do
		for _, n in ipairs({ "ESPHighlight", "ESPBillboard" }) do
			local o = c:FindFirstChild(n)
			if o then o:Destroy() end
		end
	end

	makeToggleCard("ESPToggleGui", "ToggleButton", "ESP", 15, Color3.fromRGB(46, 213, 115), 0, function()
		espEnabled = not espEnabled
		if espEnabled then
			for _, child in ipairs(listCharacters()) do createESP(child) end
		else
			disableAllESP()
		end
		return espEnabled
	end)
end)

---------------------------------------------------------------- 3) fire button
runSection("3", function()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ViralFistsGUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 220, 0, 92)
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(0.98, 0, 0.25, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 27)
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(255, 255, 255)
	frameStroke.Thickness = 2
	frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frameStroke.Parent = frame

	local strokeGradient = Instance.new("UIGradient")
	strokeGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(130, 80, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 130)),
	})
	strokeGradient.Rotation = 45
	strokeGradient.Parent = frameStroke

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -28, 0, 14)
	title.Position = UDim2.new(0, 14, 0, 10)
	title.Font = Enum.Font.GothamBold
	title.Text = "VIRAL FISTS"
	title.TextSize = 11
	title.TextColor3 = Color3.fromRGB(165, 160, 195)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 192, 0, 46)
	btn.Position = UDim2.new(0, 14, 0, 32)
	btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = "FIRE  [ F ]"
	btn.TextSize = 16
	btn.Font = Enum.Font.GothamBlack
	btn.Parent = frame
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

	local btnGradient = Instance.new("UIGradient")
	btnGradient.Color = strokeGradient.Color
	btnGradient.Rotation = 0
	btnGradient.Parent = btn

	local btnScale = Instance.new("UIScale")
	btnScale.Parent = btn

	local flash = Instance.new("Frame")
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 2
	flash.Parent = btn
	Instance.new("UICorner", flash).CornerRadius = UDim.new(0, 10)

	btn.MouseEnter:Connect(function()
		tween(btnScale, 0.12, { Scale = 1.04 })
		tween(btnGradient, 0.3, { Rotation = 25 })
	end)
	btn.MouseLeave:Connect(function()
		tween(btnScale, 0.12, { Scale = 1 })
		tween(btnGradient, 0.3, { Rotation = 0 })
	end)
	btn.MouseButton1Down:Connect(function() tween(btnScale, 0.08, { Scale = 0.95 }) end)
	btn.MouseButton1Up:Connect(function() tween(btnScale, 0.1, { Scale = 1.04 }) end)

	local FIRE_DEBOUNCE = 0.12
	local lastFire = 0
	local fireEvent = nil

	btn.MouseButton1Click:Connect(function()
		local now = os.clock()
		if now - lastFire < FIRE_DEBOUNCE then return end
		lastFire = now

		flash.BackgroundTransparency = 0.6
		tween(flash, 0.3, { BackgroundTransparency = 1 })

		if not (fireEvent and fireEvent.Parent) then
			fireEvent = ReplicatedStorage:FindFirstChild("ViralFistsKeyPressEvent")
		end
		if fireEvent then fireEvent:FireServer("F") end
	end)
end)

---------------------------------------------------------------- 4) sprint + SWAP ANIM
runSection("4", function()
	local NORMAL_SPEED = 16
	local SPRINT_SPEED = 24
	local SPRINT_START_SPEED = 19
	local SPRINT_STOP_SPEED = 12
	local SPRINT_GRACE = 0.3

	local SPRINT_ANIMATION_ID = "rbxassetid://111821553591135"

	local TARGET_IDS = { "103116263598605", "124609826792133" }
	local REPLACEMENT_ID = "rbxassetid://112634711476303"

	local SWAP_TUNING = {
		speed = 1.3, start = 0.15, fadeIn = 0.05, weight = 1, loop = false, cooldown = 0.4, owner = "swap",
	}

	local character, humanoid, animator, rootPart
	local sprintTrack
	local isSprinting, isAnimSwapped = false, false
	local lastSprintGood = 0

	local muted = {}
	local handled = setmetatable({}, { __mode = "k" })
	local lock = {}
	local connections, persistent = {}, {}

	local oldGui = PlayerGui:FindFirstChild("CombatControlsGui")
	if oldGui then oldGui:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatControlsGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui

	local BTN_SIZE = 76
	local BG_OFF     = Color3.fromRGB(20, 20, 27)
	local STROKE_OFF = Color3.fromRGB(70, 70, 88)
	local DOT_OFF    = Color3.fromRGB(80, 80, 95)
	local ICON_OFF   = Color3.fromRGB(190, 190, 210)

	local function makeButton(name, text, position, imageId, accent, bgOn)
		local glow = Instance.new("Frame")
		glow.Name = name .. "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Size = UDim2.fromOffset(BTN_SIZE + 18, BTN_SIZE + 18)
		glow.Position = UDim2.new(
			position.X.Scale, position.X.Offset + BTN_SIZE / 2,
			position.Y.Scale, position.Y.Offset + BTN_SIZE / 2
		)
		glow.BackgroundColor3 = accent
		glow.BackgroundTransparency = 1
		glow.BorderSizePixel = 0
		glow.Parent = gui
		Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)

		local button = Instance.new("ImageButton")
		button.Name = name
		button.Size = UDim2.fromOffset(BTN_SIZE, BTN_SIZE)
		button.Position = position
		button.BackgroundColor3 = BG_OFF
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Image = ""
		button.Parent = gui
		Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = STROKE_OFF
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.Size = UDim2.fromOffset(36, 36)
		icon.BackgroundTransparency = 1
		icon.Image = imageId
		icon.ImageColor3 = ICON_OFF
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = button

		local dot = Instance.new("Frame")
		dot.Name = "StatusDot"
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -2, 0, 2)
		dot.Size = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = DOT_OFF
		dot.BorderSizePixel = 0
		dot.ZIndex = 3
		dot.Parent = button
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

		local dotStroke = Instance.new("UIStroke")
		dotStroke.Thickness = 2
		dotStroke.Color = BG_OFF
		dotStroke.Parent = dot

		local pill = Instance.new("TextLabel")
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 1, 12)
		pill.Size = UDim2.fromOffset(92, 20)
		pill.BackgroundColor3 = BG_OFF
		pill.BorderSizePixel = 0
		pill.Text = text
		pill.TextColor3 = Color3.fromRGB(235, 235, 245)
		pill.Font = Enum.Font.GothamBold
		pill.TextSize = 11
		pill.Parent = button
		Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

		local pillStroke = Instance.new("UIStroke")
		pillStroke.Thickness = 1.5
		pillStroke.Color = STROKE_OFF
		pillStroke.Parent = pill

		local scale = Instance.new("UIScale")
		scale.Parent = button

		button.MouseEnter:Connect(function() tween(scale, 0.12, { Scale = 1.08 }) end)
		button.MouseLeave:Connect(function() tween(scale, 0.12, { Scale = 1 }) end)
		button.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = 0.92 }) end)
		button.MouseButton1Up:Connect(function() tween(scale, 0.1, { Scale = 1.08 }) end)

		return {
			button = button, stroke = stroke, glow = glow, dot = dot,
			icon = icon, pill = pill, pillStroke = pillStroke,
			accent = accent, bgOn = bgOn, pulse = nil,
		}
	end

	local function applyState(ui, on)
		tween(ui.button, 0.2, { BackgroundColor3 = on and ui.bgOn or BG_OFF })
		tween(ui.stroke, 0.2, { Color = on and ui.accent or STROKE_OFF })
		tween(ui.pillStroke, 0.2, { Color = on and ui.accent or STROKE_OFF })
		tween(ui.icon, 0.2, { ImageColor3 = on and Color3.fromRGB(255, 255, 255) or ICON_OFF })
		tween(ui.dot, 0.2, { BackgroundColor3 = on and ui.accent or DOT_OFF })

		if ui.pulse then ui.pulse:Cancel() ui.pulse = nil end

		if on then
			ui.glow.BackgroundTransparency = 0.82
			ui.pulse = TweenService:Create(
				ui.glow,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.6 }
			)
			ui.pulse:Play()
		else
			tween(ui.glow, 0.2, { BackgroundTransparency = 1 })
		end
	end

	local sprintUI = makeButton(
		"SprintButton", "SPRINT", UDim2.new(1, -100, 1, -220), "rbxassetid://6023426915",
		Color3.fromRGB(70, 175, 255), Color3.fromRGB(14, 60, 110)
	)
	local swapUI = makeButton(
		"AnimToggleButton", "SWAP ANIM", UDim2.new(1, -190, 1, -220), "rbxassetid://6023426916",
		Color3.fromRGB(46, 230, 130), Color3.fromRGB(12, 80, 52)
	)

	local function updateButtons()
		applyState(sprintUI, isSprinting)
		applyState(swapUI, isAnimSwapped)
	end

	local function stopSprintTrack()
		if sprintTrack and sprintTrack.IsPlaying then sprintTrack:Stop(0.15) end
	end

	local function updateSprintTrack()
		if not (humanoid and rootPart and sprintTrack) then return end
		if Shared.sin then
			if sprintTrack.IsPlaying then sprintTrack:Stop(0.1) end
			return
		end

		local v = rootPart.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
		local playing = sprintTrack.IsPlaying

		local wanted = isSprinting and humanoid.Health > 0 and humanoid.MoveDirection.Magnitude > 0.05
		local threshold = playing and SPRINT_STOP_SPEED or SPRINT_START_SPEED
		local good = wanted and horizontalSpeed >= threshold and humanoid.FloorMaterial ~= Enum.Material.Air

		if good then
			lastSprintGood = os.clock()
			if not playing then sprintTrack:Play(0.15) end
		elseif playing then
			if not wanted or (os.clock() - lastSprintGood) > SPRINT_GRACE then
				stopSprintTrack()
			end
		end
	end

	local function setSprinting(enabled)
		if not humanoid or humanoid.Health <= 0 then return end
		isSprinting = enabled
		humanoid.WalkSpeed = enabled and SPRINT_SPEED or NORMAL_SPEED
		if not enabled then stopSprintTrack() end
		updateButtons()
	end

	local lastPos = setmetatable({}, { __mode = "k" })

	local function trySwap(track, fromEvent)
		if not (isAnimSwapped and not Shared.sin) then return end
		if not Kit.matches(track, TARGET_IDS) then return end

		local firstTime = not handled[track]
		if not firstTime then
			local last, now = lastPos[track], track.TimePosition
			lastPos[track] = now
			if not fromEvent then return end
		end

		handled[track] = true
		lastPos[track] = track.TimePosition

		local rep, why = Kit.swap(animator, track, REPLACEMENT_ID, SWAP_TUNING, lock)
		if rep or why == "lock" or why == "stopped" then muted[track] = true end
		if firstTime then
			track.Stopped:Once(function()
				handled[track] = nil
				muted[track] = nil
				lastPos[track] = nil
			end)
		end
	end

	local function restoreMuted()
		for track in pairs(muted) do
			if track.IsPlaying then track:AdjustWeight(1, 0.1) end
		end
		table.clear(muted)
		table.clear(handled)
		Kit.restore("swap")
		lock.rep, lock.startedAt, lock.stopToken = nil, nil, nil
		local rep = animator and Kit.get(animator, REPLACEMENT_ID)
		if rep and rep.IsPlaying then rep:Stop(0.1) end
	end

	local function disconnectConnections()
		for _, c in ipairs(connections) do c:Disconnect() end
		table.clear(connections)
	end

	local function setupCharacter(newCharacter)
		disconnectConnections()
		stopSprintTrack()

		character = newCharacter
		humanoid, animator, rootPart, sprintTrack = nil, nil, nil, nil
		table.clear(muted)
		table.clear(handled)
		lock.rep, lock.startedAt, lock.stopToken = nil, nil, nil
		lastSprintGood = 0
		isSprinting = false
		updateButtons()

		local h = newCharacter:WaitForChild("Humanoid", 10)
		if not h or character ~= newCharacter then return end
		local a = h:WaitForChild("Animator", 10)
		local root = newCharacter:WaitForChild("HumanoidRootPart", 10)
		if not a or not root or character ~= newCharacter then return end

		humanoid, animator, rootPart = h, a, root
		humanoid.WalkSpeed = NORMAL_SPEED

		sprintTrack = Kit.get(animator, SPRINT_ANIMATION_ID)
		if sprintTrack then
			sprintTrack.Priority = Enum.AnimationPriority.Movement
			sprintTrack.Looped = true
		end

		Kit.warm(animator, REPLACEMENT_ID)

		table.insert(connections, animator.AnimationPlayed:Connect(function(t)
			trySwap(t, true)
		end))

		table.insert(connections, RunService.RenderStepped:Connect(function()
			updateSprintTrack()
			if isAnimSwapped and not Shared.sin then
				for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
					trySwap(t, false)
				end
			end
			for track in pairs(muted) do
				if track.IsPlaying and track.WeightTarget > 0 then track:AdjustWeight(0, 0) end
			end
		end))

		table.insert(connections, humanoid.Died:Connect(function()
			isSprinting = false
			stopSprintTrack()
			restoreMuted()
			updateButtons()
		end))
	end

	swapUI.button.Activated:Connect(function()
		isAnimSwapped = not isAnimSwapped
		updateButtons()
		if not isAnimSwapped then restoreMuted() end
	end)
	sprintUI.button.Activated:Connect(function() setSprinting(not isSprinting) end)

	table.insert(persistent, LocalPlayer.CharacterAdded:Connect(setupCharacter))
	table.insert(persistent, LocalPlayer.CharacterRemoving:Connect(function(old)
		if character == old then
			disconnectConnections()
			stopSprintTrack()
			character, humanoid, animator, rootPart, sprintTrack = nil, nil, nil, nil, nil
			table.clear(muted)
			table.clear(handled)
			isSprinting = false
			updateButtons()
		end
	end))

	onCleanup(function()
		disconnectConnections()
		for _, c in ipairs(persistent) do c:Disconnect() end
		table.clear(persistent)
		stopSprintTrack()
		restoreMuted()
		if humanoid and humanoid.Health > 0 then humanoid.WalkSpeed = NORMAL_SPEED end
	end)

	updateButtons()
	if LocalPlayer.Character then task.spawn(setupCharacter, LocalPlayer.Character) end
end)

---------------------------------------------------------------- 5) victim anim
runSection("5", function()
	local VICTIM_ANIMATION_ID = "rbxassetid://106247677480487"
	local TRIGGER_IDS = { "103116263598605", "124609826792133" }
	local VICTIM_RANGE = 15
	local TUNING = { speed = 1, fadeIn = 0.05, weight = 1 }
	local DEBOUNCE = 0.6

	local enabled = false
	local conns = {}
	local lastFire = 0
	local hookToken = 0

	local function clearConns()
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end

	local function hookCharacter(char)
		hookToken += 1
		local myToken = hookToken
		clearConns()
		local hum = char:WaitForChild("Humanoid", 10)
		local animator = hum and hum:WaitForChild("Animator", 10)
		if not animator or myToken ~= hookToken then return end

		Kit.warm(animator, VICTIM_ANIMATION_ID)

		table.insert(conns, animator.AnimationPlayed:Connect(function(track)
			if not enabled or Shared.sin or not Kit.matches(track, TRIGGER_IDS) then return end
			local now = os.clock()
			if now - lastFire < DEBOUNCE then return end
			local victim = Kit.nearestVictim(char, VICTIM_RANGE)
			if victim then
				lastFire = now
				Kit.playOnVictim(victim, VICTIM_ANIMATION_ID, TUNING)
			end
		end))
	end

	bind(LocalPlayer.CharacterAdded:Connect(hookCharacter))
	onCleanup(function()
		hookToken += 1
		clearConns()
	end)
	if LocalPlayer.Character then task.spawn(hookCharacter, LocalPlayer.Character) end

	makeToggleCard("VictimAnimGui", "VictimToggle", "VICTIM ANIM", 13, Color3.fromRGB(255, 170, 40), 60, function()
		enabled = not enabled
		return enabled
	end)
end)

---------------------------------------------------------------- 6) SIN
runSection("6", function()
	local TRIGGER_IDS = {
		"103116263598605", "124609826792133", "123537622120693", "107330587130064",
	}

	local ATTACKER_ANIM   = "rbxassetid://81984907411347"
	local VICTIM_ANIM     = "rbxassetid://133643981640980"
	local ATTACKER_ANIM_2 = "rbxassetid://120793050056416"
	local VICTIM_ANIM_2   = "rbxassetid://132299062878030"
	local EXEC_CHANCE     = 0.5
	local execMode = 3

	local EXEC_SOUND   = "rbxassetid://132399674940969"
	local VICTIM_RANGE  = 15
	local EXEC_COOLDOWN = 8
	local DEBUG         = false

	local MOVE_COOLDOWN = 0.8
	local MOVE_IDS = { "138691140561523", "91463196236370", "83632013221100", "91849031357031" }
	local REPLACEMENTS = { "rbxassetid://139352596916392" }
	local OVERRIDES = {}
	local TRIM_END = {}

	local SWAP_MAP = {}
	for _, moveId in ipairs(MOVE_IDS) do
		SWAP_MAP[moveId] = {
			pool = OVERRIDES[moveId] or REPLACEMENTS,
			loop = false, start = 0.15, speed = 1.3, cooldown = MOVE_COOLDOWN, owner = "sin",
			trimEnd = TRIM_END,
		}
	end

	local RUN_ANIM  = "rbxassetid://91791369037012"
	local RUN_START, RUN_STOP, RUN_GRACE = 19, 12, 0.3

	local sinOn = false
	Shared.sin = false
	local conns = {}
	local locoMuted = {}
	local handled = setmetatable({}, { __mode = "k" })
	local seenIds = {}
	local execUntil = 0
	local execTrack = nil
	local SIN_EXEC_GUARD_KEY = "__SIN_EXECUTION_GUARD_UNTIL"
	local hookToken = 0
	local rng = Random.new()
	local runTrack, lastRunGood = nil, 0

	local function playSound(parent)
		local s = Instance.new("Sound")
		s.SoundId = EXEC_SOUND
		s.Volume = 1
		s.Parent = parent or Workspace
		s:Play()
		s.Ended:Once(function() s:Destroy() end)
		task.delay(10, function() if s.Parent then s:Destroy() end end)
	end

	local function playOnAttacker(char, animator, original)
		Kit.silence(original, "sin")
		if locoMuted[original] == nil then locoMuted[original] = false end

		local now = os.clock()
		local sharedUntil = tonumber(env[SIN_EXEC_GUARD_KEY]) or 0
		if now < execUntil or now < sharedUntil then return end
		execUntil = now + EXEC_COOLDOWN
		env[SIN_EXEC_GUARD_KEY] = now + EXEC_COOLDOWN

		local useAlt
		if execMode == 1 then useAlt = false
		elseif execMode == 2 then useAlt = true
		else useAlt = rng:NextNumber() < EXEC_CHANCE end
		local attackerId = useAlt and ATTACKER_ANIM_2 or ATTACKER_ANIM
		local victimId   = useAlt and VICTIM_ANIM_2 or VICTIM_ANIM

		local track = Kit.get(animator, attackerId)
		if not track then return end
		if track.IsPlaying then track:Stop(0) end
		execUntil = os.clock() + math.max(track.Length > 0 and track.Length or 6, 1) + EXEC_COOLDOWN
		env[SIN_EXEC_GUARD_KEY] = math.max(tonumber(env[SIN_EXEC_GUARD_KEY]) or 0, execUntil)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		execTrack = track
		Kit.claim(track, "exec")
		track:Play(0.05, 1, 1)
		track.Stopped:Once(function()
			if execTrack == track and not track.IsPlaying then execUntil = os.clock() + EXEC_COOLDOWN end
		end)
		playSound(char:FindFirstChild("HumanoidRootPart"))

		local victim = Kit.nearestVictim(char, VICTIM_RANGE)
		if victim then Kit.playOnVictim(victim, victimId, { fadeIn = 0.05 }) end
	end

	local lastPos = setmetatable({}, { __mode = "k" })
	local moveLock = {}

	local function swapMove(animator, original, fromEvent)
		local id = Kit.idOf(original)
		local entry = id and SWAP_MAP[id]
		if not entry then return end

		local firstTime = not handled[original]
		if not firstTime then
			local last, now = lastPos[original], original.TimePosition
			lastPos[original] = now
			if not fromEvent then return end
		end

		handled[original] = true
		lastPos[original] = original.TimePosition

		local usable = {}
		for _, candidate in ipairs(entry.pool) do
			local t = Kit.get(animator, candidate)
			if t and t.Length > 0 then table.insert(usable, candidate) end
		end
		local choices = #usable > 0 and usable or entry.pool
		local repId = choices[#choices == 1 and 1 or rng:NextInteger(1, #choices)]
		local rep, why = Kit.swap(animator, original, repId, entry, moveLock)
		if rep then
			locoMuted[original] = rep
		elseif (why == "lock" or why == "stopped") and locoMuted[original] == nil then
			locoMuted[original] = false
		end
		if firstTime then
			original.Stopped:Once(function()
				handled[original] = nil
				locoMuted[original] = nil
				lastPos[original] = nil
			end)
		end
	end

	local function updateRun(char, animator)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (hum and root) then return end
		if not runTrack then
			runTrack = Kit.get(animator, RUN_ANIM)
			if not runTrack then return end
			runTrack.Priority = Enum.AnimationPriority.Movement
			runTrack.Looped = true
		end
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local playing = runTrack.IsPlaying
		local wanted = hum.Health > 0 and hum.MoveDirection.Magnitude > 0.05
		local good = wanted
			and speed >= (playing and RUN_STOP or RUN_START)
			and hum.FloorMaterial ~= Enum.Material.Air
		if good then
			lastRunGood = os.clock()
			if not playing then runTrack:Play(0.05) end
		elseif playing and (not wanted or os.clock() - lastRunGood > RUN_GRACE) then
			runTrack:Stop(0.15)
		end
	end

	local function stopAllLoco()
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.15) end
		for orig, rep in pairs(locoMuted) do
			if rep and rep.IsPlaying then rep:Stop(0.15) end
			if orig.IsPlaying then orig:AdjustWeight(1, 0.15) end
		end
		table.clear(locoMuted)
		table.clear(handled)
		moveLock.rep, moveLock.startedAt, moveLock.stopToken = nil, nil, nil
		local ex = execTrack
		execTrack = nil
		if ex and ex.IsPlaying then ex:Stop(0.1) end
		execUntil = 0
		Kit.restore("sin")
	end

	local function clearConns()
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end

	local function hookCharacter(char)
		hookToken += 1
		local myToken = hookToken
		clearConns()
		table.clear(locoMuted)
		table.clear(handled)
		moveLock.rep, moveLock.startedAt, moveLock.stopToken = nil, nil, nil
		execTrack, execUntil = nil, 0
		runTrack = nil
		local hum = char:WaitForChild("Humanoid", 10)
		local animator = hum and hum:WaitForChild("Animator", 10)
		if not animator or myToken ~= hookToken then return end

		for _, id in ipairs({ ATTACKER_ANIM, ATTACKER_ANIM_2, VICTIM_ANIM, VICTIM_ANIM_2, RUN_ANIM }) do
			Kit.warm(animator, id)
		end
		for _, repId in ipairs(REPLACEMENTS) do
			Kit.warm(animator, repId)
		end
		for _, entry in pairs(SWAP_MAP) do
			for _, repId in ipairs(entry.pool) do Kit.warm(animator, repId) end
		end

		local function onTrack(track)
			if not sinOn then return end
			if Kit.matches(track, TRIGGER_IDS) then
				if not handled[track] then
					handled[track] = true
					track.Stopped:Once(function()
						handled[track] = nil
						locoMuted[track] = nil
					end)
					playOnAttacker(char, animator, track)
				end
			else
				swapMove(animator, track, true)
			end
		end

		table.insert(conns, animator.AnimationPlayed:Connect(onTrack))

		table.insert(conns, RunService.RenderStepped:Connect(function()
			if not sinOn then return end
			updateRun(char, animator)

			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				if Kit.matches(t, TRIGGER_IDS) then
					if not handled[t] then onTrack(t) end
				else
					swapMove(animator, t, false)
				end
			end

			for orig in pairs(locoMuted) do
				if orig.IsPlaying and orig.WeightTarget > 0 then orig:AdjustWeight(0, 0) end
			end
		end))
	end

	bind(LocalPlayer.CharacterAdded:Connect(hookCharacter))
	onCleanup(function()
		sinOn = false
		Shared.sin = false
		hookToken += 1
		clearConns()
		stopAllLoco()
	end)

	makeToggleCard("SinSwapGui", "SIN", "SIN", 15, Color3.fromRGB(190, 60, 255), 120, function()
		sinOn = not sinOn
		Shared.sin = sinOn
		if sinOn then
			local char = LocalPlayer.Character
			if char then task.spawn(hookCharacter, char) end
		else
			hookToken += 1
			clearConns()
			stopAllLoco()
		end
		return sinOn
	end)

	makeCycleCard("ExecModeGui", "ExecMode", "EXECUTION", {
		{ label = "PAIR 1 ONLY", color = Color3.fromRGB(70, 175, 255) },
		{ label = "PAIR 2 ONLY", color = Color3.fromRGB(255, 120, 90) },
		{ label = "BOTH  50 / 50", color = Color3.fromRGB(46, 230, 130) },
	}, execMode, 180, function(i) execMode = i end)

	if LocalPlayer.Character then task.spawn(hookCharacter, LocalPlayer.Character) end
end)

---------------------------------------------------------------- 6b & 6c) visor (RIF + MENLO retro CRT overhaul)
local visorInstances = {}

local function buildVisor(cfg)
	local P = cfg.palette
	local RETRO = cfg.retro == true
	local function cr(n) return UDim.new(0, RETRO and 0 or n) end
	local BASE = {}
	for k, v in pairs(P) do BASE[k] = v end
	local RED, HOT, AMBER, ICE, DIM = P.main, P.hot, P.amber, P.ice, P.dim
	local WARN_RANGE, LOCK_RANGE, DETECT_RANGE = 35, 30, 140
	local BEHIND_RANGE, BEHIND_CLOSE, BEHIND_RATE = 40, 14, 3

	local THREAT_TIERS = {
		{ min = 0,    name = "MINIMAL"  },
		{ min = 400,  name = "LOW"      },
		{ min = 1000, name = "MODERATE" },
		{ min = 2500, name = "DANGER"   },
		{ min = 5000, name = "EXTREME"  },
	}
	local THREAT_BAR_MAX = 5000

	local ADAPT_ON = cfg.adaptive ~= false
	local ADAPT_DARK   = 0.22
	local ADAPT_BRIGHT = 0.60
	local ADAPT_BOOST  = 0.85
	local ADAPT_KEYS = { "main", "hot", "amber", "ice", "dim", "line", "dash", "idle", "text1", "text2" }

	local MINIMAP_RANGE = 140
	local MINIMAP_ROTATES = false

	local visorOn = false
	local renderConn = nil
	local scanAcc, bootStart, bootUntil, failedOnce = 0, 0, 0, false
	local targets = {}
	local seen = {}
	local ticker = { text = "", t0 = -10 }
	local lastTier = 0

	local function ckey(c)
		return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	local brightKey = {}
	for _, k in ipairs(ADAPT_KEYS) do brightKey[ckey(BASE[k])] = k end
	local ADAPT_PROPS = { BackgroundColor3 = true, TextColor3 = true, Color = true, ImageColor3 = true }
	local adaptReg = {}

	local function mk(class, parent, props)
		local o = Instance.new(class)
		for k, v in pairs(props) do
			o[k] = v
			if ADAPT_ON and ADAPT_PROPS[k] and typeof(v) == "Color3" then
				local pk = brightKey[ckey(v)]
				if pk then table.insert(adaptReg, { o, k, pk }) end
			end
		end
		if RETRO and (class == "TextLabel" or class == "TextButton") then o.Font = Enum.Font.Code end
		o.Parent = parent
		return o
	end
	local function stroke(parent, color, thick, transp)
		return mk("UIStroke", parent, {
			Color = color, Thickness = thick or 1.5, Transparency = transp or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end
	local function round(parent) return mk("UICorner", parent, { CornerRadius = UDim.new(1, 0) }) end
	local function pill(parent) return mk("UICorner", parent, { CornerRadius = RETRO and UDim.new(0, 0) or UDim.new(1, 0) }) end
	local function label(parent, props)
		props.BackgroundTransparency = 1
		props.Font = props.Font or (RETRO and Enum.Font.Code or Enum.Font.GothamMedium)
		props.TextColor3 = props.TextColor3 or RED
		props.TextSize = props.TextSize or 12
		return mk("TextLabel", parent, props)
	end

	local function brighten(c, k)
		if k <= 0.001 then return c end
		local h, s, v = c:ToHSV()
		v = math.min(1, v * (1 + ADAPT_BOOST * k) + 0.12 * k)
		s = s * (1 - 0.25 * k)
		return Color3.fromHSV(h, s, v)
	end

	local adaptCur, adaptTarget, adaptApplied, lightAcc, lightLevel = 0, 0, 0, 1, 1
	local function applyAdapt(k)
		for _, key in ipairs(ADAPT_KEYS) do P[key] = brighten(BASE[key], k) end
		RED, HOT, AMBER, ICE, DIM = P.main, P.hot, P.amber, P.ice, P.dim
		for i = #adaptReg, 1, -1 do
			local e = adaptReg[i]
			if e[1].Parent then
				e[1][e[2]] = P[e[3]]
			else
				table.remove(adaptReg, i)
			end
		end
	end

	local lamps, lampConns, lampWatch = {}, {}, false
	local function isLamp(o) return o:IsA("PointLight") or o:IsA("SpotLight") or o:IsA("SurfaceLight") end
	local function startLampWatch()
		if lampWatch then return end
		lampWatch = true
		task.spawn(function()
			local n = 0
			for _, o in ipairs(Workspace:GetDescendants()) do
				if not lampWatch then return end
				if isLamp(o) then lamps[o] = true end
				n += 1
				if n % 3000 == 0 then task.wait() end
			end
		end)
		lampConns[1] = Workspace.DescendantAdded:Connect(function(o) if isLamp(o) then lamps[o] = true end end)
		lampConns[2] = Workspace.DescendantRemoving:Connect(function(o) lamps[o] = nil end)
	end
	local function stopLampWatch()
		lampWatch = false
		for _, c in ipairs(lampConns) do c:Disconnect() end
		table.clear(lampConns)
		table.clear(lamps)
	end

	local function lum(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local function measureLight(root, char)
		local amb = lum(Lighting.Ambient)
		local outdoor = lum(Lighting.OutdoorAmbient)
		local sunUp = math.clamp(math.sin((Lighting.ClockTime - 6) / 12 * math.pi) * 1.5, 0, 1)
		local sun = sunUp * math.clamp(Lighting.Brightness / 1.5, 0.3, 1)

		rayParams.FilterDescendantsInstances = { char }
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, 400, 0), rayParams)
		local exposed = (hit == nil) or (not hit.Instance.CanCollide) or hit.Instance.Transparency > 0.8

		local light = exposed and (sun * 0.7 + math.max(outdoor, amb) * 0.5) or (amb + sun * 0.15)
		local lamp = 0
		local pos = root.Position
		for l in pairs(lamps) do
			if l.Parent and l.Enabled then
				local p = l.Parent
				local lp = p:IsA("BasePart") and p.Position or (p:IsA("Attachment") and p.WorldPosition or nil)
				if lp then
					local r = math.max(l.Range, 1)
					local d = (lp - pos).Magnitude
					if d < r and not l:IsDescendantOf(char) then
						lamp += l.Brightness * (1 - d / r)
					end
				end
			end
		end
		return math.clamp(light + math.clamp(lamp * 0.25, 0, 1), 0, 1)
	end

	local function stepAdapt(dt, char, root)
		lightAcc += dt
		if lightAcc >= 0.25 then
			lightAcc = 0
			local ok, light = pcall(measureLight, root, char)
			if ok then
				lightLevel = light
				local t = math.clamp((light - ADAPT_DARK) / (ADAPT_BRIGHT - ADAPT_DARK), 0, 1)
				t = t * t * (3 - 2 * t)
				adaptTarget = 1 - t
			end
		end
		adaptCur += (adaptTarget - adaptCur) * math.min(1, dt * 2.5)
		if math.abs(adaptCur - adaptApplied) > 0.01 then
			adaptApplied = adaptCur
			applyAdapt(adaptCur)
		end
	end

	local gui = mk("ScreenGui", PlayerGui, {
		Name = cfg.guiName, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = -5, Enabled = false,
	})
	local hud = mk("Frame", gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 })

	local tint = mk("Frame", hud, {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.tint,
		BackgroundTransparency = RETRO and 0.88 or 0.93, BorderSizePixel = 0,
	})
	local vig = {}
	local function edge(anchor, pos, size, rot)
		local f = mk("Frame", hud, {
			AnchorPoint = anchor, Position = pos, Size = size,
			BackgroundColor3 = P.vig, BorderSizePixel = 0,
		})
		mk("UIGradient", f, {
			Rotation = rot,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		})
		table.insert(vig, f)
	end
	edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.2), 90)
	edge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.2), 270)
	edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.14, 1), 0)
	edge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.14, 1), 180)

	if RETRO then
		local ROWS = 240
		for i = 0, ROWS - 1 do
			mk("Frame", hud, {
				Position = UDim2.fromScale(0, i / ROWS), Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.72, BorderSizePixel = 0,
			})
		end
	end
	local scanLine = mk("Frame", hud, {
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = RED, BackgroundTransparency = RETRO and 0.45 or 1, BorderSizePixel = 0, Visible = RETRO,
	})
	local scanGlow = mk("Frame", hud, {
		Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = RED, BorderSizePixel = 0, Visible = RETRO,
	})
	mk("UIGradient", scanGlow, {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.82, 0.88), NumberSequenceKeypoint.new(1, 1),
		}),
	})

	local function bracket(ax, ay)
		if not RETRO then return end
		local x = (ax == 0) and 18 or -18
		local y = (ay == 0) and 18 or -18
		mk("Frame", hud, {
			AnchorPoint = Vector2.new(ax, ay), Position = UDim2.new(ax, x, ay, y),
			Size = UDim2.fromOffset(34, 3), BackgroundColor3 = RED, BorderSizePixel = 0,
		})
		mk("Frame", hud, {
			AnchorPoint = Vector2.new(ax, ay), Position = UDim2.new(ax, x, ay, y),
			Size = UDim2.fromOffset(3, 34), BackgroundColor3 = RED, BorderSizePixel = 0,
		})
	end
	bracket(0, 0) bracket(1, 0) bracket(0, 1) bracket(1, 1)

	local banner = mk("Frame", hud, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(320, 30),
		BackgroundColor3 = P.panel, BackgroundTransparency = 0.25, BorderSizePixel = 0,
	})
	pill(banner)
	local bannerStroke = stroke(banner, RED, 1.5)
	local bannerText = label(banner, { Size = UDim2.fromScale(1, 1), Font = RETRO and Enum.Font.Code or Enum.Font.GothamMedium, TextSize = 12, Text = "" })

	local TAPE_W = 300
	local tape = mk("Frame", hud, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(TAPE_W, 26),
		BackgroundColor3 = P.panel, BackgroundTransparency = 0.4, BorderSizePixel = 0,
		ClipsDescendants = true,
	})
	mk("UICorner", tape, { CornerRadius = cr(8) })
	stroke(tape, P.line, 1)
	mk("Frame", tape, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 3,
	})
	local tapeTicks = {}
	for k = 1, 15 do
		local tick = mk("Frame", tape, {
			AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(1, 6),
			BackgroundColor3 = DIM, BorderSizePixel = 0,
		})
		local txt = label(tape, {
			AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(30, 11), Position = UDim2.fromOffset(0, 1),
			TextSize = 10, Text = "", TextColor3 = ICE, Font = RETRO and Enum.Font.Code or Enum.Font.GothamBold,
		})
		tapeTicks[k] = { tick = tick, txt = txt }
	end
	local tapeMarks = {}
	for i = 1, 8 do
		local m = mk("Frame", tape, {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, 0, 1, -1), Size = UDim2.fromOffset(8, 8),
			Rotation = 45, BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false, ZIndex = 2,
		})
		tapeMarks[i] = m
	end
	local headingText = label(hud, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 74), Size = UDim2.fromOffset(120, 12),
		TextSize = 11, Text = "", TextColor3 = ICE, Font = RETRO and Enum.Font.Code or Enum.Font.GothamBold,
	})
	local tickerLabel = label(hud, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88), Size = UDim2.fromOffset(300, 12),
		TextSize = 10, Text = "", TextColor3 = AMBER,
	})

	local rearWarn = mk("Frame", hud, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Size = UDim2.fromOffset(300, 30),
		BackgroundColor3 = P.panel, BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false,
	})
	pill(rearWarn)
	local rearStroke = stroke(rearWarn, RED, 1)
	local rearText = label(rearWarn, { Size = UDim2.fromScale(1, 1), Font = RETRO and Enum.Font.Code or Enum.Font.GothamMedium, TextSize = 12, Text = "" })
	local rearTrack = setmetatable({}, { __mode = "k" })
	local rearUntil, rearD, rearInc, rearName, rearWas = 0, 0, false, "", false

	local adaptText = label(hud, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 101), Size = UDim2.fromOffset(300, 11),
		TextSize = 9, Text = "", TextColor3 = ICE,
	})

	local ARC = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.22, 0),
		NumberSequenceKeypoint.new(0.23, 1), NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.51, 0), NumberSequenceKeypoint.new(0.72, 0),
		NumberSequenceKeypoint.new(0.73, 1), NumberSequenceKeypoint.new(1, 1),
	})
	local DASH = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.151, 1), NumberSequenceKeypoint.new(0.249, 1),
		NumberSequenceKeypoint.new(0.25, 0), NumberSequenceKeypoint.new(0.4, 0),
		NumberSequenceKeypoint.new(0.401, 1), NumberSequenceKeypoint.new(0.499, 1),
		NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.65, 0),
		NumberSequenceKeypoint.new(0.651, 1), NumberSequenceKeypoint.new(0.749, 1),
		NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(0.9, 0),
		NumberSequenceKeypoint.new(0.901, 1), NumberSequenceKeypoint.new(1, 1),
	})
	local center = mk("Frame", hud, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(200, 200), BackgroundTransparency = 1,
	})
	local function ring(parent, size, color, thick, seq)
		local f = mk("Frame", parent, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
		})
		round(f)
		local st = stroke(f, color, thick)
		local g = nil
		if seq then g = mk("UIGradient", st, { Transparency = seq }) end
		return f, st, g
	end
	local dashFrame, dashStroke, dashGrad = ring(center, 196, P.dash, 1.5, DASH)
	dashStroke.Transparency = 1
	local _, outerStroke, outerGrad = ring(center, 44, RED, 1.5, ARC)
	local _, innerStroke, innerGrad = ring(center, 112, HOT, 1.5, ARC)
	innerStroke.Transparency = 1
	local _, coreStroke = ring(center, 8, ICE, 1.5, nil)
	for i = 0, 3 do
		local a = math.rad(i * 90)
		mk("Frame", center, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(a) * 34, 0.5, -math.cos(a) * 34),
			Size = (i % 2 == 0) and UDim2.fromOffset(1, 6) or UDim2.fromOffset(6, 1),
			BackgroundColor3 = RED, BorderSizePixel = 0,
		})
	end
	local reticleText = label(center, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -62), Size = UDim2.fromOffset(240, 30),
		TextSize = 11, Text = "", TextColor3 = ICE,
	})

	local lockBox = mk("Frame", hud, {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(80, 80), BackgroundTransparency = 1, Visible = false,
	})
	mk("UICorner", lockBox, { CornerRadius = cr(10) })
	local lockStroke = stroke(lockBox, RED, 1.5)
	mk("UIGradient", lockStroke, { Transparency = ARC, Rotation = 45 })
	local lockText = label(lockBox, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(180, 14),
		TextSize = 11, Font = RETRO and Enum.Font.Code or Enum.Font.GothamMedium, Text = "",
	})
	local lockHpBack = mk("Frame", lockBox, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = P.barBack, BorderSizePixel = 0,
	})
	local lockHp = mk("Frame", lockHpBack, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED, BorderSizePixel = 0 })

	local arrows, arrowText = {}, {}
	for i = 1, 6 do
		local a = mk("Frame", hud, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(13, 13), Rotation = 45,
			BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false,
		})
		round(a)
		stroke(a, Color3.fromRGB(255, 255, 255), 1, 0.5)
		arrows[i] = a
		arrowText[i] = label(hud, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(44, 10), TextSize = 10,
			Font = RETRO and Enum.Font.Code or Enum.Font.GothamBold, Text = "", Visible = false,
		})
	end

	local BAR_H = 72
	local bar = mk("Frame", hud, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -cfg.barBottom),
		Size = UDim2.fromOffset(480, BAR_H), BackgroundColor3 = P.panel, BorderSizePixel = 0,
	})
	mk("UIGradient", bar, {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.3),
			NumberSequenceKeypoint.new(0.9, 0.3), NumberSequenceKeypoint.new(1, 1),
		}),
	})

	local function segBar(x0, x1, y, h, n)
		local holder = mk("Frame", bar, {
			Position = UDim2.new(x0, 0, 0, y), Size = UDim2.new(x1 - x0, 0, 0, h), BackgroundTransparency = 1,
		})
		local segs = {}
		for i = 1, n do
			segs[i] = mk("Frame", holder, {
				Position = UDim2.new((i - 1) / n, 0, 0, 0), Size = UDim2.new(1 / n, -2, 1, 0),
				BackgroundColor3 = P.barBack, BorderSizePixel = 0,
			})
		end
		return segs
	end
	local SEGS = 14
	local hpSegs = segBar(0.05, 0.33, 24, 8, SEGS)
	local thSegs = segBar(0.67, 0.95, 24, 8, SEGS)
	local hpText = label(bar, {
		Position = UDim2.new(0.05, 0, 0, 7), Size = UDim2.new(0.28, 0, 0, 12), TextSize = 10, Text = "",
		TextXAlignment = Enum.TextXAlignment.Left, Font = RETRO and Enum.Font.Code or Enum.Font.GothamBold,
	})
	local thText = label(bar, {
		Position = UDim2.new(0.67, 0, 0, 7), Size = UDim2.new(0.28, 0, 0, 12), TextSize = 10, Text = "",
		TextXAlignment = Enum.TextXAlignment.Right, Font = RETRO and Enum.Font.Code or Enum.Font.GothamBold,
	})
	local statsText = label(bar, {
		Position = UDim2.new(0.35, 0, 0, 5), Size = UDim2.new(0.30, 0, 0, 30), TextSize = 11, Text = "",
		TextColor3 = P.text1,
	})
	local chips = {}
	for i = 1, 3 do
		local x = 0.05 + (i - 1) * 0.31
		local f = mk("Frame", bar, {
			Position = UDim2.new(x, 0, 0, 43), Size = UDim2.new(0.28, 0, 0, 21),
			BackgroundColor3 = P.panel, BackgroundTransparency = 0.2, BorderSizePixel = 0,
		})
		mk("UICorner", f, { CornerRadius = cr(6) })
		stroke(f, RETRO and ICE or Color3.fromRGB(255, 255, 255), 1.5)
		local accent = mk("Frame", f, { Size = UDim2.new(0, 3, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = RED, BorderSizePixel = 0 })
		round(accent)
		local t = label(f, {
			Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -14, 1, 0), TextSize = 10, Text = "",
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = P.text2,
		})
		chips[i] = { frame = f, accent = accent, text = t }
	end

	local DOT_RED = Color3.fromRGB(170, 28, 28)
	local mapHost, mapMode, mapOverlay = nil, nil, nil
	local mapDots = {}
	local mapCheck = 0

	local function destroyOverlay()
		if mapOverlay then mapOverlay:Destroy() end
		mapOverlay, mapHost, mapMode = nil, nil, nil
		mapDots = {}
	end

	local function locateMinimap()
		local mm = PlayerGui:FindFirstChild("Minimap")
		if not mm then return nil end
		local best, bestArea = nil, 0
		for _, d in ipairs(mm:GetDescendants()) do
			if d:IsA("ViewportFrame") and not (mapOverlay and d:IsDescendantOf(mapOverlay)) then
				local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
				if a > bestArea then best, bestArea = d, a end
			end
		end
		if best then return best, "viewport" end
		local limit = 0.5 * mm.AbsoluteSize.X * mm.AbsoluteSize.Y
		for _, d in ipairs(mm:GetDescendants()) do
			if (d:IsA("Frame") or d:IsA("ImageLabel")) and not (mapOverlay and d:IsDescendantOf(mapOverlay)) then
				local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
				if a > bestArea and a < limit then best, bestArea = d, a end
			end
		end
		if best then return best, "flat" end
		return nil
	end

	local function ensureOverlay()
		if mapOverlay and mapOverlay.Parent and mapHost and mapHost:IsDescendantOf(PlayerGui) then return end
		destroyOverlay()
		local host, mode = locateMinimap()
		if not host then return end
		mapHost, mapMode = host, mode
		mapOverlay = mk("Frame", host, {
			Name = "RifMinimapOverlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 100,
		})
		for i = 1, 14 do
			local d = mk("Frame", mapOverlay, {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = DOT_RED, BorderSizePixel = 0, Visible = false, ZIndex = 102,
			})
			round(d)
			stroke(d, Color3.fromRGB(70, 0, 0), 1, 0.3)
			local halo = mk("Frame", d, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = DOT_RED, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 101,
			})
			round(halo)
			mapDots[i] = { dot = d, halo = halo }
		end
	end

	local function mapFraction(worldPos, myRoot, fwd, rgt)
		if mapMode == "viewport" and mapHost then
			local vc = mapHost.CurrentCamera
			if vc then
				local lp = vc.CFrame:PointToObjectSpace(worldPos)
				local depth = -lp.Z
				if depth > 0.01 then
					local tanH = math.tan(math.rad(vc.FieldOfView) / 2)
					local aspect = mapHost.AbsoluteSize.X / math.max(mapHost.AbsoluteSize.Y, 1)
					return 0.5 + 0.5 * (lp.X / depth) / (tanH * aspect), 0.5 - 0.5 * (lp.Y / depth) / tanH
				end
			end
		end
		local d = worldPos - myRoot.Position
		if MINIMAP_ROTATES then
			local x = d.X * rgt.X + d.Z * rgt.Z
			local y = d.X * fwd.X + d.Z * fwd.Z
			return 0.5 + 0.5 * x / MINIMAP_RANGE, 0.5 - 0.5 * y / MINIMAP_RANGE
		end
		return 0.5 + 0.5 * d.X / MINIMAP_RANGE, 0.5 + 0.5 * d.Z / MINIMAP_RANGE
	end

	local CARDINALS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

	local function pushEvent(msg)
		ticker.text = msg
		ticker.t0 = os.clock()
	end

	local function classify(c)
		local plr = Players:GetPlayerFromCharacter(c) or Players:FindFirstChild(c.Name)
		if plr and plr:IsA("Player") then
			if plr == LocalPlayer then return nil end
			if plr.Team ~= nil and plr.Team == LocalPlayer.Team then return nil end
			return "player"
		end
		return "npc"
	end

	local function scan()
		table.clear(targets)
		local char = LocalPlayer.Character
		local myRoot = char and char:FindFirstChild("HumanoidRootPart")
		if not myRoot then return end
		local pool
		local folder = Workspace:FindFirstChild("Characters")
		if folder then
			pool = folder:GetChildren()
		else
			pool = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character then table.insert(pool, p.Character) end
			end
		end
		for _, c in ipairs(pool) do
			if c ~= char and c:IsA("Model") then
				local hrp = c:FindFirstChild("HumanoidRootPart")
				local hum = c:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local kind = classify(c)
					if kind then
						local d = (hrp.Position - myRoot.Position).Magnitude
						if d <= DETECT_RANGE then
							table.insert(targets, { model = c, hrp = hrp, hum = hum, dist = d, kind = kind })
						end
					end
				end
			end
		end
		table.sort(targets, function(a, b) return a.dist < b.dist end)

		local current = {}
		for _, t in ipairs(targets) do
			current[t.model] = true
			local s = seen[t.model]
			if not s then
				seen[t.model] = { warned = t.dist <= WARN_RANGE }
				pushEvent(string.format("CONTACT ACQUIRED: %s  %dm", string.upper(t.model.Name), math.floor(t.dist + 0.5)))
			elseif t.dist <= WARN_RANGE and not s.warned then
				s.warned = true
				pushEvent(string.format("WARNING: %s CLOSING  %dm", string.upper(t.model.Name), math.floor(t.dist + 0.5)))
			elseif t.dist > WARN_RANGE * 1.4 then
				s.warned = false
			end
		end
		for m in pairs(seen) do
			if not current[m] then seen[m] = nil end
		end
	end

	local function scramble(text, progress)
		local n = math.floor(#text * math.clamp(progress, 0, 1))
		local out = { string.sub(text, 1, n) }
		for i = n + 1, #text do
			out[#out + 1] = (string.sub(text, i, i) == " ") and " " or string.char(math.random(33, 90))
		end
		return table.concat(out)
	end

	local function kindColor(t)
		if t.dist <= WARN_RANGE then return RED end
		return (t.kind == "player") and HOT or AMBER
	end

	local liftBase = setmetatable({}, { __mode = "k" })
	local function findStamina()
		local g = PlayerGui:FindFirstChild("Gui")
		local sf = g and g:FindFirstChild("statusFrame")
		local st = sf and sf:FindFirstChild("stamina")
		if st and st:IsA("GuiObject") then return st, sf end
		return nil
	end
	local function liftStamina()
		local lift = cfg.staminaLift
		if not lift or lift == 0 then return end
		local st, sf = findStamina()
		if not st then return end
		local b = liftBase[st]
		if not b then
			b = { pos = st.Position, clip = sf and sf:IsA("GuiObject") and sf.ClipsDescendants or false }
			liftBase[st] = b
		end
		if sf and sf:IsA("GuiObject") and sf.ClipsDescendants then sf.ClipsDescendants = false end
		local want = UDim2.new(b.pos.X.Scale, b.pos.X.Offset, b.pos.Y.Scale, b.pos.Y.Offset - lift)
		if st.Position ~= want then st.Position = want end
	end
	local function dropStamina()
		local st, sf = findStamina()
		local b = st and liftBase[st]
		if not b then return end
		st.Position = b.pos
		if sf and sf:IsA("GuiObject") then sf.ClipsDescendants = b.clip end
		liftBase[st] = nil
	end

	local function update(dt)
		local now = os.clock()
		liftStamina()
		scanAcc += dt
		if scanAcc > 0.12 then
			scanAcc = 0
			scan()
		end
		mapCheck += dt
		if mapCheck > 1 or not mapOverlay then
			mapCheck = 0
			ensureOverlay()
		end

		local cam = Workspace.CurrentCamera
		local char = LocalPlayer.Character
		local myRoot = char and char:FindFirstChild("HumanoidRootPart")
		local myHum = char and char:FindFirstChildOfClass("Humanoid")
		if ADAPT_ON and myRoot then stepAdapt(dt, char, myRoot) end
		if not (cam and myRoot) then return end

		dashGrad.Rotation = (now * 25) % 360
		outerGrad.Rotation = (now * 70) % 360
		innerGrad.Rotation = (-now * 110) % 360
		local sy = (now * 0.22) % 1
		scanLine.Position = UDim2.fromScale(0, sy)
		scanGlow.Position = UDim2.new(0, 0, sy, -34)

		local look = cam.CFrame.LookVector
		local fwd = Vector3.new(look.X, 0, look.Z)
		if fwd.Magnitude < 0.01 then fwd = Vector3.new(0, 0, -1) end
		fwd = fwd.Unit
		local rgt = Vector3.new(-fwd.Z, 0, fwd.X)
		local heading = (math.deg(math.atan2(fwd.X, -fwd.Z)) + 360) % 360
		headingText.Text = string.format("%03d  %s", math.floor(heading + 0.5), CARDINALS[(math.floor((heading + 22.5) / 45) % 8) + 1])

		local base = math.floor(heading / 15) * 15
		for k = 1, 15 do
			local a = base + (k - 8) * 15
			local delta = ((a - heading + 540) % 360) - 180
			local tk = tapeTicks[k]
			local x = TAPE_W / 2 + delta / 90 * (TAPE_W / 2)
			if math.abs(delta) <= 88 then
				local ang = a % 360
				local major = (ang % 45 == 0)
				tk.tick.Visible = true
				tk.tick.Size = UDim2.fromOffset(major and 2 or 1, major and 11 or 6)
				tk.tick.Position = UDim2.new(0, x, 1, -1)
				tk.txt.Visible = major
				if major then
					tk.txt.Text = CARDINALS[(ang // 45) + 1]
					tk.txt.Position = UDim2.fromOffset(x, 1)
				end
			else
				tk.tick.Visible = false
				tk.txt.Visible = false
			end
		end

		local count = 0
		local rearT, rearBest, rearClosing = nil, 1e9, false
		for _, t in ipairs(targets) do
			if t.hrp.Parent then
				t.dist = (t.hrp.Position - myRoot.Position).Magnitude
				count += 1

				local tr = rearTrack[t.model]
				if not tr then
					tr = { d = t.dist, t = now, rate = 0 }
					rearTrack[t.model] = tr
				elseif now - tr.t >= 0.1 then
					tr.rate = tr.rate * 0.6 + ((tr.d - t.dist) / (now - tr.t)) * 0.4
					tr.d, tr.t = t.dist, now
				end
				if t.dist <= BEHIND_RANGE then
					local dv = t.hrp.Position - myRoot.Position
					local flat = Vector3.new(dv.X, 0, dv.Z)
					if flat.Magnitude > 0.1 and flat.Unit:Dot(fwd) < -0.35 then
						local closing = tr.rate >= BEHIND_RATE
						if (closing or t.dist <= BEHIND_CLOSE) and t.dist < rearBest then
							rearT, rearBest, rearClosing = t, t.dist, closing
						end
					end
				end
			end
		end
		if rearT then
			rearUntil = now + 0.4
			rearD, rearInc, rearName = rearBest, rearClosing, string.upper(rearT.model.Name)
		end
		local rearActive = now < rearUntil
		if rearActive and not rearWas and now > bootUntil then
			pushEvent(string.format("REAR WARNING: %s  %dm", rearName, math.floor(rearD + 0.5)))
		end
		rearWas = rearActive
		local nearest = targets[1]
		if nearest and not nearest.hrp.Parent then nearest = nil end

		local topHp, topTarget = 0, nil
		for _, t in ipairs(targets) do
			if t.hrp.Parent then
				local h = math.max(t.hum.Health, 0)
				if h > topHp then topHp, topTarget = h, t end
			end
		end
		local tier, level, levelColor = 0, "CLEAR", ICE
		if topTarget then
			tier = 1
			for i = #THREAT_TIERS, 1, -1 do
				if topHp >= THREAT_TIERS[i].min then tier = i break end
			end
			level = THREAT_TIERS[tier].name
			if tier == 1 then levelColor = ICE
			elseif tier == 2 then levelColor = AMBER
			elseif tier == 3 then levelColor = HOT
			else levelColor = RED end
		end
		local extreme = (tier == 5)
		local critical = (tier >= 4)
		if tier ~= lastTier then
			if tier > lastTier and tier >= 2 and now > bootUntil then
				pushEvent(string.format("THREAT %s: %s  %d HP", level, string.upper(topTarget.model.Name), math.floor(topHp + 0.5)))
			end
			lastTier = tier
		end

		if now < bootUntil then
			bannerText.Text = scramble(cfg.bootText, (now - bootStart) / 1.4)
			bannerText.TextColor3 = ICE
			bannerStroke.Color = ICE
			bannerText.TextTransparency = 0
		elseif critical then
			bannerText.Text = extreme and "!!  EXTREME THREAT  !!" or "!  DANGEROUS HOSTILE  !"
			bannerText.TextColor3 = RED
			bannerStroke.Color = RED
			bannerText.TextTransparency = (math.sin(now * (extreme and 14 or 7)) > 0) and 0 or 0.65
		elseif nearest then
			bannerText.Text = "HOSTILE CONTACT  x" .. count
			bannerText.TextColor3 = levelColor
			bannerStroke.Color = levelColor
			bannerText.TextTransparency = 0
		else
			bannerText.Text = "AREA CLEAR"
			bannerText.TextColor3 = ICE
			bannerStroke.Color = P.clear
			bannerText.TextTransparency = 0
		end

		local age = now - ticker.t0
		if age < 4 then
			local shown = math.floor(#ticker.text * math.min(1, age / 0.5))
			tickerLabel.Text = string.sub(ticker.text, 1, shown) .. ((age < 0.5) and "_" or "")
			tickerLabel.TextTransparency = (age > 3) and (age - 3) or 0
		else
			tickerLabel.Text = ""
		end

		local pulse = 0
		if extreme then pulse = 0.5 + 0.5 * math.sin(now * 9)
		elseif critical then pulse = 0.5 * (0.5 + 0.5 * math.sin(now * 5)) end
		for _, f in ipairs(vig) do f.BackgroundTransparency = 0.3 - 0.25 * pulse end
		tint.BackgroundTransparency = (RETRO and 0.88 or 0.93) - 0.1 * pulse - 0.06 * adaptCur
		if RETRO then
			tint.BackgroundTransparency = tint.BackgroundTransparency - 0.04 - 0.02 * math.sin(now * 41) - ((math.random() < 0.025) and 0.05 or 0)
		end

		rearWarn.Visible = rearActive
		if rearActive then
			local flash = (math.sin(now * (rearInc and 16 or 9)) > 0)
			rearText.Text = string.format(rearInc and "!!  INCOMING FROM BEHIND  %dm  !!" or "!!  ENEMY BEHIND  %dm  !!", math.floor(rearD + 0.5))
			rearText.TextColor3 = RED
			rearText.TextTransparency = flash and 0 or 0.55
			rearStroke.Color = RED
			vig[2].BackgroundTransparency = 0.12 + 0.3 * (0.5 + 0.5 * math.sin(now * 12))
		end

		local sz = hud.AbsoluteSize
		local ringR = math.min(sz.X, sz.Y) * 0.36
		for i = 1, #arrows do
			local t = targets[i]
			local arrow, atext, mark = arrows[i], arrowText[i], tapeMarks[i]
			if t and t.hrp.Parent then
				local d = t.hrp.Position - myRoot.Position
				local x = d.X * rgt.X + d.Z * rgt.Z
				local y = d.X * fwd.X + d.Z * fwd.Z
				local theta = math.atan2(x, y)
				local col = kindColor(t)
				local near = t.dist <= WARN_RANGE
				if t.dist <= DETECT_RANGE * 0.75 then
					local s = near and 16 or 11
					local px, py = sz.X / 2 + ringR * math.sin(theta), sz.Y / 2 - ringR * math.cos(theta)
					arrow.Position = UDim2.fromOffset(px, py)
					arrow.Size = UDim2.fromOffset(s, s)
					arrow.BackgroundColor3 = col
					arrow.Visible = true
					atext.Position = UDim2.fromOffset(
						sz.X / 2 + (ringR + 20) * math.sin(theta), sz.Y / 2 - (ringR + 20) * math.cos(theta)
					)
					atext.Text = math.floor(t.dist + 0.5) .. "m"
					atext.TextColor3 = col
					atext.Visible = true
				else
					arrow.Visible = false
					atext.Visible = false
				end
				local deg = math.deg(theta)
				if mark and math.abs(deg) <= 88 then
					mark.Position = UDim2.new(0, TAPE_W / 2 + deg / 90 * (TAPE_W / 2), 1, -1)
					mark.BackgroundColor3 = col
					mark.Visible = true
				elseif mark then
					mark.Visible = false
				end
			else
				arrow.Visible = false
				atext.Visible = false
				if mark then mark.Visible = false end
			end
		end

		if mapOverlay then
			for i = 1, #mapDots do
				local t = targets[i]
				local md = mapDots[i]
				if t and t.hrp.Parent then
					local fx, fy = mapFraction(t.hrp.Position, myRoot, fwd, rgt)
					local inside = fx >= 0 and fx <= 1 and fy >= 0 and fy <= 1
					fx = math.clamp(fx, 0.04, 0.96)
					fy = math.clamp(fy, 0.04, 0.96)
					md.dot.Position = UDim2.fromScale(fx, fy)
					md.dot.BackgroundTransparency = inside and 0.12 or 0.6
					local ph = (now * 1.4 + i * 0.3) % 1
					local grow = 6 + 6 * ph
					md.halo.Size = UDim2.fromOffset(grow, grow)
					md.halo.BackgroundTransparency = 0.78 + 0.22 * ph
					md.dot.Visible = true
				else
					md.dot.Visible = false
				end
			end
		end

		local locked = nearest and nearest.dist <= LOCK_RANGE
		if locked then
			local v, onScreen = cam:WorldToViewportPoint(nearest.hrp.Position + Vector3.new(0, 1, 0))
			local frac = math.clamp(nearest.hum.Health / math.max(nearest.hum.MaxHealth, 1), 0, 1)
			if onScreen and v.Z > 0 then
				local s = math.clamp(3200 / math.max(v.Z, 1), 46, 150) + 4 * math.sin(now * 8)
				lockBox.Size = UDim2.fromOffset(s, s)
				lockBox.Position = UDim2.fromOffset(v.X, v.Y)
				lockText.Text = string.format("%s  %dm", string.upper(nearest.model.Name), math.floor(nearest.dist + 0.5))
				lockHp.Size = UDim2.fromScale(frac, 1)
				lockBox.Visible = true
			else
				lockBox.Visible = false
			end
			reticleText.Text = string.format("TARGET LOCKED\n%s   HP %d%%", string.upper(nearest.model.Name), math.floor(frac * 100 + 0.5))
			reticleText.TextColor3 = RED
			coreStroke.Color = RED
			outerStroke.Color = RED
		else
			lockBox.Visible = false
			reticleText.Text = nearest and "TRACKING..." or "NO CONTACTS"
			reticleText.TextColor3 = ICE
			coreStroke.Color = ICE
			outerStroke.Color = nearest and HOT or P.idle
		end

		bar.Size = UDim2.fromOffset(math.clamp(sz.X * cfg.barWidth, 340, 700), BAR_H)
		local hpFrac = 1
		if myHum then hpFrac = math.clamp(myHum.Health / math.max(myHum.MaxHealth, 1), 0, 1) end
		local hpLit = math.floor(hpFrac * SEGS + 0.5)
		for i = 1, SEGS do
			local sg = hpSegs[i]
			if i <= hpLit then
				sg.BackgroundColor3 = (hpFrac > 0.35) and RED or AMBER
				sg.BackgroundTransparency = (i == hpLit) and (0.15 + 0.25 * math.sin(now * 6)) or 0
			else
				sg.BackgroundColor3 = P.barBack
				sg.BackgroundTransparency = 0
			end
		end
		local thFrac = topTarget and math.clamp(topHp / THREAT_BAR_MAX, 0, 1) or 0
		local thLit = math.floor(thFrac * SEGS + 0.5)
		if topTarget and thLit < 1 then thLit = 1 end
		for i = 1, SEGS do
			local sg = thSegs[i]
			if i <= thLit then
				sg.BackgroundColor3 = levelColor
				sg.BackgroundTransparency = (extreme and (math.sin(now * 14 + i) > 0)) and 0.5 or 0
			else
				sg.BackgroundColor3 = P.barBack
				sg.BackgroundTransparency = 0
			end
		end
		hpText.Text = string.format("VITALS %d%%", math.floor(hpFrac * 100 + 0.5))
		thText.Text = "THREAT " .. level
		thText.TextColor3 = levelColor
		local vel = myRoot.AssemblyLinearVelocity
		local spd = Vector3.new(vel.X, 0, vel.Z).Magnitude
		statsText.Text = string.format(
			"SPD %04.1f  ALT %d\nHOSTILES %d  HP %s", spd, math.floor(myRoot.Position.Y + 0.5), count,
			topTarget and tostring(math.floor(topHp + 0.5)) or "--"
		)
		if ADAPT_ON and adaptCur > 0.04 then
			adaptText.Text = string.format("LOW-LIGHT ENHANCE  %d%%", math.floor(adaptCur * 100 + 0.5))
		else
			adaptText.Text = ""
		end
		for i = 1, 3 do
			local t = targets[i]
			local chip = chips[i]
			if t and t.hrp.Parent then
				local frac = math.clamp(t.hum.Health / math.max(t.hum.MaxHealth, 1), 0, 1)
				chip.text.Text = string.format(
					"%02d  %s  %dm  %d%%", i, string.sub(string.upper(t.model.Name), 1, 8),
					math.floor(t.dist + 0.5), math.floor(frac * 100 + 0.5)
				)
				chip.accent.BackgroundColor3 = kindColor(t)
				chip.frame.BackgroundTransparency = (t.dist <= WARN_RANGE and critical) and (0.45 + 0.35 * math.sin(now * 10)) or 0.2
			else
				chip.text.Text = string.format("%02d --", i)
				chip.accent.BackgroundColor3 = P.barBack
				chip.frame.BackgroundTransparency = 0.5
			end
		end
	end

	local function setVisor(on)
		visorOn = on
		gui.Enabled = on
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		if on then
			bootStart = os.clock()
			bootUntil = bootStart + 2.2
			scanAcc = 1
			mapCheck = 1
			table.clear(seen)
			lastTier = 0
			lightAcc = 1
			if ADAPT_ON then startLampWatch() end
			pushEvent(cfg.linkText)
			renderConn = RunService.RenderStepped:Connect(function(dt)
				local ok, err = pcall(update, dt)
				if not ok and not failedOnce then
					failedOnce = true
					warn("[Visor] " .. tostring(err))
				end
			end)
		else
			destroyOverlay()
			stopLampWatch()
			dropStamina()
		end
	end
	onCleanup(function()
		if renderConn then renderConn:Disconnect() renderConn = nil end
		destroyOverlay()
		stopLampWatch()
		dropStamina()
	end)

	local inst = {}
	local setCard = makeToggleCard(cfg.cardGui, cfg.cardName, cfg.cardTitle, 15, RED, cfg.cardY, function()
		local want = not visorOn
		if want then
			for _, other in ipairs(visorInstances) do
				if other ~= inst then other.off() end
			end
		end
		setVisor(want)
		return visorOn
	end)
	inst.off = function()
		if visorOn then setVisor(false) end
		setCard(false)
	end
	table.insert(visorInstances, inst)
end

runSection("6b", function()
	buildVisor({
		guiName = "RifVisorGui", cardGui = "VisorToggleGui", cardName = "VisorToggle", cardTitle = "VISOR", cardY = 240,
		bootText = "R.I.F.  VISOR  ONLINE", linkText = "RIF TACTICAL LINK ESTABLISHED",
		barWidth = 0.56, barBottom = 84,
		palette = {
			main = Color3.fromRGB(255, 56, 56), hot = Color3.fromRGB(255, 120, 70), amber = Color3.fromRGB(255, 190, 80),
			ice = Color3.fromRGB(236, 238, 242), dim = Color3.fromRGB(190, 190, 196),
			tint = Color3.fromRGB(255, 0, 0), vig = Color3.fromRGB(10, 2, 3), panel = Color3.fromRGB(8, 8, 10),
			barBack = Color3.fromRGB(52, 20, 22), line = Color3.fromRGB(120, 120, 126), dash = Color3.fromRGB(170, 50, 50),
			idle = Color3.fromRGB(190, 60, 60), text1 = Color3.fromRGB(240, 240, 244), text2 = Color3.fromRGB(205, 205, 212),
			clear = Color3.fromRGB(110, 60, 60),
		},
	})
end)

runSection("6c", function()
	buildVisor({
		guiName = "MenloVisorGui", cardGui = "MenloToggleGui", cardName = "MenloToggle", cardTitle = "MENLO", cardY = 300,
		bootText = "MENLO  VISOR  ONLINE", linkText = "MENLO TACTICAL LINK ESTABLISHED",
		barWidth = 0.56, barBottom = 84,
		retro = true,
		staminaLift = 90,
		palette = {
			main = Color3.fromRGB(50, 220, 90), hot = Color3.fromRGB(120, 255, 110), amber = Color3.fromRGB(240, 200, 70),
			ice = Color3.fromRGB(130, 245, 150), dim = Color3.fromRGB(30, 110, 50),
			tint = Color3.fromRGB(8, 50, 18), vig = Color3.fromRGB(0, 5, 2), panel = Color3.fromRGB(2, 10, 4),
			barBack = Color3.fromRGB(10, 35, 15), line = Color3.fromRGB(45, 130, 70), dash = Color3.fromRGB(30, 110, 50),
			idle = Color3.fromRGB(40, 160, 70), text1 = Color3.fromRGB(110, 235, 130), text2 = Color3.fromRGB(130, 210, 140),
			clear = Color3.fromRGB(25, 75, 40),
		},
	})
end)

---------------------------------------------------------------- 6d) hide HUD
runSection("6d", function()
	local function statusPart(name)
		return function()
			local g = PlayerGui:FindFirstChild("Gui")
			local sf = g and g:FindFirstChild("statusFrame")
			return sf and sf:FindFirstChild(name)
		end
	end
	local finders = {
		function() return PlayerGui:FindFirstChild("Gasmask") end,
		statusPart("stamina"),
		statusPart("health"),
	}

	local hidden = false
	local original = setmetatable({}, { __mode = "k" })
	local wanted = setmetatable({}, { __mode = "k" })

	local function propOf(o)
		if o:IsA("ScreenGui") then return "Enabled" end
		if o:IsA("GuiObject") then return "Visible" end
		return nil
	end

	local function hide()
		for _, find in ipairs(finders) do
			local o = find()
			local prop = o and propOf(o)
			if prop then
				local cur = o[prop]
				if original[o] == nil then original[o] = cur end
				if cur ~= false then
					wanted[o] = true
					o[prop] = false
				end
			end
		end
	end

	local function show()
		for _, find in ipairs(finders) do
			local o = find()
			local prop = o and propOf(o)
			if prop and original[o] ~= nil then
				local v = original[o]
				if wanted[o] then v = true end
				o[prop] = v
				original[o] = nil
				wanted[o] = nil
			end
		end
	end

	bind(RunService.RenderStepped:Connect(function()
		if hidden then hide() end
	end))
	onCleanup(function()
		hidden = false
		show()
	end)

	makeToggleCard("HideHudGui", "HideHudToggle", "HIDE HUD", 13, Color3.fromRGB(255, 95, 120), 360, function()
		hidden = not hidden
		if hidden then hide() else show() end
		return hidden
	end)
end)

---------------------------------------------------------------- 8) futuristic team selector (Raid & Menlo)
runSection("8", function()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeamSelectGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1500
	gui.Parent = PlayerGui

	-- Floating trigger button (dark futuristic pill)
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "TeamSelectButton"
	openBtn.Size = UDim2.new(0, 156, 0, 46)
	openBtn.Position = UDim2.new(0.02, 0, 0.45, 420)
	openBtn.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	openBtn.BackgroundTransparency = 0.25
	openBtn.BorderSizePixel = 0
	openBtn.AutoButtonColor = false
	openBtn.Text = ""
	openBtn.Parent = gui
	Instance.new("UICorner", openBtn).CornerRadius = UDim.new(1, 0)

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(110, 80, 220)
	btnStroke.Thickness = 1.5
	btnStroke.Transparency = 0.3
	btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	btnStroke.Parent = openBtn

	local btnText = Instance.new("TextLabel")
	btnText.BackgroundTransparency = 1
	btnText.Size = UDim2.new(1, 0, 1, 0)
	btnText.Font = Enum.Font.GothamBold
	btnText.Text = "SELECT TEAM"
	btnText.TextSize = 13
	btnText.TextColor3 = Color3.fromRGB(235, 235, 245)
	btnText.Parent = openBtn

	-- Fullscreen dark sci-fi modal
	local modal = Instance.new("Frame")
	modal.Name = "TeamModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	modal.BackgroundTransparency = 0.35
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = gui

	local blurDim = Instance.new("Frame")
	blurDim.Size = UDim2.fromScale(1, 1)
	blurDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	blurDim.BackgroundTransparency = 0.5
	blurDim.BorderSizePixel = 0
	blurDim.Parent = modal

	local container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromOffset(760, 460)
	container.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	container.BorderSizePixel = 0
	container.Parent = modal
	Instance.new("UICorner", container).CornerRadius = UDim.new(0, 16)

	local contStroke = Instance.new("UIStroke")
	contStroke.Color = Color3.fromRGB(120, 80, 250)
	contStroke.Thickness = 2
	contStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	contStroke.Parent = container

	local titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size = UDim2.new(1, 0, 0, 50)
	titleLbl.Position = UDim2.fromOffset(0, 16)
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.Text = "CHOOSE YOUR FACTION"
	titleLbl.TextSize = 20
	titleLbl.TextColor3 = Color3.fromRGB(245, 245, 255)
	titleLbl.Parent = container

	local subLbl = Instance.new("TextLabel")
	subLbl.BackgroundTransparency = 1
	subLbl.Size = UDim2.new(1, 0, 0, 20)
	subLbl.Position = UDim2.fromOffset(0, 46)
	subLbl.Font = Enum.Font.GothamMedium
	subLbl.Text = "THERE ARE ONLY TWO TRUE POWERS. SELECT WISELY."
	subLbl.TextSize, subLbl.TextColor3 = 11, Color3.fromRGB(140, 140, 165)
	subLbl.Parent = container

	local function makeTeamCard(posX, teamName, accentColor, descriptionText)
		local card = Instance.new("TextButton")
		card.Size = UDim2.fromOffset(340, 330)
		card.Position = UDim2.new(0, posX, 0, 85)
		card.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.Parent = container
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		local stroke = Instance.new("UIStroke")
		stroke.Color = accentColor
		stroke.Thickness = 2
		stroke.Transparency = 0.4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card

		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Position = UDim2.fromOffset(24, 24)
		nameLbl.Size = UDim2.fromOffset(290, 32)
		nameLbl.Font = Enum.Font.GothamBlack
		nameLbl.Text = string.upper(teamName)
		nameLbl.TextSize = 22
		nameLbl.TextColor3 = accentColor
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.BackgroundTransparency = 1
		descLbl.Position = UDim2.fromOffset(24, 72)
		descLbl.Size = UDim2.fromOffset(290, 170)
		descLbl.Font = Enum.Font.GothamMedium
		descLbl.Text = descriptionText
		descLbl.TextSize = 13
		descLbl.TextColor3 = Color3.fromRGB(200, 200, 215)
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.TextYAlignment = Enum.TextYAlignment.Top
		descLbl.TextWrapped = true
		descLbl.Parent = card

		local selectBtn = Instance.new("Frame")
		selectBtn.Size = UDim2.fromOffset(290, 42)
		selectBtn.Position = UDim2.fromOffset(24, 260)
		selectBtn.BackgroundColor3 = accentColor
		selectBtn.BorderSizePixel = 0
		selectBtn.Parent = card
		Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 8)

		local btnLbl = Instance.new("TextLabel")
		btnLbl.BackgroundTransparency = 1
		btnLbl.Size = UDim2.fromScale(1, 1)
		btnLbl.Font = Enum.Font.GothamBold
		btnLbl.Text = "ENLIST IN " .. string.upper(teamName)
		btnLbl.TextSize = 12
		btnLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnLbl.Parent = selectBtn

		card.MouseEnter:Connect(function() tween(card, 0.2, { BackgroundColor3 = Color3.fromRGB(24, 24, 36) }) end)
		card.MouseLeave:Connect(function() tween(card, 0.2, { BackgroundColor3 = Color3.fromRGB(16, 16, 24) }) end)

		card.MouseButton1Click:Connect(function()
			modal.Visible = false
			-- Attempt team switch via remote or Teams service, then reset character
			task.spawn(function()
				pcall(function()
					for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
						if remote:IsA("RemoteEvent") and (string.find(string.lower(remote.Name), "team") or string.find(string.lower(remote.Name), "faction")) then
							remote:FireServer(teamName)
						end
					end
					local teams = game:GetService("Teams")
					local targetTeam = teams:FindFirstChild(teamName)
					if targetTeam and LocalPlayer then
						LocalPlayer.Team = targetTeam
					end
				end)
				-- Purely client-sided team state update
				pcall(function()
					Shared.clientTeam = teamName
				end)
				if LocalPlayer.Character then
					local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
					if hum then hum.Health = 0 else LocalPlayer.Character:BreakJoints() end
				end
			end)
		end)
	end

	makeTeamCard(
		40, "Raid", Color3.fromRGB(255, 70, 70),
		"A country of proud rasonians strong both in heart and spirit. The direct successor of Russia they have great power, technology, and soldiers outnumbering most other countries in population."
	)
	makeTeamCard(
		390, "Menlo", Color3.fromRGB(50, 220, 100),
		"Menlo the country that has had fights with the rif directly and has weaker technology and is outnumbered but it doesnt mean they aren't as strong as the rif."
	)

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -16, 0, 16)
	closeBtn.Size = UDim2.fromOffset(32, 32)
	closeBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Parent = container
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

	closeBtn.MouseButton1Click:Connect(function() modal.Visible = false end)
	openBtn.MouseButton1Click:Connect(function() modal.Visible = true end)
end)

---------------------------------------------------------------- 7) layout editor
runSection("7", function()
	local SAVE_FILE = "ui_layout.json"
	local ACCENT = Color3.fromRGB(130, 80, 255)
	local CARD_BG = Color3.fromRGB(20, 20, 27)
	local BTN_BG = Color3.fromRGB(46, 46, 60)
	local STROKE_OFF = Color3.fromRGB(55, 55, 68)

	local function screen()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(800, 450)
		return v.X, v.Y
	end

	local layout = Instance.new("ScreenGui")
	layout.Name = "LayoutEditorGui"
	layout.ResetOnSpawn = false
	layout.IgnoreGuiInset = true
	layout.DisplayOrder = 5
	layout.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	layout.Parent = PlayerGui

	local order = {}
	local scaleFactor = 1
	local editing = false
	local saved = {}
	local deviceKind = nil

	pcall(function()
		if isfile and readfile and isfile(SAVE_FILE) then
			local d = HttpService:JSONDecode(readfile(SAVE_FILE))
			if type(d) == "table" then
				saved = d
				if d.__device == "phone" or d.__device == "tablet" then deviceKind = d.__device end
			end
		end
	end)

	local function curPos(it)
		local W, H = screen()
		local p = it.holder.Position
		return Vector2.new(p.X.Scale * W, p.Y.Scale * H)
	end

	local function setPos(it, p)
		local W, H = screen()
		local sx = it.w * scaleFactor
		local sy = it.h * scaleFactor
		local x = math.clamp(p.X, 0, math.max(W - sx, 0))
		local y = math.clamp(p.Y, 0, math.max(H - sy - it.pad * scaleFactor, 0))
		it.holder.Position = UDim2.fromScale(x / W, y / H)
	end

	local function save()
		if not writefile then return end
		local W, H = screen()
		local t = {}
		for _, it in ipairs(order) do
			local p = curPos(it)
			t[it.key] = { x = p.X / W, y = p.Y / H }
		end
		t.__device = deviceKind
		saved = t
		pcall(writefile, SAVE_FILE, HttpService:JSONEncode(t))
	end

	local function defaultPos(key, W, H, s)
		if key == "esp" then return Vector2.new(0.02 * W, 0.40 * H)
		elseif key == "victim" then return Vector2.new(0.02 * W, 0.40 * H + 56 * s)
		elseif key == "sin" then return Vector2.new(0.02 * W, 0.40 * H + 112 * s)
		elseif key == "exec" then return Vector2.new(0.02 * W, 0.40 * H + 168 * s)
		elseif key == "visor" then return Vector2.new(0.02 * W, 0.40 * H + 224 * s)
		elseif key == "menlo" then return Vector2.new(0.02 * W, 0.40 * H + 280 * s)
		elseif key == "hidehud" then return Vector2.new(0.02 * W, 0.40 * H + 336 * s)
		elseif key == "teams" then return Vector2.new(0.02 * W, 0.40 * H + 392 * s)
		elseif key == "fire" then return Vector2.new(W - 0.02 * W - 220 * s, 0.25 * H - 46 * s)
		elseif key == "sprint" then return Vector2.new(W - 100 * s, H - 220 * s)
		else return Vector2.new(W - 190 * s, H - 220 * s) end
	end

	local function applyAll(useDefaults)
		local W, H = screen()
		for _, it in ipairs(order) do
			it.scale.Scale = scaleFactor
			local s = saved[it.key]
			local p
			if not useDefaults and type(s) == "table" and s.x and s.y then
				p = Vector2.new(s.x * W, s.y * H)
			else
				p = defaultPos(it.key, W, H, scaleFactor)
			end
			setPos(it, p)
		end
	end

	local function makeDraggable(it)
		local overlay = Instance.new("TextButton")
		overlay.Name = "DragOverlay"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = ACCENT
		overlay.BackgroundTransparency = 0.6
		overlay.BorderSizePixel = 0
		overlay.AutoButtonColor = false
		overlay.Text = ""
		overlay.ZIndex = 100
		overlay.Visible = false
		overlay.Parent = it.holder
		Instance.new("UICorner", overlay).CornerRadius = UDim.new(0, 12)

		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(255, 255, 255)
		st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = overlay

		it.overlay = overlay

		local dragging, dragInput, startMouse, startPos = false, nil, nil, nil

		overlay.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging = true
				dragInput = input
				startMouse = Vector2.new(input.Position.X, input.Position.Y)
				startPos = curPos(it)
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
						save()
					end
				end)
			end
		end)

		bind(UIS.InputChanged:Connect(function(input)
			if not dragging or not dragInput then return end
			local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
				and dragInput.UserInputType == Enum.UserInputType.MouseButton1
			if input == dragInput or isMouse then
				local now = Vector2.new(input.Position.X, input.Position.Y)
				setPos(it, startPos + (now - startMouse))
			end
		end))
	end

	local function add(key, main, glow, pad)
		if not main then return end
		local w, h = main.Size.X.Offset, main.Size.Y.Offset

		local holder = Instance.new("Frame")
		holder.Name = "Holder_" .. key
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Size = UDim2.fromOffset(w, h)
		layout = layout
		holder.Parent = layout

		local scale = Instance.new("UIScale")
		scale.Parent = holder

		if glow then
			glow.Parent = holder
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.fromOffset(w / 2, h / 2)
		end

		main.Parent = holder
		main.AnchorPoint = Vector2.new(0, 0)
		main.Position = UDim2.new(0, 0, 0, 0)

		local it = { key = key, holder = holder, scale = scale, w = w, h = h, pad = pad or 0 }
		table.insert(order, it)
		makeDraggable(it)
	end

	local function get(guiName) return PlayerGui:WaitForChild(guiName, 5) end

	local gEsp, gFire, gCombat = get("ESPToggleGui"), get("ViralFistsGUI"), get("CombatControlsGui")
	local gVictim, gSin, gExec = get("VictimAnimGui"), get("SinSwapGui"), get("ExecModeGui")
	local gVisor, gMenlo, gHide, gTeams = get("VisorToggleGui"), get("MenloToggleGui"), get("HideHudGui"), get("TeamSelectGui")

	add("esp", gEsp and gEsp:FindFirstChild("ToggleButton"))
	add("fire", gFire and gFire:FindFirstChildOfClass("Frame"))
	add("victim", gVictim and gVictim:FindFirstChildOfClass("TextButton"))
	add("sin", gSin and gSin:FindFirstChild("SIN"))
	add("exec", gExec and gExec:FindFirstChild("ExecMode"))
	add("visor", gVisor and gVisor:FindFirstChild("VisorToggle"))
	add("menlo", gMenlo and gMenlo:FindFirstChild("MenloToggle"))
	add("hidehud", gHide and gHide:FindFirstChild("HideHudToggle"))
	add("teams", gTeams and gTeams:FindFirstChild("TeamSelectButton"))
	if gCombat then
		add("sprint", gCombat:FindFirstChild("SprintButton"), gCombat:FindFirstChild("SprintButtonGlow"), 34)
		add("swap", gCombat:FindFirstChild("AnimToggleButton"), gCombat:FindFirstChild("AnimToggleButtonGlow"), 34)
	end

	applyAll(false)

	local cam = workspace.CurrentCamera
	if cam then
		bind(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			for _, it in ipairs(order) do setPos(it, curPos(it)) end
		end))
	end

	local function pill(name, text, w, posX)
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(1, 0)
		b.Size = UDim2.fromOffset(w, 26)
		b.Position = UDim2.new(1, posX, 0, 8)
		b.BackgroundColor3 = CARD_BG
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Text = text
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.TextColor3 = Color3.fromRGB(190, 190, 210)
		b.ZIndex = 200
		b.Parent = layout
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		local s = Instance.new("UIStroke")
		s.Thickness = 1.5
		s.Color = STROKE_OFF
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = b
		return b, s
	end

	local editBtn, editStroke = pill("EditToggle", "EDIT", 48, -8)
	local resetBtn = pill("EditReset", "RESET", 54, -62)
	resetBtn.Visible = false

	local function setEditing(on)
		editing = on
		editBtn.Text = on and "LOCK" or "EDIT"
		editBtn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 190, 210)
		editBtn.BackgroundColor3 = on and ACCENT or CARD_BG
		editStroke.Color = on and ACCENT or STROKE_OFF
		resetBtn.Visible = on
		for _, it in ipairs(order) do it.overlay.Visible = on end
		if not on then save() end
	end

	editBtn.Activated:Connect(function() setEditing(not editing) end)
	local function applyDevice(kind)
		local _, H = screen()
		local ref = (kind == "tablet") and 768 or 480
		scaleFactor = math.clamp(H / ref, 0.5, 1.5)
		applyAll(false)
	end

	local function showPrompt()
		if PlayerGui:FindFirstChild("DevicePromptGui") then return end

		local pg = Instance.new("ScreenGui")
		pg.Name = "DevicePromptGui"
		pg.ResetOnSpawn = false
		pg.IgnoreGuiInset = true
		pg.DisplayOrder = 1000
		pg.Parent = PlayerGui

		local dim = Instance.new("Frame")
		dim.Size = UDim2.new(1, 0, 1, 0)
		dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		dim.BackgroundTransparency = 0.45
		dim.BorderSizePixel = 0
		dim.Active = true
		dim.Parent = pg

		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.new(0.5, 0, 0.5, 0)
		box.Size = UDim2.fromOffset(270, 130)
		box.BackgroundColor3 = CARD_BG
		box.BorderSizePixel = 0
		box.Parent = dim
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 14)
		local bs = Instance.new("UIStroke")
		bs.Color = ACCENT
		bs.Thickness = 2
		bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bs.Parent = box

		local ttl = Instance.new("TextLabel")
		ttl.BackgroundTransparency = 1
		ttl.Size = UDim2.new(1, -32, 0, 20)
		ttl.Position = UDim2.new(0, 16, 0, 16)
		ttl.Font = Enum.Font.GothamBold
		ttl.Text = "WHAT DEVICE ARE YOU ON?"
		ttl.TextSize = 13
		ttl.TextColor3 = Color3.fromRGB(240, 240, 248)
		ttl.Parent = box

		local function choice(text, x, kind)
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromOffset(110, 46)
			b.Position = UDim2.new(0, x, 0, 62)
			b.BackgroundColor3 = BTN_BG
			b.BorderSizePixel = 0
			b.AutoButtonColor = true
			b.Text = text
			b.Font = Enum.Font.GothamBold
			b.TextSize = 14
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Parent = box
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
			local s = Instance.new("UIStroke")
			s.Color = ACCENT
			s.Thickness = 1.5
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = b
			b.Activated:Connect(function()
				deviceKind = kind
				applyDevice(kind)
				save()
				pg:Destroy()
			end)
		end

		choice("PHONE", 16, "phone")
		choice("TABLET", 144, "tablet")
	end

	resetBtn.Activated:Connect(function()
		applyAll(true)
		deviceKind = nil
		save()
		showPrompt()
	end)

	applyDevice(deviceKind or "phone")
	showPrompt()
end)
