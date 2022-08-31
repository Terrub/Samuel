----------------------------------------------------------------
-- "UP VALUES" FOR SPEED ---------------------------------------
----------------------------------------------------------------

local _mathMin = math.min
local _stringFind = string.find
local _tableInsert = table.insert
local _tableRemove = table.remove
local _tostring = tostring
local _type = type
local _error = error
local _pairs = pairs

----------------------------------------------------------------
-- CONSTANTS THAT SHOULD BE GLOBAL PROBABLY --------------------
----------------------------------------------------------------

local EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE = "^Your (.-) "

local ERR_UNEXPECTED_NIL_VALUE = "Expected the following value but got nil:"

local SCRIPTHANDLER_ON_EVENT = "OnEvent"
local SCRIPTHANDLER_ON_UPDATE = "OnUpdate"
local SCRIPTHANDLER_ON_DRAG_START = "OnDragStart"
local SCRIPTHANDLER_ON_DRAG_STOP = "OnDragStop"

----------------------------------------------------------------
-- HELPER FUNCTIONS --------------------------------------------
----------------------------------------------------------------

--  These should be moved into the core at one point.

local merge = function(left, right)
    local t = {}

    if _type(left) ~= "table" or _type(right) ~= "table" then
        _error("Usage: merge(left <table>, right <table>)")
    end

    -- copy left into temp table.
    for k, v in _pairs(left) do
        t[k] = v
    end

    -- Add or overwrite right values.
    for k, v in _pairs(right) do
        t[k] = v
    end

    return t
end

--------

local toColourisedString = function(value)
    local val

    if _type(value) == "string" then
        val = "|cffffffff" .. value .. "|r"
    elseif _type(value) == "number" then
        val = "|cffffff33" .. _tostring(value) .. "|r"
    elseif _type(value) == "boolean" then
        val = "|cff9999ff" .. _tostring(value) .. "|r"
    end

    return val
end

--------

local prt = function(message)
    if (message and message ~= "") then
        if _type(message) ~= "string" then
            message = _tostring(message)
        end

        DEFAULT_CHAT_FRAME:AddMessage(message)
    end
end

--------

----------------------------------------------------------------
-- SAMUEL ADDON ------------------------------------------------
----------------------------------------------------------------

Samuel = CreateFrame("FRAME", "Samuel", UIParent)

local this = Samuel

----------------------------------------------------------------
-- INTERNAL CONSTANTS ------------------------------------------
----------------------------------------------------------------

local _SLAM_CAST_TIME = 1.5
local _SLAM_TOTAL_RANKS_IMP_SLAM = 5
local _SLAM_TOTAL_IMP_SLAM_CAST_REDUCTION = 0.5

----------------------------------------------------------------
-- DATABASE KEYS -----------------------------------------------
----------------------------------------------------------------

-- IF ANY OF THE >>VALUES<< CHANGE YOU WILL RESET THE STORED
-- VARIABLES OF THE PLAYER. EFFECTIVELY DELETING THEIR CUSTOM-
-- ISATION SETTINGS!!!
--
-- Changing the constant itself may cause errors in some cases.
-- Or outright kill the addon alltogether.

-- #TODO:   Make these version specific, allowing full
--          backwards-compatibility. Though doing so manually
--          is very _error prone. Not sure how to do this auto-
--          matically. Yet.
--
--          Consider doing something like a property list.
--          When changing a property using the slash-cmds or
--          perhaps an in-game editor, we can change the version
--          and keep a record per version.

local IS_MARKER_SHOWN = "is_marker_shown"
local IS_RANGED_MARKER_SHOWN = "is_ranged_marker_shown"
local IS_ADDON_ACTIVATED = "is_addon_activated"
local IS_ADDON_LOCKED = "is_addon_locked"
local MARKER_SIZE = "marker_size"
local RANGED_MARKER_SIZE = "ranged_marker_size"
local POSITION_POINT = "position_point"
local POSITION_X = "position_x"
local POSITION_Y = "position_y"
local ACTIVE_ALPHA = "active_alpha"
local INACTIVE_ALPHA = "inactive_alpha"
local DB_VERSION = "db_version"
local WIDTH = "WIDTH"
local HEIGHT = "HEIGHT"

local _default_db = {
    [IS_MARKER_SHOWN] = false,
    [IS_RANGED_MARKER_SHOWN] = false,
    [IS_ADDON_ACTIVATED] = false,
    [IS_ADDON_LOCKED] = true,
    [MARKER_SIZE] = 1.5,
    [RANGED_MARKER_SIZE] = 1.5,
    [POSITION_POINT] = "CENTER",
    [POSITION_X] = 0,
    [POSITION_Y] = -120,
    [ACTIVE_ALPHA] = 1,
    [INACTIVE_ALPHA] = 0.3,
    [DB_VERSION] = 6,
    [WIDTH] = 200,
    [HEIGHT] = 8
}

----------------------------------------------------------------
-- PRIVATE VARIABLES -------------------------------------------
----------------------------------------------------------------

local _initialisation_event = "ADDON_LOADED"

local _progress_bar
local _marker
local _ranged_progress_bar
local _ranged_marker

local _auto_repeat_spell_active = false
local _auto_attack_active = false

local _updateRunTime = 0
local _fps = 30
local _update_display_timer = (1 / _fps)
local _last_update = GetTime()

local _proposed_swing_time = 1
local _current_swing_time = 0
local _total_swing_time = 1

local _proposed_ranged_time = 1
local _current_ranged_time = 0
local _total_ranged_time = 1

local _unit_name
local _realm_name
local _profile_id
local _db

local _swing_reset_actions
local _event_handlers
local _command_list

local _last_swing
local _last_shot
local _ratio
local _ranged_ratio

----------------------------------------------------------------
-- PRIVATE FUNCTIONS -------------------------------------------
----------------------------------------------------------------

local _report = function(label, message)
    label = _tostring(label)
    message = _tostring(message)

    local str = "|cff22ff22Samuel|r - |cff999999" .. label .. ":|r " .. message

    DEFAULT_CHAT_FRAME:AddMessage(str)
end

--------

local _deactivateSwingTimer = function()
    this:Hide()
end

--------

local _activateSwingTimer = function()
    this:Show()
    _last_update = GetTime()
end

--------

local _resetVisibility = function()
    -- Turn on if player is in combat
    if UnitAffectingCombat("player") or (_db[IS_ADDON_LOCKED] == false) then
        _activateSwingTimer()
    else
        _deactivateSwingTimer()
    end
end

--------

local _updateSlamMarker = function()
    if (_marker) then
        _marker:SetWidth((_db[WIDTH] / _total_swing_time) * _db[MARKER_SIZE])
    end
end

--------

local _updateRangedMarker = function()
    if (_ranged_marker) then
        _ranged_marker:SetWidth((_db[WIDTH] / _total_ranged_time) * _db[RANGED_MARKER_SIZE])
    end
end

--------

local _resetSwingTimer = function()
    _last_swing = GetTime()
    _total_swing_time = _proposed_swing_time
    _updateSlamMarker()
end

--------

local _resetRangedTimer = function()
    _last_shot = GetTime()
    _total_ranged_time = _proposed_ranged_time
    _updateRangedMarker()
end

--------

local _applyParryHaste = function(combat_log_str)
    if _stringFind(combat_log_str, "parry") then
        _total_swing_time = 0.4 * _proposed_swing_time
    end
end

--------

local _resetSwingTimerOnSpellDamage = function(combat_log_str)
    if (not combat_log_str) or (combat_log_str == "") then
        _error("Usage: _resetSwingTimerOnSpellDamage(combat_log_str <string>)")
    end
    -- prt(combat_log_str);
    local _, _, action = _stringFind(combat_log_str, EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE)

    if _swing_reset_actions[action] then
        _resetSwingTimer()
    elseif action == "Auto" then
        _resetRangedTimer()
    end
end

--------

local _updateSwingTime = function()
    --http://vanilla-wow.wikia.com/wiki/API_UnitAttackSpeed
    _proposed_swing_time = UnitAttackSpeed("player")
end

--------

local _updateRangedSwingTime = function()
    _proposed_ranged_time = UnitRangedDamage("player")
end

--------

local _activateAutoAttackSymbol = function()
    if _auto_attack_active or _auto_repeat_spell_active then
        this:SetAlpha(_db[ACTIVE_ALPHA])
    end
end

--------

local _deactivateAutoAttackSymbol = function()
    if not (_auto_attack_active or _auto_repeat_spell_active) then
        this:SetAlpha(_db[INACTIVE_ALPHA])
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
        ["Shoot"] = true
    }
end

--------

local _addEvent = function(event_name, eventHandler)
    if (not event_name) or (event_name == "") or (not eventHandler) or (_type(eventHandler) ~= "function") then
        _error("Usage: _addEvent(event_name <string>, eventHandler <function>)")
    end

    _event_handlers[event_name] = eventHandler
    this:RegisterEvent(event_name)
end

--------

local _removeEvent = function(event_name)
    local eventHandler = _event_handlers[event_name]
    if eventHandler then
        -- GC should pick this up when a new assignment happens
        _event_handlers[event_name] = nil
    end

    this:UnregisterEvent(event_name)
end

--------

local _addSlashCommand = function(name, command, command_description, db_property)
    -- prt("Adding a slash command");
    if
        (not name) or (name == "") or (not command) or (_type(command) ~= "function") or (not command_description) or
            (command_description == "")
     then
        _error(
            "Usage: _addSlashCommand(name <string>, command <function>, command_description <string> [, db_property <string>])"
        )
    end

    -- prt("Creating a slash command object into the command list");
    _command_list[name] = {
        ["execute"] = command,
        ["description"] = command_description
    }

    if (db_property) then
        if (_type(db_property) ~= "string" or db_property == "") then
            _error("db_property must be a non-empty string.")
        end

        if (_db[db_property] == nil) then
            _error('The interal database property: "' .. db_property .. '" could not be found.')
        end
        -- prt("Add the database property to the command list");
        _command_list[name]["value"] = db_property
    end
end

--------

local _finishInitialisation = function()
    -- we only need this once
    this:UnregisterEvent("PLAYER_LOGIN")
    _updateSwingTime()
end

--------

local _storeLocalDatabaseToSavedVariables = function()
    -- #OPTION: We could have local variables for lots of DB
    --          stuff that we can load into the _db Object
    --          before we store it.
    --
    --          Should probably make a list of variables to keep
    --          track of which changed and should be updated.
    --          Something we can just loop through so load and
    --          unload never desync.

    -- Commit to local storage
    SamuelDB[_profile_id] = _db
end

--------

local _validatePlayerTalents = function()
    --_report("CHARACTER_POINTS_CHANGED", arg1);
end

--------

local _activateAutoAttack = function()
    _auto_attack_active = true
    _activateAutoAttackSymbol()
end

--------

local _deactivateAutoAttack = function()
    _auto_attack_active = false
    _deactivateAutoAttackSymbol()
end

--------

local _activateAutoRepeatSpell = function()
    _updateRangedSwingTime()
    _auto_repeat_spell_active = true
    _activateAutoAttackSymbol()
end

--------

local _deactivateAutoRepeatSpell = function()
    _updateSwingTime()
    _auto_repeat_spell_active = false
    _deactivateAutoAttackSymbol()
end

--------

local _eventCoordinator = function()
    -- given:
    -- event <string> The event name that triggered.
    -- arg1, arg2, ..., arg9 <*> Given arguments specific to the event.

    local eventHandler = _event_handlers[event]

    if eventHandler then
        eventHandler(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    end
end

--------

local _removeEvents = function()
    for event_name, eventHandler in _pairs(_event_handlers) do
        if eventHandler then
            _removeEvent(event_name)
        end
    end
end

--------

local _updateDisplay = function()
    local elapsed = GetTime() - _last_update

    -- elapsed is the total time since last frame update.
    -- we have to add this to our current running total timer
    -- to know when to actually do something next frame.
    _updateRunTime = _updateRunTime + elapsed

    while (_updateRunTime >= _update_display_timer) do
        _current_swing_time = GetTime() - _last_swing
        _ratio = _mathMin((_current_swing_time / _total_swing_time), 1)
        _progress_bar:SetWidth(_ratio * _db[WIDTH])

        _current_ranged_time = GetTime() - _last_shot
        _ranged_ratio = _mathMin((_current_ranged_time / _total_ranged_time), 1)
        _ranged_progress_bar:SetWidth(_ranged_ratio * _db[WIDTH])

        _updateRunTime = _updateRunTime - _update_display_timer
    end

    _last_update = GetTime()
end

--------

local _createProgressBar = function(parent, point, x, y)
    local progressBar = CreateFrame("FRAME", nil, parent)
    progressBar:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    progressBar:SetBackdropColor(0.7, 0.7, 0.7, 1)
    progressBar:SetWidth(1)
    progressBar:SetHeight(_db[HEIGHT])
    progressBar:SetPoint(point, x, y)

    return progressBar
end

--------

local _hideMarker = function()
    _db[IS_MARKER_SHOWN] = false

    -- Addon could be inactive or some other reason
    -- we don't actually have the frame on hand.
    if (_marker) then
        _marker:Hide()
    end
end

--------

local _showMarker = function()
    _db[IS_MARKER_SHOWN] = true

    -- Addon could be inactive or some other reason
    -- we don't actually have the frame on hand.
    if (_marker) then
        _marker:Show()
    end
end

--------

local _hideRangedMarker = function()
    _db[IS_RANGED_MARKER_SHOWN] = false

    -- Addon could be inactive or some other reason
    -- we don't actually have the frame on hand.
    if (_ranged_marker) then
        _ranged_marker:Hide()
    end
end

--------

local _showRangedMarker = function()
    _db[IS_RANGED_MARKER_SHOWN] = true

    -- Addon could be inactive or some other reason
    -- we don't actually have the frame on hand.
    if (_ranged_marker) then
        _ranged_marker:Show()
    end
end

--------

local _createMarker = function(progressBar, point, x, y)
    if not progressBar then
        return
    end

    local marker = CreateFrame("FRAME", nil, this)

    marker:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    marker:SetBackdropColor(1, 0, 0, 0.7)
    marker:SetPoint(point, x, y)
    marker:SetHeight(_db[HEIGHT])

    -- Making sure slam marker is visually on top of the progress bar.
    marker:SetFrameLevel(progressBar:GetFrameLevel() + 1)

    if _db[IS_MARKER_SHOWN] then
        _showMarker()
    else
        _hideMarker()
    end

    return marker
end

--------

local _printSlashCommandList = function()
    _report("Listing", "Slash commands")

    local str
    local description
    local current_value

    for name, cmd_object in _pairs(_command_list) do
        description = cmd_object.description

        if (not description) then
            _error('Attempt to print slash command with name:"' .. name .. '" without valid description')
        end

        str = "/sam " .. name .. " " .. description

        -- If the slash command sets a value we should have
        if (cmd_object.value) then
            str = str .. " (|cff666666Currently:|r " .. toColourisedString(_db[cmd_object.value]) .. ")"
        end

        prt(str)
    end
end

--------

local _startMoving = function()
    this:StartMoving()
end

--------

local _stopMovingOrSizing = function()
    this:StopMovingOrSizing()
    _db[POSITION_POINT], _, _, _db[POSITION_X], _db[POSITION_Y] = this:GetPoint()
end

--------

local _unlockAddon = function()
    -- Make the left mouse button trigger drag events
    this:RegisterForDrag("LeftButton")
    -- Set the start and stop moving events on triggered events
    this:SetScript(SCRIPTHANDLER_ON_DRAG_START, _startMoving)
    this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, _stopMovingOrSizing)
    -- Make the frame react to the mouse
    this:EnableMouse(true)
    -- Make the frame movable
    this:SetMovable(true)
    -- Show ourselves so we can be moved
    _activateSwingTimer()

    _db[IS_ADDON_LOCKED] = false
end

--------

local _lockAddon = function()
    -- Stop the frame from being movable
    this:SetMovable(false)
    -- Remove all buttons from triggering drag events
    this:RegisterForDrag()
    -- Nil the 'OnSragStart' script event
    this:SetScript(SCRIPTHANDLER_ON_DRAG_START, nil)
    this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, nil)
    -- Disable mouse interactivity on the frame
    this:EnableMouse(false)
    -- reset our visibility
    _deactivateSwingTimer()

    _db[IS_ADDON_LOCKED] = true
end

--------

local _populateRequiredEvents = function()
    _addEvent("CHAT_MSG_COMBAT_SELF_HITS", _resetSwingTimer)
    _addEvent("CHAT_MSG_COMBAT_SELF_MISSES", _resetSwingTimer)
    _addEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES", _applyParryHaste)
    _addEvent("CHAT_MSG_SPELL_SELF_DAMAGE", _resetSwingTimerOnSpellDamage)

    _addEvent("UNIT_ATTACK_SPEED", _updateSwingTime)

    _addEvent("PLAYER_REGEN_DISABLED", _activateSwingTimer)
    _addEvent("PLAYER_REGEN_ENABLED", _deactivateSwingTimer)

    _addEvent("PLAYER_ENTER_COMBAT", _activateAutoAttack)
    _addEvent("PLAYER_LEAVE_COMBAT", _deactivateAutoAttack)

    _addEvent("START_AUTOREPEAT_SPELL", _activateAutoRepeatSpell)
    _addEvent("STOP_AUTOREPEAT_SPELL", _deactivateAutoRepeatSpell)

    _addEvent("PLAYER_LOGIN", _finishInitialisation)
end

--------

local _constructAddon = function()
    this:SetWidth(_db[WIDTH] + 2)
    this:SetHeight(_db[HEIGHT] * 2 + 3)
    this:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    this:SetBackdropColor(0, 0, 0, 1)
    this:SetPoint(_db[POSITION_POINT], _db[POSITION_X], _db[POSITION_Y])

    if (not _db[IS_ADDON_LOCKED]) then
        _unlockAddon()
    end

    -- CREATE CHILDREN
    if not _progress_bar then
        _progress_bar = _createProgressBar(this, "TOPLEFT", 1, -1)
    end
    if not _ranged_progress_bar then
        _ranged_progress_bar = _createProgressBar(this, "BOTTOMLEFT", 1, 1)
    end
    if not _marker then
        _marker = _createMarker(_progress_bar, "TOPRIGHT", -1, -1)
    end
    if not _ranged_marker then
        _ranged_marker = _createMarker(_ranged_progress_bar, "BOTTOMRIGHT", -1, 1)
    end

    _updateSwingTime()
    _updateRangedSwingTime()
    _resetSwingTimer()
    _resetRangedTimer()
    _resetVisibility()

    _populateSwingResetActionsList()
    _populateRequiredEvents()

    this:SetScript(SCRIPTHANDLER_ON_UPDATE, _updateDisplay)
end

--------

local _destructAddon = function()
    -- Stop frame updates
    this:SetScript(SCRIPTHANDLER_ON_UPDATE, nil)

    -- Remove all registered events
    _removeEvents()
    _deactivateSwingTimer()
    _deactivateAutoAttack()
    _deactivateAutoRepeatSpell()
end

--------

local _activateAddon = function()
    if _db[IS_ADDON_ACTIVATED] then
        return
    end

    _constructAddon()
    _db[IS_ADDON_ACTIVATED] = true
end

--------

local _deactivateAddon = function()
    if not _db[IS_ADDON_ACTIVATED] then
        return
    end

    _destructAddon()
    _db[IS_ADDON_ACTIVATED] = false
    -- This is here and not in the destructor because
    -- _loadSavedVariables is not in the constructor either.
    _storeLocalDatabaseToSavedVariables()
end

--------

local _slashCmdHandler = function(message, chat_frame)
    local _, _, command_name, params = _stringFind(message, "^(%S+) *(.*)")

    -- Stringify it
    command_name = _tostring(command_name)

    -- Pull the given command from our list.
    local command = _command_list[command_name]
    if (command) then
        -- Run the command we found.
        if (_type(command.execute) ~= "function") then
            _error("Attempt to execute slash command without execution function.")
        end

        command.execute(params)
    else
        -- prt("Print our available command list.");
        _printSlashCommandList()
    end
end

--------

local _loadProfileID = function()
    _unit_name = UnitName("player")
    _realm_name = GetRealmName()
    _profile_id = _unit_name .. "-" .. _realm_name
end

--------

local _loadSavedVariables = function()
    -- First time install
    if not SamuelDB then
        SamuelDB = {}
    end

    -- this should produce an _error if _profile_id is not yet set, as is intended.
    _db = SamuelDB[_profile_id]

    -- This means we have a new char.
    if not _db then
        _db = _default_db
    end

    -- In this case we have a player with an older version DB.
    if (not _db[DB_VERSION]) or (_db[DB_VERSION] < _default_db[DB_VERSION]) then
        -- For now we just blindly attempt to merge.
        _db = merge(_default_db, _db)
    end
end

----------------------------------------------------------------
-- PUBLIC METHODS ----------------------------------------------
----------------------------------------------------------------

local setMarkerSize = function(time_in_seconds)
    -- Stop arsin about!
    if time_in_seconds == _db[MARKER_SIZE] then
        return
    end

    time_in_seconds = tonumber(time_in_seconds)
    if not time_in_seconds then
        _report("setMarkerSize expects", "a number in seconds")
        return
    end

    if time_in_seconds < 0 then
        _report("setMarkerSize expects", "time in seconds to be 0 or more")
        return
    end

    -- Update local database
    _db[MARKER_SIZE] = time_in_seconds
    _report("Saved marker size to", _db[MARKER_SIZE])
    -- Marker is dependant on time_in_seconds so update it now.
    _updateSlamMarker()
end

--------

local setRangedMarkerSize = function(time_in_seconds)
    -- Stop arsin about!
    if time_in_seconds == _db[RANGED_MARKER_SIZE] then
        return
    end

    time_in_seconds = tonumber(time_in_seconds)
    if not time_in_seconds then
        _report("setRangedMarkerSize expects", "a number in seconds")
        return
    end

    if time_in_seconds < 0 then
        _report("setRangedMarkerSize expects", "time in seconds to be 0 or more")
        return
    end

    -- Update local database
    _db[RANGED_MARKER_SIZE] = time_in_seconds
    _report("Saved ranged marker size to", _db[RANGED_MARKER_SIZE])
    -- Marker is dependant on time_in_seconds so update it now.
    _updateSlamMarker()
end

--------

local toggleMarkerVisibility = function()
    if _db[IS_MARKER_SHOWN] then
        _hideMarker()
    else
        _showMarker()
    end

    _report("Marker is", (_db[IS_MARKER_SHOWN] and "Showing" or "Hidden"))
end

--------

local toggleRangedMarkerVisibility = function()
    if _db[IS_RANGED_MARKER_SHOWN] then
        _hideRangedMarker()
    else
        _showRangedMarker()
    end

    _report("Ranged marker is", (_db[IS_RANGED_MARKER_SHOWN] and "Showing" or "Hidden"))
end

--------

local toggleLockToScreen = function()
    -- Inversed logic to lock the addon if _db[IS_ADDON_LOCKED] returns 'nil' for some reason.
    if not _db[IS_ADDON_LOCKED] then
        _lockAddon()
    else
        _unlockAddon()
    end

    _report("Swing timer bar", (_db[IS_ADDON_LOCKED] and "Locked" or "Unlocked"))
end

--------

local toggleAddonActivity = function()
    if not _db[IS_ADDON_ACTIVATED] then
        _activateAddon()
    else
        _deactivateAddon()
    end

    _report("is now", (_db[IS_ADDON_ACTIVATED] and "Activated" or "Deactivated"))
end

--------

local setBarWidth = function(value)
    _db[WIDTH] = value

    _report("bar width set to", value)
end

--------

local setBarHeight = function(value)
    _db[HEIGHT] = value

    _report("bar height set to", value)
end

--------

local _populateSlashCommandList = function()
    -- For now we just reset this thing.
    _command_list = {}

    _addSlashCommand(
        "setMarkerSize",
        setMarkerSize,
        "[|cffffff330+|r] |cff999999\n\t-- Set the amount of seconds of your swing time the marker should cover.|r",
        MARKER_SIZE
    )

    _addSlashCommand(
        "setRangedMarkerSize",
        setRangedMarkerSize,
        "[|cffffff330+|r] |cff999999\n\t-- Set the amount of seconds of your ranged time the marker should cover.|r",
        RANGED_MARKER_SIZE
    )

    _addSlashCommand(
        "showMarker",
        toggleMarkerVisibility,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the red marker is showing.|r",
        IS_MARKER_SHOWN
    )

    _addSlashCommand(
        "showRangedMarker",
        toggleRangedMarkerVisibility,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the red marker is showing for ranged.|r",
        IS_RANGED_MARKER_SHOWN
    )

    _addSlashCommand(
        "lock",
        toggleLockToScreen,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the bar is locked to the screen.|r",
        IS_ADDON_LOCKED
    )

    _addSlashCommand(
        "activate",
        toggleAddonActivity,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the AddOn itself is active.|r",
        IS_ADDON_ACTIVATED
    )

    _addSlashCommand("setBarWidth", setBarWidth, "[|cffffff330+|r] |cff999999\n\t-- Set the width of the bar.|r", WIDTH)

    _addSlashCommand(
        "setBarHeight",
        setBarHeight,
        "[|cffffff330+|r] |cff999999\n\t-- Set the height of the bar.|r",
        HEIGHT
    )
end

--------

local _initialise = function()
    _loadProfileID()
    _loadSavedVariables()

    this:UnregisterEvent(_initialisation_event)

    _event_handlers = {}

    _populateSlashCommandList()
    this:SetScript(SCRIPTHANDLER_ON_EVENT, _eventCoordinator)

    _addEvent("PLAYER_LOGOUT", _storeLocalDatabaseToSavedVariables)

    if _db[IS_ADDON_ACTIVATED] then
        _constructAddon()
    end
end

-- Add slashcommand match entries into the global namespace for the client to pick up.
SLASH_SAMUEL1 = "/sam"
SLASH_SAMUEL2 = "/samuel"

-- And add a handler to react on the above matches.
SlashCmdList["SAMUEL"] = _slashCmdHandler

this:SetScript(SCRIPTHANDLER_ON_EVENT, _initialise)
this:RegisterEvent(_initialisation_event)
