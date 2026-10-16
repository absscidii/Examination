--[[
	Script v11 = v10 plus:
	* OPTIMIZED (round 2): event-driven thirdperson / reload-stagger (no per-frame polling), sound index for exec muting (no scan at execution start), visibility/heading caches in the visor, cached morph look-lock checks.
	* OPTIMIZED: visor HUD refreshes ~30x/s with cached text/segment writes, idle per-frame loops exit early (Kit.tick, sprint, first-person fix), cached lookups (stamina, hide HUD), lighter lamp scan.
	* SETTINGS: "Mute sound" toggle that silences sound id 105834637703684 (saved with the other settings).
	* SETTINGS: "Mute exec sounds" silences the sounds that start playing when an execution starts (and any that start during it): Volume 0 + roll-off range 0.0001 (section 19).
	* SETTINGS: "Taunt sounds" plays a random RAIDShrouder Exo Charge Taunt1/2/3 sound when you start an execution.
	* SETTINGS: "Hide nametag" removes workspace.Characters.<you>.Head.NameTag (and keeps it removed after respawn); "Instant interact" fires proximity prompts as soon as you start holding them (section 20).
	* SETTINGS: the Morph selector is now a MORPH tab inside the Settings panel (section 17 embeds itself).

	Script v9 = v8 plus:
	* GET INFECTED button (section 16) - tap again while it runs to cancel.
	* THIRDPERSON now only UNLOCKS the camera (zoom + Classic mode); it no longer moves it.
	* RELOAD/STAGGER toggle (section 18): SquadReloadSpeedMultiplier=5000, StaggerImmune=true on workspace.Characters.<you>, re-applied automatically after respawn.
	* HATRED display is now a small pill with a wider value lookup and sits above the game HUD.
	* MORPH GUI v5 merged in (section 17). Its own Third Person toggle was removed (THIRDPERSON button handles it).

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
	"SinSwapGui", "ExecModeGui", "LayoutEditorGui", "DevicePromptGui", "ScriptStatusGui", "ScriptLogGui", "VisorToggleGui", "RifVisorGui", "MenloToggleGui", "MenloVisorGui", "HideHudGui", "TeamSelectGui", "CorpsePlayersGui", "CorpseNpcsGui", "SettingsGui", "ThirdPersonGui", "FullbrightGui", "QteSpamGui", "HatredChanceGui", "GetInfectedGui", "MorphGui", "TeleportGui", "AttrBoostGui",
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
	["5"] = "victim anim", ["6"] = "sin", ["6b"] = "rif visor", ["6c"] = "menlo visor", ["6d"] = "hide game hud", ["7"] = "layout + device prompt", ["8"] = "team selector", ["10"] = "corpse prompt", ["11"] = "settings", ["12"] = "thirdperson", ["13"] = "fullbright", ["14"] = "qte spam", ["15"] = "hatred display", ["16"] = "get infected", ["17"] = "morph gui", ["18"] = "reload/stagger attrs", ["19"] = "exec sounds", ["20"] = "nametag/instant interact",
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

-- feature name -> function that switches that feature off (used by Settings when a button is hidden)
local FeatureHooks = {}
local ExecAudio = { setMute = function() end, setTaunt = function() end } -- filled in by section 19
local Extras = { setNameTag = function() end, setInstant = function() end } -- filled in by section 20

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

function Kit.nearestVictim(myChar, range, npcOnly)
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
		local isPlayerChar = npcOnly and (Players:GetPlayerFromCharacter(c) ~= nil or Players:FindFirstChild(c.Name) ~= nil)
		if c ~= myChar and c:IsA("Model") and not isPlayerChar then
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
	if next(Kit.live) == nil and next(Kit.watching) == nil then return end -- nothing to police
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

bind(RunService.RenderStepped:Connect(Kit.tick))

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
	elseif now - Kit.lastStart < (opt.hitLockout or Kit.HIT_LOCKOUT) then busy = "other started"
	elseif now - Kit.lastEnd < (opt.refractory or Kit.REFRACTORY) then busy = "just ended"
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

-- immediately ends every victim animation started by `owner` (nil = all): restores the muted tracks and stops ours
function Kit.stopVictims(owner)
	for st in pairs(victimActive) do
		if owner == nil or st.owner == owner then
			local tr = st.track
			victimFinish(st, st.token)
			if tr then pcall(function() if tr.IsPlaying then tr:Stop(0.1) end end) end
		end
	end
	for animator, last in pairs(victimLast) do
		if owner == nil or last.owner == owner then victimLast[animator] = nil end
	end
end

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
		victimLast[animator] = { track = track, t = os.clock(), owner = opt.owner }
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
	state.track = track
	state.owner = opt.owner
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
	local FULL_BAR = UDim2.new(1, 0, 1, 0)

	local function isEnabled()
		local Toggles = env.Toggles or rawget(_G, "Toggles")
		local toggle = Toggles and Toggles.inf_stamina_toggle
		if toggle == nil then return true end
		return toggle.Value == true
	end

	local function getBar()
		if cachedBar and cachedBar.Parent then return cachedBar end
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

		local st = cachedStateObj and cachedStateObj.stamina
		if type(st) == "table" then
			st.max = 1000
			st.current = 1000
		end

		local bar = getBar()
		if bar and bar.Size ~= FULL_BAR then bar.Size = FULL_BAR end
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
		if not isSprinting and not sprintTrack.IsPlaying then return end -- idle: nothing to start or stop

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

	local VICTIM_OWNER = "victim"
	local TUNING_OWNED = { speed = TUNING.speed, fadeIn = TUNING.fadeIn, weight = TUNING.weight, owner = VICTIM_OWNER }

	local enabled = false
	local conns = {}
	local lastFire = 0
	local hookToken = 0
	local setVisual = function() end

	local function clearConns()
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end

	local function hookCharacter(char)
		hookToken += 1
		local myToken = hookToken
		clearConns()
		if not enabled then return end -- off = nothing is hooked at all
		local hum = char:WaitForChild("Humanoid", 10)
		local animator = hum and hum:WaitForChild("Animator", 10)
		if not animator or myToken ~= hookToken or not enabled then return end

		Kit.warm(animator, VICTIM_ANIMATION_ID)

		table.insert(conns, animator.AnimationPlayed:Connect(function(track)
			if not enabled or Shared.sin or not Kit.matches(track, TRIGGER_IDS) then return end
			local now = os.clock()
			if now - lastFire < DEBOUNCE then return end
			local victim = Kit.nearestVictim(char, VICTIM_RANGE, true) -- NPCs only, never other players
			if victim then
				lastFire = now
				Kit.playOnVictim(victim, VICTIM_ANIMATION_ID, TUNING_OWNED)
				-- an NPC animation only reaches other players if the game gave YOUR client network ownership of that NPC
				-- (ReceiveAge stays ~0 on parts your client simulates)
				local hrp = victim:FindFirstChild("HumanoidRootPart")
				Kit.log("victim anim on " .. victim.Name .. (hrp and hrp.ReceiveAge < 0.05 and " (you own it: replicates)" or " (server owns it: local only)"))
			end
		end))
	end

	local function setEnabled(on)
		enabled = on and true or false
		if enabled then
			if LocalPlayer.Character then task.spawn(hookCharacter, LocalPlayer.Character) end
		else
			hookToken += 1          -- cancels any hook that is still waiting for the character
			clearConns()            -- no more AnimationPlayed listener
			lastFire = 0
			Kit.stopVictims(VICTIM_OWNER) -- ends a victim animation that is running right now
		end
		return enabled
	end

	bind(LocalPlayer.CharacterAdded:Connect(hookCharacter))
	onCleanup(function()
		enabled = false
		hookToken += 1
		clearConns()
		Kit.stopVictims(VICTIM_OWNER)
	end)

	setVisual = makeToggleCard("VictimAnimGui", "VictimToggle", "VICTIM ANIM", 13, Color3.fromRGB(255, 170, 40), 60, function()
		return setEnabled(not enabled)
	end)

	-- Settings hides this button -> make sure the feature is really off too
	FeatureHooks.victim = function() setEnabled(false); setVisual(false) end
end)

---------------------------------------------------------------- 6) SIN
runSection("6", function()
	local TRIGGER_IDS = {
		"103116263598605", "124609826792133", "123537622120693", "107330587130064",
		"137506764113023",
	}

	local ATTACKER_ANIM   = "rbxassetid://81984907411347"
	local VICTIM_ANIM     = "rbxassetid://133643981640980"
	local ATTACKER_ANIM_2 = "rbxassetid://120793050056416"
	local VICTIM_ANIM_2   = "rbxassetid://132299062878030"
	local EXEC_CHANCE     = 0.5
	local execMode = 4 -- 1 = SIN only, 2 = CLOAKER only, 3 = VISA3 only, 4 = all three

	local EXEC_SOUND   = "rbxassetid://132399674940969"

	-- SIN = pair 1 (ATTACKER_ANIM / VICTIM_ANIM), CLOAKER = pair 2 (ATTACKER_ANIM_2 / VICTIM_ANIM_2)
	-- VISA3 = the new execution:
	local VISA3_ATTACKER_ANIM = "rbxassetid://99375529712653"
	local VISA3_VICTIM_ANIM   = "rbxassetid://84540363335923"
	local VISA3_SOUND         = "rbxassetid://129763735896948"
	local VICTIM_RANGE  = 15
	local EXEC_GAP      = 2    -- seconds the game's execution tracks must be gone before a NEW execution can trigger ours
	local EXEC_MAX_LOCK = 20   -- safety: never stay locked longer than this
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
			hitLockout = 0.12, refractory = 0.05, -- short lockouts so SIN moves can replay right away
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
	local execTrack = nil
	local execLocked = false      -- we already handled the execution that is currently going on
	local execLockedAt = 0
	local triggerIdleSince = nil  -- when the game's execution tracks last went quiet
	env["__SIN_EXECUTION_GUARD_UNTIL"] = nil -- clear the old global lockout left behind by earlier runs
	local ContentProvider = game:GetService("ContentProvider")
	local hookToken = 0
	local rng = Random.new()
	local runTrack, lastRunGood = nil, 0

	local function playSound(parent, soundId)
		local s = Instance.new("Sound")
		s.SoundId = soundId or EXEC_SOUND
		s:SetAttribute("ScriptSound", true) -- so the exec-sound muter leaves our own sound alone
		s.Volume = 1
		s.Parent = parent or Workspace
		s:Play()
		s.Ended:Once(function() s:Destroy() end)
		task.delay(10, function() if s.Parent then s:Destroy() end end)
	end

	local function playOnAttacker(char, animator, original)
		-- the game's own execution is always silenced so only ours shows
		Kit.silence(original, "sin")
		if locoMuted[original] == nil then locoMuted[original] = false end

		local now = os.clock()
		if execLocked and now - execLockedAt > EXEC_MAX_LOCK then execLocked = false end
		if execLocked then return end                          -- same execution, already handled
		if execTrack and execTrack.IsPlaying then return end

		local which = execMode
		if which == 4 then which = rng:NextInteger(1, 3) end -- all three, equal chance

		local attackerId, victimId, soundId
		if which == 1 then -- SIN
			attackerId, victimId, soundId = ATTACKER_ANIM, VICTIM_ANIM, EXEC_SOUND
		elseif which == 2 then -- CLOAKER
			attackerId, victimId, soundId = ATTACKER_ANIM_2, VICTIM_ANIM_2, EXEC_SOUND
		else -- VISA3
			attackerId, victimId, soundId = VISA3_ATTACKER_ANIM, VISA3_VICTIM_ANIM, VISA3_SOUND
		end

		local track = Kit.get(animator, attackerId)
		if not track then return end -- a failed attempt no longer starts a lockout

		-- lock only now that we really are going to play
		execLocked = true
		execLockedAt = now
		triggerIdleSince = nil

		task.spawn(function()
			-- if the clip isn't loaded yet, wait for it so it doesn't start late (after the kill)
			local t0 = os.clock()
			while track.Length <= 0 and os.clock() - t0 < 0.75 do task.wait() end
			if not sinOn then return end

			if track.IsPlaying then track:Stop(0) end
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			execTrack = track
			Kit.claim(track, "exec")
			track:Play(0.05, 1, 1)
			Shared.execUntil = os.clock() + math.max(track.Length, 2) + 1
			track.Stopped:Once(function()
				if execTrack == track then execTrack = nil end
			end)
			playSound(char:FindFirstChild("HumanoidRootPart"), soundId)

			-- the victim may not be in range on the very first frame, so retry briefly
			local victim = Kit.nearestVictim(char, VICTIM_RANGE)
			if not victim then
				for _ = 1, 8 do
					task.wait(0.05)
					victim = Kit.nearestVictim(char, VICTIM_RANGE)
					if victim then break end
				end
			end
			if victim then Kit.playOnVictim(victim, victimId, { fadeIn = 0.05, owner = "sin" }) end
		end)
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
		execLocked, triggerIdleSince = false, nil
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
		execTrack, execLocked, triggerIdleSince = nil, false, nil
		runTrack = nil
		local hum = char:WaitForChild("Humanoid", 10)
		local animator = hum and hum:WaitForChild("Animator", 10)
		if not animator or myToken ~= hookToken then return end

		-- preload clips + sound so the first execution doesn't start late
		task.spawn(function()
			local assets = {}
			for _, id in ipairs({ ATTACKER_ANIM, ATTACKER_ANIM_2, VICTIM_ANIM, VICTIM_ANIM_2, VISA3_ATTACKER_ANIM, VISA3_VICTIM_ANIM }) do
				local a = Instance.new("Animation")
				a.AnimationId = id
				table.insert(assets, a)
			end
			for _, sid in ipairs({ EXEC_SOUND, VISA3_SOUND }) do
				local snd = Instance.new("Sound")
				snd.SoundId = sid
				table.insert(assets, snd)
			end
			pcall(function() ContentProvider:PreloadAsync(assets) end)
			for _, a in ipairs(assets) do a:Destroy() end
		end)

		for _, id in ipairs({ ATTACKER_ANIM, ATTACKER_ANIM_2, VICTIM_ANIM, VICTIM_ANIM_2, VISA3_ATTACKER_ANIM, VISA3_VICTIM_ANIM, RUN_ANIM }) do
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

			local anyTrigger = false
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				if Kit.matches(t, TRIGGER_IDS) then
					anyTrigger = true
					if not handled[t] then onTrack(t) end
				else
					swapMove(animator, t, false)
				end
			end

			-- re-arm for the next execution once the game's execution tracks have been gone for EXEC_GAP
			if anyTrigger or (execTrack and execTrack.IsPlaying) then
				triggerIdleSince = nil
			elseif execLocked then
				triggerIdleSince = triggerIdleSince or os.clock()
				if os.clock() - triggerIdleSince >= EXEC_GAP then
					execLocked = false
					triggerIdleSince = nil
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
		{ label = "SIN ONLY", color = Color3.fromRGB(70, 175, 255) },
		{ label = "CLOAKER ONLY", color = Color3.fromRGB(255, 120, 90) },
		{ label = "VISA3 ONLY", color = Color3.fromRGB(190, 60, 255) },
		{ label = "ALL THREE", color = Color3.fromRGB(46, 230, 130) },
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
	local VISOR_STEP = 1 / 30 - 0.002 -- the HUD refreshes ~30x/s instead of every frame
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

	local adaptEpoch = 0 -- bumped when the palette is re-applied, so cached segment colours get rewritten
	local adaptCur, adaptTarget, adaptApplied, lightAcc, lightLevel = 0, 0, 0, 1, 1
	local function applyAdapt(k)
		adaptEpoch += 1
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
		if lightAcc >= 0.5 then
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

	local textCache = setmetatable({}, { __mode = "k" })
	local function setText(o, str)
		if textCache[o] ~= str then
			textCache[o] = str
			o.Text = str
		end
	end
	local hpCache, thCache = {}, {}
	local tapeHeading, lastVig = nil, nil
	local visCache = setmetatable({}, { __mode = "k" })
	local function setVis(o, v)
		if visCache[o] ~= v then
			visCache[o] = v
			o.Visible = v
		end
	end
	local function setSeg(cache, i, sg, col, tr)
		local c = cache[i]
		if not c then c = {} cache[i] = c end
		if c.col ~= col or c.epoch ~= adaptEpoch then
			c.col, c.epoch = col, adaptEpoch
			sg.BackgroundColor3 = col
		end
		if c.tr ~= tr then
			c.tr = tr
			sg.BackgroundTransparency = tr
		end
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
		setText(headingText, string.format("%03d  %s", math.floor(heading + 0.5), CARDINALS[(math.floor((heading + 22.5) / 45) % 8) + 1]))

		if tapeHeading == nil or math.abs(((heading - tapeHeading + 540) % 360) - 180) >= 0.3 then
			tapeHeading = heading
			local base = math.floor(heading / 15) * 15
			for k = 1, 15 do
				local a = base + (k - 8) * 15
				local delta = ((a - heading + 540) % 360) - 180
				local tk = tapeTicks[k]
				local x = TAPE_W / 2 + delta / 90 * (TAPE_W / 2)
				if math.abs(delta) <= 88 then
					local ang = a % 360
					local major = (ang % 45 == 0)
					setVis(tk.tick, true)
					tk.tick.Size = UDim2.fromOffset(major and 2 or 1, major and 11 or 6)
					tk.tick.Position = UDim2.new(0, x, 1, -1)
					setVis(tk.txt, major)
					if major then
						setText(tk.txt, CARDINALS[(ang // 45) + 1])
						tk.txt.Position = UDim2.fromOffset(x, 1)
					end
				else
					setVis(tk.tick, false)
					setVis(tk.txt, false)
				end
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
			setText(bannerText, scramble(cfg.bootText, (now - bootStart) / 1.4))
			bannerText.TextColor3 = ICE
			bannerStroke.Color = ICE
			bannerText.TextTransparency = 0
		elseif critical then
			setText(bannerText, extreme and "!!  EXTREME THREAT  !!" or "!  DANGEROUS HOSTILE  !")
			bannerText.TextColor3 = RED
			bannerStroke.Color = RED
			bannerText.TextTransparency = (math.sin(now * (extreme and 14 or 7)) > 0) and 0 or 0.65
		elseif nearest then
			setText(bannerText, "HOSTILE CONTACT  x" .. count)
			bannerText.TextColor3 = levelColor
			bannerStroke.Color = levelColor
			bannerText.TextTransparency = 0
		else
			setText(bannerText, "AREA CLEAR")
			bannerText.TextColor3 = ICE
			bannerStroke.Color = P.clear
			bannerText.TextTransparency = 0
		end

		local age = now - ticker.t0
		if age < 4 then
			local shown = math.floor(#ticker.text * math.min(1, age / 0.5))
			setText(tickerLabel, string.sub(ticker.text, 1, shown) .. ((age < 0.5) and "_" or ""))
			tickerLabel.TextTransparency = (age > 3) and (age - 3) or 0
		else
			setText(tickerLabel, "")
		end

		local pulse = 0
		if extreme then pulse = 0.5 + 0.5 * math.sin(now * 9)
		elseif critical then pulse = 0.5 * (0.5 + 0.5 * math.sin(now * 5)) end
		local vt = 0.3 - 0.25 * pulse
		if vt ~= lastVig then
			lastVig = vt
			for _, f in ipairs(vig) do f.BackgroundTransparency = vt end
		end
		local tv = (RETRO and 0.88 or 0.93) - 0.1 * pulse - 0.06 * adaptCur
		if RETRO then
			tv = tv - 0.04 - 0.02 * math.sin(now * 41) - ((math.random() < 0.025) and 0.05 or 0)
		end
		tint.BackgroundTransparency = tv

		setVis(rearWarn, rearActive)
		if rearActive then
			local flash = (math.sin(now * (rearInc and 16 or 9)) > 0)
			setText(rearText, string.format(rearInc and "!!  INCOMING FROM BEHIND  %dm  !!" or "!!  ENEMY BEHIND  %dm  !!", math.floor(rearD + 0.5)))
			rearText.TextColor3 = RED
			rearText.TextTransparency = flash and 0 or 0.55
			rearStroke.Color = RED
			vig[2].BackgroundTransparency = 0.12 + 0.3 * (0.5 + 0.5 * math.sin(now * 12))
			lastVig = nil -- the normal vignette value gets rewritten once the warning ends
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
					setVis(arrow, true)
					atext.Position = UDim2.fromOffset(
						sz.X / 2 + (ringR + 20) * math.sin(theta), sz.Y / 2 - (ringR + 20) * math.cos(theta)
					)
					setText(atext, math.floor(t.dist + 0.5) .. "m")
					atext.TextColor3 = col
					setVis(atext, true)
				else
					setVis(arrow, false)
					setVis(atext, false)
				end
				local deg = math.deg(theta)
				if mark and math.abs(deg) <= 88 then
					mark.Position = UDim2.new(0, TAPE_W / 2 + deg / 90 * (TAPE_W / 2), 1, -1)
					mark.BackgroundColor3 = col
					setVis(mark, true)
				elseif mark then
					setVis(mark, false)
				end
			else
				setVis(arrow, false)
				setVis(atext, false)
				if mark then setVis(mark, false) end
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
					setVis(md.dot, true)
				else
					setVis(md.dot, false)
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
				setText(lockText, string.format("%s  %dm", string.upper(nearest.model.Name), math.floor(nearest.dist + 0.5)))
				lockHp.Size = UDim2.fromScale(frac, 1)
				setVis(lockBox, true)
			else
				setVis(lockBox, false)
			end
			setText(reticleText, string.format("TARGET LOCKED\n%s   HP %d%%", string.upper(nearest.model.Name), math.floor(frac * 100 + 0.5)))
			reticleText.TextColor3 = RED
			coreStroke.Color = RED
			outerStroke.Color = RED
		else
			setVis(lockBox, false)
			setText(reticleText, nearest and "TRACKING..." or "NO CONTACTS")
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
				setSeg(hpCache, i, sg, (hpFrac > 0.35) and RED or AMBER, (i == hpLit) and (0.15 + 0.25 * math.sin(now * 6)) or 0)
			else
				setSeg(hpCache, i, sg, P.barBack, 0)
			end
		end
		local thFrac = topTarget and math.clamp(topHp / THREAT_BAR_MAX, 0, 1) or 0
		local thLit = math.floor(thFrac * SEGS + 0.5)
		if topTarget and thLit < 1 then thLit = 1 end
		for i = 1, SEGS do
			local sg = thSegs[i]
			if i <= thLit then
				setSeg(thCache, i, sg, levelColor, (extreme and (math.sin(now * 14 + i) > 0)) and 0.5 or 0)
			else
				setSeg(thCache, i, sg, P.barBack, 0)
			end
		end
		setText(hpText, string.format("VITALS %d%%", math.floor(hpFrac * 100 + 0.5)))
		setText(thText, "THREAT " .. level)
		thText.TextColor3 = levelColor
		local vel = myRoot.AssemblyLinearVelocity
		local spd = Vector3.new(vel.X, 0, vel.Z).Magnitude
		setText(statsText, string.format(
			"SPD %04.1f  ALT %d\nHOSTILES %d  HP %s", spd, math.floor(myRoot.Position.Y + 0.5), count,
			topTarget and tostring(math.floor(topHp + 0.5)) or "--"
		))
		if ADAPT_ON and adaptCur > 0.04 then
			setText(adaptText, string.format("LOW-LIGHT ENHANCE  %d%%", math.floor(adaptCur * 100 + 0.5)))
		else
			setText(adaptText, "")
		end
		for i = 1, 3 do
			local t = targets[i]
			local chip = chips[i]
			if t and t.hrp.Parent then
				local frac = math.clamp(t.hum.Health / math.max(t.hum.MaxHealth, 1), 0, 1)
				setText(chip.text, string.format(
					"%02d  %s  %dm  %d%%", i, string.sub(string.upper(t.model.Name), 1, 8),
					math.floor(t.dist + 0.5), math.floor(frac * 100 + 0.5)
				))
				chip.accent.BackgroundColor3 = kindColor(t)
				chip.frame.BackgroundTransparency = (t.dist <= WARN_RANGE and critical) and (0.45 + 0.35 * math.sin(now * 10)) or 0.2
			else
				setText(chip.text, string.format("%02d --", i))
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
			local acc = VISOR_STEP -- draw the first frame right away
			renderConn = RunService.RenderStepped:Connect(function(dt)
				acc += dt
				if acc < VISOR_STEP then return end
				local step = acc
				acc = 0
				local ok, err = pcall(update, step)
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

	local found = {}
	local function resolve(i, find)
		local o = found[i]
		if o and o.Parent then return o end
		o = find()
		found[i] = o
		return o
	end

	local function hide()
		for i, find in ipairs(finders) do
			local o = resolve(i, find)
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
		for i, find in ipairs(finders) do
			local o = resolve(i, find)
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

---------------------------------------------------------------- 10) corpse prompt (players / NPCs)
runSection("10", function()
	local OFFSET = Vector3.new(0, -4, 0)  -- how far below the torso to stand
	local SCAN_DELAY = 1                  -- seconds between scans
	local PROMPT_COOLDOWN = 4             -- seconds before retrying a prompt that failed
	local ARRIVE_WAIT = 0.4               -- wait after teleporting, before first fire
	local RETRY_DELAY = 0.5               -- seconds between fire attempts
	local FIRE_TIMEOUT = 8                -- give up on a prompt after this many seconds
	local RETURN_WAIT = 0.2               -- wait after the prompt is gone, before returning
	local BETWEEN_TARGETS = 0.8           -- pause between corpses
	local NPC_NAME = "slasher"            -- NPC models whose name contains this (case-insensitive)
	local TORSO_NAMES = { "Torso", "UpperTorso", "HumanoidRootPart" }

	local playersOn, npcsOn = false, false
	local alive = true
	local lastFired = setmetatable({}, { __mode = "k" })

	onCleanup(function() alive = false; playersOn = false; npcsOn = false end)

	local function getRoot()
		local char = LocalPlayer.Character
		return char and char:FindFirstChild("HumanoidRootPart")
	end

	local function getTorso(model)
		for _, name in ipairs(TORSO_NAMES) do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then return part end
		end
	end

	local function isPlayerModel(model)
		if Players:GetPlayerFromCharacter(model) then return true end
		local match = Players:FindFirstChild(model.Name)
		return match ~= nil and match:IsA("Player")
	end

	local function isDead(model, fromCharacters)
		if model == LocalPlayer.Character then return false end
		if not fromCharacters then return true end -- anything in PlayerCorpses counts
		local hum = model:FindFirstChildOfClass("Humanoid")
		return hum ~= nil and hum.Health <= 0
	end

	local function collectTargets()
		local targets = {}
		local function scan(folder, fromCharacters)
			if not folder then return end
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") and isDead(model, fromCharacters) then
					local isPlr = isPlayerModel(model)
					local isNpc = not isPlr and string.find(string.lower(model.Name), NPC_NAME, 1, true) ~= nil
					if (isPlr and playersOn) or (isNpc and npcsOn) then
						local torso = getTorso(model)
						local prompt = torso and torso:FindFirstChildOfClass("ProximityPrompt")
						if prompt and prompt.Enabled then
							table.insert(targets, { torso = torso, prompt = prompt })
						end
					end
				end
			end
		end
		scan(Workspace:FindFirstChild("Characters"), true)
		scan(Workspace:FindFirstChild("PlayerCorpses"), false)
		return targets
	end

	local function promptGone(prompt)
		return prompt.Parent == nil or not prompt:IsDescendantOf(Workspace) or not prompt.Enabled
	end

	local function firePrompt(prompt)
		if fireproximityprompt then
			fireproximityprompt(prompt)
		else
			prompt:InputHoldBegin()
			task.wait(prompt.HoldDuration + 0.05)
			prompt:InputHoldEnd()
		end
	end

	-- Teleport under the body, freeze there, fire until the prompt is gone, go back
	local function lootTarget(target)
		local root = getRoot()
		if not root then return end
		local backCFrame = root.CFrame

		local lock = RunService.Heartbeat:Connect(function()
			local r = getRoot()
			if r and target.torso.Parent then
				r.CFrame = target.torso.CFrame + OFFSET
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end
		end)

		task.wait(ARRIVE_WAIT)

		local started = os.clock()
		while alive and not promptGone(target.prompt)
			and (playersOn or npcsOn)
			and getRoot()
			and os.clock() - started < FIRE_TIMEOUT do
			firePrompt(target.prompt)
			task.wait(RETRY_DELAY)
		end

		lock:Disconnect()
		lastFired[target.prompt] = os.clock()
		task.wait(RETURN_WAIT)

		local currentRoot = getRoot()
		if currentRoot then
			currentRoot.CFrame = backCFrame
			currentRoot.AssemblyLinearVelocity = Vector3.zero
		end
	end

	task.spawn(function()
		while alive do
			task.wait(SCAN_DELAY)
			if not (playersOn or npcsOn) then continue end

			for _, target in ipairs(collectTargets()) do
				if not alive or not (playersOn or npcsOn) then break end
				if not getRoot() then break end

				local last = lastFired[target.prompt]
				if not promptGone(target.prompt) and (not last or os.clock() - last >= PROMPT_COOLDOWN) then
					lootTarget(target)
					task.wait(BETWEEN_TARGETS)
				end
			end
		end
	end)

	local setVisPlayers, setVisNpcs
	setVisPlayers = makeToggleCard("CorpsePlayersGui", "CorpsePlayersToggle", "LOOT PLAYERS", 11, Color3.fromRGB(255, 120, 80), 536, function()
		playersOn = not playersOn
		return playersOn
	end)
	setVisNpcs = makeToggleCard("CorpseNpcsGui", "CorpseNpcsToggle", "LOOT NPCS", 11, Color3.fromRGB(255, 80, 120), 592, function()
		npcsOn = not npcsOn
		return npcsOn
	end)

	FeatureHooks.corpse_players = function() playersOn = false; setVisPlayers(false) end
	FeatureHooks.corpse_npcs = function() npcsOn = false; setVisNpcs(false) end
end)

---------------------------------------------------------------- 12) thirdperson (first person still reachable by zooming in)
runSection("12", function()
	-- THIRDPERSON now only UNLOCKS the camera (zoom range + Classic mode).
	-- It never moves the camera: you scroll / pinch out yourself.
	local MIN_ZOOM = 0.5
	local MAX_ZOOM = 128

	local on = false
	local conn, charConn = nil, nil
	local saved = nil

	local function unlock()
		if LocalPlayer.CameraMode ~= Enum.CameraMode.Classic then
			LocalPlayer.CameraMode = Enum.CameraMode.Classic
		end
		if LocalPlayer.CameraMinZoomDistance > MIN_ZOOM then
			LocalPlayer.CameraMinZoomDistance = MIN_ZOOM
		end
		if LocalPlayer.CameraMaxZoomDistance < MAX_ZOOM then
			LocalPlayer.CameraMaxZoomDistance = MAX_ZOOM
		end
	end

	local function react()
		if on then pcall(unlock) end
	end
	local function dropConn()
		if conn then
			for _, c in ipairs(conn) do c:Disconnect() end
			conn = nil
		end
	end

	local function setOn(state)
		if state == on then return end
		on = state
		dropConn()
		if charConn then charConn:Disconnect(); charConn = nil end
		if on then
			saved = {
				mode = LocalPlayer.CameraMode,
				min = LocalPlayer.CameraMinZoomDistance,
				max = LocalPlayer.CameraMaxZoomDistance,
			}
			pcall(unlock)
			-- keeps the game from re-locking the camera
			conn = {
				LocalPlayer:GetPropertyChangedSignal("CameraMode"):Connect(react),
				LocalPlayer:GetPropertyChangedSignal("CameraMinZoomDistance"):Connect(react),
				LocalPlayer:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(react),
			}
			charConn = LocalPlayer.CharacterAdded:Connect(function()
				task.wait(0.5)
				if on then pcall(unlock) end
			end)
		elseif saved then
			pcall(function()
				LocalPlayer.CameraMaxZoomDistance = saved.max
				LocalPlayer.CameraMinZoomDistance = saved.min
				LocalPlayer.CameraMode = saved.mode
			end)
			saved = nil
		end
	end
	onCleanup(function() setOn(false) end)

	local setVisual
	setVisual = makeToggleCard("ThirdPersonGui", "ThirdPersonToggle", "THIRDPERSON", 11, Color3.fromRGB(90, 200, 255), 648, function()
		setOn(not on)
		return on
	end)
	FeatureHooks.thirdperson = function() setOn(false); setVisual(false) end
end)

---------------------------------------------------------------- 13) fullbright loop
runSection("13", function()
	local TARGET = {
		Brightness = 2,
		ClockTime = 14,
		FogEnd = 1e6,
		GlobalShadows = false,
		Ambient = Color3.new(1, 1, 1),
		OutdoorAmbient = Color3.new(1, 1, 1),
	}
	local ATMOS_CHECK = 0.5   -- seconds between atmosphere scans (keeps the loop cheap)

	local on = false
	local conn = nil
	local saved = nil
	local atmos = {}          -- Atmosphere -> original Density / Haze
	local lastAtmos = 0

	-- only writes a property when the game changed it back, so it costs almost nothing per frame
	local function enforce()
		for prop, value in pairs(TARGET) do
			if Lighting[prop] ~= value then Lighting[prop] = value end
		end
		local now = os.clock()
		if now - lastAtmos >= ATMOS_CHECK then
			lastAtmos = now
			for _, c in ipairs(Lighting:GetChildren()) do
				if c:IsA("Atmosphere") then
					if not atmos[c] then atmos[c] = { Density = c.Density, Haze = c.Haze } end
					if c.Density ~= 0 then c.Density = 0 end
					if c.Haze ~= 0 then c.Haze = 0 end
				end
			end
		end
	end

	local function setOn(state)
		if state == on then return end
		on = state
		if conn then conn:Disconnect(); conn = nil end
		if on then
			saved = {}
			for prop in pairs(TARGET) do saved[prop] = Lighting[prop] end
			lastAtmos = 0
			enforce()
			conn = RunService.RenderStepped:Connect(enforce)
		else
			if saved then
				for prop, value in pairs(saved) do pcall(function() Lighting[prop] = value end) end
				saved = nil
			end
			for c, orig in pairs(atmos) do
				if c.Parent then
					c.Density = orig.Density
					c.Haze = orig.Haze
				end
			end
			table.clear(atmos)
		end
	end
	onCleanup(function() setOn(false) end)

	local setVisual
	setVisual = makeToggleCard("FullbrightGui", "FullbrightToggle", "FULLBRIGHT", 12, Color3.fromRGB(255, 240, 120), 704, function()
		setOn(not on)
		return on
	end)
	FeatureHooks.fullbright = function() setOn(false); setVisual(false) end
end)

---------------------------------------------------------------- 14) QTE spam (every key)
runSection("14", function()
	-- Tuning: remote fires per Heartbeat frame. 2 per frame cycles all keys in ~0.3s without lag.
	local FIRES_PER_FRAME = 2
	-- If a frame takes longer than this (client hitching), skip it so the remote queue can't pile up.
	local MAX_DT = 0.1
	local KEYS = {
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
		"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
		"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	}
	local KEY_COUNT = #KEYS

	local remote, fire, conn = nil, nil, nil
	local idx = 0

	local function resolve()
		local events = ReplicatedStorage:FindFirstChild("Events")
		remote = events and events:FindFirstChild("QTEResult")
		fire = remote and remote.FireServer or nil
		return fire ~= nil
	end

	-- Defined once, so enabling/disabling never allocates a new closure per frame.
	local function step(dt)
		if dt > MAX_DT then return end
		if not (remote and remote.Parent) and not resolve() then return end
		for _ = 1, FIRES_PER_FRAME do
			idx = idx % KEY_COUNT + 1
			fire(remote, KEYS[idx])
		end
	end

	local function setActive(on)
		if on then
			if conn then return true end
			if not resolve() then return false end
			conn = RunService.Heartbeat:Connect(step)
			return true
		elseif conn then
			conn:Disconnect()
			conn = nil
		end
		return true
	end
	onCleanup(function() setActive(false) end)

	local active = false
	local setVisual
	setVisual = makeToggleCard("QteSpamGui", "QteSpamToggle", "QTE SPAM", 13, Color3.fromRGB(255, 150, 60), 760, function()
		local want = not active
		if want and not setActive(true) then
			warn("[Script] QTE spam: ReplicatedStorage.Events.QTEResult not found")
			return false
		end
		if not want then setActive(false) end
		active = want
		return active
	end)
	FeatureHooks.qte = function() active = false; setActive(false); setVisual(false) end
end)

---------------------------------------------------------------- 15) HatredChance display (small pill)
runSection("15", function()
	local POLL = 0.2   -- seconds between reads (only touches the UI when the text changes)
	local NAME = "HatredChance"

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatredChanceGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2100
	gui.Parent = PlayerGui

	local card = Instance.new("Frame")
	card.Name = "HatredChanceDisplay"
	card.Size = UDim2.new(0, 104, 0, 30)
	card.Position = UDim2.new(0.5, 160, 0, 8)
	card.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	card.BackgroundTransparency = 0.25
	card.BorderSizePixel = 0
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 80, 80)
	stroke.Thickness = 1
	stroke.Transparency = 0.25
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -24, 0, 10)
	title.Position = UDim2.new(0, 12, 0, 3)
	title.Font = Enum.Font.GothamMedium
	title.Text = "HATRED CHANCE"
	title.TextSize = 8
	title.TextColor3 = GREY_TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(1, -24, 0, 15)
	valueLabel.Position = UDim2.new(0, 12, 0, 12)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.Text = "--"
	valueLabel.TextSize = 13
	valueLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.Parent = card

	local function lookup(holder)
		if not holder then return nil end
		local obj = holder:FindFirstChild(NAME) or holder:FindFirstChild(NAME, true)
		if obj and obj:IsA("ValueBase") then return obj.Value end
		local attr = holder:GetAttribute(NAME)
		if attr ~= nil then return attr end
		return nil
	end

	-- workspace.Characters.<your name>.HatredChance, then your character, then your Player
	local function readValue()
		local folder = Workspace:FindFirstChild("Characters")
		local v = lookup(folder and folder:FindFirstChild(LocalPlayer.Name))
		if v == nil then v = lookup(LocalPlayer.Character) end
		if v == nil then v = lookup(LocalPlayer) end
		return v
	end

	local function fmt(v)
		if v == nil then return "N/A" end
		if type(v) == "number" then
			if v == math.floor(v) then return tostring(v) end
			return string.format("%.2f", v)
		end
		return tostring(v)
	end

	local alive = true
	onCleanup(function() alive = false end)

	task.spawn(function()
		local last = nil
		while alive do
			local ok, text = pcall(function() return fmt(readValue()) end)
			if not ok then text = "N/A" end
			if text ~= last then
				last = text
				valueLabel.Text = text
			end
			task.wait(POLL)
		end
	end)
end)

---------------------------------------------------------------- 16) get infected
runSection("16", function()
	local FINAL_TARGET_CFRAME = CFrame.new(-256.080963, -20.1576881, -769.15863, -0.863753378, -0.496257395, 0.0875138789, 7.76850761e-09, 0.173668012, 0.984804273, -0.503914773, 0.850628018, -0.150006339)
	local SWITCH_HEALTH = 50   -- at or below this, stop following the mutant and sit at the final spot
	local END_HEALTH = 10      -- at or below this, the sequence ends and you are sent back
	local ACCENT = Color3.fromRGB(255, 110, 60)
	local STROKE_OFF = Color3.fromRGB(235, 235, 240)

	local running = false
	local stopCurrent = nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "GetInfectedGui"
	gui.ResetOnSpawn = false
	gui.Parent = PlayerGui

	local card = Instance.new("TextButton")
	card.Name = "GetInfectedButton"
	card.Size = UDim2.new(0, 156, 0, 46)
	card.Position = UDim2.new(0.02, 168, 0.45, 280)
	card.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
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
	title.Size = UDim2.new(0, 110, 0, 18)
	title.Position = UDim2.new(0, 20, 0, 7)
	title.Font = Enum.Font.GothamMedium
	title.Text = "GET INFECTED"
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(240, 240, 248)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(0, 110, 0, 14)
	status.Position = UDim2.new(0, 20, 0, 25)
	status.Font = Enum.Font.GothamMedium
	status.Text = "READY"
	status.TextSize = 10
	status.TextColor3 = GREY_TEXT
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = card

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(1, 0.5)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.Position = UDim2.new(1, -18, 0.5, 0)
	dot.BackgroundColor3 = Color3.fromRGB(70, 70, 76)
	dot.BorderSizePixel = 0
	dot.Parent = card
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

	local function setVisual(on)
		tween(stroke, 0.2, { Color = on and ACCENT or STROKE_OFF, Transparency = on and 0.05 or 0.55 })
		tween(dot, 0.2, { BackgroundColor3 = on and ACCENT or Color3.fromRGB(70, 70, 76) })
		tween(status, 0.2, { TextColor3 = on and ACCENT or GREY_TEXT })
		status.Text = on and "RUNNING - TAP TO STOP" or "READY"
	end

	card.MouseEnter:Connect(function() tween(scale, 0.12, { Scale = 1.05 }) end)
	card.MouseLeave:Connect(function() tween(scale, 0.12, { Scale = 1 }) end)
	card.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = 0.95 }) end)
	card.MouseButton1Up:Connect(function() tween(scale, 0.1, { Scale = 1.05 }) end)

	-- first living Mutant1..Mutant10 in workspace.Characters
	local function getMutantCFrame()
		local charactersFolder = Workspace:FindFirstChild("Characters")
		if not charactersFolder then return nil end
		for _, child in ipairs(charactersFolder:GetChildren()) do
			local mutantNum = string.match(child.Name, "^Mutant(%d+)$")
			if mutantNum then
				local num = tonumber(mutantNum)
				if num and num >= 1 and num <= 10 then
					if child:IsA("Model") then
						local humanoid = child:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid.Health > 0 then
							return child:GetPivot()
						end
					elseif child:IsA("BasePart") then
						return child.CFrame
					end
				end
			end
		end
		return nil
	end

	local function start()
		if running then return end

		local character = LocalPlayer.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not rootPart or humanoid.Health <= END_HEALTH then return end

		running = true
		setVisual(true)

		local savedCFrame = rootPart.CFrame
		local connections = {}
		local phase = (humanoid.Health > SWITCH_HEALTH) and "MUTANT" or "CFRAME"
		local finished = false

		local function finish()
			if finished then return end
			finished = true
			for _, c in ipairs(connections) do c:Disconnect() end
			table.clear(connections)

			if character and character:IsDescendantOf(Workspace) and rootPart.Parent then
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
				character:PivotTo(savedCFrame)
			end

			running = false
			stopCurrent = nil
			setVisual(false)
		end
		stopCurrent = finish

		local function forcePosition()
			if not (character and character:IsDescendantOf(Workspace) and rootPart.Parent) then return end
			local target = FINAL_TARGET_CFRAME
			if phase == "MUTANT" then
				target = getMutantCFrame() or FINAL_TARGET_CFRAME
			end
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			rootPart.CFrame = target
			character:PivotTo(target)
		end

		for _, signalName in ipairs({ "PreRender", "PreSimulation", "PostSimulation" }) do
			local ok, c = pcall(function() return RunService[signalName]:Connect(forcePosition) end)
			if ok and c then table.insert(connections, c) end
		end

		table.insert(connections, humanoid.HealthChanged:Connect(function(hp)
			if hp <= END_HEALTH then
				finish()
			elseif hp <= SWITCH_HEALTH and phase == "MUTANT" then
				phase = "CFRAME"
			end
		end))
		table.insert(connections, humanoid.Died:Connect(finish))
		table.insert(connections, character.AncestryChanged:Connect(function(_, parent)
			if not parent then finish() end
		end))
	end

	card.MouseButton1Click:Connect(function()
		if running then
			if stopCurrent then stopCurrent() end
		else
			start()
		end
	end)

	onCleanup(function() if stopCurrent then stopCurrent() end end)
	FeatureHooks.infect = function() if stopCurrent then stopCurrent() end end
end)

---------------------------------------------------------------- 18) reload / stagger attributes
runSection("18", function()
	local ATTRS = {
		SquadReloadSpeedMultiplier = 5000,
		StaggerImmune = true,
	}

	local on = false
	local conn = nil
	local model = nil
	local originals = {}
	local attrConn = nil

	-- workspace.Characters.<your name>, falling back to your live character
	local function findModel()
		local folder = Workspace:FindFirstChild("Characters")
		local m = folder and folder:FindFirstChild(LocalPlayer.Name)
		if m and m:IsA("Model") then return m end
		return LocalPlayer.Character
	end

	local function restore(m)
		if not (m and m.Parent) then return end
		for name in pairs(ATTRS) do
			pcall(function() m:SetAttribute(name, originals[name]) end)
		end
	end

	-- Runs every frame while ON. When the model changes (respawn / reset) it
	-- "refreshes": remembers the new model's original values and re-applies.
	local function step()
		local m = findModel()
		if not m then return end
		if m ~= model then
			model = m
			originals = {}
			for name in pairs(ATTRS) do originals[name] = m:GetAttribute(name) end
			if attrConn then attrConn:Disconnect() end
			-- re-apply the moment the game changes one of the values
			attrConn = m.AttributeChanged:Connect(function(name)
				local want = ATTRS[name]
				if want ~= nil and on and m:GetAttribute(name) ~= want then m:SetAttribute(name, want) end
			end)
		end
		for name, value in pairs(ATTRS) do
			if m:GetAttribute(name) ~= value then
				m:SetAttribute(name, value)
			end
		end
	end

	local function setOn(state)
		if state == on then return end
		on = state
		if conn then conn:Disconnect(); conn = nil end
		if on then
			local acc = 0.2
			conn = RunService.Heartbeat:Connect(function(dt)
				acc += dt
				if acc < 0.2 then return end -- model changes (respawn) are found within 0.2s
				acc = 0
				pcall(step)
			end)
		else
			if attrConn then attrConn:Disconnect() attrConn = nil end
			restore(model)
			model = nil
			originals = {}
		end
	end
	onCleanup(function() setOn(false) end)

	local setVisual
	setVisual = makeToggleCard("AttrBoostGui", "AttrBoostToggle", "RELOAD/STAGGER", 10, Color3.fromRGB(120, 255, 170), 816, function()
		setOn(not on)
		return on
	end)
	FeatureHooks.attrboost = function() setOn(false); setVisual(false) end
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
	layout.DisplayOrder = 150
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
		elseif key == "corpse_players" then return Vector2.new(0.02 * W + 168 * s, 0.40 * H)
		elseif key == "corpse_npcs" then return Vector2.new(0.02 * W + 168 * s, 0.40 * H + 56 * s)
		elseif key == "thirdperson" then return Vector2.new(0.02 * W + 168 * s, 0.40 * H + 112 * s)
		elseif key == "fullbright" then return Vector2.new(0.02 * W + 168 * s, 0.40 * H + 168 * s)
		elseif key == "qte" then return Vector2.new(0.02 * W + 168 * s, 0.40 * H + 224 * s)
		elseif key == "infect" then return Vector2.new(0.02 * W + 168 * s, 0.40 * H + 280 * s)
		elseif key == "hatred" then return Vector2.new(W / 2 + 160 * s, 8 * s)
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
	local gCorpseP, gCorpseN = get("CorpsePlayersGui"), get("CorpseNpcsGui")
	local gTP, gFB, gQTE = get("ThirdPersonGui"), get("FullbrightGui"), get("QteSpamGui")
	local gHatred = get("HatredChanceGui")
	local gInfect = get("GetInfectedGui")
	local gAttr = get("AttrBoostGui")

	add("esp", gEsp and gEsp:FindFirstChild("ToggleButton"))
	add("fire", gFire and gFire:FindFirstChildOfClass("Frame"))
	add("victim", gVictim and gVictim:FindFirstChildOfClass("TextButton"))
	add("sin", gSin and gSin:FindFirstChild("SIN"))
	add("exec", gExec and gExec:FindFirstChild("ExecMode"))
	add("visor", gVisor and gVisor:FindFirstChild("VisorToggle"))
	add("menlo", gMenlo and gMenlo:FindFirstChild("MenloToggle"))
	add("hidehud", gHide and gHide:FindFirstChild("HideHudToggle"))
	add("teams", gTeams and gTeams:FindFirstChild("TeamSelectButton"))
	add("corpse_players", gCorpseP and gCorpseP:FindFirstChild("CorpsePlayersToggle"))
	add("corpse_npcs", gCorpseN and gCorpseN:FindFirstChild("CorpseNpcsToggle"))
	add("thirdperson", gTP and gTP:FindFirstChild("ThirdPersonToggle"))
	add("fullbright", gFB and gFB:FindFirstChild("FullbrightToggle"))
	add("qte", gQTE and gQTE:FindFirstChild("QteSpamToggle"))
	add("hatred", gHatred and gHatred:FindFirstChild("HatredChanceDisplay"))
	add("infect", gInfect and gInfect:FindFirstChild("GetInfectedButton"))
	add("attrboost", gAttr and gAttr:FindFirstChild("AttrBoostToggle"))
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

---------------------------------------------------------------- 19) execution sounds (mute the game's own + taunt sound)
runSection("19", function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local SoundService = game:GetService("SoundService")

	local TRIGGER_IDS = {
		"103116263598605", "124609826792133", "123537622120693", "107330587130064",
		"137506764113023",
	}
	local TAIL = 2.5          -- seconds the muter stays active after the game's execution track is gone
	local NEW_EXEC_GAP = 1.0  -- a trigger track this long after the last one counts as a NEW execution
	local DEBUG = true        -- prints every sound it silences, so you can see what the game plays
	local TINY_RANGE = 0.0001 -- muted sounds get this roll-off range (they play right at you, so nothing is left to hear)
	local START_GRACE = 0.75  -- a sound already playing when the execution starts counts as part of it if it began within this many seconds
	local TAUNT_PATH = { "ClassModels", "DEV FOLDER", "DEV MORPH", "RAIDShrouder", "Tools", "Exo Charge", "Sounds" }
	local TAUNT_NAMES = { "Taunt1", "Taunt2", "Taunt3" }

	local muteOn, tauntOn = false, false
	local lastTriggerAt = -math.huge
	local armed = false
	local muted = {}       -- [Sound] = { vol, min, max, active } original values, restored after the execution
	local currentAnimator, animConn
	local rng = Random.new()
	Shared.execUntil = 0

	---------------- taunt sound (played when YOU start an execution)
	local function getTaunts()
		local node = ReplicatedStorage
		for _, name in ipairs(TAUNT_PATH) do
			node = node and node:FindFirstChild(name)
		end
		local out = {}
		if node then
			for _, n in ipairs(TAUNT_NAMES) do
				local snd = node:FindFirstChild(n)
				if snd and snd:IsA("Sound") then table.insert(out, snd) end
			end
		end
		return out
	end

	local function playTaunt()
		local taunts = getTaunts()
		if #taunts == 0 then
			if DEBUG then warn("[ExecAudio] Taunt sounds not found in ReplicatedStorage") end
			return
		end
		local snd = taunts[rng:NextInteger(1, #taunts)]:Clone()
		snd.Looped = false
		snd:SetAttribute("ScriptSound", true)
		local char = LocalPlayer.Character
		snd.Parent = (char and char:FindFirstChild("HumanoidRootPart")) or Workspace
		snd:Play()
		snd.Ended:Once(function() snd:Destroy() end)
		task.delay(15, function() if snd.Parent then snd:Destroy() end end)
	end

	---------------- muting the game's own execution sounds
	-- a muted sound gets Volume 0 and a roll-off range of 0.0001, and is left to play out silently
	local function silence(snd)
		if not snd.Parent then return end
		local rec = muted[snd]
		if not rec then
			rec = { vol = snd.Volume, min = snd.RollOffMinDistance, max = snd.RollOffMaxDistance }
			muted[snd] = rec
			if DEBUG then print("[ExecAudio] muted " .. snd:GetFullName() .. " (" .. tostring(snd.SoundId) .. ")") end
		end
		rec.active = true
		if snd.RollOffMinDistance ~= TINY_RANGE then snd.RollOffMinDistance = TINY_RANGE end
		if snd.RollOffMaxDistance ~= TINY_RANGE then snd.RollOffMaxDistance = TINY_RANGE end
		if snd.Volume ~= 0 then snd.Volume = 0 end
	end

	local function restore(snd, rec)
		if rec.active or muted[snd] ~= rec then return end -- a newer execution is holding it muted
		muted[snd] = nil
		if snd.Parent then
			snd.RollOffMaxDistance = rec.max
			snd.RollOffMinDistance = rec.min
			snd.Volume = rec.vol
		end
	end

	-- index of every Sound in Workspace / SoundService / PlayerGui, kept up to date while muting is on,
	-- so nothing has to scan the whole game when an execution starts
	local index = {}       -- [Sound] = { connections }
	local indexConns = {}
	local indexing = false

	local function onStart(snd)
		if armed and not snd:GetAttribute("ScriptSound") then silence(snd) end
	end

	local function indexSound(snd, fresh)
		if index[snd] or snd:GetAttribute("ScriptSound") then return end
		index[snd] = {
			snd.Played:Connect(function() onStart(snd) end),
			snd:GetPropertyChangedSignal("Playing"):Connect(function()
				if snd.Playing then onStart(snd) end
			end),
		}
		if fresh then onStart(snd) end
	end

	local function unindexSound(snd)
		local conns = index[snd]
		if conns then
			for _, c in ipairs(conns) do c:Disconnect() end
			index[snd] = nil
		end
	end

	local function inScope(d)
		return d:IsDescendantOf(Workspace) or d:IsDescendantOf(SoundService) or d:IsDescendantOf(PlayerGui)
	end

	local function setIndexing(on)
		if on == indexing then return end
		indexing = on
		if on then
			indexConns[1] = game.DescendantAdded:Connect(function(d)
				if d:IsA("Sound") and inScope(d) then indexSound(d, true) end
			end)
			indexConns[2] = game.DescendantRemoving:Connect(function(d)
				if index[d] then unindexSound(d) end
			end)
			task.spawn(function()
				local n = 0
				for _, root in ipairs({ Workspace, SoundService, PlayerGui }) do
					for _, d in ipairs(root:GetDescendants()) do
						if not indexing then return end
						if d:IsA("Sound") then indexSound(d, false) end
						n += 1
						if n % 1500 == 0 then task.wait() end
					end
				end
			end)
		else
			for _, c in ipairs(indexConns) do c:Disconnect() end
			table.clear(indexConns)
			for snd in pairs(index) do unindexSound(snd) end
		end
	end

	local function arm()
		if armed then return end
		armed = true
		-- sounds that began right when the execution did are part of it
		for snd in pairs(index) do
			if snd.Parent and snd.IsPlaying and not snd.Looped and snd.TimePosition <= START_GRACE then
				silence(snd)
			end
		end
	end

	local function disarm()
		if not armed then return end
		armed = false
		for snd, rec in pairs(muted) do
			rec.active = false
			if snd.Parent and snd.IsPlaying then
				-- still playing: keep it silent until it ends
				local wait = (snd.TimeLength > 0 and math.max(snd.TimeLength - snd.TimePosition, 0) or 5) + 0.5
				task.delay(wait, function() restore(snd, rec) end)
			else
				restore(snd, rec)
			end
		end
	end

	-- only the sounds already muted are re-checked each frame (the game may reset their volume)
	local function poll()
		for snd, rec in pairs(muted) do
			if not snd.Parent then
				muted[snd] = nil
			elseif rec.active and snd.IsPlaying then
				silence(snd)
			end
		end
	end

	---------------- execution detection (the game's execution animation tracks on YOUR character)
	local function onTrigger()
		local now = os.clock()
		local fresh = now - lastTriggerAt > NEW_EXEC_GAP
		lastTriggerAt = now
		if fresh and tauntOn then task.spawn(playTaunt) end
		if muteOn then arm() end
	end

	local function hookCharacter(char)
		if animConn then animConn:Disconnect() animConn = nil end
		currentAnimator = nil
		local hum = char:WaitForChild("Humanoid", 10)
		local animator = hum and hum:WaitForChild("Animator", 10)
		if not animator or LocalPlayer.Character ~= char then return end
		currentAnimator = animator
		animConn = animator.AnimationPlayed:Connect(function(track)
			if (muteOn or tauntOn) and Kit.matches(track, TRIGGER_IDS) then onTrigger() end
		end)
	end

	bind(LocalPlayer.CharacterAdded:Connect(hookCharacter))
	if LocalPlayer.Character then task.spawn(hookCharacter, LocalPlayer.Character) end

	local nextDetect = 0
	bind(RunService.Heartbeat:Connect(function()
		if not (muteOn or tauntOn) then return end
		local now = os.clock()
		local animator = currentAnimator
		if animator and animator.Parent and now >= nextDetect then
			nextDetect = now + 0.1 -- checking 10x/s is plenty; AnimationPlayed catches the start instantly
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				if Kit.matches(t, TRIGGER_IDS) then
					if now - lastTriggerAt > NEW_EXEC_GAP then onTrigger() end
					lastTriggerAt = now
					break
				end
			end
		end
		if not muteOn then return end
		-- active while the game's execution track plays, shortly after, or while our own replacement runs
		if now - lastTriggerAt < TAIL or now < (Shared.execUntil or 0) then
			arm()
			poll()
		elseif armed then
			disarm()
		end
	end))

	ExecAudio.setMute = function(on)
		muteOn = on == true
		setIndexing(muteOn)
		if not muteOn then disarm() end
	end
	ExecAudio.setTaunt = function(on)
		tauntOn = on == true
	end

	onCleanup(function()
		muteOn, tauntOn = false, false
		if animConn then animConn:Disconnect() animConn = nil end
		setIndexing(false)
		disarm()
		ExecAudio.setMute = function() end
		ExecAudio.setTaunt = function() end
	end)
end)

---------------------------------------------------------------- 20) hide nametag + instant interact
runSection("20", function()
	local ProximityPromptService = game:GetService("ProximityPromptService")
	local fire = fireproximityprompt -- nil if the executor doesn't have it

	local nameTagOn, instantOn = false, false
	local alive = true
	local removed = {}      -- { inst = NameTag, parent = Head } so switching the toggle off puts it back
	local watchedHead, headConn

	local function findHead()
		local chars = Workspace:FindFirstChild("Characters")
		local char = chars and chars:FindFirstChild(LocalPlayer.Name)
		return char and char:FindFirstChild("Head")
	end

	local function removeTag(tag)
		if tag and tag.Parent then
			table.insert(removed, { inst = tag, parent = tag.Parent })
			tag.Parent = nil
		end
	end

	local function refresh()
		local head = findHead()
		if head ~= watchedHead then
			if headConn then headConn:Disconnect() headConn = nil end
			watchedHead = head
			if head then
				headConn = head.ChildAdded:Connect(function(child)
					if nameTagOn and child.Name == "NameTag" then
						task.defer(removeTag, child)
					end
				end)
			end
		end
		if head then removeTag(head:FindFirstChild("NameTag")) end
	end

	local function restoreTags()
		for _, r in ipairs(removed) do
			if r.inst and r.parent and r.parent.Parent and not r.parent:FindFirstChild(r.inst.Name) then
				r.inst.Parent = r.parent
			end
		end
		table.clear(removed)
	end

	task.spawn(function()
		while alive do
			if nameTagOn then pcall(refresh) end
			task.wait(0.5)
		end
	end)

	bind(ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if instantOn and fire then pcall(fire, prompt) end
	end))

	Extras.setNameTag = function(on)
		nameTagOn = on == true
		if nameTagOn then
			pcall(refresh)
		else
			restoreTags()
		end
	end
	Extras.setInstant = function(on)
		instantOn = on == true
		if instantOn and not fire then
			warn("[Script] instant interact: this executor has no fireproximityprompt")
		end
	end

	onCleanup(function()
		alive = false
		nameTagOn, instantOn = false, false
		if headConn then headConn:Disconnect() headConn = nil end
		restoreTags()
		Extras.setNameTag = function() end
		Extras.setInstant = function() end
	end)
end)

---------------------------------------------------------------- 11) settings (enable/disable buttons + hide all)
runSection("11", function()
	local ACCENT = Color3.fromRGB(130, 80, 255)
	local CARD_BG = Color3.fromRGB(20, 20, 27)
	local ROW_BG = Color3.fromRGB(32, 32, 42)
	local STROKE_OFF = Color3.fromRGB(55, 55, 68)
	local ON_COLOR = Color3.fromRGB(60, 190, 110)
	local OFF_COLOR = Color3.fromRGB(120, 120, 140)
	local HIDE_KEY = Enum.KeyCode.RightControl

	local layoutGui = PlayerGui:FindFirstChild("LayoutEditorGui")
	if not layoutGui then error("layout editor gui not found") end

	-- key = layout-editor key (holder name is "Holder_<key>"); hook = FeatureHooks entry that turns the feature off
	local features = {
		{ key = "esp", label = "ESP" },
		{ key = "fire", label = "Fire button" },
		{ key = "victim", label = "Victim anim", hook = "victim" },
		{ key = "sin", label = "SIN" },
		{ key = "exec", label = "Exec mode" },
		{ key = "visor", label = "RIF visor" },
		{ key = "menlo", label = "MENLO visor" },
		{ key = "hidehud", label = "Hide HUD" },
		{ key = "teams", label = "Team select" },
		{ key = "corpse_players", label = "Loot players", hook = "corpse_players" },
		{ key = "corpse_npcs", label = "Loot NPCs", hook = "corpse_npcs" },
		{ key = "thirdperson", label = "Thirdperson", hook = "thirdperson" },
		{ key = "fullbright", label = "Fullbright", hook = "fullbright" },
		{ key = "qte", label = "QTE spam", hook = "qte" },
		{ key = "infect", label = "Get infected", hook = "infect" },
		{ key = "hatred", label = "Hatred display" },
		{ key = "sprint", label = "Sprint" },
		{ key = "swap", label = "Swap anim" },
	}

	local shown = {}
	for _, f in ipairs(features) do shown[f.key] = true end
	local masterHidden = false
	local muteSound = false
	local muteExec = false
	local tauntExec = false
	local hideNameTag = false
	local instantInteract = false

	-- saved configuration (which buttons are shown + hide-all), restored on the next execute
	local SETTINGS_FILE = "ui_settings.json"

	local function saveConfig()
		if not writefile then return end
		pcall(writefile, SETTINGS_FILE, HttpService:JSONEncode({ shown = shown, masterHidden = masterHidden, muteSound = muteSound, muteExec = muteExec, tauntExec = tauntExec, hideNameTag = hideNameTag, instantInteract = instantInteract }))
	end

	local function loadConfig()
		pcall(function()
			if not (isfile and readfile and isfile(SETTINGS_FILE)) then return end
			local d = HttpService:JSONDecode(readfile(SETTINGS_FILE))
			if type(d) ~= "table" then return end
			if type(d.shown) == "table" then
				for k, v in pairs(d.shown) do
					if shown[k] ~= nil and type(v) == "boolean" then shown[k] = v end
				end
			end
			if type(d.masterHidden) == "boolean" then masterHidden = d.masterHidden end
			if type(d.muteSound) == "boolean" then muteSound = d.muteSound end
			if type(d.muteExec) == "boolean" then muteExec = d.muteExec end
			if type(d.tauntExec) == "boolean" then tauntExec = d.tauntExec end
			if type(d.hideNameTag) == "boolean" then hideNameTag = d.hideNameTag end
			if type(d.instantInteract) == "boolean" then instantInteract = d.instantInteract end
		end)
	end
	loadConfig()

	local function applyVisibility()
		for _, f in ipairs(features) do
			local h = layoutGui:FindFirstChild("Holder_" .. f.key)
			if h then h.Visible = shown[f.key] and not masterHidden end
		end
	end

	-- hiding a feature that keeps running invisibly (taunt spam, looting) would be bad, so switch those off
	local function turnOff(f)
		local hook = f.hook and FeatureHooks[f.hook]
		if hook then pcall(hook) end
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "SettingsGui"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 210
	sg.Parent = PlayerGui

	-- SETTINGS pill (always visible, left of RESET/EDIT)
	local pill = Instance.new("TextButton")
	pill.Name = "SettingsToggle"
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Size = UDim2.fromOffset(78, 26)
	pill.Position = UDim2.new(1, -122, 0, 8)
	pill.BackgroundColor3 = CARD_BG
	pill.BorderSizePixel = 0
	pill.AutoButtonColor = false
	pill.Text = "SETTINGS"
	pill.Font = Enum.Font.GothamBold
	pill.TextSize = 11
	pill.TextColor3 = Color3.fromRGB(190, 190, 210)
	pill.Parent = sg
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Thickness = 1.5
	pillStroke.Color = STROKE_OFF
	pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pillStroke.Parent = pill

	-- panel
	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 44)
	panel.Size = UDim2.new(0, 250, 0.75, 0)
	panel.BackgroundColor3 = CARD_BG
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = sg
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
	local pstroke = Instance.new("UIStroke")
	pstroke.Color = ACCENT
	pstroke.Thickness = 1.5
	pstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pstroke.Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(250, 340)
	limit.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -50, 0, 30)
	title.Position = UDim2.new(0, 14, 0, 4)
	title.Font = Enum.Font.GothamBold
	title.Text = "SETTINGS"
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(240, 240, 248)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(26, 26)
	closeBtn.Position = UDim2.new(1, -34, 0, 6)
	closeBtn.BackgroundColor3 = ROW_BG
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 12
	closeBtn.TextColor3 = Color3.fromRGB(200, 200, 215)
	closeBtn.Parent = panel
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -76)
	scroll.Position = UDim2.new(0, 8, 0, 68)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 5)
	list.Parent = scroll

	-- tab bar: SETTINGS | MORPH
	local tabBar = Instance.new("Frame")
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.new(1, -16, 0, 26)
	tabBar.Position = UDim2.new(0, 8, 0, 36)
	tabBar.Parent = panel

	local function makeSettingsTab(text, idx)
		local t = Instance.new("TextButton")
		t.Size = UDim2.new(0.5, -3, 1, 0)
		t.Position = UDim2.new((idx - 1) * 0.5, (idx - 1) * 3, 0, 0)
		t.BackgroundColor3 = ROW_BG
		t.BorderSizePixel = 0
		t.AutoButtonColor = false
		t.Text = text
		t.Font = Enum.Font.GothamBold
		t.TextSize = 11
		t.TextColor3 = Color3.fromRGB(235, 235, 245)
		t.Parent = tabBar
		Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8)
		return t
	end
	local settingsTabBtn = makeSettingsTab("SETTINGS", 1)
	local morphTabBtn = makeSettingsTab("MORPH", 2)

	-- the Morph selector (section 17) parents its window into this frame
	local morphHost = Instance.new("Frame")
	morphHost.Name = "MorphHost"
	morphHost.BackgroundTransparency = 1
	morphHost.BorderSizePixel = 0
	morphHost.ClipsDescendants = true
	morphHost.Size = UDim2.new(1, -16, 1, -74)
	morphHost.Position = UDim2.new(0, 8, 0, 68)
	morphHost.Visible = false
	morphHost.Parent = panel
	Shared.MorphHost = morphHost

	local morphLoading = Instance.new("TextLabel")
	morphLoading.Name = "MorphLoading"
	morphLoading.BackgroundTransparency = 1
	morphLoading.Size = UDim2.new(1, 0, 0, 40)
	morphLoading.Font = Enum.Font.GothamMedium
	morphLoading.Text = "Loading morphs..."
	morphLoading.TextSize = 12
	morphLoading.TextColor3 = Color3.fromRGB(150, 150, 170)
	morphLoading.Parent = morphHost

	local function setSettingsTab(name)
		local isMorph = name == "morph"
		scroll.Visible = not isMorph
		morphHost.Visible = isMorph
		settingsTabBtn.BackgroundColor3 = isMorph and ROW_BG or ACCENT
		morphTabBtn.BackgroundColor3 = isMorph and ACCENT or ROW_BG
		if isMorph then
			panel.Size = UDim2.new(0, 280, 1, -52)
			limit.MaxSize = Vector2.new(280, 480)
		else
			panel.Size = UDim2.new(0, 250, 0.75, 0)
			limit.MaxSize = Vector2.new(250, 340)
		end
	end
	settingsTabBtn.Activated:Connect(function() setSettingsTab("settings") end)
	morphTabBtn.Activated:Connect(function() setSettingsTab("morph") end)
	setSettingsTab("settings")

	local function setPanel(open)
		panel.Visible = open
		pill.BackgroundColor3 = open and ACCENT or CARD_BG
		pill.TextColor3 = open and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 190, 210)
		pillStroke.Color = open and ACCENT or STROKE_OFF
	end
	pill.Activated:Connect(function() setPanel(not panel.Visible) end)
	closeBtn.Activated:Connect(function() setPanel(false) end)

	-- one row: label on the left, state on the right; tap to flip
	local function makeRow(order, text, onText, offText, startOn, handler)
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -6, 0, 34)
		row.BackgroundColor3 = ROW_BG
		row.BorderSizePixel = 0
		row.AutoButtonColor = false
		row.Text = ""
		row.LayoutOrder = order
		row.Parent = scroll
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -80, 1, 0)
		label.Position = UDim2.new(0, 12, 0, 0)
		label.Font = Enum.Font.GothamMedium
		label.Text = text
		label.TextSize = 12
		label.TextColor3 = Color3.fromRGB(235, 235, 245)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = row

		local stateLbl = Instance.new("TextLabel")
		stateLbl.BackgroundTransparency = 1
		stateLbl.Size = UDim2.new(0, 64, 1, 0)
		stateLbl.Position = UDim2.new(1, -72, 0, 0)
		stateLbl.Font = Enum.Font.GothamBold
		stateLbl.TextSize = 11
		stateLbl.TextXAlignment = Enum.TextXAlignment.Right
		stateLbl.Parent = row

		local on = startOn
		local function render()
			stateLbl.Text = on and onText or offText
			stateLbl.TextColor3 = on and ON_COLOR or OFF_COLOR
		end
		row.Activated:Connect(function()
			on = not on
			render()
			handler(on)
		end)
		render()
		return function(v) on = v; render() end
	end

	local setMasterRow
	local function setMasterHidden(hidden)
		masterHidden = hidden
		if hidden then
			for _, f in ipairs(features) do turnOff(f) end
		end
		applyVisibility()
		saveConfig()
	end
	setMasterRow = makeRow(0, "Hide all buttons", "HIDDEN", "SHOWN", masterHidden, setMasterHidden)

	---------------- mute sound 105834637703684
	local MUTE_SOUND_ID = "105834637703684"
	local mutedSounds = {} -- [Sound] = its original volume
	local soundConns = {}  -- [Sound] = { connections }
	local pendingConns = {} -- SoundId watchers for sounds that had no id yet
	local descConn

	local function isTarget(s)
		return s:IsA("Sound") and string.find(s.SoundId, MUTE_SOUND_ID, 1, true) ~= nil
	end

	local function watchSound(s)
		if soundConns[s] then return end
		mutedSounds[s] = s.Volume
		s.Volume = 0
		if s.Playing then s:Stop() end
		soundConns[s] = {
			s:GetPropertyChangedSignal("Volume"):Connect(function()
				if s.Volume ~= 0 then mutedSounds[s] = s.Volume; s.Volume = 0 end
			end),
			s:GetPropertyChangedSignal("Playing"):Connect(function()
				if s.Playing then s:Stop() end
			end),
			s.Destroying:Connect(function()
				mutedSounds[s] = nil
				soundConns[s] = nil
			end),
		}
	end

	local function considerSound(s)
		if not s:IsA("Sound") then return end
		if isTarget(s) then
			watchSound(s)
		elseif s.SoundId == "" then
			-- the id can be assigned after the Sound is parented
			local c
			c = s:GetPropertyChangedSignal("SoundId"):Connect(function()
				if s.SoundId == "" then return end
				c:Disconnect()
				if muteSound and isTarget(s) then watchSound(s) end
			end)
			table.insert(pendingConns, c)
		end
	end

	local function setMuteSound(on)
		muteSound = on
		if on then
			if descConn then return end
			descConn = game.DescendantAdded:Connect(function(d)
				if d:IsA("Sound") then pcall(considerSound, d) end
			end)
			task.spawn(function()
				local n = 0
				for _, d in ipairs(game:GetDescendants()) do
					if not muteSound then return end
					if d:IsA("Sound") then pcall(considerSound, d) end
					n += 1
					if n % 1500 == 0 then task.wait() end
				end
			end)
		else
			if descConn then descConn:Disconnect() descConn = nil end
			for _, c in ipairs(pendingConns) do pcall(function() c:Disconnect() end) end
			table.clear(pendingConns)
			for s, conns in pairs(soundConns) do
				for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
			end
			for s, vol in pairs(mutedSounds) do
				if s.Parent then s.Volume = vol end
			end
			table.clear(soundConns)
			table.clear(mutedSounds)
		end
	end
	onCleanup(function() setMuteSound(false) end)

	makeRow(1, "Mute sound", "MUTED", "PLAYING", muteSound, function(on)
		setMuteSound(on)
		saveConfig()
	end)
	if muteSound then setMuteSound(true) end

	makeRow(2, "Mute exec sounds", "MUTED", "PLAYING", muteExec, function(on)
		muteExec = on
		ExecAudio.setMute(on)
		saveConfig()
	end)
	makeRow(3, "Taunt sounds", "ON", "OFF", tauntExec, function(on)
		tauntExec = on
		ExecAudio.setTaunt(on)
		saveConfig()
	end)
	makeRow(4, "Hide nametag", "HIDDEN", "SHOWN", hideNameTag, function(on)
		hideNameTag = on
		Extras.setNameTag(on)
		saveConfig()
	end)
	makeRow(5, "Instant interact", "ON", "OFF", instantInteract, function(on)
		instantInteract = on
		Extras.setInstant(on)
		saveConfig()
	end)
	ExecAudio.setMute(muteExec)
	ExecAudio.setTaunt(tauntExec)
	Extras.setNameTag(hideNameTag)
	Extras.setInstant(instantInteract)

	for i, f in ipairs(features) do
		makeRow(i + 5, f.label, "SHOWN", "HIDDEN", shown[f.key], function(show)
			shown[f.key] = show
			if not show then turnOff(f) end
			applyVisibility()
			saveConfig()
		end)
	end


	---------------- teleport list (everything in workspace.Characters)
	local tpGui = Instance.new("ScreenGui")
	tpGui.Name = "TeleportGui"
	tpGui.ResetOnSpawn = false
	tpGui.IgnoreGuiInset = true
	tpGui.DisplayOrder = 220
	tpGui.Parent = PlayerGui

	local tpPanel = Instance.new("Frame")
	tpPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	tpPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
	tpPanel.Size = UDim2.new(0, 250, 0.8, 0)
	tpPanel.BackgroundColor3 = CARD_BG
	tpPanel.BorderSizePixel = 0
	tpPanel.Visible = false
	tpPanel.Parent = tpGui
	Instance.new("UICorner", tpPanel).CornerRadius = UDim.new(0, 12)
	local tpStroke = Instance.new("UIStroke")
	tpStroke.Color = ACCENT
	tpStroke.Thickness = 1.5
	tpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tpStroke.Parent = tpPanel
	local tpLimit = Instance.new("UISizeConstraint")
	tpLimit.MaxSize = Vector2.new(250, 380)
	tpLimit.Parent = tpPanel

	local tpTitle = Instance.new("TextLabel")
	tpTitle.BackgroundTransparency = 1
	tpTitle.Size = UDim2.new(1, -50, 0, 30)
	tpTitle.Position = UDim2.new(0, 14, 0, 4)
	tpTitle.Font = Enum.Font.GothamBold
	tpTitle.Text = "TELEPORT"
	tpTitle.TextSize = 13
	tpTitle.TextColor3 = Color3.fromRGB(240, 240, 248)
	tpTitle.TextXAlignment = Enum.TextXAlignment.Left
	tpTitle.Parent = tpPanel

	local tpClose = Instance.new("TextButton")
	tpClose.Size = UDim2.fromOffset(26, 26)
	tpClose.Position = UDim2.new(1, -34, 0, 6)
	tpClose.BackgroundColor3 = ROW_BG
	tpClose.BorderSizePixel = 0
	tpClose.Text = "X"
	tpClose.Font = Enum.Font.GothamBold
	tpClose.TextSize = 12
	tpClose.TextColor3 = Color3.fromRGB(200, 200, 215)
	tpClose.Parent = tpPanel
	Instance.new("UICorner", tpClose).CornerRadius = UDim.new(1, 0)

	local tpSearch = Instance.new("TextBox")
	tpSearch.Size = UDim2.new(1, -16, 0, 28)
	tpSearch.Position = UDim2.new(0, 8, 0, 38)
	tpSearch.BackgroundColor3 = ROW_BG
	tpSearch.BorderSizePixel = 0
	tpSearch.PlaceholderText = "Search..."
	tpSearch.PlaceholderColor3 = Color3.fromRGB(130, 130, 150)
	tpSearch.Text = ""
	tpSearch.ClearTextOnFocus = false
	tpSearch.Font = Enum.Font.GothamMedium
	tpSearch.TextSize = 12
	tpSearch.TextColor3 = Color3.fromRGB(235, 235, 245)
	tpSearch.Parent = tpPanel
	Instance.new("UICorner", tpSearch).CornerRadius = UDim.new(0, 8)

	local tpScroll = Instance.new("ScrollingFrame")
	tpScroll.Size = UDim2.new(1, -16, 1, -112)
	tpScroll.Position = UDim2.new(0, 8, 0, 72)
	tpScroll.BackgroundTransparency = 1
	tpScroll.BorderSizePixel = 0
	tpScroll.ScrollBarThickness = 3
	tpScroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
	tpScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	tpScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tpScroll.Parent = tpPanel
	local tpList = Instance.new("UIListLayout")
	tpList.SortOrder = Enum.SortOrder.LayoutOrder
	tpList.Padding = UDim.new(0, 4)
	tpList.Parent = tpScroll

	local tpStatus = Instance.new("TextLabel")
	tpStatus.BackgroundTransparency = 1
	tpStatus.Size = UDim2.new(1, -16, 0, 28)
	tpStatus.Position = UDim2.new(0, 8, 1, -32)
	tpStatus.Font = Enum.Font.GothamMedium
	tpStatus.Text = ""
	tpStatus.TextSize = 11
	tpStatus.TextColor3 = Color3.fromRGB(150, 150, 170)
	tpStatus.TextXAlignment = Enum.TextXAlignment.Left
	tpStatus.TextTruncate = Enum.TextTruncate.AtEnd
	tpStatus.Parent = tpPanel

	local function pivotOf(obj)
		if obj:IsA("Model") then
			local ok, cf = pcall(function() return obj:GetPivot() end)
			return ok and cf or nil
		elseif obj:IsA("BasePart") then
			return obj.CFrame
		end
		return nil
	end

	local function teleportTo(obj)
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local cf = obj and obj.Parent and pivotOf(obj)
		if not root then tpStatus.Text = "No character" return end
		if not cf then tpStatus.Text = obj.Name .. " is gone" return end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		char:PivotTo(cf * CFrame.new(0, 0, 4)) -- 4 studs behind it, so you don't spawn inside it
		tpStatus.Text = "Teleported to " .. obj.Name
	end

	local tpButtons = {}
	local function rebuildTp()
		for _, b in pairs(tpButtons) do b:Destroy() end
		table.clear(tpButtons)
		local folder = Workspace:FindFirstChild("Characters")
		if not folder then tpStatus.Text = "workspace.Characters not found" return end
		local q = string.lower(tpSearch.Text)
		local items = folder:GetChildren()
		table.sort(items, function(a, b) return string.lower(a.Name) < string.lower(b.Name) end)
		local n = 0
		for _, obj in ipairs(items) do
			if obj ~= LocalPlayer.Character and pivotOf(obj) and (q == "" or string.find(string.lower(obj.Name), q, 1, true)) then
				n += 1
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(1, -6, 0, 30)
				b.BackgroundColor3 = ROW_BG
				b.BorderSizePixel = 0
				b.AutoButtonColor = true
				b.Text = obj.Name
				b.Font = Enum.Font.GothamMedium
				b.TextSize = 12
				b.TextColor3 = Color3.fromRGB(235, 235, 245)
				b.LayoutOrder = n
				b.Parent = tpScroll
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
				b.Activated:Connect(function() teleportTo(obj) end)
				tpButtons[obj] = b
			end
		end
		tpStatus.Text = n .. " in workspace.Characters"
	end

	local rebuildQueued = false
	local function queueRebuild()
		if rebuildQueued or not tpPanel.Visible then return end
		rebuildQueued = true
		task.delay(0.3, function()
			rebuildQueued = false
			if tpPanel.Visible then rebuildTp() end
		end)
	end

	local function hookFolder(folder)
		bind(folder.ChildAdded:Connect(queueRebuild))
		bind(folder.ChildRemoved:Connect(queueRebuild))
	end
	local charsFolder = Workspace:FindFirstChild("Characters")
	if charsFolder then hookFolder(charsFolder) end
	bind(Workspace.ChildAdded:Connect(function(c)
		if c.Name == "Characters" then hookFolder(c) queueRebuild() end
	end))

	tpSearch:GetPropertyChangedSignal("Text"):Connect(function()
		if tpPanel.Visible then rebuildTp() end
	end)
	tpClose.Activated:Connect(function() tpPanel.Visible = false end)

	-- row inside the settings panel (sits at the very top)
	local tpRow = Instance.new("TextButton")
	tpRow.Size = UDim2.new(1, -6, 0, 34)
	tpRow.BackgroundColor3 = ACCENT
	tpRow.BorderSizePixel = 0
	tpRow.AutoButtonColor = true
	tpRow.Text = "TELEPORT TO...  >"
	tpRow.Font = Enum.Font.GothamBold
	tpRow.TextSize = 12
	tpRow.TextColor3 = Color3.fromRGB(255, 255, 255)
	tpRow.LayoutOrder = -1
	tpRow.Parent = scroll
	Instance.new("UICorner", tpRow).CornerRadius = UDim.new(0, 8)
	tpRow.Activated:Connect(function()
		setPanel(false)
		tpPanel.Visible = true
		rebuildTp()
	end)

	applyVisibility() -- apply the saved configuration

	bind(UIS.InputBegan:Connect(function(input, gp)
		if gp or input.KeyCode ~= HIDE_KEY then return end
		setMasterHidden(not masterHidden)
		setMasterRow(masterHidden)
	end))
end)

---------------------------------------------------------------- 17) morph gui (MorphGui v5)
runSection("17", function()
	onCleanup(function()
		local u = env.MorphGuiUnload
		if type(u) == "function" then pcall(u) end
	end)
	-- the morph script waits on ReplicatedStorage folders, so it runs in its own thread
	task.spawn(function()
		local ok, err = xpcall(function()
			--[[
				MorphGui v5

				New in v5 (on top of v4):
				  * Misc tab: "First Person: Show Body" - in first person you see your whole body and non-head
				    accessories (capes, backpacks, waist/shoulder items). The head and head accessories stay hidden
				    so they don't block your view.
				  * Misc tab: "First Person: Hide Head Accs" - head accessories are always invisible in first person,
				    even if Show Body is off.

				v4 features: look lock, single instance, reconcile + watchdog, X unloads and restores your outfit.
			]]

			local Players = game:GetService("Players")
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local UserInputService = game:GetService("UserInputService")
			local TweenService = game:GetService("TweenService")
			local RunService = game:GetService("RunService")

			local player = Players.LocalPlayer

			----------------------------------------------------------------
			-- Single instance: unload the previous copy of this script
			----------------------------------------------------------------
			local env = (getgenv and getgenv()) or _G
			if env.MorphGuiUnload then
				pcall(env.MorphGuiUnload)
				env.MorphGuiUnload = nil
			end

			-- clean up leftovers from older versions of this script
			pcall(function() RunService:UnbindFromRenderStep("MorphGuiStep") end)
			pcall(function() RunService:UnbindFromRenderStep("MorphGuiLook") end)
			pcall(function() RunService:UnbindFromRenderStep("MorphGuiFP") end)
			pcall(function()
				local oldFolder = workspace:FindFirstChild("MG_Acc")
				if oldFolder then oldFolder:Destroy() end
			end)
			pcall(function()
				local oldGui = player:WaitForChild("PlayerGui"):FindFirstChild("MorphGui")
				if oldGui then oldGui:Destroy() end
			end)

			----------------------------------------------------------------
			-- Morph source folder
			----------------------------------------------------------------
			local classModels = ReplicatedStorage:WaitForChild("ClassModels", 15)
			local devFolder = classModels and classModels:WaitForChild("DEV FOLDER", 15)
			local morphFolder = devFolder and devFolder:WaitForChild("DEV MORPH", 15)

			if not morphFolder then
				warn("[MorphGui] Could not find ReplicatedStorage.ClassModels['DEV FOLDER']['DEV MORPH'] - check the names.")
				if classModels then
					warn("[MorphGui] ClassModels contains:")
					for _, c in ipairs(classModels:GetChildren()) do
						warn("   " .. c.Name .. " (" .. c.ClassName .. ")")
					end
				end
				morphFolder = Instance.new("Folder")
			end

			local function findHats(morph)
				for _, c in ipairs(morph:GetChildren()) do
					if c.Name:lower():gsub("%s", "") == "hats" then
						return c
					end
				end
				for _, c in ipairs(morph:GetDescendants()) do
					if c.Name:lower():gsub("%s", "") == "hats" then
						return c
					end
				end
				for _, c in ipairs(morph:GetChildren()) do
					if c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants") then
						return morph
					end
				end
				return nil
			end

			----------------------------------------------------------------
			-- Settings
			----------------------------------------------------------------
			local DEBUG = true            -- prints what the game changed / what got fixed
			local WATCHDOG_INTERVAL = 0.5 -- seconds between safety-net checks
			-- false = the game may make your morph transparent (first-person executions, invisibility, fades).
			-- true  = the look lock also forces Transparency back (this is what blocked your view in v4)
			local LOCK_TRANSPARENCY = false

			----------------------------------------------------------------
			-- State
			----------------------------------------------------------------
			local TAG = "MG_Added" -- attribute put on everything this GUI adds to the character

			local alive = true
			local conns = {}      -- script-wide connections (disconnected on unload)
			local charConns = {}  -- connections to the current character

			local snapshot = nil
			local snapshotBC = nil      -- original BodyColors instance (if any)
			local snapshotColors = nil  -- original per-part colors

			local currentMorph = nil
			local currentMorphObj = nil
			local currentHatsOverride = nil
			local plan = {}             -- list of source items that SHOULD be on the character
			local planColors = nil      -- BodyColors the morph wants (or nil)

			local hideHead = false
			local autoRefresh = true
			local lockLookOn = true
			local thirdPerson = false
			local origCam = nil

			local busy = false          -- lock so full operations never overlap (they can yield)
			local charGen = 0           -- increments every respawn, lets stale tasks bail out
			local ready = true          -- false while a respawn is still loading its outfit

			local createdBy = setmetatable({}, { __mode = "k" })  -- [item on character] = source item it was built from
			local released = setmetatable({}, { __mode = "k" })   -- items WE removed on purpose
			local unattached = setmetatable({}, { __mode = "k" }) -- accessories that could not be welded at all
			local knownDesc = setmetatable({}, { __mode = "k" })  -- every descendant that was part of a piece when WE built it
			local dirtyPieces = setmetatable({}, { __mode = "k" })-- pieces whose parts were destroyed / swapped by the game
			local looks = {}                                      -- [piece] = list of { instance, property, expectedValue, rebuildOnly }
			local bodyLook = {}                                   -- list of { bodyPart, property, expectedValue }
			local lookWarned = {}
			local lookFixes = 0
			local curStats = nil
			local lastStats = nil

			local statusLabel
			local gui

			local function connect(signal, fn)
				local c = signal:Connect(fn)
				conns[#conns + 1] = c
				return c
			end

			local function setStatus(text)
				if statusLabel then
					statusLabel.Text = text
				end
			end

			-- removes one of OUR pieces on purpose (so nothing tries to "restore" it)
			local function dropPiece(inst)
				released[inst] = true
				looks[inst] = nil
				dirtyPieces[inst] = nil
				pcall(function() inst:Destroy() end)
			end

			----------------------------------------------------------------
			-- Look lock bookkeeping
			----------------------------------------------------------------
			local LOOK_PROPS = {
				{ "BasePart", { "Color", "Material", "Transparency", "Reflectance" } },
				{ "MeshPart", { "TextureID", "MeshId" } },
				{ "SpecialMesh", { "TextureId", "MeshId", "VertexColor" } },
				{ "Decal", { "Color3", "Transparency", "Texture" } }, -- also covers Texture
				{ "SurfaceAppearance", { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap", "Color" } },
			}

			-- game effects that get removed if they appear INSIDE one of our pieces
			local OVERLAY = {
				Highlight = true, SurfaceAppearance = true, Decal = true, Texture = true,
				ParticleEmitter = true, Fire = true, Smoke = true, Sparkles = true, Trail = true, Beam = true,
				PointLight = true, SpotLight = true, SurfaceLight = true, SpecialMesh = true,
				BillboardGui = true, SurfaceGui = true,
			}

			local function warnLook(inst, prop, cur)
				if not DEBUG then return end
				local key = inst.Name .. "." .. prop
				if lookWarned[key] then return end
				lookWarned[key] = true
				print("[MorphGui] game changed " .. inst:GetFullName() .. "." .. prop .. " to " .. tostring(cur) .. ", putting it back")
			end

			-- records how a freshly built piece looks (called BEFORE it is parented to the character)
			local function recordLook(piece)
				local rec = {}
				local function visit(d)
					knownDesc[d] = true
					for _, entry in ipairs(LOOK_PROPS) do
						if d:IsA(entry[1]) then
							for _, prop in ipairs(entry[2]) do
								local ok, v = pcall(function() return d[prop] end)
								if ok then
									-- MeshPart.MeshId can't be assigned by scripts: if it changes, the piece is rebuilt instead
									rec[#rec + 1] = { d, prop, v, entry[1] == "MeshPart" and prop == "MeshId" }
								end
							end
						end
					end
				end
				visit(piece)
				for _, d in ipairs(piece:GetDescendants()) do
					visit(d)
				end
				looks[piece] = rec
			end

			local function recordBody(char)
				table.clear(bodyLook)
				for _, v in ipairs(char:GetChildren()) do
					if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
						bodyLook[#bodyLook + 1] = { v, "Color", v.Color }
						bodyLook[#bodyLook + 1] = { v, "Material", v.Material }
					end
				end
			end

			-- body colors take a moment to apply, so record them shortly after any color change
			local bodyPending = false
			local function scheduleRecordBody()
				if bodyPending then return end
				bodyPending = true
				local gen = charGen
				task.delay(0.4, function()
					bodyPending = false
					if not alive or gen ~= charGen or not currentMorphObj then return end
					local char = player.Character
					if char then recordBody(char) end
				end)
			end

			----------------------------------------------------------------
			-- Character helpers
			----------------------------------------------------------------
			local function getCharacter()
				local char = player.Character or player.CharacterAdded:Wait()
				local hum = char:WaitForChild("Humanoid")
				return char, hum
			end

			local function isOutfitItem(v)
				return v:IsA("Accoutrement") or v:IsA("Shirt") or v:IsA("Pants") or v:IsA("ShirtGraphic")
			end

			local function takeSnapshot(char)
				local items = {}
				for _, v in ipairs(char:GetChildren()) do
					if isOutfitItem(v) and not v:GetAttribute(TAG) then
						table.insert(items, v:Clone())
					end
				end
				snapshot = items

				local bc = char:FindFirstChildOfClass("BodyColors")
				snapshotBC = (bc and not bc:GetAttribute(TAG)) and bc:Clone() or nil

				snapshotColors = {}
				for _, v in ipairs(char:GetChildren()) do
					if v:IsA("BasePart") then
						snapshotColors[v.Name] = v.Color
					end
				end
			end

			local function setBodyColors(char, bc)
				table.clear(bodyLook) -- old expectations would fight the new colors
				local old = char:FindFirstChildOfClass("BodyColors")
				if old then old:Destroy() end
				if bc then
					local c = bc:Clone()
					c:SetAttribute(TAG, true)
					c.Parent = char
				end
				scheduleRecordBody()
			end

			local function restoreOriginalColors(char)
				table.clear(bodyLook)
				setBodyColors(char, snapshotBC)
				if snapshotColors then
					for name, color in pairs(snapshotColors) do
						local part = char:FindFirstChild(name)
						if part and part:IsA("BasePart") then
							part.Color = color
						end
					end
				end
				scheduleRecordBody()
			end

			local function sameColors(a, b)
				return a.HeadColor3 == b.HeadColor3 and a.TorsoColor3 == b.TorsoColor3
					and a.LeftArmColor3 == b.LeftArmColor3 and a.RightArmColor3 == b.RightArmColor3
					and a.LeftLegColor3 == b.LeftLegColor3 and a.RightLegColor3 == b.RightLegColor3
			end

			-- is this instance part of something this GUI added (walks up to the character's direct child)
			local function isOurs(d, char)
				local top = d
				while top.Parent and top.Parent ~= char do
					top = top.Parent
				end
				return top:GetAttribute(TAG) == true
			end

			----------------------------------------------------------------
			-- Hide face / head
			----------------------------------------------------------------
			local mgCache = setmetatable({}, { __mode = "k" }) -- inst -> true while hidden by the Hide Face & Head toggle
			local function isMgHidden(inst)
				local v = mgCache[inst]
				if v == nil then
					v = inst:GetAttribute("MG_T") ~= nil
					mgCache[inst] = v
				end
				return v
			end

			local function setHidden(obj, hide)
				if hide then
					if obj:GetAttribute("MG_T") == nil then
						obj:SetAttribute("MG_T", obj.Transparency)
					end
					mgCache[obj] = true
					obj.Transparency = 1
				else
					local orig = obj:GetAttribute("MG_T")
					if orig ~= nil then
						obj.Transparency = orig
						obj:SetAttribute("MG_T", nil)
					end
					mgCache[obj] = false
				end
			end

			local function hideVisuals(root, hide)
				for _, d in ipairs(root:GetDescendants()) do
					if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
						setHidden(d, hide)
					end
				end
				if root:IsA("BasePart") then
					setHidden(root, hide)
				end
			end

			local function isFaceItem(item)
				if item:IsA("Accessory") then
					if item.AccessoryType == Enum.AccessoryType.Face then
						return true
					end
					local handle = item:FindFirstChild("Handle")
					if handle then
						for _, a in ipairs(handle:GetChildren()) do
							if a:IsA("Attachment") and a.Name:find("^Face") then
								return true
							end
						end
					end
				end
				return item.Name:lower():find("face") ~= nil
			end

			local function applyHeadState()
				local char = player.Character
				if not char then return end

				local hide = hideHead and currentMorph ~= nil

				local head = char:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					-- the head part itself + every decal/texture (the face) on it
					setHidden(head, hide)
					for _, d in ipairs(head:GetDescendants()) do
						if d:IsA("Decal") or d:IsA("Texture") or d:IsA("BasePart") then
							setHidden(d, hide)
						end
					end
				end

				-- face accessories / face models, including any decals inside them
				for _, item in ipairs(char:GetChildren()) do
					if (item:IsA("Accessory") or item:IsA("Model")) and isFaceItem(item) then
						hideVisuals(item, hide)
					end
				end
			end

			local headPending = false
			local function scheduleHeadState()
				if headPending then return end
				headPending = true
				task.delay(0.1, function()
					headPending = false
					if alive and hideHead and currentMorph then
						applyHeadState()
					end
				end)
			end

			----------------------------------------------------------------
			-- Building ONE piece (every piece we add is tagged and registered in createdBy)
			----------------------------------------------------------------
			local function prepParts(root)
				for _, p in ipairs(root:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Anchored = false
						p.CanCollide = false
						p.Massless = true
					end
				end
			end

			-- welds the accessory to the matching attachment on the character (the method that worked in the old version)
			local function attachAccessory(acc, char)
				local handle = acc:FindFirstChild("Handle")
				if not handle or not handle:IsA("BasePart") then
					unattached[acc] = true
					if curStats then curStats.failed += 1 end
					warn("[MorphGui] accessory '" .. acc.Name .. "' has no Handle part, can't attach it")
					return false
				end

				-- drop stale welds copied along with the item
				for _, d in ipairs(handle:GetChildren()) do
					if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("ManualWeld") then
						if not (d.Part1 and d.Part1:IsDescendantOf(acc)) then
							d:Destroy()
						end
					end
				end

				local weld = Instance.new("Weld")
				weld.Name = "AccessoryWeld"
				weld.Part0 = handle

				local function finish(part1)
					weld.Part1 = part1
					handle.CFrame = part1.CFrame * weld.C1 * weld.C0:Inverse()
					weld.Parent = handle
				end

				for _, att in ipairs(handle:GetChildren()) do
					if att:IsA("Attachment") then
						for _, bodyPart in ipairs(char:GetChildren()) do
							if bodyPart:IsA("BasePart") then
								local target = bodyPart:FindFirstChild(att.Name)
								if target and target:IsA("Attachment") then
									weld.C0 = att.CFrame
									weld.C1 = target.CFrame
									finish(bodyPart)
									return true
								end
							end
						end
					end
				end

				local head = char:FindFirstChild("Head")
				if head then
					weld.C0 = acc.AttachmentPoint
					weld.C1 = CFrame.new(0, head.Size.Y / 2, 0)
					finish(head)
					warn("[MorphGui] '" .. acc.Name .. "' has no matching attachment on your character, placed on head")
					return true
				end

				unattached[acc] = true
				if curStats then curStats.failed += 1 end
				return false
			end

			local function buildAccessory(template, src, char)
				local acc = template:Clone()
				acc:SetAttribute(TAG, true)
				createdBy[acc] = src
				prepParts(acc)

				if not acc:FindFirstChild("Handle") then
					-- main part isn't called "Handle": use the first part inside the accessory
					local part = acc:FindFirstChildWhichIsA("BasePart")
					if part then
						part.Name = "Handle"
					end
				end

				attachAccessory(acc, char)
				recordLook(acc) -- remember the pristine look BEFORE the game can touch it
				acc.Parent = char
				return acc
			end

			local function attachModel(model, char)
				local clone = model:Clone()
				local root = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
				local head = char:FindFirstChild("Head")
				if not root or not head then
					clone:Destroy()
					return nil
				end
				for _, p in ipairs(clone:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Anchored = false
						p.CanCollide = false
						p.Massless = true
						if p ~= root then
							local wc = Instance.new("WeldConstraint")
							wc.Part0 = root
							wc.Part1 = p
							wc.Parent = p
						end
					end
				end
				clone:SetAttribute(TAG, true)
				createdBy[clone] = model
				recordLook(clone)
				clone.Parent = char
				local w = Instance.new("Weld")
				w.Part0 = head
				w.Part1 = root
				w.C0 = CFrame.new(0, head.Size.Y / 2 + root.Size.Y / 2, 0)
				w.Parent = root
				return clone
			end

			-- builds exactly one instance on the character for one source item; returns it (or nil)
			local function buildLeaf(src, char)
				if src:IsA("Accoutrement") then
					return buildAccessory(src, src, char)
				elseif src:IsA("BasePart") then
					local tmpl = Instance.new("Accessory")
					tmpl.Name = src.Name
					local h = src:Clone()
					h.Name = "Handle"
					h.Parent = tmpl
					local made = buildAccessory(tmpl, src, char)
					tmpl:Destroy()
					return made
				elseif src:IsA("Shirt") or src:IsA("Pants") or src:IsA("ShirtGraphic") then
					local c = src:Clone()
					c:SetAttribute(TAG, true)
					createdBy[c] = src
					c.Parent = char
					return c
				elseif src:IsA("Model") then
					return attachModel(src, char)
				end
				return nil
			end

			-- flattens a morph's "hats" container into a list of leaf items
			local function collectLeaves(item, out)
				if item:IsA("Accoutrement") or item:IsA("BasePart")
					or item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic") then
					out[#out + 1] = item
				elseif item:IsA("Folder") or item:IsA("Model") then
					local hasNested = item:IsA("Folder")
					if not hasNested then
						for _, d in ipairs(item:GetDescendants()) do
							if d:IsA("Accoutrement") or d:IsA("Shirt") or d:IsA("Pants") then
								hasNested = true
								break
							end
						end
					end
					if hasNested then
						for _, child in ipairs(item:GetChildren()) do
							collectLeaves(child, out)
						end
					else
						out[#out + 1] = item
					end
				elseif item:IsA("BodyColors") or item:IsA("Humanoid") or item:IsA("ValueBase") then
					-- handled separately / ignored
				else
					warn("[MorphGui] unsupported item type: " .. item:GetFullName() .. " (" .. item.ClassName .. ")")
				end
			end

			----------------------------------------------------------------
			-- RECONCILE: make the character match the plan. Safe to run any number of times.
			--   keeps healthy pieces, re-adds missing ones, rebuilds damaged ones, removes duplicates,
			--   leftovers from other morphs and the game's own outfit pieces.
			-- It never yields, so it can't overlap itself.
			----------------------------------------------------------------
			local function isHealthy(inst, char)
				if inst.Parent ~= char then return false end
				if inst:IsA("Accoutrement") then
					if unattached[inst] then return true end -- can't be fixed by rebuilding anyway
					local h = inst:FindFirstChild("Handle")
					if not (h and h:IsA("BasePart")) then return false end
					for _, d in ipairs(h:GetChildren()) do
						if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
							local other = (d.Part0 == h) and d.Part1 or d.Part0
							if other and other ~= h and other:IsDescendantOf(char) then
								return true
							end
						end
					end
					return false
				end
				return true
			end

			local function ensureColors(char, stats)
				if not planColors then return end
				local cur = char:FindFirstChildOfClass("BodyColors")
				if cur and sameColors(cur, planColors) then return end
				setBodyColors(char, planColors)
				if stats then stats.colors = true end
			end

			local function reconcile(char, hum, force)
				local stats = { added = 0, removed = 0, deduped = 0, foreign = 0, failed = 0, colors = false }
				curStats = stats

				local want = {}
				for _, s in ipairs(plan) do want[s] = true end

				-- 1) look at everything on the character
				local have = {} -- [source] = { our instances built from it }
				for _, v in ipairs(char:GetChildren()) do
					if v:IsA("BodyColors") then
						-- colors are handled by ensureColors
					elseif v:GetAttribute(TAG) then
						local src = createdBy[v]
						if force or not (src and want[src]) then
							-- leftover from another morph / another copy of the script / forced rebuild
							dropPiece(v)
							stats.removed += 1
						elseif dirtyPieces[v] then
							-- the game destroyed / swapped a part of it: rebuild it from the source below
							dropPiece(v)
						else
							local l = have[src]
							if not l then
								l = {}
								have[src] = l
							end
							l[#l + 1] = v
						end
					elseif currentMorphObj and isOutfitItem(v) then
						-- the game's own outfit piece, the morph replaces it
						pcall(function() v:Destroy() end)
						stats.foreign += 1
					end
				end

				-- 2) every planned piece must exist exactly once and be healthy
				for _, src in ipairs(plan) do
					local keep = nil
					local l = have[src]
					if l then
						for _, inst in ipairs(l) do
							if not keep and isHealthy(inst, char) then
								keep = inst
							else
								dropPiece(inst)
								stats.deduped += 1
							end
						end
					end
					if not keep then
						local ok, res = pcall(buildLeaf, src, char)
						if ok and res then
							stats.added += 1
						else
							stats.failed += 1
							warn("[MorphGui] couldn't add '" .. src.Name .. "' (" .. src.ClassName .. ")"
								.. (ok and "" or (": " .. tostring(res))))
						end
					end
				end

				-- 3) colors
				ensureColors(char, stats)

				curStats = nil
				return stats
			end

			local function changedCount(s)
				return s.added + s.removed + s.deduped + s.foreign + (s.colors and 1 or 0)
			end

			local function describe(s)
				local parts = {}
				if s.added > 0 then parts[#parts + 1] = "re-added " .. s.added end
				local extra = s.removed + s.deduped + s.foreign
				if extra > 0 then parts[#parts + 1] = "removed " .. extra .. " extra" end
				if s.colors then parts[#parts + 1] = "fixed colors" end
				if s.failed > 0 then parts[#parts + 1] = s.failed .. " FAILED (see Output)" end
				if #parts == 0 then
					return "all " .. #plan .. " pieces OK"
				end
				return table.concat(parts, ", ")
			end

			----------------------------------------------------------------
			-- Auto refresh (debounced events + a cheap watchdog; all of it funnels into the same reconcile)
			----------------------------------------------------------------
			local fight = { n = 0, t = 0, block = 0 }
			local function noteFix()
				local now = os.clock()
				if now - fight.t > 3 then
					fight.n = 0
					fight.t = now
				end
				fight.n += 1
				if fight.n > 8 then
					fight.n = 0
					fight.block = now + 4
					warn("[MorphGui] something keeps changing your outfit (8 fixes in 3s) - pausing auto refresh for 4s. "
						.. "If this keeps happening, an older copy of a morph script is still running: rejoin and run only this version.")
				end
			end

			local function runReconcile(reason)
				if not alive or not currentMorphObj or not ready or busy or not autoRefresh then return end
				if os.clock() < fight.block then return end
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not char or not hum or hum.Health <= 0 or not char:IsDescendantOf(workspace) then return end

				local ok, stats = pcall(reconcile, char, hum)
				curStats = nil
				if not ok then
					warn("[MorphGui] auto refresh failed: " .. tostring(stats))
					return
				end
				if changedCount(stats) > 0 then
					noteFix()
					if DEBUG then
						print("[MorphGui] auto refresh (" .. reason .. "): " .. describe(stats))
					end
					if hideHead then applyHeadState() end
					setStatus("Auto refresh: " .. describe(stats))
				end
			end

			local pending = false
			local function scheduleReconcile(reason)
				if pending or not alive or not currentMorphObj or not autoRefresh then return end
				pending = true
				task.delay(0.05, function()
					pending = false
					runReconcile(reason)
				end)
			end

			----------------------------------------------------------------
			-- LOOK LOCK: runs every frame right before rendering (after the game's own render-step code),
			-- so whatever the game set this frame is replaced by the morph's real look before you see it.
			----------------------------------------------------------------
			local function enforceLooks()
				if not alive or not currentMorphObj or not lockLookOn then return end
				local fixed = 0
				local dirty = false

				for piece, rec in pairs(looks) do
					if piece.Parent then
						for i = 1, #rec do
							local r = rec[i]
							local inst, prop = r[1], r[2]
							if inst.Parent == nil then
								-- a part of this piece was destroyed by the game
								if not dirtyPieces[piece] then
									dirtyPieces[piece] = true
									dirty = true
								end
								break
							end
							local expected = r[3]
							if prop == "Transparency" and isMgHidden(inst) then
								expected = 1 -- hidden on purpose by the "Hide Face & Head" toggle
							end
							local cur = inst[prop]
							if cur ~= expected then
								if r[4] then
									-- can't be assigned (mesh swapped): rebuild the piece instead
									warnLook(inst, prop, cur)
									if not dirtyPieces[piece] then
										dirtyPieces[piece] = true
										dirty = true
									end
									break
								end
								warnLook(inst, prop, cur)
								if pcall(function() inst[prop] = expected end) then
									fixed += 1
								end
							end
						end
					end
				end

				for i = 1, #bodyLook do
					local r = bodyLook[i]
					local inst, prop = r[1], r[2]
					if inst.Parent then
						local cur = inst[prop]
						if cur ~= r[3] then
							warnLook(inst, prop, cur)
							if pcall(function() inst[prop] = r[3] end) then
								fixed += 1
							end
						end
					end
				end

				if fixed > 0 then
					lookFixes += fixed
				end
				if dirty then
					scheduleReconcile("a part of a morph piece changed")
				end
			end

			pcall(function() RunService:UnbindFromRenderStep("MorphGuiLook") end)
			RunService:BindToRenderStep("MorphGuiLook", Enum.RenderPriority.Last.Value + 1, function()
				local ok, err = pcall(enforceLooks)
				if not ok and not lookWarned["_err"] then
					lookWarned["_err"] = true
					warn("[MorphGui] look lock error: " .. tostring(err))
				end
			end)

			----------------------------------------------------------------
			-- Morph / reset / refresh
			----------------------------------------------------------------
			local function doMorph(morph, hatsOverride)
				local char, hum = getCharacter()
				if not snapshot then
					takeSnapshot(char)
				end

				local hats = hatsOverride or findHats(morph)
				if not hats then
					warn("Morph '" .. morph.Name .. "' has no hats folder")
					return false
				end

				local leaves = {}
				for _, item in ipairs(hats:GetChildren()) do
					collectLeaves(item, leaves)
				end
				local bc = morph:FindFirstChildOfClass("BodyColors") or hats:FindFirstChildOfClass("BodyColors")

				plan = leaves
				planColors = bc
				currentMorph = morph.Name
				currentMorphObj = morph
				currentHatsOverride = hatsOverride
				table.clear(lookWarned)
				table.clear(bodyLook)

				lastStats = reconcile(char, hum)
				if not bc then
					-- no colors in the morph: go back to the original ones (stops the previous morph's colors sticking)
					restoreOriginalColors(char)
				end

				applyHeadState()
				scheduleRecordBody()
				return true
			end

			local function morphMessage(name)
				local msg = "Morphed into: " .. name .. " (" .. #plan .. " pieces"
				if lastStats and lastStats.failed > 0 then
					msg = msg .. ", " .. lastStats.failed .. " FAILED - see Output"
				end
				return msg .. ")"
			end

			-- synchronous reset (no yielding), also used by unload
			local function resetNow()
				if not snapshot then return false end
				local char = player.Character
				if not char then return false end

				plan = {}
				planColors = nil
				currentMorph = nil
				currentMorphObj = nil
				currentHatsOverride = nil
				table.clear(bodyLook)

				for _, v in ipairs(char:GetChildren()) do
					if not v:IsA("BodyColors") and (v:GetAttribute(TAG) or isOutfitItem(v)) then
						dropPiece(v)
					end
				end
				for _, item in ipairs(snapshot) do
					local ok, err = pcall(buildLeaf, item, char)
					if not ok then
						warn("[MorphGui] couldn't restore '" .. item.Name .. "': " .. tostring(err))
					end
				end
				table.clear(looks) -- no morph active: nothing to lock
				curStats = nil
				restoreOriginalColors(char)
				applyHeadState() -- brings face/head back
				return true
			end

			local function locked(fn, ...)
				while busy do task.wait() end
				busy = true
				local ok, res = pcall(fn, ...)
				busy = false
				if not ok then
					warn("[MorphGui] " .. tostring(res))
					return false
				end
				return res
			end

			local function morphInto(morph, hatsOverride)
				return locked(doMorph, morph, hatsOverride)
			end

			local function resetMorph()
				return locked(resetNow)
			end

			-- Refresh button: reconcile (keeps what's fine, fixes what's not). force = rebuild everything.
			local function refreshNow(force)
				if not currentMorphObj then return false end
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not (char and hum) then return false end
				local stats = reconcile(char, hum, force)
				applyHeadState()
				return stats
			end

			----------------------------------------------------------------
			-- First person body / head accessory control
			----------------------------------------------------------------
			local fpBody = false         -- show whole body + accessories in first person
			local fpHideHeadAcc = false  -- head accessories always invisible in first person
			local fpTouched = setmetatable({}, { __mode = "k" }) -- parts we forced via LocalTransparencyModifier
			local fpPieceCache = setmetatable({}, { __mode = "k" })

			pcall(function() RunService:UnbindFromRenderStep("MorphGuiFP") end)

			-- true if this accessory/model is welded to the head (hats, hair, face items)
			local function isHeadPiece(piece, head)
				local cached = fpPieceCache[piece]
				if cached ~= nil then return cached end
				local foundJoint = false
				for _, d in ipairs(piece:GetDescendants()) do
					if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
						local p0, p1 = d.Part0, d.Part1
						if p0 == head or p1 == head then
							fpPieceCache[piece] = true
							return true
						end
						if p0 and p1 and not (p0:IsDescendantOf(piece) and p1:IsDescendantOf(piece)) then
							foundJoint = true -- welded to something outside the piece, and it isn't the head
						end
					end
				end
				if foundJoint then fpPieceCache[piece] = false end
				return false
			end

			local function setPieceFP(piece, mod)
				for _, d in ipairs(piece:GetDescendants()) do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = mod
						fpTouched[d] = true
					end
				end
				if piece:IsA("BasePart") then
					piece.LocalTransparencyModifier = mod
					fpTouched[piece] = true
				end
			end

			local function fpStep()
				if not alive then return end
				if not (fpBody or fpHideHeadAcc) and next(fpTouched) == nil then return end -- both options off, nothing to undo
				local char = player.Character
				local cam = workspace.CurrentCamera
				local head = char and char:FindFirstChild("Head")
				if not (head and cam) then return end

				local inFP = (cam.CFrame.Position - head.Position).Magnitude < 1.5
					or player.CameraMode == Enum.CameraMode.LockFirstPerson

				if not (inFP and (fpBody or fpHideHeadAcc)) then
					-- leaving first person (or toggles off): give control back
					for part in pairs(fpTouched) do
						if part.Parent then part.LocalTransparencyModifier = 0 end
						fpTouched[part] = nil
					end
					return
				end

				for _, v in ipairs(char:GetChildren()) do
					if v.Name ~= "HumanoidRootPart" then
						if v:IsA("Accoutrement") or v:IsA("Model") then
							if isHeadPiece(v, head) then
								setPieceFP(v, 1) -- head accessories: always invisible in first person
							elseif fpBody then
								setPieceFP(v, 0)
							end
						elseif v:IsA("BasePart") and fpBody then
							setPieceFP(v, v == head and 1 or 0)
						end
					end
				end
			end

			RunService:BindToRenderStep("MorphGuiFP", Enum.RenderPriority.Last.Value + 2, function()
				pcall(fpStep)
			end)

			----------------------------------------------------------------
			-- Third person (first person stays available by scrolling in)
			----------------------------------------------------------------
			local TP_DISTANCE = 12
			local zoomBusy = false

			local function fixCamera()
				local cam = workspace.CurrentCamera
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if cam and hum then
					cam.CameraType = Enum.CameraType.Custom
					cam.CameraSubject = hum
				end
			end

			-- keeps the game from locking you back into first person, but doesn't lock you out of it
			local function enforceThirdPerson()
				if not alive or not thirdPerson or zoomBusy then return end
				if player.CameraMode ~= Enum.CameraMode.Classic then
					player.CameraMode = Enum.CameraMode.Classic
				end
				if player.CameraMinZoomDistance > 0.5 then
					player.CameraMinZoomDistance = 0.5
				end
				if player.CameraMaxZoomDistance < 20 then
					player.CameraMaxZoomDistance = 128
				end
			end

			-- pushes the camera out to a third person distance once, then frees the zoom range again
			local function pushOut()
				if not thirdPerson then return end
				zoomBusy = true
				player.CameraMode = Enum.CameraMode.Classic
				player.CameraMaxZoomDistance = math.max(TP_DISTANCE, player.CameraMinZoomDistance)
				player.CameraMinZoomDistance = TP_DISTANCE
				player.CameraMaxZoomDistance = TP_DISTANCE
				fixCamera()
				task.wait(0.35)
				player.CameraMinZoomDistance = 0.5
				player.CameraMaxZoomDistance = 128
				zoomBusy = false
				enforceThirdPerson()
			end

			local function setThirdPerson(on)
				if on == thirdPerson then return end
				if on then
					origCam = {
						mode = player.CameraMode,
						min = player.CameraMinZoomDistance,
						max = player.CameraMaxZoomDistance,
					}
					thirdPerson = true
					task.spawn(pushOut)
				else
					thirdPerson = false
					zoomBusy = false
					if origCam then
						player.CameraMaxZoomDistance = origCam.max
						player.CameraMinZoomDistance = origCam.min
						player.CameraMode = origCam.mode
					end
				end
			end

			connect(player:GetPropertyChangedSignal("CameraMode"), enforceThirdPerson)
			connect(player:GetPropertyChangedSignal("CameraMinZoomDistance"), enforceThirdPerson)
			connect(player:GetPropertyChangedSignal("CameraMaxZoomDistance"), enforceThirdPerson)

			----------------------------------------------------------------
			-- Character hooks + respawn
			----------------------------------------------------------------
			local function disconnectChar()
				for _, c in ipairs(charConns) do
					pcall(function() c:Disconnect() end)
				end
				table.clear(charConns)
			end

			local function hookCharacter(char)
				disconnectChar()
				local function add(c) charConns[#charConns + 1] = c end

				-- something took one of OUR pieces off the character
				add(char.ChildRemoved:Connect(function(child)
					if not alive or not currentMorphObj then return end
					if child:GetAttribute(TAG) and not released[child] and not child:IsA("BodyColors") then
						if child.Parent ~= nil then
							-- it was moved somewhere else (not destroyed): drop that stray copy, reconcile re-adds a clean one
							dropPiece(child)
						end
						scheduleReconcile("a morph piece was removed")
					end
				end))

				-- something was added that isn't ours (game outfit / colors), or a stray copy of ours
				add(char.ChildAdded:Connect(function(child)
					if not alive or not currentMorphObj then return end
					if child:GetAttribute(TAG) then
						if not createdBy[child] and not child:IsA("BodyColors") then
							scheduleReconcile("stray copy")
						end
					elseif isOutfitItem(child) or child:IsA("BodyColors") then
						scheduleReconcile("the game added " .. child.Name)
					end
				end))

				add(char.DescendantAdded:Connect(function(d)
					if not alive then return end
					if hideHead and currentMorph and not isOurs(d, char) then
						scheduleHeadState()
					end
					if not currentMorphObj then return end

					-- the game put a visual effect INSIDE one of our pieces (highlight, extra texture, particles...): remove it
					if lockLookOn and OVERLAY[d.ClassName] and not knownDesc[d] and isOurs(d, char) then
						if DEBUG then
							print("[MorphGui] removed a game effect (" .. d.ClassName .. " '" .. d.Name .. "') from a morph piece")
						end
						pcall(function() d:Destroy() end)
					elseif DEBUG and (d:IsA("Highlight") or d:IsA("ForceField")) and not isOurs(d, char) then
						local key = "fx" .. d.ClassName
						if not lookWarned[key] then
							lookWarned[key] = true
							print("[MorphGui] the game added a " .. d.ClassName .. " to your character (" .. d:GetFullName() .. ")")
						end
					end
				end))
			end

			-- HasAppearanceLoaded is already true when a respawned character is added, so wait for
			-- CharacterAppearanceLoaded (with a minimum wait and a timeout as a safety net)
			local function waitForAppearance(timeout)
				local done = false
				local c = player.CharacterAppearanceLoaded:Connect(function() done = true end)
				local t = os.clock()
				while alive and not done and os.clock() - t < timeout do
					if player:HasAppearanceLoaded() and os.clock() - t >= 1.5 then
						break
					end
					task.wait(0.1)
				end
				c:Disconnect()
			end

			connect(player.CharacterAdded, function(char)
				charGen += 1
				local myGen = charGen
				snapshot = nil
				snapshotBC = nil
				snapshotColors = nil
				ready = false
				table.clear(looks)
				table.clear(bodyLook)
				table.clear(fpTouched)
				hookCharacter(char)

				task.spawn(function()
					local hum = char:WaitForChild("Humanoid", 10)
					if not hum then
						if charGen == myGen then ready = true end
						return
					end

					waitForAppearance(8)
					task.wait(0.5)
					if not alive or charGen ~= myGen or player.Character ~= char then return end

					-- remember the game's outfit for "Reset", then put the morph back on
					takeSnapshot(char)
					if currentMorphObj then
						local stats = locked(function()
							local s = reconcile(char, hum)
							applyHeadState()
							return s
						end)
						if stats then
							setStatus("Morph re-applied: " .. tostring(currentMorph))
						end
						scheduleRecordBody()
					end

					if charGen ~= myGen then return end
					ready = true

					if thirdPerson then
						pushOut()
					end
				end)
			end)

			if player.Character then
				local okHook, errHook = pcall(hookCharacter, player.Character)
				if not okHook then
					warn("[MorphGui] hookCharacter failed: " .. tostring(errHook))
				end
			end

			-- watchdog: catches whatever the events miss (broken welds, new game outfit pieces, moved pieces)
			-- and reports how many game changes the look lock has undone
			task.spawn(function()
				while alive do
					task.wait(WATCHDOG_INTERVAL)
					if not alive then break end
					runReconcile("watchdog")
					if lookFixes > 0 then
						setStatus("Look lock: undid " .. (lookFixes > 99 and "99+" or tostring(lookFixes)) .. " game changes")
						lookFixes = 0
					end
				end
			end)

			----------------------------------------------------------------
			-- GUI
			----------------------------------------------------------------
			gui = Instance.new("ScreenGui")
			gui.Name = "MorphGui"
			gui.ResetOnSpawn = false
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			gui.Parent = player:WaitForChild("PlayerGui")

			local main = Instance.new("Frame")
			main.Name = "Main"
			main.Size = UDim2.fromOffset(300, 420)
			main.Position = UDim2.new(0.5, -150, 0.5, -210)
			main.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
			main.BorderSizePixel = 0
			main.ClipsDescendants = true
			-- embed into the Settings panel's MORPH tab when it exists (falls back to a floating window)
			local host = Shared.MorphHost
			local embedded = host ~= nil and host.Parent ~= nil
			if embedded then
				local loading = host:FindFirstChild("MorphLoading")
				if loading then loading:Destroy() end
				main.Parent = host
				main.Position = UDim2.new(0, 0, 0, -42) -- the title bar sits above the visible area
				main.Size = UDim2.new(1, 0, 1, 42)
				main.BackgroundTransparency = 1
			else
				main.Parent = gui
			end

			Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

			local stroke = Instance.new("UIStroke", main)
			stroke.Enabled = not embedded
			stroke.Color = Color3.fromRGB(120, 90, 255)
			stroke.Thickness = 1.5

			local title = Instance.new("Frame")
			title.Name = "TitleBar"
			title.Size = UDim2.new(1, 0, 0, 42)
			title.BackgroundColor3 = Color3.fromRGB(36, 34, 52)
			title.BorderSizePixel = 0
			title.Parent = main
			title.Visible = not embedded

			local grad = Instance.new("UIGradient", title)
			grad.Color = ColorSequence.new(Color3.fromRGB(120, 90, 255), Color3.fromRGB(60, 160, 255))
			grad.Rotation = 0

			local titleLabel = Instance.new("TextLabel")
			titleLabel.BackgroundTransparency = 1
			titleLabel.Size = UDim2.new(1, -90, 1, 0)
			titleLabel.Position = UDim2.fromOffset(14, 0)
			titleLabel.Text = "Morph Selector"
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			titleLabel.Font = Enum.Font.GothamBold
			titleLabel.TextSize = 17
			titleLabel.TextColor3 = Color3.new(1, 1, 1)
			titleLabel.Parent = title

			local function makeTitleButton(text, xOffset)
				local b = Instance.new("TextButton")
				b.Size = UDim2.fromOffset(26, 26)
				b.Position = UDim2.new(1, xOffset, 0.5, -13)
				b.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
				b.BackgroundTransparency = 0.35
				b.Text = text
				b.Font = Enum.Font.GothamBold
				b.TextSize = 16
				b.TextColor3 = Color3.new(1, 1, 1)
				b.AutoButtonColor = true
				b.Parent = title
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
				return b
			end

			local closeBtn = makeTitleButton("X", -36)
			local minBtn = makeTitleButton("-", -68)

			local search = Instance.new("TextBox")
			search.Size = UDim2.new(1, -24, 0, 30)
			search.Position = UDim2.fromOffset(12, 84)
			search.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
			search.PlaceholderText = "Search morphs..."
			search.PlaceholderColor3 = Color3.fromRGB(140, 140, 160)
			search.Text = ""
			search.ClearTextOnFocus = false
			search.Font = Enum.Font.Gotham
			search.TextSize = 14
			search.TextColor3 = Color3.new(1, 1, 1)
			search.Parent = main
			Instance.new("UICorner", search).CornerRadius = UDim.new(0, 8)

			local function makeList(name)
				local l = Instance.new("ScrollingFrame")
				l.Name = name
				l.Size = UDim2.new(1, -24, 1, -208)
				l.Position = UDim2.fromOffset(12, 122)
				l.BackgroundTransparency = 1
				l.BorderSizePixel = 0
				l.ScrollBarThickness = 4
				l.ScrollBarImageColor3 = Color3.fromRGB(120, 90, 255)
				l.CanvasSize = UDim2.new()
				l.AutomaticCanvasSize = Enum.AutomaticSize.Y
				l.Visible = false
				l.Parent = main

				local lay = Instance.new("UIListLayout", l)
				lay.Padding = UDim.new(0, 6)
				lay.SortOrder = Enum.SortOrder.Name
				return l
			end

			local list = makeList("MorphList")
			local customList = makeList("CustomList")
			local miscList = makeList("MiscList")

			local tabBar = Instance.new("Frame")
			tabBar.Name = "TabBar"
			tabBar.Size = UDim2.new(1, -24, 0, 28)
			tabBar.Position = UDim2.fromOffset(12, 50)
			tabBar.BackgroundTransparency = 1
			tabBar.Parent = main

			local function makeTab(text, index)
				local t = Instance.new("TextButton")
				t.Size = UDim2.new(1 / 3, -4, 1, 0)
				t.Position = UDim2.new((index - 1) / 3, (index - 1) * 2, 0, 0)
				t.BackgroundColor3 = Color3.fromRGB(40, 40, 56)
				t.Text = text
				t.Font = Enum.Font.GothamBold
				t.TextSize = 13
				t.TextColor3 = Color3.new(1, 1, 1)
				t.AutoButtonColor = false
				t.Parent = tabBar
				Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8)
				return t
			end

			local morphsTab = makeTab("Morphs", 1)
			local customTab = makeTab("Custom", 2)
			local miscTab = makeTab("Misc", 3)

			local status = Instance.new("TextLabel")
			status.BackgroundTransparency = 1
			status.Size = UDim2.new(1, -24, 0, 18)
			status.Position = UDim2.new(0, 12, 1, -76)
			status.Text = "Pick a morph"
			status.Font = Enum.Font.Gotham
			status.TextSize = 13
			status.TextColor3 = Color3.fromRGB(170, 170, 190)
			status.TextXAlignment = Enum.TextXAlignment.Left
			status.TextTruncate = Enum.TextTruncate.AtEnd
			status.Parent = main
			statusLabel = status

			local resetBtn = Instance.new("TextButton")
			resetBtn.Size = UDim2.new(1, -24, 0, 34)
			resetBtn.Position = UDim2.new(0, 12, 1, -46)
			resetBtn.BackgroundColor3 = Color3.fromRGB(200, 70, 90)
			resetBtn.Text = "Reset to my outfit"
			resetBtn.Font = Enum.Font.GothamBold
			resetBtn.TextSize = 14
			resetBtn.TextColor3 = Color3.new(1, 1, 1)
			resetBtn.Parent = main
			Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 8)

			----------------------------------------------------------------
			-- Morph / custom buttons
			----------------------------------------------------------------
			local buttons = {}
			local selected = nil

			local function setSelected(btn)
				if selected then
					TweenService:Create(selected, TweenInfo.new(0.15), {
						BackgroundColor3 = Color3.fromRGB(40, 40, 56),
					}):Play()
				end
				selected = btn
				if btn then
					TweenService:Create(btn, TweenInfo.new(0.15), {
						BackgroundColor3 = Color3.fromRGB(100, 75, 220),
					}):Play()
				end
			end

			local function addMorphButton(morph)
				if buttons[morph.Name] then return end

				local b = Instance.new("TextButton")
				b.Name = morph.Name
				b.Size = UDim2.new(1, -6, 0, 38)
				b.BackgroundColor3 = Color3.fromRGB(40, 40, 56)
				b.Text = morph.Name
				b.Font = Enum.Font.GothamMedium
				b.TextSize = 15
				b.TextColor3 = Color3.new(1, 1, 1)
				b.AutoButtonColor = false
				b.Parent = list
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

				b.MouseEnter:Connect(function()
					if b ~= selected then
						TweenService:Create(b, TweenInfo.new(0.12), {
							BackgroundColor3 = Color3.fromRGB(56, 56, 78),
						}):Play()
					end
				end)
				b.MouseLeave:Connect(function()
					if b ~= selected then
						TweenService:Create(b, TweenInfo.new(0.12), {
							BackgroundColor3 = Color3.fromRGB(40, 40, 56),
						}):Play()
					end
				end)

				b.MouseButton1Click:Connect(function()
					if morphInto(morph) then
						setSelected(b)
						status.Text = morphMessage(morph.Name)
					else
						status.Text = "Failed: no Hats folder"
					end
				end)

				buttons[morph.Name] = b
			end

			local count = 0
			for _, morph in ipairs(morphFolder:GetChildren()) do
				addMorphButton(morph)
				count += 1
			end
			status.Text = count > 0 and ("Pick a morph (" .. count .. " found)")
				or "No morphs found - check Output for details"

			connect(morphFolder.ChildAdded, function(child)
				task.wait(0.2)
				if alive then addMorphButton(child) end
			end)

			connect(morphFolder.ChildRemoved, function(child)
				local b = buttons[child.Name]
				if b then
					if b == selected then selected = nil end
					b:Destroy()
					buttons[child.Name] = nil
				end
			end)

			search:GetPropertyChangedSignal("Text"):Connect(function()
				local q = search.Text:lower()
				for name, b in pairs(buttons) do
					b.Visible = q == "" or name:lower():find(q, 1, true) ~= nil
				end
			end)

			resetBtn.MouseButton1Click:Connect(function()
				resetMorph()
				setSelected(nil)
				status.Text = "Outfit restored"
			end)

			----------------------------------------------------------------
			-- Tabs / minimize
			----------------------------------------------------------------
			local minimized = false
			local fullSize = main.Size
			local currentTab = "morphs"

			local function refreshVisibility()
				for _, item in ipairs({ status, resetBtn, tabBar }) do
					item.Visible = not minimized
				end
				search.Visible = (not minimized) and currentTab ~= "misc"
				list.Visible = (not minimized) and currentTab == "morphs"
				customList.Visible = (not minimized) and currentTab == "custom"
				miscList.Visible = (not minimized) and currentTab == "misc"
			end

			local ACTIVE = Color3.fromRGB(100, 75, 220)
			local INACTIVE = Color3.fromRGB(40, 40, 56)

			local function setTab(name)
				currentTab = name
				morphsTab.BackgroundColor3 = name == "morphs" and ACTIVE or INACTIVE
				customTab.BackgroundColor3 = name == "custom" and ACTIVE or INACTIVE
				miscTab.BackgroundColor3 = name == "misc" and ACTIVE or INACTIVE
				search.Text = ""
				search.PlaceholderText = name == "custom" and "Type a Roblox username + Enter to add"
					or "Search morphs..."
				refreshVisibility()
			end

			morphsTab.MouseButton1Click:Connect(function() setTab("morphs") end)
			customTab.MouseButton1Click:Connect(function() setTab("custom") end)
			miscTab.MouseButton1Click:Connect(function() setTab("misc") end)

			----------------------------------------------------------------
			-- Custom (username) morphs
			----------------------------------------------------------------
			local function morphIntoUser(username, btn)
				status.Text = "Loading " .. username .. "..."
				task.spawn(function()
					local okId, userId = pcall(function()
						return Players:GetUserIdFromNameAsync(username)
					end)
					if not okId or not userId then
						status.Text = "User not found: " .. username
						return
					end

					local okM, model = pcall(function()
						return Players:GetCharacterAppearanceAsync(userId)
					end)
					if not okM or not model then
						warn("[MorphGui] couldn't load appearance for " .. username .. ": " .. tostring(model))
						status.Text = "Couldn't load " .. username .. "'s avatar"
						return
					end

					local container = Instance.new("Folder")
					container.Name = username
					for _, c in ipairs(model:GetChildren()) do
						if c:IsA("Accessory") or c:IsA("Hat") or c:IsA("Shirt") or c:IsA("Pants")
							or c:IsA("ShirtGraphic") or c:IsA("BodyColors") then
							c.Parent = container
						end
					end
					model:Destroy()

					if morphInto(container, container) then
						setSelected(btn)
						status.Text = morphMessage(username)
					else
						status.Text = "Failed to morph into " .. username
					end
				end)
			end

			local customButtons = {}

			local function addCustomEntry(username)
				local key = username:lower()
				if customButtons[key] then return end

				local b = Instance.new("TextButton")
				b.Name = key
				b.Size = UDim2.new(1, -6, 0, 38)
				b.BackgroundColor3 = Color3.fromRGB(40, 40, 56)
				b.Text = "@" .. username
				b.Font = Enum.Font.GothamMedium
				b.TextSize = 15
				b.TextColor3 = Color3.new(1, 1, 1)
				b.AutoButtonColor = false
				b.Parent = customList
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

				b.MouseEnter:Connect(function()
					if b ~= selected then
						TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(56, 56, 78) }):Play()
					end
				end)
				b.MouseLeave:Connect(function()
					if b ~= selected then
						TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(40, 40, 56) }):Play()
					end
				end)

				b.MouseButton1Click:Connect(function()
					morphIntoUser(username, b)
				end)

				customButtons[key] = b
			end

			addCustomEntry("chayofigel")

			search.FocusLost:Connect(function(enterPressed)
				if enterPressed and currentTab == "custom" then
					local name = search.Text:gsub("%s", "")
					if name ~= "" then
						addCustomEntry(name)
						status.Text = "Added @" .. name
					end
					search.Text = ""
				end
			end)

			----------------------------------------------------------------
			-- Misc tab
			----------------------------------------------------------------
			local function makeToggle(name, text, callback, initial)
				local row = Instance.new("TextButton")
				row.Name = name
				row.Size = UDim2.new(1, -6, 0, 40)
				row.BackgroundColor3 = Color3.fromRGB(40, 40, 56)
				row.Text = ""
				row.AutoButtonColor = false
				row.Parent = miscList
				Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.new(1, -70, 1, 0)
				label.Position = UDim2.fromOffset(12, 0)
				label.Text = text
				label.Font = Enum.Font.GothamMedium
				label.TextSize = 14
				label.TextColor3 = Color3.new(1, 1, 1)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.Parent = row

				local track = Instance.new("Frame")
				track.Size = UDim2.fromOffset(40, 20)
				track.Position = UDim2.new(1, -52, 0.5, -10)
				track.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
				track.BorderSizePixel = 0
				track.Parent = row
				Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

				local knob = Instance.new("Frame")
				knob.Size = UDim2.fromOffset(16, 16)
				knob.Position = UDim2.new(0, 2, 0.5, -8)
				knob.BackgroundColor3 = Color3.new(1, 1, 1)
				knob.BorderSizePixel = 0
				knob.Parent = track
				Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

				local on = initial == true
				local function render()
					local info = TweenInfo.new(0.15)
					TweenService:Create(track, info, {
						BackgroundColor3 = on and ACTIVE or Color3.fromRGB(70, 70, 90),
					}):Play()
					TweenService:Create(knob, info, {
						Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
					}):Play()
				end
				render()

				row.MouseButton1Click:Connect(function()
					on = not on
					render()
					callback(on)
				end)

				return row
			end

			local function makeMiscButton(name, text, color)
				local b = Instance.new("TextButton")
				b.Name = name
				b.Size = UDim2.new(1, -6, 0, 40)
				b.BackgroundColor3 = color
				b.Text = text
				b.Font = Enum.Font.GothamBold
				b.TextSize = 14
				b.TextColor3 = Color3.new(1, 1, 1)
				b.AutoButtonColor = true
				b.Parent = miscList
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
				return b
			end

			-- (Third Person toggle removed: use the THIRDPERSON button from the main script)

			makeToggle("B_HideHead", "Hide Face & Head (morphed)", function(on)
				hideHead = on
				applyHeadState()
				status.Text = on and "Face & head hidden while morphed" or "Face & head shown"
			end)

			makeToggle("C_AutoRefresh", "Auto Refresh (fix changes)", function(on)
				autoRefresh = on
				status.Text = on and "Auto refresh: ON" or "Auto refresh: OFF"
				if on then scheduleReconcile("auto refresh turned on") end
			end, true)

			makeToggle("D_LockLook", "Lock Look (undo recolors)", function(on)
				lockLookOn = on
				status.Text = on and "Look lock: ON" or "Look lock: OFF"
			end, true)

			makeToggle("D_M_FPBody", "First Person: Show Body", function(on)
				fpBody = on
				status.Text = on and "First person: full body visible (head hidden)" or "First person body: OFF"
			end)

			makeToggle("D_N_FPHeadAcc", "First Person: Hide Head Accs", function(on)
				fpHideHeadAcc = on
				status.Text = on and "Head accessories always hidden in first person" or "Head accessory hiding: OFF"
			end)

			local refreshBtn = makeMiscButton("E_Refresh", "Refresh Morph / Camera", Color3.fromRGB(60, 160, 255))
			local rebuildBtn = makeMiscButton("F_Rebuild", "Rebuild Morph (from scratch)", Color3.fromRGB(90, 110, 200))

			local function doRefreshButton(force)
				local msgs = {}
				if currentMorphObj then
					local stats = locked(refreshNow, force)
					if stats then
						msgs[#msgs + 1] = force and ("rebuilt " .. #plan .. " pieces") or describe(stats)
					end
				end
				if not force and thirdPerson then
					task.spawn(pushOut)
					msgs[#msgs + 1] = "camera reset"
				end
				status.Text = #msgs > 0 and ((force and "Rebuild: " or "Refresh: ") .. table.concat(msgs, ", "))
					or "Nothing to refresh"
			end

			refreshBtn.MouseButton1Click:Connect(function() doRefreshButton(false) end)
			rebuildBtn.MouseButton1Click:Connect(function() doRefreshButton(true) end)

			setTab("morphs")

			----------------------------------------------------------------
			-- Unload (X button, or re-executing the script)
			----------------------------------------------------------------
			local function unload()
				if not alive then return end

				-- put the original outfit back, switch the features off
				pcall(function()
					if currentMorphObj then resetNow() end
				end)
				pcall(function() setThirdPerson(false) end)
				hideHead = false
				pcall(applyHeadState)

				-- hand first person visibility back to the game
				fpBody, fpHideHeadAcc = false, false
				pcall(fpStep)
				pcall(function() RunService:UnbindFromRenderStep("MorphGuiFP") end)

				alive = false
				pcall(function() RunService:UnbindFromRenderStep("MorphGuiLook") end)
				for _, c in ipairs(conns) do
					pcall(function() c:Disconnect() end)
				end
				table.clear(conns)
				disconnectChar()
				table.clear(looks)
				table.clear(bodyLook)
				if env.MorphGuiUnload == unload then
					env.MorphGuiUnload = nil
				end
				if embedded then pcall(function() main:Destroy() end) end
				if gui then
					pcall(function() gui:Destroy() end)
				end
			end

			env.MorphGuiUnload = unload

			----------------------------------------------------------------
			-- Window behaviour
			----------------------------------------------------------------
			title.ZIndex = 10
			titleLabel.ZIndex = 11
			closeBtn.ZIndex = 12
			minBtn.ZIndex = 12

			minBtn.MouseButton1Click:Connect(function()
				minimized = not minimized
				refreshVisibility()
				local target = minimized and UDim2.fromOffset(fullSize.X.Offset, 42) or fullSize
				TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Size = target }):Play()
				minBtn.Text = minimized and "+" or "-"
			end)

			closeBtn.MouseButton1Click:Connect(unload)

			connect(UserInputService.InputBegan, function(input, processed)
				if processed or embedded then return end
				if input.KeyCode == Enum.KeyCode.RightShift then
					main.Visible = not main.Visible
				end
			end)

			local dragging = false
			local dragStart, startPos

			title.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					dragStart = input.Position
					startPos = main.Position

					input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then
							dragging = false
						end
					end)
				end
			end)

			connect(UserInputService.InputChanged, function(input)
				if not dragging then return end
				if input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch then
					local delta = input.Position - dragStart
					main.Position = UDim2.new(
						startPos.X.Scale, startPos.X.Offset + delta.X,
						startPos.Y.Scale, startPos.Y.Offset + delta.Y
					)
				end
			end)

			print("[MorphGui] v5 loaded - GUI is in PlayerGui.MorphGui (RightShift hides/shows it, X unloads it)")
		end, function(e) return tostring(e) .. " | " .. tostring(debug and debug.traceback and debug.traceback("", 2) or "") end)
		if not ok then warn("[MorphGui] failed: " .. tostring(err)) end
	end)
end)
