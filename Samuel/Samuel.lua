--[[
    SAMUEL SWING TIMERS:

    Scenario's we need to take into account:

    Player enters the world with a single 2-handed weapon
    Player enters the world with a single 1-handed (and a shield)
    Player enters the world with two 1-handed weapons
    Player starts combat (regen disabled event) with sam active:
    -   Show parent frame 
    Player enables auto attack (combat starts event)
    -   Capture current time for all three timers
        -   This should start filling up the bars as they should
        ?   Test if we start autoattack out of range and both bars are filled up
            whether both MH and OH hit at the same time or if there's a delay
            for the OH and if so how long that delay is.
    Player swaps out off-hand weapon mid swing (1h/1h -> 1h/Sh)
    Player swaps in off-hand weapon mid swing (1h/Sh -> 1h/1h)
    Player swaps main-hand weapon with 2-handed (1h/1h -> 2h or 1h/Sh -> 2h)
    Player swap 2-handed with main-hand weapon (2h -> 1h/1h or 2h -> 1h/Sh)
    Player hits target with main-hand weapon
    Player hits target with off-hand weapon
    Player misses target with main-hand weapon
    Player misses target with off-hand weapon
    Player parries opponent's attack

    Addon receives update event
    -   Update current progress on main-hand weapon
    -   Check if off-hand is equipped
        -   Check if off-hand should be shown (_db)
            *   Update current progress on off-hand weapon

]]
----------------------------------------------------------------
-- "UP VALUES" FOR SPEED ---------------------------------------
----------------------------------------------------------------

local mathMin = math.min
local mathMax = math.max
local stringFind = string.find
local tableInsert = table.insert
local tableRemove = table.remove
local tostring = tostring
local type = type
local error = error
local pairs = pairs

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

local function merge(left, right)
    local t = {}

    if type(left) ~= "table" or type(right) ~= "table" then
        error("Usage: merge(left <table>, right <table>)")
    end

    -- copy left into temp table.
    for k, v in pairs(left) do
        t[k] = v
    end

    -- Add or overwrite right values.
    for k, v in pairs(right) do
        t[k] = v
    end

    return t
end

--------

local function toColourisedString(value)
    local val

    if type(value) == "string" then
        val = "|cffffffff" .. value .. "|r"
    elseif type(value) == "number" then
        val = "|cffffff33" .. tostring(value) .. "|r"
    elseif type(value) == "boolean" then
        val = "|cff9999ff" .. tostring(value) .. "|r"
    end

    return val
end

--------

local function prt(message)
    if (message and message ~= "") then
        if type(message) ~= "string" then
            message = tostring(message)
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

local SLAM_CAST_TIME = 1.5
local SLAM_TOTAL_RANKS_IMP_SLAM = 5
local SLAM_TOTAL_IMP_SLAM_CAST_REDUCTION = 0.5

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
--          is very error prone. Not sure how to do this auto-
--          matically. Yet.
--
--          Consider doing something like a property list.
--          When changing a property using the slash-cmds or
--          perhaps an in-game editor, we can change the version
--          and keep a record per version.

local IS_MH_MARKER_SHOWN = "is_mh_marker_shown"
local IS_OH_MARKER_SHOWN = "is_oh_marker_shown"
local IS_RANGED_MARKER_SHOWN = "is_ranged_marker_shown"
local MH_BAR_SHOWN = "main_hand_bar_shown"
local OH_BAR_SHOWN = "off_hand_bar_shown"
local RANGED_BAR_SHOWN = "ranged_bar_shown"
local IS_ADDON_ACTIVATED = "is_addon_activated"
local IS_ADDON_LOCKED = "is_addon_locked"
local MH_MARKER_SIZE = "main_hand_marker_size"
local OH_MARKER_SIZE = "off_hand_marker_size"
local RANGED_MARKER_SIZE = "ranged_marker_size"
local POSITION_POINT = "position_point"
local POSITION_X = "position_x"
local POSITION_Y = "position_y"
local ACTIVE_ALPHA = "active_alpha"
local INACTIVE_ALPHA = "inactive_alpha"
local DB_VERSION = "db_version"
local WIDTH = "WIDTH"
local HEIGHT = "HEIGHT"
local IS_DEBUGGING = "is_debugging"

local _defaultDB = {
    [IS_MH_MARKER_SHOWN] = false,
    [IS_OH_MARKER_SHOWN] = false,
    [IS_RANGED_MARKER_SHOWN] = false,
    [IS_ADDON_ACTIVATED] = false,
    [IS_ADDON_LOCKED] = true,
    [MH_BAR_SHOWN] = true,
    [OH_BAR_SHOWN] = true,
    [RANGED_BAR_SHOWN] = true,
    [MH_MARKER_SIZE] = 1.5,
    [OH_MARKER_SIZE] = 1,
    [RANGED_MARKER_SIZE] = 0.8,
    [POSITION_POINT] = "CENTER",
    [POSITION_X] = 0,
    [POSITION_Y] = -120,
    [ACTIVE_ALPHA] = 1,
    [INACTIVE_ALPHA] = 0.3,
    [DB_VERSION] = 8,
    [WIDTH] = 200,
    [HEIGHT] = 8,
    [IS_DEBUGGING] = false,
}

----------------------------------------------------------------
-- PRIVATE VARIABLES -------------------------------------------
----------------------------------------------------------------

local initialisationEvent = "ADDON_LOADED"

local _db

local unitName
local realmName
local profileId

local mainHandBackground
local mainHandProgressBar
local mainHandMarker
local offHandBackground
local offHandProgressBar
local offHandMarker
local rangedBackground
local rangedProgressBar
local rangedMarker

local autoRepeatSpellActive = false
local autoAttackActive = false

local updateRunTime = 0
local fps = 30
local secondsPerFrame = (1 / fps)
local lastUpdate = GetTime()
local elapsed

local proposedMHSwingTime = 1
local currentMHSwingTime = 0
local totalMHSwingTime = 1

local proposedOHSwingTime = 1
local currentOHSwingTime = 0
local totalOHSwingTime = 1

local proposedRangedTime = 1
local currentRangedTime = 0
local totalRangedTime = 1

local swingResetActions
local eventHandlers
local commandList

local lastMHSwing
local lastOHSwing
local lastShot
local mhCleanHit
local ohCleanHit
local mainHandRatio
local offHandRatio
local rangedRatio

local isDebugging = false

----------------------------------------------------------------
-- PRIVATE FUNCTIONS -------------------------------------------
----------------------------------------------------------------

local function report(label, message)
    label = tostring(label)
    message = tostring(message)

    local str = "|cff22ff22Samuel|r - |cff999999" .. label .. ":|r " .. message

    DEFAULT_CHAT_FRAME:AddMessage(str)
end

--------

local function debugLog(message)
    if _db[IS_DEBUGGING] then
        report("DEBUG", message)
    end
end

--------

local function updateMainHandMarker()
    if mainHandMarker and totalMHSwingTime then
        mainHandMarker:SetWidth((_db[WIDTH] / totalMHSwingTime) * _db[MH_MARKER_SIZE])
    end
end

--------

local function updateOffHandMarker()
    if offHandMarker and totalOHSwingTime then
        offHandMarker:SetWidth((_db[WIDTH] / totalOHSwingTime) * _db[OH_MARKER_SIZE])
    end
end

--------

local function updateRangedMarker()
    if rangedMarker and totalRangedTime then
        rangedMarker:SetWidth((_db[WIDTH] / totalRangedTime) * _db[RANGED_MARKER_SIZE])
    end
end

--------

local function resetMainHandSwingTimer()
    lastMHSwing = GetTime()
    currentMHSwingTime = 0
    totalMHSwingTime = proposedMHSwingTime
    updateMainHandMarker()
end

--------

local function resetOffHandSwingTimer()
    lastOHSwing = GetTime()
    currentOHSwingTime = 0
    totalOHSwingTime = proposedOHSwingTime
    updateOffHandMarker()
end

--------

local function resetRangedSwingTimer()
    lastShot = GetTime()
    currentRangedTime = 0
    totalRangedTime = proposedRangedTime
    updateRangedMarker()
end

--------

local function hideSwingTimers()
    this:Hide()
    mainHandRatio = 0
    offHandRatio = 0
end

--------

local function showSwingTimers()
    resetMainHandSwingTimer()
    resetOffHandSwingTimer()
    this:Show()
    lastUpdate = GetTime()
end

--------

local function resetSwingTimer()
    if not proposedOHSwingTime or not totalOHSwingTime then
        resetMainHandSwingTimer()
        return
    end

    local mhDelta = currentMHSwingTime - totalMHSwingTime
    if math.abs(mhDelta) <= 0.1 then
        debugLog("Main hand clean hit")
        mhCleanHit = true
        resetMainHandSwingTimer()
        return
    end
    debugLog("currentOHSwingTime: "..currentOHSwingTime)
    debugLog("totalOHSwingTime: "..totalOHSwingTime)
    local ohDelta = currentOHSwingTime - totalOHSwingTime
    if math.abs(ohDelta) <= 0.1 then
        debugLog("Off hand clean hit")
        ohCleanHit = true
        resetOffHandSwingTimer()
        return
    end

    if mhCleanHit and mhDelta < 0.1 then
        debugLog("Off hand dirty hit")
        resetOffHandSwingTimer()
        ohCleanHit = false
        return
    end

    if ohCleanHit and ohDelta < 0.1 then
        debugLog("Main hand dirty hit")
        resetMainHandSwingTimer()
        mhCleanHit = false
        return
    end

    if mhDelta >= ohDelta then
        resetMainHandSwingTimer()
        mhCleanHit = false
        debugLog("No clear hit detection, resetting highest delta: mainHand")
    else
        resetOffHandSwingTimer()
        ohCleanHit = false
        debugLog("No clear hit detection, resetting highest delta: offHand")
    end
end

--------

local function applyParryHaste(combatLogStr)
    if stringFind(combatLogStr, "parry") then
        totalMHSwingTime = proposedMHSwingTime * 0.4
    end
end

--------

local function resetSwingTimerOnSpellDamage(combatLogStr)
    if (not combatLogStr) or (combatLogStr == "") then
        error("Usage: resetSwingTimerOnSpellDamage(combatLogStr <string>)")
    end
    -- prt(combatLogStr);
    local _, _, action = stringFind(combatLogStr, EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE)

    if swingResetActions[action] then
        resetMainHandSwingTimer()
        mhCleanHit = true
    elseif action == "Auto" then
        resetRangedSwingTimer()
    end
end

--------

local function updateSwingTime()
    --http://vanilla-wow.wikia.com/wiki/API_UnitAttackSpeed
    debugLog("updateSwingTime")
    proposedMHSwingTime, proposedOHSwingTime = UnitAttackSpeed("player")
    if _db[OH_BAR_SHOWN] then
        resetOffHandSwingTimer()
        if not proposedOHSwingTime then
            offHandBackground:Hide()
        else
            offHandBackground:Show()
        end
    end
end

--------

local function updateRangedSwingTime()
    proposedRangedTime = UnitRangedDamage("player")
end

--------

local function activateAutoAttackSymbol()
    if autoAttackActive or autoRepeatSpellActive then
        this:SetAlpha(_db[ACTIVE_ALPHA])
    end
end

--------

local function deactivateAutoAttackSymbol()
    if not (autoAttackActive or autoRepeatSpellActive) then
        this:SetAlpha(_db[INACTIVE_ALPHA])
    end
end

--------

local function populateSwingResetActionsList()
    swingResetActions = {
        ["Heroic"] = true,
        ["Slam"] = true,
        ["Cleave"] = true,
        ["Raptor"] = true,
        ["Maul"] = true,
        ["Shoot"] = true
    }
end

--------

local function addEvent(eventName, eventHandler)
    if (not eventName) or (eventName == "") or (not eventHandler) or (type(eventHandler) ~= "function") then
        error("Usage: addEvent(eventName <string>, eventHandler <function>)")
    end

    eventHandlers[eventName] = eventHandler
    this:RegisterEvent(eventName)
end

--------

local function removeEvent(eventName)
    local eventHandler = eventHandlers[eventName]
    if eventHandler then
        -- GC should pick this up when a new assignment happens
        eventHandlers[eventName] = nil
    end

    this:UnregisterEvent(eventName)
end

--------

local function addSlashCommand(name, command, commandDescription, dbProperty)
    -- prt("Adding a slash command");
    if
        (not name) or (name == "") or (not command) or (type(command) ~= "function") or (not commandDescription) or
            (commandDescription == "")
     then
        error(
            "Usage: addSlashCommand(name <string>, command <function>, commandDescription <string> [, dbProperty <string>])"
        )
    end

    -- prt("Creating a slash command object into the command list");
    commandList[name] = {
        ["execute"] = command,
        ["description"] = commandDescription
    }

    if (dbProperty) then
        if (type(dbProperty) ~= "string" or dbProperty == "") then
            error("dbProperty must be a non-empty string.")
        end

        if (_db[dbProperty] == nil) then
            error('The internal database property: "' .. dbProperty .. '" could not be found.')
        end
        -- prt("Add the database property to the command list");
        commandList[name]["value"] = dbProperty
    end
end

--------

local function finishInitialisation()
    -- we only need this once
    this:UnregisterEvent("PLAYER_LOGIN")
    updateSwingTime()
    updateRangedSwingTime()
end

--------

local function storeLocalDatabaseToSavedVariables()
    -- #OPTION: We could have local variables for lots of DB
    --          stuff that we can load into the _db Object
    --          before we store it.
    --
    --          Should probably make a list of variables to keep
    --          track of which changed and should be updated.
    --          Something we can just loop through so load and
    --          unload never desync.

    -- Commit to local storage
    SamuelDB[profileId] = _db
end

--------

local function activateAutoAttack()
    autoAttackActive = true
    activateAutoAttackSymbol()
end

--------

local function deactivateAutoAttack()
    autoAttackActive = false
    mhCleanHit = false
    ohCleanHit = false
    deactivateAutoAttackSymbol()
end

--------

local function activateAutoRepeatSpell()
    updateRangedSwingTime()
    autoRepeatSpellActive = true
    activateAutoAttackSymbol()
end

--------

local function deactivateAutoRepeatSpell()
    updateSwingTime()
    autoRepeatSpellActive = false
    deactivateAutoAttackSymbol()
end

--------

local function eventCoordinator()
    -- given:
    -- event <string> The event name that triggered.
    -- arg1, arg2, ..., arg9 <*> Given arguments specific to the event.

    local eventHandler = eventHandlers[event]

    if eventHandler then
        eventHandler(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    end
end

--------

local function removeEvents()
    for eventName, eventHandler in pairs(eventHandlers) do
        if eventHandler then
            removeEvent(eventName)
        end
    end
end

--------

local function updateDisplay()
    elapsed = GetTime() - lastUpdate

    -- Limit updates to intended framerate
    if elapsed < secondsPerFrame then
        return
    end
    -- prt(
    --     string.format(
    --         "MH showing: %s speed: %f\nOH showing: %s speed: %f\nRA showing: %s speed: %f",
    --         _db[MH_BAR_SHOWN] and 'true' or 'false',
    --         totalMHSwingTime,
    --         _db[OH_BAR_SHOWN] and 'true' or 'false',
    --         totalOHSwingTime,
    --         _db[RANGED_BAR_SHOWN] and 'true' or 'false',
    --         totalRangedTime
    --     )
    -- )
    if totalMHSwingTime and totalMHSwingTime ~= 0 then
        currentMHSwingTime = GetTime() - lastMHSwing
        mainHandRatio = (currentMHSwingTime / totalMHSwingTime)
        mainHandProgressBar:SetWidth(mathMin(mainHandRatio, 1) * _db[WIDTH])
    end

    if totalOHSwingTime and totalOHSwingTime ~= 0 then
        currentOHSwingTime = GetTime() - lastOHSwing
        offHandRatio = (currentOHSwingTime / totalOHSwingTime)
        offHandProgressBar:SetWidth(mathMin(offHandRatio, 1) * _db[WIDTH])
    end

    if totalRangedTime and totalRangedTime ~= 0 then
        currentRangedTime = GetTime() - lastShot
        rangedRatio = mathMin((currentRangedTime / totalRangedTime), 1)
        rangedProgressBar:SetWidth(rangedRatio * _db[WIDTH])
    end

    lastUpdate = GetTime()
end

--------

local function hideMainHandMarker()
    _db[IS_MH_MARKER_SHOWN] = false

    if (mainHandMarker) then
        mainHandMarker:Hide()
    end
end

--------

local function showMainHandMarker()
    _db[IS_MH_MARKER_SHOWN] = true

    if (mainHandMarker) then
        mainHandMarker:Show()
    end
end

--------

local function hideOffHandMarker()
    _db[IS_OH_MARKER_SHOWN] = false

    if (offHandMarker) then
        offHandMarker:Hide()
    end
end

--------

local function showOffHandMarker()
    _db[IS_OH_MARKER_SHOWN] = true

    if (offHandMarker) then
        offHandMarker:Show()
    end
end

--------

local function hideRangedMarker()
    _db[IS_RANGED_MARKER_SHOWN] = false

    if (rangedMarker) then
        rangedMarker:Hide()
    end
end

--------

local function showRangedMarker()
    _db[IS_RANGED_MARKER_SHOWN] = true

    if (rangedMarker) then
        rangedMarker:Show()
    end
end

--------

local function hideOHBar()
    _db[OH_BAR_SHOWN] = false

    if (offHandBackground) then
        offHandBackground:Hide()
    end
end

--------

local function showOHBar()
    _db[OH_BAR_SHOWN] = true

    if (offHandBackground) then
        offHandBackground:Show()
    end
end

--------

local function hideRangedBar()
    _db[RANGED_BAR_SHOWN] = false

    if (rangedBackground) then
        rangedBackground:Hide()
    end
end

--------

local function showRangedBar()
    _db[RANGED_BAR_SHOWN] = true

    if (rangedBackground) then
        rangedBackground:Show()
    end
end

--------

local function resetVisibility()
    if _db[OH_BAR_SHOWN] then
        showOHBar()
    else
        hideOHBar()
    end

    if _db[RANGED_BAR_SHOWN] then
        showRangedBar()
    else
        hideRangedBar()
    end

    -- Turn on if player is in combat
    if UnitAffectingCombat("player") or (_db[IS_ADDON_LOCKED] == false) then
        showSwingTimers()
    else
        hideSwingTimers()
    end
end

--------

local function printSlashCommandList()
    report("Listing", "Slash commands")

    local str
    local description

    for name, cmdObject in pairs(commandList) do
        description = cmdObject.description

        if (not description) then
            error('Attempt to print slash command with name:"' .. name .. '" without valid description')
        end

        str = "/sam " .. name .. " " .. description

        -- If the slash command sets a value we should have
        if (cmdObject.value) then
            str = str .. " (|cff666666Currently:|r " .. toColourisedString(_db[cmdObject.value]) .. ")"
        end

        prt(str)
    end
end

--------

local function startMoving()
    this:StartMoving()
end

--------

local function stopMovingOrSizing()
    this:StopMovingOrSizing()
    _db[POSITION_POINT], _, _, _db[POSITION_X], _db[POSITION_Y] = this:GetPoint()
end

--------

local function unlockAddon()
    -- Make the left mouse button trigger drag events
    this:RegisterForDrag("LeftButton")
    -- Set the start and stop moving events on triggered events
    this:SetScript(SCRIPTHANDLER_ON_DRAG_START, startMoving)
    this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, stopMovingOrSizing)
    -- Make the frame react to the mouse
    this:EnableMouse(true)
    -- Make the frame movable
    this:SetMovable(true)
    -- Show ourselves so we can be moved
    showSwingTimers()

    _db[IS_ADDON_LOCKED] = false
end

--------

local function lockAddon()
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
    hideSwingTimers()

    _db[IS_ADDON_LOCKED] = true
end

--------

local function populateRequiredEvents()
    addEvent("CHAT_MSG_COMBAT_SELF_HITS", resetSwingTimer)
    addEvent("CHAT_MSG_COMBAT_SELF_MISSES", resetSwingTimer)
    addEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES", applyParryHaste)
    addEvent("CHAT_MSG_SPELL_SELF_DAMAGE", resetSwingTimerOnSpellDamage)

    addEvent("UNIT_INVENTORY_CHANGED", updateSwingTime)
    addEvent("UNIT_ATTACK_SPEED", updateSwingTime)

    addEvent("PLAYER_REGEN_DISABLED", showSwingTimers)
    addEvent("PLAYER_REGEN_ENABLED", hideSwingTimers)

    addEvent("PLAYER_ENTER_COMBAT", activateAutoAttack)
    addEvent("PLAYER_LEAVE_COMBAT", deactivateAutoAttack)

    addEvent("START_AUTOREPEAT_SPELL", activateAutoRepeatSpell)
    addEvent("STOP_AUTOREPEAT_SPELL", deactivateAutoRepeatSpell)

    addEvent("PLAYER_LOGIN", finishInitialisation)
end

--------

local function createMainHandProgressBar(parent)
    -- Don't bother recreating existing progress bar
    if mainHandProgressBar then
        return
    end

    mainHandBackground = CreateFrame("FRAME", nil, parent)
    mainHandBackground:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
    mainHandBackground:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    mainHandBackground:SetBackdropColor(0.1, 0.1, 0.1, 1)
    mainHandBackground:SetFrameLevel(10)
    mainHandBackground:SetWidth(_db[WIDTH])
    mainHandBackground:SetHeight(_db[HEIGHT])

    mainHandProgressBar = CreateFrame("FRAME", nil, mainHandBackground)
    mainHandProgressBar:SetPoint("TOPLEFT", mainHandBackground, "TOPLEFT", 0, 0)
    mainHandProgressBar:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    mainHandProgressBar:SetBackdropColor(0.78, 0.61, 0.43, 1)
    mainHandProgressBar:SetFrameLevel(11)
    mainHandProgressBar:SetHeight(_db[HEIGHT])
    mainHandProgressBar:SetWidth(1)

    -- mainHandBackground:Hide()
end

--------

local function createOffHandProgressBar(parent)
    -- Don't bother recreating existing progress bar
    if offHandProgressBar then
        return
    end

    offHandBackground = CreateFrame("FRAME", nil, parent)
    offHandBackground:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -(_db[HEIGHT] + 2))
    offHandBackground:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    offHandBackground:SetBackdropColor(0.1, 0.1, 0.1, 1)
    offHandBackground:SetFrameLevel(10)
    offHandBackground:SetWidth(_db[WIDTH])
    offHandBackground:SetHeight(_db[HEIGHT])

    offHandProgressBar = CreateFrame("FRAME", nil, offHandBackground)
    offHandProgressBar:SetPoint("TOPLEFT", offHandBackground, "TOPLEFT", 0, 0)
    offHandProgressBar:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    offHandProgressBar:SetBackdropColor(1.00, 0.96, 0.41, 1)
    offHandProgressBar:SetFrameLevel(11)
    offHandProgressBar:SetHeight(_db[HEIGHT])
    offHandProgressBar:SetWidth(1)

    -- offHandBackground:Hide()
end

--------

local function createRangedProgressBar(parent)
    -- Don't bother recreating existing progress bar
    if rangedProgressBar then
        return
    end

    rangedBackground = CreateFrame("FRAME", nil, parent)
    rangedBackground:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -(_db[HEIGHT] * 2 + 3))
    rangedBackground:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    rangedBackground:SetBackdropColor(0.1, 0.1, 0.1, 1)
    rangedBackground:SetFrameLevel(10)
    rangedBackground:SetWidth(_db[WIDTH])
    rangedBackground:SetHeight(_db[HEIGHT])

    rangedProgressBar = CreateFrame("FRAME", nil, rangedBackground)
    rangedProgressBar:SetPoint("TOPLEFT", rangedBackground, "TOPLEFT", 0, 0)
    rangedProgressBar:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    rangedProgressBar:SetBackdropColor(0.67, 0.83, 0.45, 1)
    rangedProgressBar:SetFrameLevel(11)
    rangedProgressBar:SetHeight(_db[HEIGHT])
    rangedProgressBar:SetWidth(1)

    -- rangedBackground:Hide()
end

--------

local function createMainHanderMarker()
    if mainHandMarker or not mainHandBackground then
        return
    end

    mainHandMarker = CreateFrame("FRAME", nil, mainHandBackground)

    mainHandMarker:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    mainHandMarker:SetBackdropColor(1, 0, 0, 0.7)
    mainHandMarker:SetPoint("TOPRIGHT", 0, 0)
    mainHandMarker:SetHeight(_db[HEIGHT])
    mainHandMarker:SetFrameLevel(12)

    if _db[IS_MH_MARKER_SHOWN] then
        showMainHandMarker()
    else
        hideMainHandMarker()
    end
end

--------

local function createOffHandMarker()
    if offHandMarker or not offHandBackground then
        return
    end

    offHandMarker = CreateFrame("FRAME", nil, offHandBackground)

    offHandMarker:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    offHandMarker:SetBackdropColor(1, 0, 0, 0.7)
    offHandMarker:SetPoint("TOPRIGHT", 0, 0)
    offHandMarker:SetHeight(_db[HEIGHT])
    offHandMarker:SetFrameLevel(12)

    if _db[IS_OH_MARKER_SHOWN] then
        showOffHandMarker()
    else
        hideOffHandMarker()
    end
end

--------

local function createRangedMarker()
    if rangedMarker or not rangedBackground then
        return
    end

    rangedMarker = CreateFrame("FRAME", nil, rangedBackground)

    rangedMarker:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    rangedMarker:SetBackdropColor(1, 0, 0, 0.7)
    rangedMarker:SetPoint("TOPRIGHT", 0, 0)
    rangedMarker:SetHeight(_db[HEIGHT])
    rangedMarker:SetFrameLevel(12)

    if _db[IS_MH_MARKER_SHOWN] then
        showRangedMarker()
    else
        hideRangedMarker()
    end
end

--------

local function constructAddon()
    this:SetWidth(_db[WIDTH] + 2)
    this:SetHeight(_db[HEIGHT] * 3 + 4)
    this:SetPoint(_db[POSITION_POINT], _db[POSITION_X], _db[POSITION_Y])

    if (not _db[IS_ADDON_LOCKED]) then
        unlockAddon()
    end

    -- CREATE CHILDREN
    createMainHandProgressBar(this)
    createOffHandProgressBar(this)
    createRangedProgressBar(this)

    createMainHanderMarker()
    createOffHandMarker()
    createRangedMarker()

    updateSwingTime()
    updateRangedSwingTime()
    resetMainHandSwingTimer()
    resetOffHandSwingTimer()
    resetRangedSwingTimer()
    resetVisibility()

    populateSwingResetActionsList()
    populateRequiredEvents()

    this:SetScript(SCRIPTHANDLER_ON_UPDATE, updateDisplay)
end

--------

local function destructAddon()
    -- Stop frame updates
    this:SetScript(SCRIPTHANDLER_ON_UPDATE, nil)

    -- Remove all registered events
    removeEvents()
    hideSwingTimers()
    deactivateAutoAttack()
    deactivateAutoRepeatSpell()
end

--------

local function activateAddon()
    if _db[IS_ADDON_ACTIVATED] then
        return
    end

    constructAddon()
    _db[IS_ADDON_ACTIVATED] = true
end

--------

local function deactivateAddon()
    if not _db[IS_ADDON_ACTIVATED] then
        return
    end

    destructAddon()
    _db[IS_ADDON_ACTIVATED] = false
    -- This is here and not in the destructor because
    -- loadSavedVariables is not in the constructor either.
    storeLocalDatabaseToSavedVariables()
end

--------

local function slashCmdHandler(message, chatFrame)
    local _, _, commandName, params = stringFind(message, "^(%S+) *(.*)")

    -- Stringify it
    commandName = tostring(commandName)

    -- Pull the given command from our list.
    local command = commandList[commandName]
    if (command) then
        -- Run the command we found.
        if (type(command.execute) ~= "function") then
            error("Attempt to execute slash command without execution function.")
        end

        command.execute(params)
    else
        -- prt("Print our available command list.");
        printSlashCommandList()
    end
end

--------

local function loadProfileID()
    unitName = UnitName("player")
    realmName = GetRealmName()
    profileId = unitName .. "-" .. realmName
end

--------

local function loadSavedVariables()
    -- First time install
    if not SamuelDB then
        SamuelDB = {}
    end

    -- this should produce an error if profileId is not yet set, as is intended.
    _db = SamuelDB[profileId]

    -- This means we have a new char.
    if not _db then
        _db = _defaultDB
    end

    -- In this case we have a player with an older version DB.
    if (not _db[DB_VERSION]) or (_db[DB_VERSION] < _defaultDB[DB_VERSION]) then
        -- For now we just blindly attempt to merge.
        _db = merge(_defaultDB, _db)
    end
end

----------------------------------------------------------------
-- PUBLIC METHODS ----------------------------------------------
----------------------------------------------------------------

local function setMainHandMarkerSize(timeInSeconds)
    -- Stop arsin about!
    if timeInSeconds == _db[MH_MARKER_SIZE] then
        return
    end

    timeInSeconds = tonumber(timeInSeconds)
    if not timeInSeconds then
        report("setMainHandMarkerSize expects", "a number in seconds")
        return
    end

    if timeInSeconds < 0 then
        report("setMainHandMarkerSize expects", "time in seconds to be 0 or more")
        return
    end

    _db[MH_MARKER_SIZE] = timeInSeconds
    report("Saved main-hand marker size to", _db[MH_MARKER_SIZE])
    updateMainHandMarker()
end

--------

local function setOffHandMarkerSize(timeInSeconds)
    -- Stop arsin about!
    if timeInSeconds == _db[OH_MARKER_SIZE] then
        return
    end

    timeInSeconds = tonumber(timeInSeconds)
    if not timeInSeconds then
        report("setOffHandMarkerSize expects", "a number in seconds")
        return
    end

    if timeInSeconds < 0 then
        report("setOffHandMarkerSize expects", "time in seconds to be 0 or more")
        return
    end

    _db[OH_MARKER_SIZE] = timeInSeconds
    report("Saved off-hand marker size to", _db[OH_MARKER_SIZE])
    updateOffHandMarker()
end

--------

local function setRangedMarkerSize(timeInSeconds)
    -- Stop arsin about!
    if timeInSeconds == _db[RANGED_MARKER_SIZE] then
        return
    end

    timeInSeconds = tonumber(timeInSeconds)
    if not timeInSeconds then
        report("setRangedMarkerSize expects", "a number in seconds")
        return
    end

    if timeInSeconds < 0 then
        report("setRangedMarkerSize expects", "time in seconds to be 0 or more")
        return
    end

    _db[RANGED_MARKER_SIZE] = timeInSeconds
    report("Saved ranged marker size to", _db[RANGED_MARKER_SIZE])
    updateMainHandMarker()
end

--------

local function toggleMainHandMarkerVisibility()
    if _db[IS_MH_MARKER_SHOWN] then
        hideMainHandMarker()
    else
        showMainHandMarker()
    end

    report("Main-hand marker is", (_db[IS_MH_MARKER_SHOWN] and "Showing" or "Hidden"))
end

--------

local function toggleOffHandMarkerVisibility()
    if _db[IS_OH_MARKER_SHOWN] then
        hideOffHandMarker()
    else
        showOffHandMarker()
    end

    report("Off-hand marker is", (_db[IS_OH_MARKER_SHOWN] and "Showing" or "Hidden"))
end

--------

local function toggleRangedMarkerVisibility()
    if _db[IS_RANGED_MARKER_SHOWN] then
        hideRangedMarker()
    else
        showRangedMarker()
    end

    report("Ranged marker is", (_db[IS_RANGED_MARKER_SHOWN] and "Showing" or "Hidden"))
end

--------

local function toggleLockToScreen()
    -- Inversed logic to lock the addon if _db[IS_ADDON_LOCKED] returns 'nil' for some reason.
    if not _db[IS_ADDON_LOCKED] then
        lockAddon()
    else
        unlockAddon()
    end

    report("Swing timer bar", (_db[IS_ADDON_LOCKED] and "Locked" or "Unlocked"))
end

--------

local function toggleOffHandBar()
    if _db[OH_BAR_SHOWN] then
        hideOHBar()
    else
        showOHBar()
    end

    report("Off-hand bar is", (_db[OH_BAR_SHOWN] and "Showing" or "Hidden"))
end

--------

local function toggleRangedBar()
    if _db[RANGED_BAR_SHOWN] then
        hideRangedBar()
    else
        showRangedBar()
    end

    report("Ranged bar is", (_db[RANGED_BAR_SHOWN] and "Showing" or "Hidden"))
end

--------

local function toggleAddonActivity()
    if not _db[IS_ADDON_ACTIVATED] then
        activateAddon()
    else
        deactivateAddon()
    end

    report("is now", (_db[IS_ADDON_ACTIVATED] and "Activated" or "Deactivated"))
end

--------

local function toggleDebugging()
    if not _db[IS_DEBUGGING] then
        _db[IS_DEBUGGING] = true
    else
        _db[IS_DEBUGGING] = false
    end

    report("Debugging", (_db[IS_DEBUGGING] and "Yes" or "No"))
end

--------

local function setBarWidth(value)
    _db[WIDTH] = value

    report("bar width set to", value)
end

--------

local function setBarHeight(value)
    _db[HEIGHT] = value

    report("bar height set to", value)
end

--------

local function populateSlashCommandList()
    -- For now we just reset this thing.
    commandList = {}

    addSlashCommand(
        "toggleOffHandBar",
        toggleOffHandBar,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the off-hand bar is showing.|r",
        OH_BAR_SHOWN
    )

    addSlashCommand(
        "toggleRangedBar",
        toggleRangedBar,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the ranged bar is showing.|r",
        RANGED_BAR_SHOWN
    )

    addSlashCommand(
        "showMainHandMarker",
        toggleMainHandMarkerVisibility,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the red main-hand marker is showing.|r",
        IS_MH_MARKER_SHOWN
    )

    addSlashCommand(
        "setMainHandMarkerSize",
        setMainHandMarkerSize,
        "[|cffffff330+|r] |cff999999\n\t-- Set the amount of seconds of your swing time the main-hand marker should cover.|r",
        MH_MARKER_SIZE
    )

    addSlashCommand(
        "showOffHandMarker",
        toggleOffHandMarkerVisibility,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the red off-hand marker is showing.|r",
        IS_MH_MARKER_SHOWN
    )

    addSlashCommand(
        "setOffHandMarkerSize",
        setOffHandMarkerSize,
        "[|cffffff330+|r] |cff999999\n\t-- Set the amount of seconds of your swing time the off-hand marker should cover.|r",
        OH_MARKER_SIZE
    )

    addSlashCommand(
        "showRangedMarker",
        toggleRangedMarkerVisibility,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the red ranged marker is showing.|r",
        IS_RANGED_MARKER_SHOWN
    )

    addSlashCommand(
        "setRangedMarkerSize",
        setRangedMarkerSize,
        "[|cffffff330+|r] |cff999999\n\t-- Set the amount of seconds of your ranged time the marker should cover.|r",
        RANGED_MARKER_SIZE
    )

    addSlashCommand(
        "lock",
        toggleLockToScreen,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the bar is locked to the screen.|r",
        IS_ADDON_LOCKED
    )

    addSlashCommand(
        "activate",
        toggleAddonActivity,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether the AddOn itself is active.|r",
        IS_ADDON_ACTIVATED
    )

    addSlashCommand("setBarWidth", setBarWidth, "[|cffffff330+|r] |cff999999\n\t-- Set the width of the bar.|r", WIDTH)

    addSlashCommand(
        "setBarHeight",
        setBarHeight,
        "[|cffffff330+|r] |cff999999\n\t-- Set the height of the bar.|r",
        HEIGHT
    )

    addSlashCommand(
        "debug",
        toggleDebugging,
        "<|cff9999fftoggle|r> |cff999999\n\t-- Toggle whether debug messages are shown.|r",
        IS_DEBUGGING
    )
end

--------

local function initialise()
    loadProfileID()
    loadSavedVariables()

    this:UnregisterEvent(initialisationEvent)

    eventHandlers = {}

    populateSlashCommandList()
    this:SetScript(SCRIPTHANDLER_ON_EVENT, eventCoordinator)

    addEvent("PLAYER_LOGOUT", storeLocalDatabaseToSavedVariables)

    if _db[IS_ADDON_ACTIVATED] then
        constructAddon()
    end
end

-- Add slashcommand match entries into the global namespace for the client to pick up.
SLASH_SAMUEL1 = "/sam"
SLASH_SAMUEL2 = "/samuel"

-- And add a handler to react on the above matches.
SlashCmdList["SAMUEL"] = slashCmdHandler

this:SetScript(SCRIPTHANDLER_ON_EVENT, initialise)
this:RegisterEvent(initialisationEvent)
