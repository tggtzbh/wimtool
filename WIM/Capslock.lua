﻿--[[
Author:			Mimma
Create Date:	2018-02-04

The latest version of Capslock can always be found at:
https://armory.digam.dk/capslock

The source code can be found at Github:
https://github.com/Sentilix/capslock

Please see the ReadMe.txt for addon details.

Change by 夜晨 2023-08-06
修复部分报错
增加监控频道设置选项
增加设置监控的关键词功能
增加灵魂碎片和召唤仪式技能有没有的判断
]]


-- Channel settings:
local PARTY_CHANNEL					= "PARTY"
local RAID_CHANNEL					= "RAID"
local YELL_CHANNEL					= "YELL"
local SAY_CHANNEL					= "SAY"
local WARN_CHANNEL					= "RAID_WARNING"
local GUILD_CHANNEL					= "GUILD"
local WHISPER_CHANNEL				= "WHISPER"
local CHAT_END						= "|r"
local COLOUR_CHAT   				= "|c80ffff00"
local COLOUR_INTRO  				= "|c8080A0F8"
local CAPSLOCK_PREFIX				= "Capslockv1"
local CTRA_PREFIX					= "CTRA"


--	Sync.state: 0=idle, 1=initializing, 2=synchronizing
local synchronizationState			= 0;
local synchronizationSource			= "";
-- To be configurable:
--	Update player status each <n> second:
CAPSLOCK_OPTION_PLAYER_UPDATE		= 2;

-- Globals:
CAPSLOCK_TITAN_ID					= "Capslock"
CAPSLOCK_TITAN_TITLE				= "CAPSLOCK"
CAPSLOCK_AND_TITAN_LOADED			= 0

local CAPSLOCK_CURRENT_VERSION		= 0
local CAPSLOCK_UPDATE_MESSAGE_SHOWN = false

-- List of people (in raid) requesting a summon.
-- Format is: { <playername>, <priority>, <playerstatus>, <location> }
-- Player status: 0=ready, 1=Offline, 2=Dead, 3=Not in Instance
local CAPSLOCK_SUMMON_QUEUE			= {}
local CAPSLOCK_SUMMON_KEYWORD		= "123"
local CAPSLOCK_SUMMON_MAXVISIBLE	= 6
local CAPSLOCK_SUMMON_MAXQUEUED		= 40
-- TRUE if summon dialog is open. "!summon" will always be accepted/queued.
local CAPSLOCK_SUMMON_ENABLED		= false;



--[[
--	Echo a message for the local user only.
--	Added in: 0.0.1
--]]
local function echo(msg)
	if not msg then
		msg = ""
	end
	DEFAULT_CHAT_FRAME:AddMessage(COLOUR_CHAT .. msg .. CHAT_END)
end

--[[
--	Echo in raid chat (if in raid) or party chat (if not)
--	Added in: 0.0.1
--]]
function CAPSLOCK_PartyEcho(msg)
	if CAPSLOCK_IsInRaid() then
		SendChatMessage(msg, RAID_CHANNEL)
	elseif CAPSLOCK_IsInParty() then
		SendChatMessage(msg, PARTY_CHANNEL)
	end
end

--[[
--	Echo a message for the local user only, including CAPSLOCK "logo"
--	Added in: 0.0.1
--]]
function CAPSLOCK_Echo(msg)
	echo("<"..COLOUR_INTRO.."CAPSLOCK"..COLOUR_CHAT.."> "..msg);
end


--[[
--	Whisper specific target with a message.
--	Added in: 0.0.1
--]]
 function CAPSLOCK_Whisper(receiver, msg)
	if not CAPSLOCK_IsHaveSoulShard() then
		return;
	end
	
	if receiver == UnitName("player") then
		CAPSLOCK_Echo(msg);
	else
		SendChatMessage(msg, WHISPER_CHANNEL, nil, receiver);
	end

end




--  *******************************************************
--
--	Slash commands
--
--  *******************************************************

--[[
--	Main entry for CAPSLOCK.
--	This will send the request to one of the sub slash commands.
--	Syntax: /capslock [option, defaulting to "summon"]
--	Added in: 0.0.1
--]]
SLASH_CAPSLOCK_CAPSLOCK1 = "/capslock"
SLASH_CAPSLOCK_CAPSLOCK2 = "/caps"
SlashCmdList["CAPSLOCK_CAPSLOCK"] = function(msg)
	local _, _, option = string.find(msg, "(%S*)")

	if not option or option == "" then
		option = "TOGGLE"
	end
	option = string.upper(option);
		
	if (option == "SUM" or option == "SUMMON") then
		SlashCmdList["CAPSLOCK_SUMMON"]();
	elseif option == "SHOW" then
		SlashCmdList["CAPSLOCK_SHOW_SUMMON"]();
	elseif option == "HIDE" then
		SlashCmdList["CAPSLOCK_HIDE_SUMMON"]();
	elseif option == "TOGGLE" then
		SlashCmdList["CAPSLOCK_TOGGLE_SUMMON"]();
	elseif option == "HELP" then
		SlashCmdList["CAPSLOCK_HELP"]();
	elseif (option == "VER") or (option == "VERSION") then
		SlashCmdList["CAPSLOCK_VERSION"]();
	elseif (option == "ONLY") then
		SlashCmdList["CAPSLOCK_ONLYWHISPER_SUMMON"]();
	else
		CAPSLOCK_Echo(string.format("未知命令: %s", option));
	end
end



--[[
--	Summon highest priority target.
--	Syntax: /capslocksummon
--	Alternatives: /capssum, /summon
--	If a playername is added, he/she will be added to summon queue.
--	Added in: 0.0.1
--]]
SLASH_CAPSLOCK_SUMMON1 = "/capslocksummon"
SLASH_CAPSLOCK_SUMMON2 = "/capssum"
SLASH_CAPSLOCK_SUMMON3 = "/summon"
SlashCmdList["CAPSLOCK_SUMMON"] = function(msg)
	if CAPSLOCK_IsWarlock() then
		
		local _, _, playername = string.find(msg, "(%S*)");
		if playername == "" then
			CAPSLOCK_SummonPriorityTarget();
		else
			-- If no zone, then this player is not in the party/raid.
			-- playername = CAPSLOCK_UCFirst(playername);
			local zone = CAPSLOCK_GetPlayerZone(playername);
			if zone then
				CAPSLOCK_AddToSummonQueue(playername);
			else
				CAPSLOCK_Echo(string.format("%s 不在团队/小队!", playername));
			end;		
		end;
	end;
end


--[[
--	Request client version information
--	Syntax: /capslockversion
--	Added in: 0.0.1
--]]
SLASH_CAPSLOCK_VERSION1 = "/capslockversion"
SlashCmdList["CAPSLOCK_VERSION"] = function(msg)
	if CAPSLOCK_IsInRaid() or CAPSLOCK_IsInParty() then
		CAPSLOCK_SendAddonMessage("TX_VERSION##");
	else
		CAPSLOCK_Echo(string.format("%s 正在使用 CAPSLOCK 版本 %s", UnitName("player"), GetAddOnMetadata("Capslock", "Version")));
	end
end

--[[
--	SHow/hide CAPSLOCK summon dialog
--	Syntax: /capslock
--	Alternative: /caps
--	Added in: 0.0.1
--]]
CAPSLOCK_TOGGLE_SUMMON1 = "/capslock"
CAPSLOCK_TOGGLE_SUMMON2 = "/caps"
SlashCmdList["CAPSLOCK_TOGGLE_SUMMON"] = function(msg)
	if CAPSLOCK_IsWarlock() then
		CAPSLOCK_ToggleConfigurationDialog();
	end;
end

CAPSLOCK_ONLYWHISPER_SUMMON = "/capsonly"
SlashCmdList["CAPSLOCK_ONLYWHISPER_SUMMON"] = function(msg)
	CAPSLOCK_ChangeWhisper()
end

--[[
--	Show CAPSLOCK summon dialog
--	Syntax: /capsshow
--	Alternative: /caps show
--	Added in: 0.0.1
--]]
CAPSLOCK_SHOW_SUMMON = "/capsshow"
SlashCmdList["CAPSLOCK_SHOW_SUMMON"] = function(msg)
	if CAPSLOCK_IsWarlock() then
		CAPSLOCK_OpenConfigurationDialog();
	end;
end

--[[
--	Hide CAPSLOCK summon dialog
--	Syntax: /capshide
--	Alternative: /caps hide
--	Added in: 0.0.1
--]]
CAPSLOCK_HIDE_SUMMON = "/capshide"
SlashCmdList["CAPSLOCK_HIDE_SUMMON"] = function(msg)
	if CAPSLOCK_IsWarlock() then
		CAPSLOCK_CloseConfigurationDialog();
	end;
end

--[[
--	Show HELP options
--	Syntax: /capslockhelp
--	Alternative: /capslock help
--	Added in: 0.0.1
--]]
SLASH_CAPSLOCK_HELP1 = "/capslockhelp"
SlashCmdList["CAPSLOCK_HELP"] = function(msg)
	CAPSLOCK_Echo(string.format("CAPSLOCK version %s - by Mimma @ vanillagaming.org", GetAddOnMetadata("Capslock", "Version")));
	CAPSLOCK_Echo("语法:");
	CAPSLOCK_Echo("    /capslock [选项]");
	CAPSLOCK_Echo("选项列表:");
	CAPSLOCK_Echo("    Show         显示/隐藏设置列表窗口");
	CAPSLOCK_Echo("    only      	监控频道关键词设置");
	CAPSLOCK_Echo("    Summon       召唤下一个目标，如果目标已经加入，立即召唤");
	CAPSLOCK_Echo("    Help         此语法列表");
	CAPSLOCK_Echo("    Version      获取版本");

end



--  *******************************************************
--
--	Configuration functions
--
--  *******************************************************
function CAPSLOCK_ToggleConfigurationDialog()
	if CAPSLOCK_SUMMON_ENABLED then
		CAPSLOCK_CloseConfigurationDialog();
	else
		CAPSLOCK_OpenConfigurationDialog();
	end;
end;



function CAPSLOCK_OpenConfigurationDialog()
	CAPSLOCK_SUMMON_ENABLED = true;
	CAPSLOCK_UpdateMessageList();
	CapslockFrame:Show();
	CAPSLOCK_Config_SetKeyWordText()
	
end;

function CAPSLOCK_CloseConfigurationDialog()
	CAPSLOCK_SUMMON_ENABLED = false;
	CapslockFrame:Hide();
end;

function CAPSLOCK_Config_SetKeyWordText()
	getglobal("Capslock_KeyWordEditBox"):SetText(CAPSLOCK_KEYWORD);
end

function CAPSLOCK_Config_GetKeyWordText()
	CAPSLOCK_KEYWORD = getglobal("Capslock_KeyWordEditBox"):GetText();
	if CAPSLOCK_KEYWORD == "" then
		CAPSLOCK_KEYWORD = "求拉";
	end
end

function CAPSLOCK_ChangeWhisper()
	if CAPSLOCK_ONLY_WHISPER then
		CAPSLOCK_ONLY_WHISPER = false;
		CAPSLOCK_Echo("监控密语/小队/团队频道")
		
	else
		CAPSLOCK_ONLY_WHISPER = true;
		CAPSLOCK_Echo("只监控密语频道")
	end
	CAPSLOCK_Config_OnLoad()
end

function CAPSLOCK_Config_SetButtonState(val)
	if (val == 0 or val == false or val == nil) then
		getglobal("Capslock_CheckButton"):SetChecked(0);
	else
		getglobal("Capslock_CheckButton"):SetChecked(1);
	end
end

function CAPSLOCK_Config_OnLoad()
	CAPSLOCK_Config_SetButtonState(CAPSLOCK_ONLY_WHISPER); -- 是否只使用密语频道 还是使用密语+队伍+团队
end

--  *******************************************************
--
--	Helper functions
--
--  *******************************************************

function CAPSLOCK_IsWarlock()
	return (UnitClass("player") == "术士");
end;


function CAPSLOCK_IsInParty()
	if not CAPSLOCK_IsInRaid() then
		return ( GetNumPartyMembers() > 0 );
	end
	return false
end


function CAPSLOCK_IsInRaid()
	return ( GetNumRaidMembers() > 0 );
end


--[[
	Convert a msg so first letter is uppercase, and rest as lower case.
]]
function CAPSLOCK_UCFirst(msg)
	if not msg then
		return ""
	end	

	-- local f = string.sub(msg, 1, 1)
	-- local r = string.sub(msg, 2)
	-- return string.upper(f) .. string.lower(r)
	return msg
end


function CAPSLOCK_SortTableAscending(sourcetable, index)
	local doSort = true
	while doSort do
		doSort = false
		for n=table.getn(sourcetable), 2, -1 do
			local a = sourcetable[n - 1];
			local b = sourcetable[n];
			if (a[index]) > (b[index]) then
				sourcetable[n - 1] = b;
				sourcetable[n] = a;
				doSort = true;
			end
		end
	end
	return sourcetable;
end

function CAPSLOCK_SortTableDescending(sourcetable, index)
	local doSort = true
	while doSort do
		doSort = false
		for n=1,table.getn(sourcetable) - 1, 1 do
			local a = sourcetable[n]
			local b = sourcetable[n + 1]
			if (a[index]) < (b[index]) then
				sourcetable[n] = b
				sourcetable[n + 1] = a
				doSort = true
			end
		end
	end
	return sourcetable;
end

function CAPSLOCK_RenumberTable(sourcetable)
	local index = 1;
	local temptable = { };
	for key,value in ipairs(sourcetable) do
		if value and table.getn(value) > 0 then
			temptable[index] = value;
			index = index + 1
		end
	end
	return temptable;
end


function CAPSLOCK_GetUnitIDFromGroup(playerName)
	-- playerName = CAPSLOCK_UCFirst(playerName);
	local unitid = nil;
	if CAPSLOCK_IsInRaid() then
		for n=1, GetNumRaidMembers(), 1 do
			if UnitName("raid"..n) == playerName then
				unitid = "raid"..n;
			end
		end
	else
		for n=1, GetNumPartyMembers(), 1 do
			if UnitName("party"..n) == playerName then
				unitid = "party"..n;
			end
		end
	end
	return unitid;
end


function CAPSLOCK_AddToQueue(element)
	if not element[1] then
		return;
	end;

	-- Check if player is already listed in queue:
	for n=1, table.getn(CAPSLOCK_SUMMON_QUEUE), 1 do
		if CAPSLOCK_SUMMON_QUEUE[n][1] == element[1] then
			return false;
		end;
	end;
	
	CAPSLOCK_SUMMON_QUEUE[table.getn(CAPSLOCK_SUMMON_QUEUE) + 1] = element;
	return true;
end;


function CAPSLOCK_RemoveFromQueue(playername)
	local target;
	local newTable = { };
	
	for n=1, table.getn(CAPSLOCK_SUMMON_QUEUE), 1 do
		target = CAPSLOCK_SUMMON_QUEUE[n];
		
		if target and not(target[1] == playername) then
			newTable[table.getn(newTable)+1] = CAPSLOCK_SUMMON_QUEUE[n];
		end;
	end;
	CAPSLOCK_SUMMON_QUEUE = newTable;
end;





--  *******************************************************
--
--	Internal Communication Functions
--
--  *******************************************************
--[[
	Handle incoming message from other CAPSLOCK clients.
	Added in: 0.0.1
--]]
function CAPSLOCK_HandleCapslockMessage(msg, sender)
	--echo(sender.." --> "..msg);
	local _, _, cmd, message, recipient = string.find(msg, "([^#]*)#([^#]*)#([^#]*)");	
	
	--	Ignore message if it is not for me. 
	--	Receipient can be blank, which means it is for everyone.
	if not (recipient == "") then
		if not (recipient == UnitName("player")) then
			return
		end
	end

	if cmd == "TX_VERSION" then
		CAPSLOCK_HandleTXVersion(message, sender)
	elseif cmd == "RX_VERSION" then
		CAPSLOCK_HandleRXVersion(message, sender)		
	elseif cmd == "TX_SYNCINIT" then
		CAPSLOCK_HandleTXSyncInit(message, sender)
	elseif cmd == "RX_SYNCINIT" then
		CAPSLOCK_HandleRXSyncInit(message, sender)
	elseif cmd == "TX_SYNCADDQ" then
		CAPSLOCK_HandleTXSyncAddQueue(message, sender)
	elseif cmd == "TX_SYNCREMQ" then
		CAPSLOCK_HandleTXSyncRemoveQueue(message, sender)
	elseif cmd == "TX_SYNCSUMQ" then
		CAPSLOCK_HandleTXSyncSummonQueue(message, sender)
	elseif cmd == "RX_SYNCSUMQ" then
		CAPSLOCK_HandleRXSyncSummonQueue(message, sender)
	elseif cmd == "TX_SUMBEGIN" then
		CAPSLOCK_HandleTXSyncStartSummon(message, sender)
	elseif cmd == "TX_VERCHECK" then
		CAPSLOCK_HandleTXVerCheck(message, sender)
	end
end


function CAPSLOCK_SendAddonMessage(message)
	local channel = nil
	
	if CAPSLOCK_IsInRaid() then
		channel = "RAID";
	elseif CAPSLOCK_IsInParty() then
		channel = "PARTY";
	else
		return;
	end

	SendAddonMessage(CAPSLOCK_PREFIX, message, channel);
end


function CAPSLOCK_OnChatMsgAddon(event, prefix, msg, channel, sender)
	if prefix == CAPSLOCK_PREFIX then
		CAPSLOCK_HandleCapslockMessage(msg, sender);	
	end
--	if prefix == CTRA_PREFIX then
--		CAPSLOCK_HandleCTRAMessage(msg, sender);
--	end
end


--[[
	Respond to a TX_VERSION command.
	Input:
		msg is the raw message
		sender is the name of the message sender.
	We should whisper this guy back with our current version number.
	We therefore generate a response back (RX) in raid with the syntax:
	Capslock:<sender (which is actually the receiver!)>:<version number>
]]
function CAPSLOCK_HandleTXVersion(message, sender)
	local response = GetAddOnMetadata("Capslock", "Version")	
	CAPSLOCK_SendAddonMessage("RX_VERSION#"..response.."#"..sender)
end

--[[
	A version response (RX) was received. The version information is displayed locally.
]]
function CAPSLOCK_HandleRXVersion(message, sender)
	CAPSLOCK_Echo(string.format("%s 正在使用 CAPSLOCK 版本 %s", sender, message))
end

function CAPSLOCK_HandleTXVerCheck(message, sender)
	CAPSLOCK_CheckIsNewVersion(message);
end


function CAPSLOCK_Synchronize()
	--	This initiates step 1: send a TX_SYNCINIT to all clients.
	if synchronizationState == 0 then	
		synchronizationState = 1			-- Set INIT mode
		synchronizationSource = "";			-- Clear current source
		
		CAPSLOCK_SendAddonMessage("TX_SYNCINIT##");
		
		CAPSLOCK_AddTimer(CAPSLOCK_HandleRXSyncInitDone, 3);
	end;
end


--[[
--	Client received a TX_SYNCINIT request. This means sender is looking
--	for clients to sync data from.
--	This client must respond with a RX_SYNCINIT. A "0" is added as payload,
--	and is reserved for future use.
--	Added in: 0.3.0
--]]
function CAPSLOCK_HandleTXSyncInit(message, sender)
	--	Message was from SELF, we must not return RX_SYNCINIT.
	if sender == UnitName("player") then
		return;
	end

	syncResults = { };
	syncRQResults = { };

	CAPSLOCK_SendAddonMessage("RX_SYNCINIT#0#"..sender)
end

--[[
	Handle RX_SYNCINIT responses from clients.
	A client responded back! We'll just pick the first client and
	fetch data from him/her!
--]]
function CAPSLOCK_HandleRXSyncInit(message, sender)
	--	Check we are still in TX_SYNCINIT state
	if not (synchronizationState == 1) then
		return
	end

	synchronizationState = 2;
	synchronizationSource = sender;
end


--[[
--	TX_SYNCADDQ: Add one element to summon queue.
--	Added in: 0.3.0
--]]
function CAPSLOCK_HandleTXSyncAddQueue(message, sender)
	local _, _, playername, priority = string.find(message, "([^/]*)/([^/]*)");
	if playername == UnitName("player") then
		return;
	end
	local unitid = CAPSLOCK_GetUnitIDFromGroup(playername);
	if not unitid then
		--CAPSLOCK_Whisper(playername, string.format("Hi %s, 你未在队伍中，无法被召唤.", playername))
		return;
	end
	if UnitIsVisible(unitid) then
		SendChatMessage("你已经到达，无需再次召唤","WHISPER","通用语",playername);
		return;
	end
	-- playername = CAPSLOCK_UCFirst(playername);
	priority = tonumber(priority);

	CAPSLOCK_AddToQueue({ playername, priority, 0, ""});
	CAPSLOCK_UpdateMessageList();
end


--[[
--	Remove target from summon queue.
--	Added in: 0.3.0
--]]
function CAPSLOCK_HandleTXSyncRemoveQueue(message, sender)
	local _, _, playername = string.find(message, "([^/]*)");

	CAPSLOCK_RemoveFromQueue(playername);
end;

--[[
--	TX_SYNCSUMQ: Sync all elements in summon queue to sender.
--	Added in: 0.3.0
--]]
function CAPSLOCK_HandleTXSyncSummonQueue(message, sender)
	local playername, priority;
	local response;

	-- { <playername>, <priority>, <playerstatus>, <location> }
	-- No reason to sync playerstatus or location; they will be updated by client.
	for n=1, table.getn(CAPSLOCK_SUMMON_QUEUE), 1 do
		playername = CAPSLOCK_SUMMON_QUEUE[n][1];
		priority = CAPSLOCK_SUMMON_QUEUE[n][2];

		response = playername.."/"..priority;
		CAPSLOCK_SendAddonMessage("RX_SYNCSUMQ#"..response.."#"..sender);
	end

	--	Last, send an EOF to signal all records were sent.
	CAPSLOCK_SendAddonMessage("RX_SYNCSUMQ#EOF#"..sender);
end


--[[
--	RX_SYNCSUMQ: Handle receiving data from client.
--	Added in: 0.3.0
--]]
function CAPSLOCK_HandleRXSyncSummonQueue(message, sender)
	if message == "EOF" then
		synchronizationState = 0;
		CAPSLOCK_UpdateMessageList();
		return;
	end

	local _, _, playername, priority = string.find(message, "([^/]*)/([^/]*)");
	if playername == UnitName("player") then
		return;
	end
	local unitid = CAPSLOCK_GetUnitIDFromGroup(playername);
	
	if not unitid then
		--CAPSLOCK_Whisper(playername, string.format("Hi %s, 你未在队伍中，无法被召唤.", playername))
		return;
	end
	if UnitIsVisible(unitid) then
		SendChatMessage("你已经到达，无需再次召唤","WHISPER","通用语",playername);
		return;
	end
	-- playername = CAPSLOCK_UCFirst(playername);
	priority = tonumber(priority);

	CAPSLOCK_AddToQueue({ playername, priority, 0, ""});
end


--[[
--	A client started to summon; remove this entry from queue.
--	Added in: 0.3.0
--]]
function CAPSLOCK_HandleTXSyncStartSummon(message, sender)
	local _, _, playername = string.find(message, "([^/]*)");

	CAPSLOCK_RemoveFromQueue(playername);
end;


--[[
--	This is called by the timer when responses are no longer accepted
--	After this, responses must be investigated and we can read data from
--	the selected (the first) source.
--	Added in: 0.3.0
--]]
function CAPSLOCK_HandleRXSyncInitDone()
	synchronizationState = 2;			-- We are in SYNC mode
	
	if synchronizationSource == "" then
		synchronizationState = 0;		-- Back to IDLE mode
		return;
	end;

	-- Now ask for details from the selected source:
	CAPSLOCK_SendAddonMessage("TX_SYNCSUMQ##"..synchronizationSource);	
end;






--  *******************************************************
--
--	Timer functions
--
--  *******************************************************
local CAPSLOCK_TimerTick = 0;
local CAPSLOCK_LocationTimer = 0;
--	Timer job: { method, duration }
local CAPSLOCK_GeneralTimers = { };

-- 每3s自动更新一次列表
function CAPSLOCK_OnTimer(elapsed)
	CAPSLOCK_TimerTick = CAPSLOCK_TimerTick + elapsed

	if floor(CAPSLOCK_LocationTimer) < floor(CAPSLOCK_TimerTick) then
		CAPSLOCK_OnLocationTimer();
		CAPSLOCK_LocationTimer = CAPSLOCK_TimerTick + (CAPSLOCK_OPTION_PLAYER_UPDATE + 1);
	end
	
	local timer;
	for n=1, table.getn(CAPSLOCK_GeneralTimers), 1 do
		timer = CAPSLOCK_GeneralTimers[n];
		if (CAPSLOCK_TimerTick > timer[2]) then
			CAPSLOCK_GeneralTimers[n] = nil;
			timer[1]();
		end
	end	
end

function CAPSLOCK_OnLocationTimer()
	if CAPSLOCK_SUMMON_ENABLED and table.getn(CAPSLOCK_SUMMON_QUEUE) >0 then
		CAPSLOCK_UpdateMessageList();
	end;
end

function CAPSLOCK_AddTimer( method, duration )
	CAPSLOCK_GeneralTimers[table.getn(CAPSLOCK_GeneralTimers) + 1] = { method, CAPSLOCK_TimerTick + duration }
end



--  *******************************************************
--
--	Queue functions
--
--  *******************************************************

--[[
--	Add a player to the summon queue.
--	Added in: 0.0.2
--]]
function CAPSLOCK_AddToSummonQueue(playername, manualMode)

	if not CAPSLOCK_IsWarlock() then
		return;
	end;
	-- playername = CAPSLOCK_UCFirst(playername);
	if (CAPSLOCK_IsLearnedSummonSpell()) then
		local q = CAPSLOCK_GetFromQueueByName(playername);
		if q then
			for i=0,table.getn(CAPSLOCK_SUMMON_QUEUE) do
				local b=CAPSLOCK_SUMMON_QUEUE[i+1]
				if b[1] == playername then
					-- 如果是界面主动点击则开始召唤该玩家
					if manualMode then
						CAPSLOCK_SummonPriorityTarget(playername, manualMode);
						return;
					else
						SendChatMessage("你已在队列中，排队顺位["..(i+1).."]，请耐心等待","WHISPER","通用语",playername);	
					end
					break;
				end;
			end
		else
			if playername == UnitName("player") then
				return;
			end
			local unitid = CAPSLOCK_GetUnitIDFromGroup(playername);
			if not manualMode and UnitIsVisible(unitid) then
				SendChatMessage("你已经到达，无需再次召唤","WHISPER","通用语",playername);
				return;
			end
			local id = 1 + table.getn(CAPSLOCK_SUMMON_QUEUE);
			-- Currently priority is always 10. Location is updated later.
			local priority = 10;
			CAPSLOCK_SUMMON_QUEUE[id] = { playername, priority, 0 , "" };
			
			local lockInstance = "";
			if IsInInstance() then
				lockInstance = GetRealZoneText();
			end;
				
			if not unitid then
				--CAPSLOCK_Whisper(playername, string.format("Hi %s, 你未在队伍中，无法被召唤.", playername))
				return;
			end
			local playerZone = CAPSLOCK_GetPlayerZone(UnitName(unitid))
			local status = CAPSLOCK_GetPlayerStatus(lockInstance, playerZone, unitid);
			
			if status == 1 then
				-- Player is disconnected; don't send a message.
			elseif status == 2 then
				SendChatMessage("你需要在复活后，才能被召唤","WHISPER","通用语",playername);
				--CAPSLOCK_Whisper(playername, string.format("Hi %s, 当你复活后，你会被召唤.", playername));
			elseif status == 3 then
				SendChatMessage("你需要在进本后，才能被召唤","WHISPER","通用语",playername);
				--CAPSLOCK_Whisper(playername, string.format("Hi %s, 当你在 %s 里面时你会被召唤.", playername, lockInstance));
			else
				CAPSLOCK_OpenConfigurationDialog();
				SendChatMessage("如需取消排队，请私信回复'取消'或'cancel'","WHISPER","通用语",playername);
				SendChatMessage("排队顺位["..(table.getn(CAPSLOCK_SUMMON_QUEUE)).."]，请耐心等待并留意是否有邪恶双子Debuff，若长时间未拉到重新M","WHISPER","通用语",playername);
				CAPSLOCK_EchoQueueList();
			end;
		end;
	end;
	CAPSLOCK_UpdateMessageList();
	
	local priority = 10;
	CAPSLOCK_SendAddonMessage(string.format("TX_SYNCADDQ#%s/%d#", playername, priority));

end

function CAPSLOCK_EchoQueueList()
	local list = "";
	if table.getn(CAPSLOCK_SUMMON_QUEUE) <= 1 then
		CAPSLOCK_AnnounceSummons();
	else
		for i=0,(table.getn(CAPSLOCK_SUMMON_QUEUE)) do
			local b = CAPSLOCK_SUMMON_QUEUE[i+1];
			if b then
				if i>0 then
					list = list.."，";
				end
				list = list..(b[1]);
			end
		end
		local message = "排队等待：".. list .."。";
		CAPSLOCK_PartyEcho(message);
	end
end

--[[
--	Get queue information for requested player.
--	Added in: 0.0.2
--]]
function CAPSLOCK_GetFromQueueByName(playername)
	local target;
	for n=1, table.getn(CAPSLOCK_SUMMON_QUEUE), 1 do
		target = CAPSLOCK_SUMMON_QUEUE[n];
		if target[1] == playername then
			return target;
		end
	end
	
	return nil;
end


--[[
--	Get queue information for player with highest priority.
--	Added in: 0.0.2
--]]
function CAPSLOCK_GetFromQueueByPriority()
	local entry = nil;
	local target;

	CAPSLOCK_UpdateQueueStatus();
	--CAPSLOCK_SortTableAscending(CAPSLOCK_SUMMON_QUEUE, 1);
	
	for n=1, table.getn(CAPSLOCK_SUMMON_QUEUE), 1 do
		target = CAPSLOCK_SUMMON_QUEUE[n];			
		if target[3] == 0 then
			entry = target;
			break;
		end;	
	end;

	-- If we found a target we will remove it from the table:		
	if entry then
		CAPSLOCK_SendAddonMessage(string.format("TX_SYNCREMQ#%s#", entry[1]));
		CAPSLOCK_RemoveFromQueue(entry[1]);
	end;
	CAPSLOCK_UpdateMessageList();
	
	return entry;
end


--[[
--	Return player status for one player: 
--	0=ready, 1=Offline, 2=Dead, 3=Not in Instance
--	Added in: 0.1.1
--]]
function CAPSLOCK_GetPlayerStatus(lockInstance, playerZone, unitid)
	-- Status 1: Unit is offline
	if not UnitIsConnected(unitid) then
		return 1;
	end;

	-- Status 2: Unit is dead!
	if UnitIsDeadOrGhost(unitid) then
		return 2;
	end;
	
	-- Status 3: lock is in an instance but target is not!
	if not(lockInstance == "") then
		if not(lockInstance == playerZone) then
			return 3;
		end;
	end;
	
	return 0;
end


--[[
--	Return player status for all players in queue:
--	Added in: 0.1.1
--]]
function CAPSLOCK_UpdateQueueStatus()
	local lockInstance = "";	
	local status, unitid, playerZone;

	if IsInInstance() then
		lockInstance = GetRealZoneText();
	end;
	
	for n=1, table.getn(CAPSLOCK_SUMMON_QUEUE), 1 do
		target = CAPSLOCK_SUMMON_QUEUE[n];
		unitid = CAPSLOCK_GetUnitIDFromGroup(target[1]);
		if unitid then
			playerZone = CAPSLOCK_GetPlayerZone(UnitName(unitid))
			target[3] = CAPSLOCK_GetPlayerStatus(lockInstance, playerZone, unitid);
			target[4] = playerZone;
		end
		CAPSLOCK_SUMMON_QUEUE[n] = target;
	end;
end;


function CAPSLOCK_AnnounceSummons()
	local location = GetRealZoneText();
	local message = "要拉单M我扣'"..CAPSLOCK_KEYWORD.."'，收到后会按顺序召唤，请耐心等待，感谢支持";
	CAPSLOCK_PartyEcho(message);
end;



--  *******************************************************
--
--	Summon functions
--
--  *******************************************************

-- 判断包里是否有灵魂碎片
function CAPSLOCK_IsHaveSoulShard()
	for bagId = 0, 4 do
        for slot = 1, GetContainerNumSlots(bagId) do
			local l = GetContainerItemLink(bagId,slot)
            if l and string.find(l,"灵魂碎片") then
                return true;
            end
        end
    end
    return false;
end

-- 判断是否已经学习召唤技能
function CAPSLOCK_IsLearnedSummonSpell()
	local i = 1;
	while true do
		local name = GetSpellName(i,"spell");
		if name then
			if string.find(name, "召唤仪式") then
				return true;
			end;
			i=i+1;
		else
			break;
		end;
	end;
	return false;
end



--[[
--	Summon next target in priority.
--	(optional) playername: set if specific player is to be summoned.
--	Added in: 0.0.2
--]]
function CAPSLOCK_SummonPriorityTarget(playername ,manualMode)
	if not CAPSLOCK_IsHaveSoulShard() then
		CAPSLOCK_PartyEcho("我没有灵魂碎片了！！！");
		return;
	end
	-- if not CAPSLOCK_IsLearnedSummonSpell() then
	-- 	CAPSLOCK_Echo("你还未学会召唤仪式技能！");
	-- 	return;
	-- end
	if not CAPSLOCK_IsInRaid() and not CAPSLOCK_IsInParty() then
		CAPSLOCK_Echo("你必须有团队或小队才能召唤！");
		return;
	end
	if UnitAffectingCombat("player") then
		CAPSLOCK_Echo("你不能在战斗中被召唤,请退出战斗.");
		return;
	end

	local nearbyCount = CAPSLOCK_CountNearbyPlayers();
	if nearbyCount < 2 then
		CAPSLOCK_Echo("附近没有足够的人点门, 请再耐心等待下.");
		return;
	end;

	local target;
	if playername then
		target = { playername, 0, 0 , ""};	
		CAPSLOCK_RemoveFromQueue(target[1]);
		CAPSLOCK_UpdateMessageList();
	else
		target = CAPSLOCK_GetFromQueueByPriority();
		if not target then
			if table.getn(CAPSLOCK_SUMMON_QUEUE) > 0 then
				CAPSLOCK_Echo("队列中没有符合条件的召唤目标！");
			else
				CAPSLOCK_Echo("召唤队列是空的！");
			end;
		
			return;
		end;
	end;

	-- This will remove the target from other locks as well:
	CAPSLOCK_SendAddonMessage("TX_SUMBEGIN#"..target[1].."#");

	local unitid = CAPSLOCK_GetUnitIDFromGroup(target[1]);
	if not unitid then
		CAPSLOCK_Echo(string.format("Oops, 无法找到 %s 的玩家", target[1]));
		return;
	end

	TargetUnit(unitid);
	if not manualMode and UnitIsVisible(unitid) then
		CAPSLOCK_Echo(">>>"..target[1].."<<<(在附近)，移出召唤队列！")
		CAPSLOCK_RemoveFromQueue(target[1])
		return;
	end
	
	CastSpellByName("召唤仪式");

	CAPSLOCK_AnnounceSummoning(target[1]);
end


--[[
--	Summon specific target.
--	Added in: 0.1.1
--]]
function CAPSLOCK_OnTargetClick(object, buttonname)
	currentObjectId = object:GetID();
	
	local frame = getglobal("CapslockFrameSummonQueueEntry"..currentObjectId);
	local playername = getglobal(frame:GetName().."Target"):GetText();

	if not playername or (playername == "") then
		return;
	end;

	if buttonname == "RightButton" then
		-- Right button: Remove player from queue
		CAPSLOCK_SendAddonMessage(string.format("TX_SYNCREMQ#%s#", playername));
		CAPSLOCK_RemoveFromQueue(playername);
		CAPSLOCK_Echo("将>>>"..playername.."<<<移出召唤队列！")
		
		CAPSLOCK_UpdateMessageList();
	else
		-- Left button: Summon immediately (regardless of status)
		if not(playername == "") then
			CAPSLOCK_SummonPriorityTarget(playername);
		end;
	end
end;


--[[
--	Announce summon instructions in party/raid.
--	Will check if there are at least 3 persons within 100 yards range.
--	Added in: 0.0.1
--]]
function CAPSLOCK_AnnounceSummoning(playername)
	local tmp = 0;
	for bagId = 0, 4 do
        for slot = 1, GetContainerNumSlots(bagId) do
			local l = GetContainerItemLink(bagId,slot)
            if l and string.find(l,"灵魂碎片") then
                tmp = tmp + 1;
            end
        end
    end
	CAPSLOCK_PartyEcho("当前召唤：["..playername.."]，剩余片["..(tmp-1).."]，伸出你们的双手点下门");
	SendChatMessage("正在拉你，注意不要进入战斗","WHISPER","通用语",playername);
	--CAPSLOCK_EchoQueueList();
end


function CAPSLOCK_UpdateMessageList()
	FauxScrollFrame_Update(CapslockFrameSummonQueue, CAPSLOCK_SUMMON_MAXQUEUED, 10, 20);
	local offset = FauxScrollFrame_GetOffset(CapslockFrameSummonQueue);

	CAPSLOCK_RefreshVisibleSummonQueue(offset);
end;


function CAPSLOCK_InitializeListElements()
	local entry = CreateFrame("Button", "$parentEntry1", CapslockFrameSummonQueue, "CAPSLOCK_CellTemplate");
	entry:SetID(1);
	entry:SetPoint("TOPLEFT", 4, -4);
	for n=2, CAPSLOCK_SUMMON_MAXQUEUED, 1 do
		local entry = CreateFrame("Button", "$parentEntry"..n, CapslockFrameSummonQueue, "CAPSLOCK_CellTemplate");
		entry:SetID(n);
		entry:SetPoint("TOP", "$parentEntry"..(n-1), "BOTTOM");
	end
end


function CAPSLOCK_RefreshVisibleSummonQueue(offset)
	local summons = CAPSLOCK_SUMMON_QUEUE;

	CAPSLOCK_UpdateQueueStatus();

	CAPSLOCK_SortTableAscending(summons, 2);
	
	local summon, playername, playerprio, playerstatus;
	for n=1, CAPSLOCK_SUMMON_MAXVISIBLE, 1 do
		local frame = getglobal("CapslockFrameSummonQueueEntry"..n);
		
		playername = "";
		playerzone = "";
		
		summon = summons[n + offset]
		if summon then
			playername = summon[1];
			playerprio = summon[2];
			playerstatus = summon[3];
			playerzone = summon[4];

			local clasColor = { 1.00, 1.00, 1.00 };
			local zoneColor = { 1.00, 0.80, 0.00 };

			-- Not in instance? Make zone color red
			if playerstatus == 3 then	
				zoneColor = { 1.00, 0.00,  0.00 }
			end;
			
			if playerstatus == 1 then		-- Offline
				clasColor = { 0.50, 0.50, 0.50 }
				zoneColor = { 0.50, 0.50, 0.50 }
			elseif playerstatus == 2 then	-- Dead
				clasColor = { 1.00, 0.00, 0.00 }			
			else
				-- Use class colour
				local unitid = CAPSLOCK_GetUnitIDFromGroup(playername);

				local cls = UnitClass(unitid);
				if cls == "德鲁伊" then
					clasColor = { 1.00, 0.49, 0.04 }
				elseif cls == "猎人" then
					clasColor = { 0.67, 0.83, 0.45 }
				elseif cls == "法师" then
					clasColor = { 0.41, 0.80, 0.94 }
				elseif cls == "圣骑士" then
					clasColor = { 0.96, 0.55, 0.73 }
				elseif cls == "牧师" then
					clasColor = { 1.00, 1.00, 1.00 }
				elseif cls == "盗贼" then
					clasColor = { 1.00, 0.96, 0.41 }
				elseif cls == "萨满祭司" then
					clasColor = { 0.96, 0.55, 0.73 }
				elseif cls == "术士" then
					clasColor = { 0.58, 0.51, 0.79 }
				elseif cls == "战士" then
					clasColor = { 0.78, 0.61, 0.43 }
				end;
			end;
						
			getglobal(frame:GetName().."Target"):SetTextColor(clasColor[1], clasColor[2], clasColor[3]);			
			getglobal(frame:GetName().."Zone"):SetTextColor(zoneColor[1], zoneColor[2], zoneColor[3]);			
		end
		
		getglobal(frame:GetName().."Target"):SetText(playername);
		getglobal(frame:GetName().."Zone"):SetText(playerzone);
		frame:Show();
	end
end



--  *******************************************************
--
--	Location functions
--
--  *******************************************************

--[[
--	Return zonename where <playername> currently is.
--	Returned value is nil if no zone was found (e.g. due to being offline).
--	Added in: 0.1.0
--]]
function CAPSLOCK_GetPlayerZone(playername)
	if CAPSLOCK_IsInRaid() then
		for n=1, GetNumRaidMembers(), 1 do
			local name, _, _, _, _, _, zone = GetRaidRosterInfo(n);
			if name == playername then
				return zone;
			end
		end
	end;
	
	return nil;
end;


--[[
	Count how many players are within visible range (100 yards).
	Added in: 0.2.3
--]]
function CAPSLOCK_CountNearbyPlayers()
	local counter = 0;
	local unitid;

	if CAPSLOCK_IsInRaid() then
		for n=1, GetNumRaidMembers(), 1 do
			unitid = "raid"..n;
			if CheckInteractDistance(unitid, 4) and not UnitIsDeadOrGhost(unitid) then
				counter = counter + 1;
			end;
		end
	elseif CAPSLOCK_IsInParty() then
		for n=1, GetNumPartyMembers(), 1 do
			unitid = "party"..n;
			if CheckInteractDistance(unitid, 4) and not UnitIsDeadOrGhost(unitid) then
				counter = counter + 1;
			end;
		end
	end;
	return counter;
end;



--  *******************************************************
--
--	Version functions
--
--  *******************************************************

--[[
--	Broadcast my version if this is not a beta (CurrentVersion > 0) and
--	my version has not been identified as being too low (MessageShown = false)
--]]
function CAPSLOCK_OnRaidRosterUpdate(event, arg1, arg2, arg3, arg4, arg5)
--	if CAPSLOCK_CURRENT_VERSION > 0 and not CAPSLOCK_UPDATE_MESSAGE_SHOWN then
--		if CAPSLOCK_IsInRaid() or CAPSLOCK_IsInParty() then
--			local versionstring = GetAddOnMetadata("Capslock", "Version");
--			CAPSLOCK_SendAddonMessage(string.format("TX_VERCHECK#%s#", versionstring));
--		end
--	end
end

function CAPSLOCK_CalculateVersion(versionString)
--	local _, _, major, minor, patch = string.find(versionString, "([^\.]*)\.([^\.]*)\.([^\.]*)");
	local version = 0;

--	if (tonumber(major) and tonumber(minor) and tonumber(patch)) then
--		version = major * 100 + minor;
--		--echo(string.format("major=%s, minor=%s, patch=%s, version=%d", major, minor, patch, version));
--	end
	
	return version;
end

function CAPSLOCK_CheckIsNewVersion(versionstring)
--	local incomingVersion = CAPSLOCK_CalculateVersion( versionstring );

--	if (CAPSLOCK_CURRENT_VERSION > 0 and incomingVersion > 0) then
--		if incomingVersion > CAPSLOCK_CURRENT_VERSION then
--			if not CAPSLOCK_UPDATE_MESSAGE_SHOWN then
--				CAPSLOCK_UPDATE_MESSAGE_SHOWN = true;
--				CAPSLOCK_Echo(string.format("NOTE: A newer version of ".. COLOUR_INTRO .."CAPSLOCK"..COLOUR_CHAT.."! is available (version %s)!", versionstring));
--				CAPSLOCK_Echo("NOTE: Go to https://armory.digam.dk/capslock to download latest version.");
--			end
--		end	
--	end
end


--[[
--	Handle incoming chat whisper.
--	"!" commands are redirected here too with the "raw" command line.
--	Since 0.0.2
--]]
function CAPSLOCK_OnChatWhisper(event, message, sender)
	if not message then
		return
	end
	
	-- Skip messages from self:
	if sender == UnitName("player") then
		return;
	end;
	
	-- local _, _, cmd = string.find(message, "(%a+)");	
	-- if not cmd then
	-- 	return
	-- end
	-- cmd = string.lower(cmd);

	-- if cmd == "summon" then
	-- 	CAPSLOCK_AddToSummonQueue(sender);
	-- end;

	-- if ( string.find(message, "拉我") or
	-- 	string.find(message, "求拉") or
	-- 	string.find(message, "术士 拉我") or
	-- 	string.find(message, "术士求拉") or
	-- 	string.find(message, "拉下") or
	-- 	string.find(message, "la") or
	-- 	string.find(message, "ss 拉") or
	-- 	string.find(message, "啦我") or
	-- 	string.find(message, "summon") or
	-- 	string.find(message, "求啦"))
	-- then
	if message == CAPSLOCK_KEYWORD then
		CAPSLOCK_AddToSummonQueue(sender);
	elseif CAPSLOCK_GetFromQueueByName(sender) then
		if (message == "取消") then
			CAPSLOCK_RemoveFromQueue(sender);
			SendChatMessage("排队已取消排队","WHISPER","通用语",sender);
			CAPSLOCK_UpdateMessageList();
		elseif (message == "cancle") then
			CAPSLOCK_RemoveFromQueue(sender);
			SendChatMessage("排队已取消","WHISPER","通用语",sender);
			CAPSLOCK_UpdateMessageList();
		end
	end
end


--[[
--	There's a message in the Party / Raid channel - investigate that!
--]]
function CAPSLOCK_HandleRaidChatMessage(event, message, sender)
	-- if (not message or message == "" or 
		-- not string.sub(message, 1, 1) == "!" or

		-- if ( string.find(message, "拉我") or
		-- 		string.find(message, "求拉") or
		-- 		string.find(message, "术士 拉我") or
		-- 		string.find(message, "术士求拉") or
		-- 		string.find(message, "拉下") or
		-- 		string.find(message, "la") or
		-- 		string.find(message, "ss 拉") or
		-- 		string.find(message, "啦我") or
		-- 		string.find(message, "summon") or
		-- 		string.find(message, "求啦"))
		-- then
		
		
		if (string.find(message,CAPSLOCK_KEYWORD)) then
			CAPSLOCK_OnChatWhisper(event, CAPSLOCK_KEYWORD, sender);
		end

end




--  *******************************************************
--if not CAPSLOCK_ONLY_WHISPER then
--	Event handlers
--
--  *******************************************************
function CAPSLOCK_OnEvent(event)
	if (event == "CHAT_MSG_ADDON") then
		CAPSLOCK_OnChatMsgAddon(event, arg1, arg2, arg3, arg4, arg5)
	elseif (event == "CHAT_MSG_WHISPER") then
		CAPSLOCK_OnChatWhisper(event, arg1, arg2, arg3, arg4, arg5);
	elseif (not CAPSLOCK_ONLY_WHISPER and (event == "CHAT_MSG_RAID" or
			event == "CHAT_MSG_RAID_LEADER" or
			event == "CHAT_MSG_PARTY")) then
		CAPSLOCK_HandleRaidChatMessage(event, arg1, arg2, arg3, arg4, arg5);
	elseif (event == "VARIABLES_LOADED") then
		if (CAPSLOCK_KEYWORD == nil or CAPSLOCK_KEYWORD == "") then CAPSLOCK_KEYWORD = "求拉";end
		if (CAPSLOCK_ONLY_WHISPER == nil) then CAPSLOCK_ONLY_WHISPER = true;end
		-- if not CAPSLOCK_ONLY_WHISPER then
		-- 	CAPSLOCK_ONLY_WHISPER = true;
		-- end
		CAPSLOCK_Config_SetKeyWordText()
	end
	CAPSLOCK_Config_OnLoad()
	
end

function CAPSLOCK_OnLoad()
	CAPSLOCK_CURRENT_VERSION = CAPSLOCK_CalculateVersion( GetAddOnMetadata("WIM", "Version") );

--	CAPSLOCK_Echo(string.format("version %s by %s", GetAddOnMetadata("Capslock", "Version"), GetAddOnMetadata("Capslock", "Author")));
	
	if CAPSLOCK_IsWarlock() then
		this:RegisterEvent("ADDON_LOADED");
		this:RegisterEvent("CHAT_MSG_ADDON");   
		this:RegisterEvent("RAID_ROSTER_UPDATE")    
		this:RegisterEvent("CHAT_MSG_WHISPER");
		this:RegisterEvent("CHAT_MSG_PARTY");
		this:RegisterEvent("CHAT_MSG_RAID");
		this:RegisterEvent("CHAT_MSG_RAID_LEADER");
		this:RegisterEvent("VARIABLES_LOADED");
		CAPSLOCK_InitializeListElements();
		
		CAPSLOCK_Synchronize();
	end
end

