--------------------------------------------------------------------------
--[[ WorldCharacterSelectLobby class definition ]]
--------------------------------------------------------------------------

return Class(function(self, inst)

--------------------------------------------------------------------------
--[[ Constants ]]
--------------------------------------------------------------------------

local ALLOW_DEBUG_START = BRANCH == "dev"

local COUNTDOWN_TIME = ALLOW_DEBUG_START and 1 or 6
local COUNTDOWN_INACTIVE = 255

--------------------------------------------------------------------------
--[[ Member variables ]]
--------------------------------------------------------------------------

--Public
self.inst = inst

-- various parts of the code need to access these config vars
self.MIN_PLAYERS = 2
self.ADMIN_MODE = "ALL"
self.LATE_JOIN = true

--Private
local _world = TheWorld
local _ismastersim = _world.ismastersim

local _lobby_up_time = 0
local _client_wait_time = {}

--Master simulation
local _countdownf = -1

--Network
local _countdowni = net_byte(inst.GUID, "worldcharacterselectlobby._countdowni", "spawncharacterdelaydirty")
local _lockedforshutdown = net_bool(inst.GUID, "worldcharacterselectlobby._lockedforshutdown", "lockedforshutdown")

local _players_ready_to_start = {}
for i = 1, TheNet:GetServerMaxPlayers() do
	table.insert(_players_ready_to_start, net_string(inst.GUID, "worldcharacterselectlobby._players_ready_to_start."..i, "player_ready_to_start_dirty"))
end

--------------------------------------------------------------------------
--[[ Local Functions ]]
--------------------------------------------------------------------------
local function GetPlayersClientTable()
    local clients = TheNet:GetClientTable() or {}
    if not TheNet:GetServerIsClientHosted() then
		for i, v in ipairs(clients) do
			if v.performance ~= nil then
				table.remove(clients, i) -- remove "host" object
				break
			end
		end
    end
    return clients
end

local function SetPlayerReadyToStart(userid, is_ready)
	if _countdowni:value() ~= COUNTDOWN_INACTIVE then
		return
	end
	    
    if is_ready then
		local empty_slot = nil
		for i, v in ipairs(_players_ready_to_start) do
			local value = v:value()
			if value == userid then
				return
			elseif value == "" then
				empty_slot = i
			end
		end
		if empty_slot ~= nil then
			_players_ready_to_start[empty_slot]:set(userid)
		end
    else
		for i, v in ipairs(_players_ready_to_start) do
			if v:value() == userid then
				_players_ready_to_start[i]:set("")
				return
			end
		end
	end
end

local function TogglePlayerReadyToStart(userid)
	if _countdowni:value() ~= COUNTDOWN_INACTIVE then
		return
	end

	local empty_slot = nil
	for i, v in ipairs(_players_ready_to_start) do
		local value = v:value()
		if value == userid then
			_players_ready_to_start[i]:set("")
			return
		elseif value == "" then
			empty_slot = i
		end
	end
	if empty_slot ~= nil then
		_players_ready_to_start[empty_slot]:set(userid)
	end
end

--------------------------------------------------------------------------
--[[ Global Setup ]]
--------------------------------------------------------------------------

AddUserCommand("playerreadytostart", {
    prettyname = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.PRETTYNAME
    desc = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.DESC
    permission = COMMAND_PERMISSION.USER,
    slash = false,
    usermenu = false,
    servermenu = false,
    params = {"ready"},
    vote = false,
    canstartfn = function(command, caller, targetid)
        return _countdowni:value() == COUNTDOWN_INACTIVE and not _lockedforshutdown:value()
    end,
    serverfn = function(params, caller)
		TogglePlayerReadyToStart(caller.userid)
    end,
})

--------------------------------------------------------------------------
--[[ Private Server event handlers ]]
--------------------------------------------------------------------------

local function ClearAllPlayersReadyToStart()
	for i, v in ipairs(_players_ready_to_start) do
		v:set("")
	end
end

local function CalcLobbyUpTime()
	return _lobby_up_time and (GetTimeRealSeconds() - _lobby_up_time) or 0
end

local function StarTimer(time)
	print ("[WorldCharacterSelectLobby] Countdown started")
	TheNet:Announce("Starting game in "..time.." seconds...")

	local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
	if analytics ~= nil then
		analytics:SendAnalyticsLobbyEvent("lobby.startmatch", nil, { up_time = CalcLobbyUpTime() })
	
		for userid, _ in pairs(_client_wait_time) do
			local data = {play_t = _client_wait_time[userid] ~= nil and (GetTimeRealSeconds() - _client_wait_time[userid]) or 0}
			analytics:SendAnalyticsLobbyEvent("lobby.clientstartmatch", userid, data)
		end
	end

	_countdownf = time
    _countdowni:set(math.ceil(time))

	if not self.LATE_JOIN then
		TheNet:SetAllowNewPlayersToConnect(false)
	end
    TheNet:SetIsMatchStarting(true)
	ClearAllPlayersReadyToStart()

	self.inst:StartWallUpdatingComponent(self)
end

-- used by the admin's "start" button
AddUserCommand("forcestartgame", {
	prettyname = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.PRETTYNAME
	desc = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.DESC
	permission = COMMAND_PERMISSION.ADMIN,
	-- seems like slash commands dont work in the lobby screen :(
	slash = true,
	usermenu = false,
	servermenu = false,
	params = {},
	vote = false,
	canstartfn = function(command, caller, targetid)
		return _countdowni:value() == COUNTDOWN_INACTIVE and not _lockedforshutdown:value()
	end,
	serverfn = function(params, caller)
		StarTimer(COUNTDOWN_TIME)
	end,
})

local function CountPlayersReadyToStart()
	local count = 0
	for i, v in ipairs(_players_ready_to_start) do
		if v:value() ~= "" then
			count = count + 1
		end
	end
	return count
end

local function TryStartCountdown()
	if not self:IsAllowingCharacterSelect() then
		return
	end

-- case
	local modeActions = {
		["ALL"] = function()
			local clients = GetPlayersClientTable()
			if CountPlayersReadyToStart() < #clients or CountPlayersReadyToStart() < self.MIN_PLAYERS then
				return
			end
			StarTimer(COUNTDOWN_TIME)
		end,
		["MIN"] = function()
			local clients = GetPlayersClientTable()
			if CountPlayersReadyToStart() < self.MIN_PLAYERS then
				return
			end
			StarTimer(COUNTDOWN_TIME)
		end,
		["ADMIN"] = function()
			-- Do nothing because admin start is triggered elsewhere
		end,
	}
	local func = modeActions[self.ADMIN_MODE]
	if (func) then
		func()
	else
		print("Error: Unknown Mode: ", self.ADMIN_MODE)
	end
end

local function OnRequestLobbyCharacter(world, data)
	if data == nil or not self:IsAllowingCharacterSelect() then
		return
	end

	local client = TheNet:GetClientTableForUser(data.userid)
	if not client then
		return
	end

	TheNet:SetLobbyCharacter(data.userid, data.prefab_name, data.skin_base, data.clothing_body, data.clothing_hand, data.clothing_legs, data.clothing_feet)
	SetPlayerReadyToStart(data.userid, false)
	
	TryStartCountdown()
end

local function OnLobbyClientConnected(src, data)
	ClearAllPlayersReadyToStart()

	if _countdowni:value() == COUNTDOWN_INACTIVE then
		if GetTableSize(_client_wait_time) == 0 then
			_lobby_up_time = GetTimeRealSeconds()
		end
		_client_wait_time[data.userid] = GetTimeRealSeconds()

		
		local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
		if analytics ~= nil then
			local msg = {}
			msg.up_time = CalcLobbyUpTime()
			analytics:SendAnalyticsLobbyEvent("lobby.join", nil, msg)
		end		
	else		
		-- players will have no choice but to disconncet at this point.
	end
end

local function OnLobbyClientDisconnected(src, data)
	ClearAllPlayersReadyToStart()

	if self:IsAllowingCharacterSelect() and _client_wait_time[data.userid] ~= nil then
		local wait_time = _client_wait_time[data.userid] and (GetTimeRealSeconds() - _client_wait_time[data.userid]) or 0
		_client_wait_time[data.userid] = nil 
		local num_remaining_players = GetTableSize(_client_wait_time)

		local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
		if analytics ~= nil then
			local msg = {}
			msg.up_time = CalcLobbyUpTime()
			msg.play_t = wait_time
			msg.consecutive_match = TheNet:IsConsecutiveMatchForPlayer(data.userid)
			local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
			analytics:SendAnalyticsLobbyEvent("lobby.leave", data.userid, msg)
		
			if GetTableSize(_client_wait_time) == 0 then
				local msg2 = {}
				msg2.up_time = msg.up_time
				analytics:SendAnalyticsLobbyEvent("lobby.cancelmatch", nil, msg2)

				_lobby_up_time = nil
			end
		end
	end
end



--------------------------------------------------------------------------
--[[ Private Client event handlers ]]
--------------------------------------------------------------------------

local function OnCountdownDirty()
    if _ismastersim and _countdowni:value() == 0 then
        inst:StopWallUpdatingComponent(self)
        print("[WorldCharacterSelectLobby] Countdown finished")
        TheNet:Announce("Game Started!")

        --Use regular update to poll for when to clear match starting flag
        inst:StartUpdatingComponent(self)
    end

    local t = _countdowni:value()
    _world:PushEvent("lobbyplayerspawndelay", { time = t, active = t ~= COUNTDOWN_INACTIVE })
end

--------------------------------------------------------------------------
--[[ Initialization ]]
--------------------------------------------------------------------------

--Initialize network variables
_countdowni:set(COUNTDOWN_INACTIVE)

--Register network variable sync events
inst:ListenForEvent("spawncharacterdelaydirty", OnCountdownDirty)

if _ismastersim then
    TheNet:SetIsMatchStarting(false) --Reset flag in case it's invalid

    --Register events
    inst:ListenForEvent("ms_requestedlobbycharacter", OnRequestLobbyCharacter, _world)
    inst:ListenForEvent("player_ready_to_start_dirty", TryStartCountdown)
    inst:ListenForEvent("ms_clientauthenticationcomplete", OnLobbyClientConnected, _world)
    inst:ListenForEvent("ms_clientdisconnected", OnLobbyClientDisconnected, _world)

	local clients = GetPlayersClientTable()
	for _, c in ipairs(clients) do
		OnLobbyClientConnected(TheWorld, {userid = c.userid})
	end
end

--------------------------------------------------------------------------
--[[ Public members ]]
--------------------------------------------------------------------------

function self:GetSpawnDelay()
	local delay = _countdowni:value()
	return delay ~= COUNTDOWN_INACTIVE and delay or -1
end

if _ismastersim then function self:IsAllowingCharacterSelect()
	return _countdowni:value() == COUNTDOWN_INACTIVE and not _lockedforshutdown:value()
end end

function self:IsServerLockedForShutdown()
	return _lockedforshutdown:value()
end

function self:IsPlayerReadyToStart(userid)
	for i, v in ipairs(_players_ready_to_start) do
		if v:value() == userid then
			return true
		end
	end
	return false
end

if _ismastersim then function self:OnPostInit()
	if TheNet:GetDeferredServerShutdownRequested() then
		_lockedforshutdown:set(true)
	end
end end

-- TheWorld.net.components.worldcharacterselectlobby:Dump()
function self:Dump()
	local str = ""
	for i, v in ipairs(_players_ready_to_start) do
		str = str .. ", " .. tostring(v:value())
	end
	print(str)
end

function self:CanPlayersSpawn()
	return _countdownf == 0
end

-- Simple wrapper of the local function to expose it as a public function
function self:CountPlayersReadyToStart()
	return CountPlayersReadyToStart()
end

-- client will need to know if the game has started (e.g. so they go to the game instead of the lobby)
-- similar to CanPlayersSpawn() but works clientside
function self:HasGameStarted()
	return _countdowni:value() == 0
end

--------------------------------------------------------------------------
--[[ Update ]]
--------------------------------------------------------------------------

function self:OnWallUpdate(dt)
	_countdownf = math.max(0, _countdownf - dt)
	local c = math.ceil(_countdownf)
	if _countdowni:value() ~= c then
		_countdowni:set(c)
	end
end

function self:OnUpdate(dt)
    if #AllPlayers <= 0 then
        local clients = TheNet:GetClientTable()
        if clients ~= nil then
            local isdedicated = not TheNet:GetServerIsClientHosted()
            for i, v in ipairs(TheNet:GetClientTable() or {}) do
                if not isdedicated or v.performance == nil then
                    --Still someone connected
                    return
                end
            end
        end
    end
    --Either someone has spawned in, or everybody disconnceted
    TheNet:SetIsMatchStarting(false)
    inst:StopUpdatingComponent(self)
end

--------------------------------------------------------------------------
--[[ Save/Load ]]
--------------------------------------------------------------------------

if _ismastersim then function self:OnSave()
	local data =
	{
		match_started = _countdowni:value() == 0,
	}

	return data
end end

if _ismastersim then function self:OnLoad(data)
	if data then
		if data.match_started then
			_countdownf = 0
			_countdowni:set(0)
			if not self.LATE_JOIN then
				inst:DoTaskInTime(0, function() TheNet:SetAllowNewPlayersToConnect(false) end)
			end
		end
	end
end end

--------------------------------------------------------------------------
--[[ End ]]
--------------------------------------------------------------------------

end)