----------------------------------------------------------------
-- "UP VALUES" FOR SPEED ---------------------------------------
----------------------------------------------------------------

local mathMin = math.min;
local stringFind = string.find;
local tableInsert = table.insert;
local tableRemove = table.remove;
local tostring = tostring;
local type = type;

----------------------------------------------------------------
-- CONSTANTS THAT SHOULD BE GLOBAL PROBABLY --------------------
----------------------------------------------------------------

local EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE = "^Your (.-) ";

local ERR_UNEXPECTED_NIL_VALUE = "Expected the following value but got nil:"

local SCRIPTHANDLER_ON_EVENT = "OnEvent";
local SCRIPTHANDLER_ON_UPDATE = "OnUpdate";
local SCRIPTHANDLER_ON_DRAG_START = "OnDragStart";
local SCRIPTHANDLER_ON_DRAG_STOP = "OnDragStop";

----------------------------------------------------------------
-- HELPER FUNCTIONS --------------------------------------------
----------------------------------------------------------------

--	These should be moved into the core at one point.

local merge = function(left, right)
	
	local t = {};
	
	if type(left) ~= "table" or type(right) ~= "table" then
	
		error("Usage: merge(left <table>, right <table>)");
		
	end

	-- copy left into temp table.
	for k, v in pairs(left) do
	
		t[k] = v;
	
	end
	
	-- Add or overwrite right values.
	for k, v in pairs(right) do
		
		t[k] = v;
	
	end
	
	return t;
	
end

--------

local toColourisedString = function(value)

	local val;

	if type(value) == "string" then

		val = "|cffffffff" .. value .. "|r";
	
	elseif type(value) == "number" then
	
		val = "|cffffff33" .. tostring(value) .. "|r";
	
	elseif type(value) == "boolean" then
	
		val = "|cff9999ff" .. tostring(value) .. "|r";
	
	end
	
	return val;
	
end

--------

local prt = function(message)

	if (message and message ~= "") then
	
		if type(message) ~= "string" then
			
			message = tostring(message);
			
		end
		
		DEFAULT_CHAT_FRAME:AddMessage(message);
	
	end

end;

--------

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
-- DATABASE KEYS -----------------------------------------------
----------------------------------------------------------------

-- IF ANY OF THE >>VALUES<< CHANGE YOU WILL RESET THE STORED
-- VARIABLES OF THE PLAYER. EFFECTIVELY DELETING THEIR CUSTOM-
-- ISATION SETTINGS!!!
--
-- Changing the constant itself may cause errors in some cases.
-- Or outright kill the addon alltogether.

-- #TODO:	Make these version specific, allowing full
--			backwards-compatability. Though doing so manually
--			is very error prone. Not sure how to do this auto-
--			matically. Yet.
--
--			Consider doing something like a property list.
--			When changing a property using the slash-cmds or
--			perhaps an in-game editor, we can change the version
--			and keep a record per version.

local IS_SLAM_MARKER_SHOWN = "is_slam_marker_shown";
local IS_ADDON_ACTIVATED = "is_addon_activated";
local IS_ADDON_LOCKED = "is_addon_locked";
local RANK_IMP_SLAM = "rank_imp_slam";
local POSITION_POINT = "position_point";
local POSITION_X = "position_x";
local POSITION_Y = "position_y";
local ACTIVE_ALPHA = "active_alpha";
local INACTIVE_ALPHA = "inactive_alpha";
local DB_VERSION = "db_version";

----------------------------------------------------------------
-- PRIVATE VARIABLES -------------------------------------------
----------------------------------------------------------------

local _initialisation_event = "ADDON_LOADED";

local _progress_bar;
local _slam_marker;

local _auto_repeat_spell_active = false;
local _auto_attack_active = false;

local _updateRunTime = 0;
local _fps = 30; -- target FPS.
local _update_display_timer = ( 1 / _fps );
local _last_update = GetTime();
local _proposed_swing_time = 1;
local _current_swing_time = 0; -- The x in x/y * 100 percentage calc.
local _total_swing_time = 1; -- the y in x/y * 100 percentage calc.

local _unit_name;
local _realm_name;
local _profile_id;
local _db;

local _swing_reset_actions;
local _event_handlers;
local _command_list;

local _last_swing;
local _ratio;

local _default_width = 200;
local _default_height = 5;

local _default_db = {
	[IS_SLAM_MARKER_SHOWN] = false;
	[IS_ADDON_ACTIVATED] = false;
	[IS_ADDON_LOCKED] = true;
	[RANK_IMP_SLAM] = 0;
	[POSITION_POINT] = "CENTER";
	[POSITION_X] = 0;
	[POSITION_Y] = -120;
	[ACTIVE_ALPHA] = 1;
	[INACTIVE_ALPHA] = 0.3;
	[DB_VERSION] = 2;
};

----------------------------------------------------------------
-- PRIVATE FUNCTIONS -------------------------------------------
----------------------------------------------------------------

local _report = function(label, message)

	label = tostring(label);
	message = tostring(message);

	local str = "|cff22ff22Samuel|r - |cff999999" .. label .. ":|r " .. message;

	DEFAULT_CHAT_FRAME:AddMessage(str);

end

--------

local _deactivateSwingTimer = function()

	this:Hide();

end

--------

local _activateSwingTimer = function()

	this:Show();
	
	_last_update = GetTime();
	
end

--------

local _resetVisibility = function()

	-- Turn on if player is in combat
	if UnitAffectingCombat("player") then
		
		_activateSwingTimer();
	
	else
		
		_deactivateSwingTimer();
	
	end
	
end

--------

local _updateSlamMarker = function()
	
	if (_slam_marker) then
	
		_slam_marker:SetWidth( (_default_width / _total_swing_time) * (_SLAM_CAST_TIME - (_db[RANK_IMP_SLAM] / _SLAM_TOTAL_RANKS_IMP_SLAM * _SLAM_TOTAL_IMP_SLAM_CAST_REDUCTION) ) );
		
	end

end

--------

local _resetSwingTimer = function()

	_last_swing = GetTime();
	_total_swing_time = _proposed_swing_time;
	_updateSlamMarker();

end

--------

local _resetSwingTimerOnSpellDamage = function(combat_log_str)

	if (not combat_log_str) or (combat_log_str == "") then
	
		error("Usage: _resetSwingTimerOnSpellDamage(combat_log_str <string>)");
		
	end
	
	-- Parse the combatlog string.
	local _,_,action = stringFind(combat_log_str, EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE)
	
	-- If it's in the list, it should reset the swingtimer.
	if _swing_reset_actions[action] then
	
		_resetSwingTimer();
		
	end
	
end

--------

local _setImpSlamRank = function(rank)

	-- Stop arsin about!
	if rank == _db[RANK_IMP_SLAM] then return end;

	rank = tonumber(rank);

	if 	rank < 0
	or 	rank > _SLAM_TOTAL_RANKS_IMP_SLAM then
	
		error("Usage: _setImpSlamRank(rank <number> [0-" .. _SLAM_TOTAL_RANKS_IMP_SLAM .. "])");
	
	end
	
	-- Update local database
	_db[RANK_IMP_SLAM] = rank;
	
	_report("Saved Improved Slam rank", _db[RANK_IMP_SLAM]);
	
	-- Slam marker is dependant on rank so update it now.
	_updateSlamMarker();

end

--------

local _updateRangedSwingTime = function()

	_proposed_swing_time = UnitRangedDamage("player");

end

--------

local _updateSwingTime = function()

	_proposed_swing_time = UnitAttackSpeed("player"); --http://vanilla-wow.wikia.com/wiki/API_UnitAttackSpeed
	
end

--------

local _activateAutoAttackSymbol = function()

	if _auto_attack_active or _auto_repeat_spell_active then
	
		this:SetAlpha(_db[ACTIVE_ALPHA]);
	
	end
	
end

--------

local _deactivateAutoAttackSymbol = function()

	if not (_auto_attack_active or _auto_repeat_spell_active) then
	
		this:SetAlpha(_db[INACTIVE_ALPHA]);
	
	end

end

--------

local _populateSwingResetActionsList = function()

	_swing_reset_actions = {
		["Heroic"] = true,
		["Slam"] = true,
		["Cleave"] = true,
		["Raptor"] = true,
		["Maul"] = true,
		["Shoot"] = true,
	}

end

--------

local _addEvent = function(event_name, eventHandler)

	if 	(not event_name)
	or 	(event_name == "")
	or 	(not eventHandler)
	or 	(type(eventHandler) ~= "function") then
	
		error("Usage: _addEvent(event_name <string>, eventHandler <function>)");
	
	end
	
	_event_handlers[event_name] = eventHandler;
	
	this:RegisterEvent(event_name);

end

--------

local _removeEvent = function(event_name)

	local eventHandler = _event_handlers[event_name];
	
	if eventHandler then
	
		-- GC should pick this up.
		_event_handlers[event_name] = nil;
	
	end
	
	this:UnregisterEvent(event_name);

end

--------

local _addSlashCommand = function(name, command, command_description, db_property)

	-- prt("Adding a slash command");
	if 	(not name)
	or	(name == "")
	or	(not command)
	or 	(type(command) ~= "function")
	or 	(not command_description)
	or 	(command_description == "") then
	
		error("Usage: _addSlashCommand(name <string>, command <function>, command_description <string> [, db_property <string>])");
	
	end
	
	-- prt("Creating a slash command object into the command list");
	_command_list[name] = {
		["execute"] = command,
		["description"] = command_description
	};
	
	if (db_property) then
	
		if (type(db_property) ~= "string" or db_property == "") then
	
			error("db_property must be a non-empty string.");
			
		end
		
		if (_db[db_property] == nil) then
		
			error('The interal database property: "' .. db_property .. '" could not be found.');
		
		end
		-- prt("Add the database property to the command list");
		_command_list[name]["value"] = db_property;
	
	end
	
end

--------

local _finishInitialisation = function()
	
	-- we only need this once
	this:UnregisterEvent("PLAYER_LOGIN");
	
	_updateSwingTime();

end

--------

local _storeLocalDatabaseToSavedVariables = function()
	
	-- #OPTION: We could have local variables for lots of DB
	-- 			stuff that we can load into the _db Object
	--			before we store it.
	--
	--			Should probably make a list of variables to keep
	--			track of which changed and should be updated.
	--			Something we can just loop through so load and
	--			unload never desync.
	
	-- Commit to local storage
	SamuelDB[_profile_id] = _db;

end

--------

local _validatePlayerTalents = function()
	
	--_report("CHARACTER_POINTS_CHANGED", arg1);

end

--------

local _activateAutoAttack = function()

	_auto_attack_active = true;

	_activateAutoAttackSymbol();

end

--------

local _deactivateAutoAttack = function()

	_auto_attack_active = false;

	_deactivateAutoAttackSymbol();
	
end

--------

local _activateAutoRepeatSpell = function()

	_updateRangedSwingTime();
	
	_auto_repeat_spell_active = true;
	
	_activateAutoAttackSymbol();
	
end

--------

local _deactivateAutoRepeatSpell = function()

	_updateSwingTime();
	
	_auto_repeat_spell_active = false;
	
	_deactivateAutoAttackSymbol();

end

--------

local _eventCoordinator = function()

	-- given:
	-- event <string> The event name that triggered.
	-- arg1, arg2, ..., arg9 <*> Given arguments specific to the event.
	
	local eventHandler = _event_handlers[event];
	
	if eventHandler then
	
		eventHandler(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9);
		
	end
	
end

--------

local _removeEvents = function()

	for event_name, eventHandler in pairs(_event_handlers) do
	
		if eventHandler then
		
			_removeEvent(event_name);
		
		end
	
	end

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
				error(ERR_UNEXPECTED_NIL_VALUE .. ": _total_swing_time");
				
			end
			
			_current_swing_time = GetTime() - _last_swing;
			
			-- Use the native math library to prevent us overshooting our bar length.
			_ratio = mathMin((_current_swing_time / _total_swing_time), 1);
			
			_progress_bar:SetWidth(_ratio * _default_width);
		
		-- OK STOP DOTS!!!
		
		-- Remove this and you've gone full retard.
		_updateRunTime = _updateRunTime - _update_display_timer;
	
	end
	
	_last_update = GetTime();
	
end

--------

local _createProgressBar = function()
	
	-- We already made one, no use in making another.
	if _progress_bar then
	
		return;
	
	end
	
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

local _hideSlamMarker = function()

	_db[IS_SLAM_MARKER_SHOWN] = false;
	
	-- Addon could be inactive or some other reason
	-- we don't actually have the frame on hand.
	if (_slam_marker) then
	
		_slam_marker:Hide();
		
	end
	
	_report("Slam marker is", "Hidden");

end

--------

local _showSlamMarker = function()

	_db[IS_SLAM_MARKER_SHOWN] = true;

	-- Addon could be inactive or some other reason
	-- we don't actually have the frame on hand.
	if (_slam_marker) then
	
		_slam_marker:Show();
		
	end
	
	_report("Slam marker is", "Shown");
	
end

--------

local _toggleSlamMarkerVisibility = function()

	if _db[IS_SLAM_MARKER_SHOWN] then
		
		_hideSlamMarker();
		
	else
	
		_showSlamMarker();
		
	end

end

--------

local _createSlamMarker = function()
	
	-- We already made one, no use in making another.
	if _slam_marker then
	
		return;
	
	end
	
	_slam_marker = CreateFrame("FRAME", nil, this);
	
	_slam_marker:SetBackdrop(
		{
			["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
		}
	);
	_slam_marker:SetBackdropColor(1, 0, 0, 0.7);
	
	_slam_marker:SetPoint("RIGHT", 0, 0);
	
	_slam_marker:SetHeight(_default_height);
	
	if (_progress_bar) then
		-- Making sure slam marker is visually on top of the progress bar.		
		_slam_marker:SetFrameLevel(_progress_bar:GetFrameLevel()+1);
		
	end
	
	if _db[IS_SLAM_MARKER_SHOWN] then
	
		_slam_marker:Show();
		
	else
	
		_slam_marker:Hide();
		
	end
	
end

--------

local _printSlashCommandList = function()

	_report("Listing", "Slash commands");

	local str;
	local description;
	local current_value;
	
	for name, cmd_object in pairs(_command_list) do
		
		description = cmd_object.description;
		
		if (not description) then
		
			error('Attempt to print slash command with name:"' .. name .. '" without valid description');
			
		end
	
		str = "/sam " .. name .. " " .. description;
		
		-- If the slash command sets a value we should have 
		if (cmd_object.value) then
		
			str = str .. " (|cff666666Currently:|r " .. toColourisedString(_db[cmd_object.value]) .. ")";
		
		end
		
		prt(str);
	
	end
	
	
	
end

--------

local _startMoving = function()

	this:StartMoving();

end

--------

local _stopMovingOrSizing = function()

	this:StopMovingOrSizing();
	
	_db[POSITION_POINT], _, _, _db[POSITION_X], _db[POSITION_Y] = this:GetPoint();

end

--------

local _unlockAddon = function()

	-- Make the left mouse button trigger drag events
	this:RegisterForDrag("LeftButton");
	
	-- Set the start and stop moving events on triggered events
	this:SetScript(SCRIPTHANDLER_ON_DRAG_START, _startMoving);
	this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, _stopMovingOrSizing);
	
	-- Make the frame react to the mouse
	this:EnableMouse(true);
	
	-- Make the frame movable
	this:SetMovable(true);
	
	-- Show ourselves so we can be moved
	_activateSwingTimer();
	
	_db[IS_ADDON_LOCKED] = false;
	
	_report("Swing timer bar", "Unlocked");

end

--------

local _lock_addon = function()
	
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

	_db[IS_ADDON_LOCKED] = true;
	
	_report("Swing timer bar", "Locked");
	
end

--------

local _toggleLockToScreen = function()

	-- Inversed logic to lock the addon if _db[IS_ADDON_LOCKED] returns 'nil' for some reason.
	if not _db[IS_ADDON_LOCKED] then
	
		_lock_addon();
	
	else
	
		_unlockAddon();
	
	end

end

--------

local _populateRequiredEvents = function()
	
	_addEvent("CHAT_MSG_COMBAT_SELF_HITS", _resetSwingTimer);
	_addEvent("CHAT_MSG_COMBAT_SELF_MISSES", _resetSwingTimer);
	_addEvent("CHAT_MSG_SPELL_SELF_DAMAGE", _resetSwingTimerOnSpellDamage);
	
	_addEvent("UNIT_ATTACK_SPEED", _updateSwingTime);
	
	_addEvent("PLAYER_REGEN_DISABLED", _activateSwingTimer);
	_addEvent("PLAYER_REGEN_ENABLED", _deactivateSwingTimer);
	
	_addEvent("PLAYER_ENTER_COMBAT", _activateAutoAttack);
	_addEvent("PLAYER_LEAVE_COMBAT", _deactivateAutoAttack);
	
	_addEvent("START_AUTOREPEAT_SPELL", _activateAutoRepeatSpell);
	_addEvent("STOP_AUTOREPEAT_SPELL", _deactivateAutoRepeatSpell);
	
	_addEvent("PLAYER_LOGIN", _finishInitialisation);
	
	if UnitClass("player") == "warrior" then
	
		_addEvent("CHARACTER_POINTS_CHANGED", _validatePlayerTalents);
		
	end

end

--------

local _constructAddon = function()

	this:SetWidth(_default_width);
	this:SetHeight(_default_height);
	
	this:SetBackdrop(
		{
			["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
		}
	);
	
	this:SetBackdropColor(0, 0, 0, 1);
	
	this:SetPoint(_db[POSITION_POINT], _db[POSITION_X], _db[POSITION_Y]);
	
	if (not _db[IS_ADDON_LOCKED]) then _unlockAddon() end;
	
	-- CREATE CHILDREN
	_createProgressBar();
	_createSlamMarker();
		
	_resetSwingTimer();
	_resetVisibility();

	_populateSwingResetActionsList();
	_populateRequiredEvents();
	
	this:SetScript(SCRIPTHANDLER_ON_UPDATE, _updateDisplay);

end

--------

local _destructAddon = function()

	
	-- Stop frame updates
	this:SetScript(SCRIPTHANDLER_ON_UPDATE, nil);
	
	-- Remove all registered events
	_removeEvents();
	
	_deactivateSwingTimer();
	_deactivateAutoAttack();
	_deactivateAutoRepeatSpell();
	
end

--------

local _activateAddon = function()

	if _db[IS_ADDON_ACTIVATED] then
	
		return;
	
	end

	_constructAddon();

	_db[IS_ADDON_ACTIVATED] = true;
	
	_report("is now", "Activated");
		
end

--------

local _deactivateAddon = function()

	if not _db[IS_ADDON_ACTIVATED] then
	
		return;
	
	end

	_destructAddon();
	
	_db[IS_ADDON_ACTIVATED] = false;

	-- This is here and not in the destructor because
	-- _loadSavedVariables is not in the constructor either.
	_storeLocalDatabaseToSavedVariables();
	
	_report("is now", "Deactivated");
	
end

--------

local _toggleAddonActivity = function()

	if not _db[IS_ADDON_ACTIVATED] then
		
		_activateAddon();
		
	else
	
		_deactivateAddon();
		
	end

end

--------

local _slashCmdHandler = function(message, chat_frame)

	local _,_,command_name, params = stringFind(message, "^(%S+) *(.*)");
	
	-- Stringify it
	command_name = tostring(command_name);
	
	-- Pull the given command from our list.
	local command = _command_list[command_name];
	
	if (command) then
		-- Run the command we found.
		if (type(command.execute) ~= "function") then
			
			error("Attempt to execute slash command without execution function.");
			
		end
		
		command.execute(params);

	else
		-- prt("Print our available command list.");
		_printSlashCommandList();
		
	end
		
end

--------

local _loadProfileID = function()

	_unit_name = UnitName("player");
	_realm_name = GetRealmName();
	_profile_id = _unit_name .. "-" .. _realm_name;
	
end

--------

local _loadSavedVariables = function()

	-- First time install
	if not SamuelDB then
		SamuelDB = {};
	end
	
	-- this should produce an error if _profile_id is not yet set, as is intended.
	_db = SamuelDB[_profile_id];
	
	-- This means we have a new char.
	if not _db then
		_db = _default_db
	end
	
	-- In this case we have a player with an older version DB.
	if (not _db[DB_VERSION]) or (_db[DB_VERSION] < _default_db[DB_VERSION]) then
		
		-- For now we just blindly attempt to merge.
		_db = merge(_default_db, _db);
		
	end

end

--------

local _resetSlashCommands = function()

	-- For now we just reset this thing.
	_command_list = {};
	
	_addSlashCommand(
		"impSlam",
		_setImpSlamRank,
		'[|cffffff330|r-|cffffff33' .. _SLAM_TOTAL_RANKS_IMP_SLAM .. '|r] |cff999999-- Set your current rank of the "Improved Slam" talent.|r',
		RANK_IMP_SLAM
	);
	
	_addSlashCommand(
		"showSlamMarker",
		_toggleSlamMarkerVisibility,
		'<|cff9999fftoggle|r> |cff999999-- Toggle whether the red slam marker is showing.|r',
		IS_SLAM_MARKER_SHOWN
	);
		
	_addSlashCommand(
		"lock",
		_toggleLockToScreen,
		'<|cff9999fftoggle|r> |cff999999-- Toggle whether the bar is movable.|r',
		IS_ADDON_LOCKED
	);
		
	_addSlashCommand(
		"activate",
		_toggleAddonActivity,
		'<|cff9999fftoggle|r> |cff999999-- Toggle whether the AddOn itself is active.|r',
		IS_ADDON_ACTIVATED
	);
	
end

--------

local _initialise = function()
	
	_loadProfileID();
	_loadSavedVariables();
	
	this:UnregisterEvent(_initialisation_event);
	
	_event_handlers = {};
	
	_resetSlashCommands();
	
	this:SetScript(SCRIPTHANDLER_ON_EVENT, _eventCoordinator);
	
	_addEvent("PLAYER_LOGOUT", _storeLocalDatabaseToSavedVariables);
	
	if _db[IS_ADDON_ACTIVATED] then
	
		_constructAddon();
	
	end
	
end

-- Add slashcommand match entries into the global namespace for the client to pick up.
SLASH_SAMUEL1 = "/sam";
SLASH_SAMUEL2 = "/samuel";

-- And add a handler to react on the above matches.
SlashCmdList["SAMUEL"] = _slashCmdHandler;

this:SetScript(SCRIPTHANDLER_ON_EVENT, _initialise);
this:RegisterEvent(_initialisation_event);