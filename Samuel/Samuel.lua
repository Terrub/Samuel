local EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE = "^Your (.+) c*[rh]its";

local ERR_UNEXPECTED_NIL_VALUE = "Expected the following value but got nil."

local SCRIPTHANDLER_ON_EVENT = "OnEvent";
local SCRIPTHANDLER_ON_UPDATE = "OnUpdate";


----------------------------------------------------------------
-- SAMUEL ADDON ------------------------------------------------
----------------------------------------------------------------


Samuel = CreateFrame("FRAME", "Samuel", UIParent);

local this = Samuel;

----------------------------------------------------------------
-- PRIVATE VARIABLES -------------------------------------------
----------------------------------------------------------------

local _initialisation_event = "ADDON_LOADED";

local _progress;
local _slamMarker;

local _updateRunTime = 0;
local _update_display_timer = ( 1 / 30 ); -- update FPS target;
local _last_update = GetTime();
local _current_swing_time = 0; -- The x in x/y * 100 percentage calc.
local _total_swing_time = 1; -- the y in x/y * 100 percentage calc.

local _swing_reset_actions;

local _last_swing;
local _ratio;

local _default_width = 200;
local _default_height = 5;

----------------------------------------------------------------
-- LOCAL UP VALUES FOR SPEED -----------------------------------
----------------------------------------------------------------

local math_min = math.min;
local string_find = string.find;

----------------------------------------------------------------
-- PRIVATE FUNCTIONS -------------------------------------------
----------------------------------------------------------------

local _resetSwingTimer = function()

	_last_swing = GetTime();

end

--------

local _updateSlamMarker = function()

	-- length = _default_width / _total_swing_time ( * 1.5 if 0/5 imp. slam)
	_slamMarker:SetWidth(_default_width / _total_swing_time);

end

--------

local _updateSwingTime = function()

	_total_swing_time,_ = UnitAttackSpeed("player"); --http://vanilla-wow.wikia.com/wiki/API_UnitAttackSpeed
	
	_updateSlamMarker();

end

--------

local _createSwingResetActionsList = function()

	_swing_reset_actions = {
		["Heroic Strike"] = true,
		["Slam"] = true,
		["Cleave"] = true,
		["Raptor Strike"] = true,
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
	this:RegisterEvent("PLAYER_LOGIN");

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
			
				_progress:SetScript(SCRIPTHANDLER_ON_UPDATE, nil);
				error(ERR_UNEXPECTED_NIL_VALUE..": _total_swing_time");
				
			end
			
			_current_swing_time = GetTime() - _last_swing;
			
			-- Use the native math library to prevent us overshooting our bar length.
			_ratio = math_min((_current_swing_time / _total_swing_time), 1);
			
			_progress:SetWidth(_ratio * _default_width);
		
		-- OK STOP DOTS!!!
		
		-- Remove this and you've gone full retard.
		_updateRunTime = _updateRunTime - _update_display_timer;
	
	end
	
	_last_update = GetTime();
	
end

--------

local _createProgressBar = function()
	
	_progress = CreateFrame("FRAME", nil, this);
	
	_progress:SetBackdrop(
		{
			["bgFile"] = "Interface/Tooltips/UI-Tooltip-Background"
		}
	);
	
	_progress:SetBackdropColor(1, 1, 1, 1);
	
	_progress:SetWidth(1);
	_progress:SetHeight(_default_height);
	
	_progress:SetPoint("LEFT", 0, 0);
	
end

--------

local _createSlamMarker = function()
	
	_slamMarker = CreateFrame("FRAME", nil, this);
	
	_slamMarker:SetBackdrop(
		{
			["bgFile"] = "Interface/Tooltips/UI-Tooltip-Background"
		}
	);
	_slamMarker:SetBackdropColor(1, 0, 0, 0.9);
	
	_slamMarker:SetPoint("RIGHT", 0, 0);
	
	_slamMarker:SetHeight(_default_height);
	
end

--------

local _initialise = function()

	this:UnregisterEvent(_initialisation_event);
	
	this:SetWidth(_default_width);
	this:SetHeight(_default_height);
	
	this:SetBackdrop(
		{
			["bgFile"] = "Interface/Tooltips/UI-Tooltip-Background"
		}
	);
	
	this:SetBackdropColor(0, 0, 0, 1);
	
	this:SetPoint("CENTER", 0, -120);
	
	_createProgressBar();
	_createSlamMarker();
	
	_resetSwingTimer();
	_createSwingResetActionsList();
	
	_registerRequiredEvents();
	
	-- Turn off by default unless we're in combat
	if not UnitAffectingCombat("player") then
		
		this:Hide();
		
	end
	
	this:SetScript(SCRIPTHANDLER_ON_EVENT, _eventHandler);
	
	-- We need to update, so set the update display script.
	this:SetScript(SCRIPTHANDLER_ON_UPDATE, _updateDisplay);
	
end

this:SetScript(SCRIPTHANDLER_ON_EVENT, _initialise);
this:RegisterEvent(_initialisation_event);