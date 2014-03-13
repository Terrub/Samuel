local EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE = "^Your (.-) ";

local ERR_UNEXPECTED_NIL_VALUE = "Expected the following value but got nil:"

local SCRIPTHANDLER_ON_EVENT = "OnEvent";
local SCRIPTHANDLER_ON_UPDATE = "OnUpdate";
local SCRIPTHANDLER_ON_DRAG_START = "OnDragStart";
local SCRIPTHANDLER_ON_DRAG_STOP = "OnDragStop";

----------------------------------------------------------------
-- SAMUEL ADDON ------------------------------------------------
----------------------------------------------------------------

Samuel = CreateFrame("FRAME", "Samuel", UIParent);

local this = Samuel;

----------------------------------------------------------------
-- INTERNAL CONSTANTS ------------------------------------------
----------------------------------------------------------------

local _SLAM_CAST_TIME = 1.5;
local _SLAM_TOTAL_RANKS_IMP_SLAM = 5;
local _SLAM_TOTAL_IMP_SLAM_CAST_REDUCTION = 0.5;

----------------------------------------------------------------
-- PRIVATE VARIABLES -------------------------------------------
----------------------------------------------------------------

local _initialisation_event = "ADDON_LOADED";

local _progress_bar;
local _slam_marker;

local _is_locked_to_screen = true;

local _updateRunTime = 0;
local _update_display_timer = ( 1 / 30 ); -- update FPS target;
local _last_update = GetTime();
local _proposed_swing_time = 1;
local _current_swing_time = 0; -- The x in x/y * 100 percentage calc.
local _total_swing_time = 1; -- the y in x/y * 100 percentage calc.
--local _fps = 30;

local _rank_imp_slam = 0;

local _unit_name;
local _realm_name;
local _profile_id;
local _db;

local _swing_reset_actions;

local _last_swing;
local _ratio;

local _default_width = 200;
local _default_height = 5;

local _default_db = {
	["is_slam_marker_shown"] = false;
	["rank_imp_slam"] = 0;
	["position_point"] = "CENTER";
	["position_x"] = 0;
	["position_y"] = -120;
};

----------------------------------------------------------------
-- LOCAL UP VALUES FOR SPEED -----------------------------------
----------------------------------------------------------------

local math_min = math.min;
local string_find = string.find;

----------------------------------------------------------------
-- PRIVATE FUNCTIONS -------------------------------------------
----------------------------------------------------------------

local _report = function(label, message)

	label = tostring(label);
	message = tostring(message);

	local str = "";
	
	str = str.."|cff22ff22Samuel|r - |cff999999"..label..":|r "..message;

	DEFAULT_CHAT_FRAME:AddMessage(str);

end

--------

local _resetVisibility = function()

	-- Turn off by default unless we're in combat
	if not UnitAffectingCombat("player") then
		
		this:Hide();
	
	else
		
		this:Show();
	
	end
	
end

--------

local _updateSlamMarker = function()
	
	_slam_marker:SetWidth( (_default_width / _total_swing_time) * (_SLAM_CAST_TIME - (_rank_imp_slam / _SLAM_TOTAL_RANKS_IMP_SLAM * _SLAM_TOTAL_IMP_SLAM_CAST_REDUCTION) ) );

end

--------

local _resetSwingTimer = function()

	_last_swing = GetTime();
	_total_swing_time = _proposed_swing_time;
	_updateSlamMarker();

end

--------

local _setImpSlamRank = function(rank)

	-- Stop arsin about!
	if rank == _rank_imp_slam then return end;

	rank = tonumber(rank);

	if not rank then
	
		error("Usage: _setImpSlamRank(rank <number>)");
	
	end
	
	-- Update local var
	_rank_imp_slam = rank;
	
	-- Update local database
	_db["rank_imp_slam"] = _rank_imp_slam;
	
	_report("Saved Improved Slam rank", _rank_imp_slam);
	
	-- Slam marker is dependant on rank so update it now.
	_updateSlamMarker();

end

--------

local _updateSwingTime = function()

	_proposed_swing_time,_ = UnitAttackSpeed("player"); --http://vanilla-wow.wikia.com/wiki/API_UnitAttackSpeed
	
end

--------

local _populateSwingResetActionsList = function()

	_swing_reset_actions = {
		["Heroic"] = true,
		["Slam"] = true,
		["Cleave"] = true,
		["Raptor"] = true,
		["Maul"] = true,
	}

end

--------

local _eventHandler = function()

	if event == "PLAYER_REGEN_ENABLED" then --http://www.wowwiki.com/Events/Combat#PLAYER_REGEN_ENABLED
	
		this:Hide();
	
	elseif event == "PLAYER_REGEN_DISABLED" then --http://www.wowwiki.com/Events/Combat#PLAYER_REGEN_DISABLED

		this:Show();
		_last_update = GetTime();
	
	elseif event == "CHAT_MSG_COMBAT_SELF_HITS" then
	
		-- Confirmed swing. Reset our timer
		_resetSwingTimer();
	
	elseif event == "CHAT_MSG_COMBAT_SELF_MISSES" then
	
		-- Confirmed swing. Reset our timer
		_resetSwingTimer();
	
	elseif event == "UNIT_ATTACK_SPEED" then
	
		-- Unit attack speed changed
		_updateSwingTime();
	
	elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
		
		local _,_,action = string_find(arg1, EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE)
		
		if _swing_reset_actions[action] then
		
			_resetSwingTimer();
			
		end
		
	elseif event == "CHARACTER_POINTS_CHANGED" then
	
		_report("CHARACTER_POINTS_CHANGED", arg1);
		
	elseif event == "PLAYER_LOGOUT" then
	
		-- Commit to local storage
		SamuelDB[_profile_id] = _db;
	
	elseif event == "PLAYER_LOGIN" then
	
		-- we only need this once
		this:UnregisterEvent("PLAYER_LOGIN");
		
		_updateSwingTime();
	
	end
	
end

--------

local _registerRequiredEvents = function()
	
	-- This is here temporarily
	this:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS");
	this:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES");
	this:RegisterEvent("UNIT_ATTACK_SPEED");
	this:RegisterEvent("PLAYER_REGEN_ENABLED");
	this:RegisterEvent("PLAYER_REGEN_DISABLED");
	this:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE");
	this:RegisterEvent("CHARACTER_POINTS_CHANGED");
	this:RegisterEvent("PLAYER_LOGIN");
	this:RegisterEvent("PLAYER_LOGOUT");

end

--------

local _updateDisplay = function()

	local elapsed = GetTime() - _last_update;

	-- elapsed is the total time since last frame update.
	-- we have to add this to our current running total timer
	-- to know when to actually do something next frame.
	_updateRunTime = _updateRunTime + elapsed;
	
	-- This is the actual update loop.
	while (_updateRunTime >= _update_display_timer) do
		
		-- MORE DOTS MORE DOTS!!!
		
			-- Cause an emergency escape
			if not _total_swing_time then
			
				this:SetScript(SCRIPTHANDLER_ON_UPDATE, nil);
				error(ERR_UNEXPECTED_NIL_VALUE..": _total_swing_time");
				
			end
			
			_current_swing_time = GetTime() - _last_swing;
			
			-- Use the native math library to prevent us overshooting our bar length.
			_ratio = math_min((_current_swing_time / _total_swing_time), 1);
			
			_progress_bar:SetWidth(_ratio * _default_width);
		
		-- OK STOP DOTS!!!
		
		-- Remove this and you've gone full retard.
		_updateRunTime = _updateRunTime - _update_display_timer;
	
	end
	
	_last_update = GetTime();
	
end

--------

local _createProgressBar = function()
	
	_progress_bar = CreateFrame("FRAME", nil, this);
	
	_progress_bar:SetBackdrop(
		{
			["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
		}
	);
	
	_progress_bar:SetBackdropColor(0.7, 0.7, 0.7, 1);
	
	_progress_bar:SetWidth(1);
	_progress_bar:SetHeight(_default_height);
	
	_progress_bar:SetPoint("LEFT", 0, 0);
	
end

--------

local _hide_slam_marker = function()

	_slam_marker:Hide();
	_db["is_slam_marker_shown"] = false;

end

--------

local _show_slam_marker = function()

	_slam_marker:Show();
	_db["is_slam_marker_shown"] = true;

end

--------

local _toggleSlamMarkerVisibility = function()

	if _db["is_slam_marker_shown"] then
		
		_hide_slam_marker();
		_report("Slam marker is now", "Hidden");
		
	else
	
		_show_slam_marker();
		_report("Slam marker is now", "Shown");
		
	end

end

--------

local _createSlamMarker = function()
	
	_slam_marker = CreateFrame("FRAME", nil, this);
	
	_slam_marker:SetBackdrop(
		{
			["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
		}
	);
	_slam_marker:SetBackdropColor(1, 0, 0, 0.7);
	
	_slam_marker:SetPoint("RIGHT", 0, 0);
	
	_slam_marker:SetHeight(_default_height);
	
	_slam_marker:SetFrameLevel(_progress_bar:GetFrameLevel()+1);
	
	if _db["is_slam_marker_shown"] then
		_show_slam_marker();
	else
		_hide_slam_marker();
	end
	
end

--------

local _printSlashCommandList = function()

	-- for loop through our local slash command list and add all our cmds to the return string.

	_report("Slash commands",
		[[
		   /sam impSlam [|cffffff330|r-|cffffff335|r] |cff999999-- Set your current rank of the "Improved Slam" talent.|r
		   /sam impSlam |cff999999-- Display the current registered rank of "Improved Slam".|r
		   /sam showSlamMarker <|cff9999fftoggle|r> |cff999999-- Toggle the red slam marker ON or OFF.|r
		   /sam lock <|cff9999fftoggle|r> |cff999999-- Toggle the ability to move the bar ON or OFF.|r]]
	);

end

--------

local _startMoving = function()

	this:StartMoving();

end

--------

local _stopMovingOrSizing = function()

	this:StopMovingOrSizing();
	
	local _;
	
	_,_, _db["position_point"], _db["position_x"], _db["position_y"] = this:GetPoint();

end

--------

local _toggleLockToScreen = function()

	if _is_locked_to_screen then
		
		-- Make the left mouse button trigger drag events
		this:RegisterForDrag("LeftButton");
	
		-- Set the start and stop moving events on triggered events
		this:SetScript(SCRIPTHANDLER_ON_DRAG_START, _startMoving);
		this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, _stopMovingOrSizing);
		
		-- Make the frame react to the mouse
		this:EnableMouse(true);
		
		-- Stop the frame from being movable
		this:SetMovable(true);
		
		-- Show ourselves so we can be moved
		this:Show();
		
		_is_locked_to_screen = false;
		
		_report("Swing timer bar", "Unlocked");
	
	else
	
		-- Stop the frame from being movable
		this:SetMovable(false);
	
		-- Remove all buttons from triggering drag events
		this:RegisterForDrag();
		
		-- Nil the 'OnSragStart' script event
		this:SetScript(SCRIPTHANDLER_ON_DRAG_START, nil);
		this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, nil);
		
		-- Disable mouse interactivity on the frame
		this:EnableMouse(false)
	
		-- reset our visibility
		_resetVisibility();
	
		_is_locked_to_screen = true;
		
		_report("Swing timer bar", "Locked");
	
	end

end

--------

local _slashCmdHandler = function(message, chat_frame)

	local _,_,cmd, params = string_find(message, "^(%S+) *(.*)");
	
	cmd = tostring(cmd);
		
	if cmd == "impSlam" then
		
		params = tonumber(params);
		
		if type(params) ~= "number"
			or params < 0
			or params > _SLAM_TOTAL_RANKS_IMP_SLAM then
		
			_report("Current rank Improved Slam", _rank_imp_slam);
			return;
			
		end
	
		_setImpSlamRank(params);
		
	elseif cmd == "showSlamMarker" then
	
		_toggleSlamMarkerVisibility();
		
	elseif cmd == "lock" then
	
		_toggleLockToScreen();
	
	else
	
		_printSlashCommandList();
	
	end

end;

--------

local _loadProfileID = function()

	_unit_name = UnitName("player");
	_realm_name = GetRealmName();
	_profile_id = _unit_name.."-".._realm_name;
	
end

--------

local _loadSavedVariables = function()

	-- First time install
	if not SamuelDB then
		SamuelDB = {};
	end
	
	-- New char profile
	if not SamuelDB[_profile_id] then
		SamuelDB[_profile_id] = _default_db
	end

	_db = SamuelDB[_profile_id];
		
	-- local value for speed
	_rank_imp_slam = _db["rank_imp_slam"];

end

--------

local _initialise = function()
	
	_loadProfileID();
	_loadSavedVariables();
	
	_populateSwingResetActionsList();
	
	this:UnregisterEvent(_initialisation_event);
	
	this:SetWidth(_default_width);
	this:SetHeight(_default_height);
	
	this:SetBackdrop(
		{
			["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
		}
	);
	
	this:SetBackdropColor(0, 0, 0, 1);
	
	this:SetPoint(_db["position_point"], _db["position_x"], _db["position_y"]);
	
	-- CREATE CHILDREN
	_createProgressBar();
	_createSlamMarker();
	
	_resetSwingTimer();
	_resetVisibility();
	
	_registerRequiredEvents();
	
	this:SetScript(SCRIPTHANDLER_ON_EVENT, _eventHandler);
	this:SetScript(SCRIPTHANDLER_ON_UPDATE, _updateDisplay);
	
end

-- Add slashcommand match entries into the global namespace for the client to pick up.
SLASH_SAMUEL1 = "/sam";
SLASH_SAMUEL2 = "/samuel";

-- And add a handler to react on the above matches.
SlashCmdList["SAMUEL"] = _slashCmdHandler;

this:SetScript(SCRIPTHANDLER_ON_EVENT, _initialise);
this:RegisterEvent(_initialisation_event);