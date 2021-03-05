--[[ GenericTrigger.lua
This file contains the generic trigger system. That is every trigger except the aura triggers
It registers the GenericTrigger table for the trigger types "status", "event" and "custom".
The GenericTrigger has the following API:
Modernize(data)
  Modernizes all generic triggers in data

LoadDisplay(id)
  Loads all triggers of display id

UnloadDisplay(id)
  Unloads all triggers of the display id

Add(data)
  Adds a display, creating all internal data structures for all triggers

CanHaveTooltip(data)
  Returns the type of tooltip to show for the trigger

Delete(id)
  Deletes all triggers for display id

ScanAll
  Resets the trigger state for all triggers

UnloadAll
  Unloads all triggers

Rename(oldid, newid)
  Updates all trigger information from oldid to newid

GetNameAndIcon(data)
    Returns the name and icon to show in the options

GetTriggerConditions(data, triggernum)
  Returns potential conditions that this trigger provides.

#####################################################
# Helper functions mainly for the WeakAuras Options #
#####################################################
CanGroupShowWithZero(data)
  Returns whether the first trigger could be shown without any affected group members.
  If that is the case no automatic icon can be determined. Only used by the Options dialog.
  (If I understood the code correctly)

CanHaveDuration(data)
  Returns whether the trigger can have a duration

CanHaveAuto(data)
  Returns whether the icon can be automatically selected

CanHaveClones(data)
  Returns whether the trigger can have clones

]]
-- Lua APIs
local tinsert, tconcat, wipe = table.insert, table.concat, wipe
local tostring, select, pairs, type = tostring, select, pairs, type
local error, setmetatable = error, setmetatable

WeakAurasAceEvents =
    setmetatable(
    {},
    {
        __tostring = function()
            return "WeakAuras"
        end
    }
)
LibStub("AceEvent-3.0"):Embed(WeakAurasAceEvents)
local aceEvents = WeakAurasAceEvents

local WeakAuras = WeakAuras
local L = WeakAuras.L
local GenericTrigger = {}

local event_prototypes = WeakAuras.event_prototypes

local timer = WeakAuras.timer
local debug = WeakAuras.debug

local events = WeakAuras.events
local loaded_events = WeakAuras.loaded_events
local timers = WeakAuras.timers
local specificBosses = WeakAuras.specificBosses

-- local function
local HandleEvent

function WeakAuras.split(input)
    input = input or ""
    local ret = {}
    local split, element = true
    split = input:find("[,%s]")
    while (split) do
        element, input = input:sub(1, split - 1), input:sub(split + 1)
        if (element ~= "") then
            tinsert(ret, element)
        end
        split = input:find("[,%s]")
    end
    if (input ~= "") then
        tinsert(ret, input)
    end
    return ret
end

function WeakAuras.EndEvent(id, triggernum, force)
    local allStates = WeakAuras.GetTriggerStateForTrigger(id, triggernum)
    allStates[""] = allStates[""] or {}
    local state = allStates[""]

    if (state.show ~= false and state.show ~= nil) then
        state.show = false
        state.changed = true
    end
    return state.changed
end

function WeakAuras.ActivateEvent(id, triggernum, data)
    local changed = false
    local allStates = WeakAuras.GetTriggerStateForTrigger(id, triggernum)
    allStates[""] = allStates[""] or {}
    local state = allStates[""]
    if (state.show ~= true) then
        state.show = true
        changed = true
    end

    if (data.duration) then
        local expirationTime = GetTime() + data.duration
        if (state.expirationTime ~= expirationTime) then
            state.resort = state.expirationTime ~= expirationTime
            state.expirationTime = expirationTime
            changed = true
        end
        if (state.duration ~= data.duration) then
            state.duration = data.duration
            changed = true
        end
        if (state.progressType ~= "timed") then
            state.progressType = "timed"
            changed = true
        end
        if (state.value or state.total or state.inverse or not state.autoHide) then
            changed = true
        end
        state.value = nil
        state.total = nil
        state.inverse = nil
        state.autoHide = true
    elseif (data.durationFunc) then
        local arg1, arg2, arg3, inverse = data.durationFunc(data.trigger)
        arg1 = type(arg1) == "number" and arg1 or 0
        arg2 = type(arg2) == "number" and arg2 or 0

        if (type(arg3) == "string") then
            if (state.durationFunc ~= data.durationFunc) then
                state.durationFunc = data.durationFunc
                changed = true
            end
        elseif (type(arg3) == "function") then
            if (state.durationFunc ~= arg3) then
                state.durationFunc = arg3
                changed = true
            end
        else
            if (state.durationFunc ~= nil) then
                state.durationFunc = nil
                changed = true
            end
        end

        if (arg3) then
            if (state.progressType ~= "static") then
                state.progressType = "static"
                changed = true
            end
            if (state.duration) then
                state.duration = nil
                changed = true
            end
            if (state.expirationTime) then
                state.resort = state.expirationTime ~= nil
                state.expirationTime = nil
                changed = true
            end

            if (state.autoHide or state.inverse) then
                changed = trueM
            end
            state.autoHide = nil
            state.inverse = nil
            if (state.value ~= arg1) then
                state.value = arg1
                changed = true
            end
            if (state.total ~= arg2) then
                state.total = arg2
                changed = true
            end
        else
            if (state.progressType ~= "timed") then
                state.progressType = "timed"
                changed = true
            end
            if (state.duration ~= arg1) then
                state.duration = arg1
            end
            if (state.expirationTime ~= arg2) then
                state.resort = state.expirationTime ~= arg2
                state.expirationTime = arg2
                changed = true
            end
            if (state.autoHide ~= (arg1 > 0.01)) then
                state.autoHide = arg1 > 0.01
            end
            if (state.value or state.total) then
                changed = true
            end
            state.value = nil
            state.total = nil
            if (state.inverse ~= inverse) then
                state.inverse = inverse
                changed = true
            end
        end
    else
        if (state.progressType ~= "timed") then
            state.progressType = "timed"
            changed = true
        end
        if (state.duration ~= 0) then
            state.duration = 0
            changed = true
        end
        if (state.expirationTime ~= math.huge) then
            state.resort = state.expirationTime ~= math.huge
            state.expirationTime = math.huge
            changed = true
        end
    end

    local name = data.nameFunc and data.nameFunc(data.trigger) or nil
    local icon = data.iconFunc and data.iconFunc(data.trigger) or nil
    local texture = data.textureFunc and data.textureFunc(data.trigger) or nil
    local stacks = data.stacksFunc and data.stacksFunc(data.trigger) or nil
    if (state.name ~= name) then
        state.name = name
        changed = true
    end
    if (state.icon ~= icon) then
        state.icon = icon
        changed = true
    end
    if (state.texture ~= texture) then
        state.texture = texture
        changed = true
    end
    if (state.stacks ~= stacks) then
        state.stacks = stacks
        changed = true
    end

    state.changed = changed
    return changed
end

function WeakAuras.ScanEvents(event, arg1, arg2, ...)
    local event_list = loaded_events[event]
    if (event == "COMBAT_LOG_EVENT_UNFILTERED") then
        event_list = event_list and event_list[arg2]
    end
    if (event_list) then
        -- This reverts the COMBAT_LOG_EVENT_UNFILTERED_CUSTOM workaround so that custom triggers that check the event argument will work as expected
        if (event == "COMBAT_LOG_EVENT_UNFILTERED_CUSTOM") then
            event = "COMBAT_LOG_EVENT_UNFILTERED"
        end
        for id, triggers in pairs(event_list) do
            WeakAuras.ActivateAuraEnvironment(id)
            local updateTriggerState = false
            for triggernum, data in pairs(triggers) do
                if (data.triggerFunc) then
                    if (data.triggerFunc(event, arg1, arg2, ...)) then
                        if (WeakAuras.ActivateEvent(id, triggernum, data)) then
                            updateTriggerState = true
                        end
                    else
                        if (data.untriggerFunc and data.untriggerFunc(event, arg1, arg2, ...)) then
                            if (WeakAuras.EndEvent(id, triggernum)) then
                                updateTriggerState = true
                            end
                        end
                    end
                end
            end
            if (updateTriggerState) then
                WeakAuras.UpdatedTriggerState(id)
            end
            WeakAuras.ActivateAuraEnvironment(nil)
        end
    end
end

function GenericTrigger.ScanAll()
    for event, v in pairs(WeakAuras.forceable_events) do
        if (type(v) == "table") then
            for index, arg1 in pairs(v) do
                WeakAuras.ScanEvents(event, arg1)
            end
        elseif (event == "SPELL_COOLDOWN_FORCE") then
            WeakAuras.SpellCooldownForce()
        elseif (event == "ITEM_COOLDOWN_FORCE") then
            WeakAuras.ItemCooldownForce()
        elseif (event == "RUNE_COOLDOWN_FORCE") then
            WeakAuras.RuneCooldownForce()
        else
            WeakAuras.ScanEvents(event)
        end
    end
end

local function HandleEvent(frame, event, arg1, arg2, ...)
    WeakAuras.debug("HandleEvent - " .. event)
    if not (WeakAuras.IsPaused()) then
        if (event == "COMBAT_LOG_EVENT_UNFILTERED") then
            if (loaded_events[event] and loaded_events[event][arg2]) then
                WeakAuras.ScanEvents(event, arg1, arg2, ...)
            end
            -- This is triggers the scanning of "hacked" COMBAT_LOG_EVENT_UNFILTERED events that were renamed in order to circumvent
            -- the "proper" COMBAT_LOG_EVENT_UNFILTERED checks
            if (loaded_events["COMBAT_LOG_EVENT_UNFILTERED_CUSTOM"]) then
                WeakAuras.ScanEvents("COMBAT_LOG_EVENT_UNFILTERED_CUSTOM", arg1, arg2, ...)
            end
        else
            if (loaded_events[event]) then
                WeakAuras.ScanEvents(event, arg1, arg2, ...)
            end
        end
    end
    if (event == "PLAYER_ENTERING_WORLD") then
        timer:ScheduleTimer(
            function()
                HandleEvent(frame, "WA_DELAYED_PLAYER_ENTERING_WORLD")
                WeakAuras.CheckCooldownReady()
            end,
            0.5
        ) -- Data not available
    end
end

local frame = CreateFrame("FRAME")
WeakAuras.frames["WeakAuras Generic Trigger Frame"] = frame
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", HandleEvent)

function GenericTrigger.UnloadAll()
    wipe(loaded_events)
end

function GenericTrigger.UnloadDisplay(id)
    for eventname, events in pairs(loaded_events) do
        if (eventname == "COMBAT_LOG_EVENT_UNFILTERED") then
            for subeventname, subevents in pairs(events) do
                subevents[id] = nil
            end
        else
            events[id] = nil
        end
    end
end

function GenericTrigger.Add(data, region)
    local id = data.id
    events[id] = nil

    local register_for_frame_updates = false
    for triggernum = 0, (data.numTriggers or 9) do
        local trigger, untrigger
        if (triggernum == 0) then
            trigger = data.trigger
            data.untrigger = data.untrigger or {}
            untrigger = data.untrigger
        elseif (data.additional_triggers and data.additional_triggers[triggernum]) then
            trigger = data.additional_triggers[triggernum].trigger
            data.additional_triggers[triggernum].untrigger = data.additional_triggers[triggernum].untrigger or {}
            untrigger = data.additional_triggers[triggernum].untrigger
        end
        local triggerType
        if (trigger and type(trigger) == "table") then
            triggerType = trigger.type
            if (triggerType == "status" or triggerType == "event" or triggerType == "custom") then
                local triggerFuncStr, triggerFunc, untriggerFuncStr, untriggerFunc
                local trigger_events = {}
                local durationFunc, nameFunc, iconFunc, textureFunc, stacksFunc
                if (triggerType == "status" or triggerType == "event") then
                    if not (trigger.event) then
                        error('Improper arguments to WeakAuras.Add - trigger type is "event" but event is not defined')
                    elseif not (event_prototypes[trigger.event]) then
                        if (event_prototypes["Health"]) then
                            trigger.event = "Health"
                        else
                            error(
                                'Improper arguments to WeakAuras.Add - no event prototype can be found for event type "' ..
                                    trigger.event .. '" and default prototype reset failed.'
                            )
                        end
                    elseif (trigger.event == "Combat Log" and not (trigger.subeventPrefix .. trigger.subeventSuffix)) then
                        error(
                            'Improper arguments to WeakAuras.Add - event type is "Combat Log" but subevent is not defined'
                        )
                    else
                        triggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], trigger)
                        WeakAuras.debug(id .. " - " .. triggernum .. " - Trigger", 1)
                        WeakAuras.debug(triggerFuncStr)
                        triggerFunc = WeakAuras.LoadFunction(triggerFuncStr)

                        durationFunc = event_prototypes[trigger.event].durationFunc
                        nameFunc = event_prototypes[trigger.event].nameFunc
                        iconFunc = event_prototypes[trigger.event].iconFunc
                        textureFunc = event_prototypes[trigger.event].textureFunc
                        stacksFunc = event_prototypes[trigger.event].stacksFunc

                        trigger.unevent = trigger.unevent or "auto"

                        if (trigger.unevent == "custom") then
                            untriggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], untrigger)
                        elseif (trigger.unevent == "auto") then
                            untriggerFuncStr =
                                WeakAuras.ConstructFunction(event_prototypes[trigger.event], trigger, true)
                        end
                        if (untriggerFuncStr) then
                            WeakAuras.debug(id .. " - " .. triggernum .. " - Untrigger", 1)
                            WeakAuras.debug(untriggerFuncStr)
                            untriggerFunc = WeakAuras.LoadFunction(untriggerFuncStr)
                        end

                        local prototype = event_prototypes[trigger.event]
                        if (prototype) then
                            trigger_events = prototype.events
                            for index, event in ipairs(trigger_events) do
                                WeakAuras.debug(id .. " - " .. " Event: " .. event)
                                frame:RegisterEvent(event)
                                -- WeakAuras.cbh.RegisterCallback(WeakAuras.cbh.events, event)
                                aceEvents:RegisterMessage(event, HandleEvent, frame)
                                if
                                    (type(prototype.force_events) == "boolean" or
                                        type(prototype.force_events) == "table")
                                 then
                                    WeakAuras.forceable_events[event] = prototype.force_events
                                end
                            end
                            if (type(prototype.force_events) == "string") then
                                WeakAuras.forceable_events[prototype.force_events] = true
                            end
                        end
                    end
                else
                    triggerFunc = WeakAuras.LoadFunction("return " .. (trigger.custom or ""))
                    if (trigger.custom_type == "status" or trigger.custom_hide == "custom") then
                        untriggerFunc = WeakAuras.LoadFunction("return " .. (untrigger.custom or ""))
                    end

                    if (trigger.customDuration and trigger.customDuration ~= "") then
                        durationFunc = WeakAuras.LoadFunction("return " .. trigger.customDuration)
                    end
                    if (trigger.customName and trigger.customName ~= "") then
                        nameFunc = WeakAuras.LoadFunction("return " .. trigger.customName)
                    end
                    if (trigger.customIcon and trigger.customIcon ~= "") then
                        iconFunc = WeakAuras.LoadFunction("return " .. trigger.customIcon)
                    end
                    if (trigger.customTexture and trigger.customTexture ~= "") then
                        textureFunc = WeakAuras.LoadFunction("return " .. trigger.customTexture)
                    end
                    if (trigger.customStacks and trigger.customStacks ~= "") then
                        stacksFunc = WeakAuras.LoadFunction("return " .. trigger.customStacks)
                    end

                    if (trigger.custom_type == "status" and trigger.check == "update") then
                        register_for_frame_updates = true
                        trigger_events = {"FRAME_UPDATE"}
                    else
                        trigger_events = WeakAuras.split(trigger.events)
                        for index, event in pairs(trigger_events) do
                            if (event == "COMBAT_LOG_EVENT_UNFILTERED") then
                                -- This is a dirty, lazy, dirty hack. "Proper" COMBAT_LOG_EVENT_UNFILTERED events are indexed by their sub-event types (e.g. SPELL_PERIODIC_DAMAGE),
                                -- but custom COMBAT_LOG_EVENT_UNFILTERED events are not guaranteed to have sub-event types. Thus, if the user specifies that they want to use
                                -- COMBAT_LOG_EVENT_UNFILTERED, this hack renames the event to COMBAT_LOG_EVENT_UNFILTERED_CUSTOM to circumvent the COMBAT_LOG_EVENT_UNFILTERED checks
                                -- that are already in place. Replacing all those checks would be a pain in the ass.
                                trigger_events[index] = "COMBAT_LOG_EVENT_UNFILTERED_CUSTOM"
                                frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                            else
                                frame:RegisterEvent(event)
                                -- WeakAuras.cbh.RegisterCallback(WeakAuras.cbh.events, event)
                                aceEvents:RegisterMessage(event, HandleEvent, frame)
                            end
                            if (trigger.custom_type == "status") then
                                WeakAuras.forceable_events[event] = true
                            end
                        end
                    end
                end

                local duration = nil
                if (triggerType == "custom" and trigger.custom_type == "event" and trigger.custom_hide == "timed") then
                    duration = tonumber(trigger.duration)
                end

                events[id] = events[id] or {}
                events[id][triggernum] = {
                    trigger = trigger,
                    triggerFunc = triggerFunc,
                    untriggerFunc = untriggerFunc,
                    bar = data.bar,
                    timer = data.timer,
                    cooldown = data.cooldown,
                    icon = data.icon,
                    event = trigger.event,
                    events = trigger_events,
                    inverse = trigger.use_inverse,
                    subevent = trigger.event == "Combat Log" and trigger.subeventPrefix and trigger.subeventSuffix and
                        (trigger.subeventPrefix .. trigger.subeventSuffix),
                    unevent = trigger.unevent,
                    durationFunc = durationFunc,
                    nameFunc = nameFunc,
                    iconFunc = iconFunc,
                    textureFunc = textureFunc,
                    stacksFunc = stacksFunc,
                    expiredHideFunc = triggerType ~= "custom" and event_prototypes[trigger.event].expiredHideFunc,
                    duration = duration
                }

                if
                    (((triggerType == "status" or triggerType == "event") and trigger.unevent == "timed") or
                        (triggerType == "custom" and trigger.custom_type == "event" and trigger.custom_hide == "timed"))
                 then
                    events[id][triggernum].duration = tonumber(trigger.duration)
                end
            end
        end
    end

    if (register_for_frame_updates) then
        WeakAuras.RegisterEveryFrameUpdate(id)
    else
        WeakAuras.UnregisterEveryFrameUpdate(id)
    end
end

do
    local update_clients = {}
    local update_clients_num = 0
    local update_frame
    WeakAuras.frames["Custom Trigger Every Frame Updater"] = update_frame
    local updating = false

    function WeakAuras.RegisterEveryFrameUpdate(id)
        if not (update_clients[id]) then
            update_clients[id] = true
            update_clients_num = update_clients_num + 1
        end
        if not (update_frame) then
            update_frame = CreateFrame("FRAME")
        end
        if not (updating) then
            update_frame:SetScript(
                "OnUpdate",
                function()
                    if not (WeakAuras.IsPaused()) then
                        WeakAuras.ScanEvents("FRAME_UPDATE")
                    end
                end
            )
            updating = true
        end
    end

    function WeakAuras.EveryFrameUpdateRename(oldid, newid)
        update_clients[newid] = update_clients[oldid]
        update_clients[oldid] = nil
    end

    function WeakAuras.UnregisterEveryFrameUpdate(id)
        if (update_clients[id]) then
            update_clients[id] = nil
            update_clients_num = update_clients_num - 1
        end
        if (update_clients_num == 0 and update_frame and updating) then
            update_frame:SetScript("OnUpdate", nil)
            updating = false
        end
    end
end

do
    local scheduled_scans = {}

    local function doCooldownScan(fireTime)
        WeakAuras.debug("Performing cooldown scan at " .. fireTime .. " (" .. GetTime() .. ")")
        scheduled_scans[fireTime] = nil
        WeakAuras.ScanEvents("COOLDOWN_REMAINING_CHECK")
    end
    function WeakAuras.ScheduleCooldownScan(fireTime)
        if not (scheduled_scans[fireTime]) then
            WeakAuras.debug("Scheduled cooldown scan at " .. fireTime)
            scheduled_scans[fireTime] = timer:ScheduleTimer(doCooldownScan, fireTime - GetTime() + 0.1, fireTime)
        end
    end
end

function GenericTrigger.Delete(id)
    GenericTrigger.UnloadDisplay(id)
end

function GenericTrigger.Rename(oldid, newid)
    events[newid] = events[oldid]
    events[oldid] = nil

    for eventname, events in pairs(loaded_events) do
        if (eventname == "COMBAT_LOG_EVENT_UNFILTERED") then
            for subeventname, subevents in pairs(events) do
                subevents[oldid] = subevents[newid]
                subevents[oldid] = nil
            end
        else
            events[newid] = events[oldid]
            events[oldid] = nil
        end
    end

    WeakAuras.EveryFrameUpdateRename(oldid, newid)
end

local function LoadEvent(id, triggernum, data)
    local events = data.events or {}
    for index, event in pairs(events) do
        loaded_events[event] = loaded_events[event] or {}
        if (event == "COMBAT_LOG_EVENT_UNFILTERED" and data.subevent) then
            loaded_events[event][data.subevent] = loaded_events[event][data.subevent] or {}
            loaded_events[event][data.subevent][id] = loaded_events[event][data.subevent][id] or {}
            loaded_events[event][data.subevent][id][triggernum] = data
        else
            loaded_events[event][id] = loaded_events[event][id] or {}
            loaded_events[event][id][triggernum] = data
        end
    end
end

function GenericTrigger.LoadDisplay(id)
    if (events[id]) then
        for triggernum, data in pairs(events[id]) do
            if (events[id] and events[id][triggernum]) then
                LoadEvent(id, triggernum, data)
            end
        end
    end
end

function GenericTrigger.Modernize(data)
    -- Convert any references to "COMBAT_LOG_EVENT_UNFILTERED_CUSTOM" to "COMBAT_LOG_EVENT_UNFILTERED"
    for triggernum = 0, (data.numTriggers or 9) do
        local trigger, untrigger
        if (triggernum == 0) then
            trigger = data.trigger
        elseif (data.additional_triggers and data.additional_triggers[triggernum]) then
            trigger = data.additional_triggers[triggernum].trigger
        end
        if (trigger and trigger.custom) then
            trigger.custom = trigger.custom:gsub("COMBAT_LOG_EVENT_UNFILTERED_CUSTOM", "COMBAT_LOG_EVENT_UNFILTERED")
        end
        if (untrigger and untrigger.custom) then
            untrigger.custom =
                untrigger.custom:gsub("COMBAT_LOG_EVENT_UNFILTERED_CUSTOM", "COMBAT_LOG_EVENT_UNFILTERED")
        end
    end

    -- Rename ["event"] = "Cooldown (Spell)" to ["event"] = "Cooldown Progress (Spell)"
    for triggernum = 0, (data.numTriggers or 9) do
        local trigger, untrigger

        if (triggernum == 0) then
            trigger = data.trigger
        elseif (data.additional_triggers and data.additional_triggers[triggernum]) then
            trigger = data.additional_triggers[triggernum].trigger
        end

        if trigger and trigger["event"] and trigger["event"] == "Cooldown (Spell)" then
            trigger["event"] = "Cooldown Progress (Spell)"
        end
    end

    -- Add status/event information to triggers
    for triggernum = 0, (data.numTriggers or 9) do
        local trigger, untrigger
        if (triggernum == 0) then
            trigger = data.trigger
            untrigger = data.untrigger
        elseif (data.additional_triggers and data.additional_triggers[triggernum]) then
            trigger = data.additional_triggers[triggernum].trigger
            untrigger = data.additional_triggers[triggernum].untrigger
        end
        -- Add status/event information to triggers
        if (trigger and trigger.event and (trigger.type == "status" or trigger.type == "event")) then
            local prototype = event_prototypes[trigger.event]
            if (prototype) then
                trigger.type = prototype.type
            end
        end

        if
            (trigger and trigger.type and trigger.event and trigger.type == "status" and
                trigger.event == "Cooldown Progress (Spell)")
         then
            if (not trigger.showOn) then
                if (trigger.use_inverse) then
                    trigger.showOn = "showOnReady"
                else
                    trigger.showOn = "showOnCooldown"
                end
                trigger.use_inverse = nil
            end
        end
    end
end

--#############################
--# Support code for triggers #
--#############################
-- Swing Timer Support code
do
    local mh = GetInventorySlotInfo("MainHandSlot")
    local oh = GetInventorySlotInfo("SecondaryHandSlot")

    local swingTimerFrame
    local lastSwingMain, lastSwingOff, lastSwingRange
    local swingDurationMain, swingDurationOff, swingDurationRange
    local mainTimer, offTimer, rangeTimer

    function WeakAuras.GetSwingTimerInfo(hand)
        if (hand == "main") then
            local itemId = GetInventoryItemID("player", mh)
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId or 0)
            if (lastSwingMain) then
                return swingDurationMain, lastSwingMain + swingDurationMain, name, icon
            elseif (lastSwingRange) then
                return swingDurationRange, lastSwingRange + swingDurationRange, name, icon
            else
                return 0, math.huge, name, icon
            end
        elseif (hand == "off") then
            local itemId = GetInventoryItemID("player", oh)
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId or 0)
            if (lastSwingOff) then
                return swingDurationOff, lastSwingOff + swingDurationOff, name, icon
            else
                return 0, math.huge, name, icon
            end
        end

        return 0, math.huge
    end

    local function swingEnd(hand)
        if (hand == "main") then
            lastSwingMain, swingDurationMain = nil, nil
        elseif (hand == "off") then
            lastSwingOff, swingDurationOff = nil, nil
        elseif (hand == "range") then
            lastSwingRange, swingDurationRange = nil, nil
        end
        WeakAuras.ScanEvents("SWING_TIMER_END")
    end

    local function swingTimerCheck(frame, event, _, message, _, _, source)
        if (UnitIsUnit(source or "", "player")) then
            if (message == "SWING_DAMAGE" or message == "SWING_MISSED") then
                local event
                local currentTime = GetTime()
                local mainSpeed, offSpeed = UnitAttackSpeed("player")
                offSpeed = offSpeed or 0
                if not (lastSwingMain) then
                    lastSwingMain = currentTime
                    swingDurationMain = mainSpeed
                    event = "SWING_TIMER_START"
                    mainTimer = timer:ScheduleTimer(swingEnd, mainSpeed, "main")
                elseif (OffhandHasWeapon() and not lastSwingOff) then
                    lastSwingOff = currentTime
                    swingDurationOff = offSpeed
                    event = "SWING_TIMER_START"
                    offTimer = timer:ScheduleTimer(swingEnd, offSpeed, "off")
                else
                    -- A swing occurred while both weapons are supposed to be on cooldown
                    -- Simply refresh the timer of the weapon swing which would have ended sooner
                    local mainRem, offRem =
                        (lastSwingMain or math.huge) + mainSpeed - currentTime,
                        (lastSwingOff or math.huge) + offSpeed - currentTime
                    if (mainRem < offRem or not OffhandHasWeapon()) then
                        timer:CancelTimer(mainTimer, true)
                        lastSwingMain = currentTime
                        swingDurationMain = mainSpeed
                        event = "SWING_TIMER_CHANGE"
                        mainTimer = timer:ScheduleTimer(swingEnd, mainSpeed, "main")
                    else
                        timer:CancelTimer(mainTimer, true)
                        lastSwingOff = currentTime
                        swingDurationOff = offSpeed
                        event = "SWING_TIMER_CHANGE"
                        offTimer = timer:ScheduleTimer(swingEnd, offSpeed, "off")
                    end
                end

                WeakAuras.ScanEvents(event)
            elseif (message == "RANGE_DAMAGE" or message == "RANGE_MISSED") then
                local event
                local currentTime = GetTime()
                local speed = UnitRangedDamage("player")
                if (lastSwingRange) then
                    timer:CancelTimer(rangeTimer, true)
                    event = "SWING_TIMER_CHANGE"
                else
                    event = "SWING_TIMER_START"
                end
                lastSwingRange = currentTime
                swingDurationRange = speed
                rangeTimer = timer:ScheduleTimer(swingEnd, speed, "range")

                WeakAuras.ScanEvents(event)
            end
        end
    end

    function WeakAuras.InitSwingTimer()
        if not (swingTimerFrame) then
            swingTimerFrame = CreateFrame("frame")
            swingTimerFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            swingTimerFrame:SetScript("OnEvent", swingTimerCheck)
        end
    end
end

-- CD/Rune/GCD Support Code
do
    local cdReadyFrame
    WeakAuras.frames["Cooldown Trigger Handler"] = cdReadyFrame

    local spells = {}
    local spellsRune = {}
    local spellCdDurs = {}
    local spellCdExps = {}
    local spellCdDursRune = {}
    local spellCdExpsRune = {}
    local spellCharges = {}
    local spellCdHandles = {}

    local items = {}
    local itemCdDurs = {}
    local itemCdExps = {}
    local itemCdHandles = {}

    local runes = {}
    local runeCdDurs = {}
    local runeCdExps = {}
    local runeCdHandles = {}

    local gcdReference
    local gcdStart
    local gcdDuration
    local gcdSpellName
    local gcdSpellIcon
    local gcdEndCheck

    function WeakAuras.InitCooldownReady()
        cdReadyFrame = CreateFrame("FRAME")
        cdReadyFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        cdReadyFrame:RegisterEvent("RUNE_POWER_UPDATE")
        cdReadyFrame:RegisterEvent("RUNE_TYPE_UPDATE")
        cdReadyFrame:SetScript(
            "OnEvent",
            function(self, event, ...)
                if (event == "SPELL_UPDATE_COOLDOWN" or event == "RUNE_POWER_UPDATE" or event == "RUNE_TYPE_UPDATE") then
                    WeakAuras.CheckCooldownReady()
                elseif (event == "UNIT_SPELLCAST_SENT") then
                    local unit, name = ...
                    if (unit == "player") then
                        if (gcdSpellName ~= name) then
                            local icon = GetSpellTexture(name)
                            gcdSpellName = name
                            gcdSpellIcon = icon
                        end
                    end
                end
            end
        )
    end

    function WeakAuras.GetRuneCooldown(id)
        if (runes[id] and runeCdExps[id] and runeCdDurs[id]) then
            return runeCdExps[id] - runeCdDurs[id], runeCdDurs[id]
        else
            return 0, 0
        end
    end

    function WeakAuras.GetSpellCooldown(id, ignoreRuneCD)
        if (ignoreRuneCD) then
            if (spellsRune[id] and spellCdExpsRune[id] and spellCdDursRune[id]) then
                return spellCdExpsRune[id] - spellCdDursRune[id], spellCdDursRune[id]
            else
                return 0, 0
            end
        end

        if (spells[id] and spellCdExps[id] and spellCdDurs[id]) then
            return spellCdExps[id] - spellCdDurs[id], spellCdDurs[id]
        else
            return 0, 0
        end
    end

    function WeakAuras.GetSpellCharges(id)
        return spellCharges[id]
    end

    function WeakAuras.GetItemCooldown(id)
        if (items[id] and itemCdExps[id] and itemCdDurs[id]) then
            return itemCdExps[id] - itemCdDurs[id], itemCdDurs[id]
        else
            return 0, 0
        end
    end

    function WeakAuras.GetGCDInfo()
        if (gcdStart) then
            return gcdDuration, gcdStart + gcdDuration, gcdSpellName or "Invalid", gcdSpellIcon or
                "Interface\\Icons\\INV_Misc_QuestionMark"
        else
            return 0, math.huge, gcdSpellName or "Invalid", gcdSpellIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
        end
    end

    local function RuneCooldownFinished(id)
        runeCdHandles[id] = nil
        runeCdDurs[id] = nil
        runeCdExps[id] = nil
        WeakAuras.ScanEvents("RUNE_COOLDOWN_READY", id)
    end

    local function SpellCooldownFinished(id)
        spellCdHandles[id] = nil
        spellCdDurs[id] = nil
        spellCdExps[id] = nil
        spellCdDursRune[id] = nil
        spellCdExpsRune[id] = nil
        spellCharges[id] = nil
        WeakAuras.ScanEvents("SPELL_COOLDOWN_READY", id, nil)
    end

    local function ItemCooldownFinished(id)
        itemCdHandles[id] = nil
        itemCdDurs[id] = nil
        itemCdExps[id] = nil
        WeakAuras.ScanEvents("ITEM_COOLDOWN_READY", id)
    end

    local classGCDSpells = {
        PALADIN = GetSpellInfo(19750),
        HUNTER = GetSpellInfo(1978),
        ROGUE = GetSpellInfo(1752),
        SHAMAN = GetSpellInfo(8004),
        MAGE = GetSpellInfo(1449),
        WARRIOR = GetSpellInfo(1715),
        WARLOCK = GetSpellInfo(5676),
        PRIEST = GetSpellInfo(139)
    }

    local function CheckGCD()
        local event
        local _, class = UnitClass("player")
        local startTime, duration = GetSpellCooldown(classGCDSpells[class])
        if (duration and duration > 0) then
            if not (gcdStart) then
                event = "GCD_START"
            elseif (gcdStart ~= startTime) then
                event = "GCD_CHANGE"
            end
            gcdStart, gcdDuration = startTime, duration
            local endCheck = startTime + duration + 0.1
            if (gcdEndCheck ~= endCheck) then
                gcdEndCheck = endCheck
                timer:ScheduleTimer(CheckGCD, duration + 0.1)
            end
        else
            if (gcdStart) then
                event = "GCD_END"
            end
            gcdStart, gcdDuration = nil, nil
            gcdEndCheck = 0
        end
        if (event) then
            WeakAuras.ScanEvents(event)
        end
    end

    function WeakAuras.CheckCooldownReady()
        if (gcdReference) then
            CheckGCD()
        end

        for id, _ in pairs(runes) do
            local startTime, duration = GetRuneCooldown(id)
            startTime = startTime or 0
            duration = duration or 0
            local time = GetTime()

            if (not startTime or startTime == 0) then
                startTime = 0
                duration = 0
            end

            if (startTime > 0 and duration > 1.51) then
                -- On non-GCD cooldown
                local endTime = startTime + duration

                if not (runeCdExps[id]) then
                    -- New cooldown
                    runeCdDurs[id] = duration
                    runeCdExps[id] = endTime
                    runeCdHandles[id] = timer:ScheduleTimer(RuneCooldownFinished, endTime - time, id)
                    WeakAuras.ScanEvents("RUNE_COOLDOWN_STARTED", id)
                elseif (runeCdExps[id] ~= endTime) then
                    -- Cooldown is now different
                    if (runeCdHandles[id]) then
                        timer:CancelTimer(runeCdHandles[id])
                    end
                    runeCdDurs[id] = duration
                    runeCdExps[id] = endTime
                    runeCdHandles[id] = timer:ScheduleTimer(RuneCooldownFinished, endTime - time, id)
                    WeakAuras.ScanEvents("RUNE_COOLDOWN_CHANGED", id)
                end
            elseif (startTime > 0 and duration > 0) then
                -- GCD, do nothing
            else
                if (runeCdExps[id]) then
                    -- Somehow CheckCooldownReady caught the rune cooldown before the timer callback
                    -- This shouldn't happen, but if it doesn, no problem
                    if (runeCdHandles[id]) then
                        timer:CancelTimer(runeCdHandles[id])
                    end
                    RuneCooldownFinished(id)
                end
            end
        end

        for id, _ in pairs(spells) do
            local maxCharges = nil
            local name = GetSpellInfo(id)
            local startTime, duration = GetSpellCooldown(name)
            local charges = nil
            startTime = startTime or 0
            duration = duration or 0
            local time = GetTime()
            local remaining = startTime + duration - time

            if (duration > 1.51) then
                -- On non-GCD cooldown
                local endTime = startTime + duration

                if not (spellCdExps[id]) then
                    -- New cooldown
                    spellCdDurs[id] = duration
                    spellCdExps[id] = endTime
                    spellCdHandles[id] = timer:ScheduleTimer(SpellCooldownFinished, endTime - time, id)
                    if (spellsRune[id] and duration ~= 10) then
                        spellCdDursRune[id] = duration
                        spellCdExpsRune[id] = endTime
                    end
                    WeakAuras.ScanEvents("SPELL_COOLDOWN_STARTED", id)
                elseif (spellCdExps[id] ~= endTime) then
                    -- Cooldown is now different
                    if (spellCdHandles[id]) then
                        timer:CancelTimer(spellCdHandles[id])
                    end

                    spellCdDurs[id] = duration
                    spellCdExps[id] = endTime
                    if (maxCharges == nil or charges + 1 == maxCharges) then
                        spellCdHandles[id] = timer:ScheduleTimer(SpellCooldownFinished, endTime - time, id)
                    end
                    if (spellsRune[id] and duration ~= 10) then
                        spellCdDursRune[id] = duration
                        spellCdExpsRune[id] = endTime
                    end
                    WeakAuras.ScanEvents("SPELL_COOLDOWN_CHANGED", id)
                end
            elseif (duration > 0 and not (spellCdExps[id] and spellCdExps[id] - time > 1.51)) then
                -- GCD
                -- Do nothing
            else
                if (spellCdExps[id]) then
                    -- Somehow CheckCooldownReady caught the spell cooldown before the timer callback
                    -- This shouldn't happen, but if it does, no problem
                    if (spellCdHandles[id]) then
                        timer:CancelTimer(spellCdHandles[id])
                    end
                    SpellCooldownFinished(id)
                end
            end
        end

        for id, _ in pairs(items) do
            local startTime, duration = GetItemCooldown(id)
            startTime = startTime or 0
            duration = duration or 0
            local time = GetTime()

            if (duration > 1.51) then
                -- On non-GCD cooldown
                local endTime = startTime + duration

                if not (itemCdExps[id]) then
                    -- New cooldown
                    itemCdDurs[id] = duration
                    itemCdExps[id] = endTime
                    itemCdHandles[id] = timer:ScheduleTimer(ItemCooldownFinished, endTime - time, id)
                    WeakAuras.ScanEvents("ITEM_COOLDOWN_STARTED", id)
                elseif (itemCdExps[id] ~= endTime) then
                    -- Cooldown is now different
                    if (itemCdHandles[id]) then
                        timer:CancelTimer(itemCdHandles[id])
                    end
                    itemCdDurs[id] = duration
                    itemCdExps[id] = endTime
                    itemCdHandles[id] = timer:ScheduleTimer(ItemCooldownFinished, endTime - time, id)
                    WeakAuras.ScanEvents("ITEM_COOLDOWN_CHANGED", id)
                end
            elseif (duration > 0) then
                -- GCD
                -- Do nothing
            else
                if (itemCdExps[id]) then
                    -- Somehow CheckCooldownReady caught the item cooldown before the timer callback
                    -- This shouldn't happen, but if it doesn, no problem
                    if (itemCdHandles[id]) then
                        timer:CancelTimer(itemCdHandles[id])
                    end
                    ItemCooldownFinished(id)
                end
            end
        end
    end

    function WeakAuras.WatchGCD()
        if not (cdReadyFrame) then
            WeakAuras.InitCooldownReady()
        end
        cdReadyFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        cdReadyFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
        gcdReference = true
    end

    function WeakAuras.WatchRuneCooldown(id)
        if not (cdReadyFrame) then
            WeakAuras.InitCooldownReady()
        end

        if not id or id == 0 then
            return
        end

        if not (runes[id]) then
            runes[id] = true
            local startTime, duration = GetRuneCooldown(id)

            if (not startTime or startTime == 0) then
                startTime = 0
                duration = 0
            end

            if (startTime and duration and startTime > 0 and duration > 1.51) then
                local time = GetTime()
                local endTime = startTime + duration
                runeCdDurs[id] = duration
                runeCdExps[id] = endTime
                if not (runeCdHandles[id]) then
                    runeCdHandles[id] = timer:ScheduleTimer(RuneCooldownFinished, endTime - time, id)
                end
            end
        end
    end

    function WeakAuras.WatchSpellCooldown(id)
        if not (cdReadyFrame) then
            WeakAuras.InitCooldownReady()
        end

        if not id or id == 0 then
            return
        end

        if not (spells[id]) then
            spells[id] = true
            local name = GetSpellInfo(id)
            local startTime, duration = GetSpellCooldown(name)
            startTime = startTime or 0
            duration = duration or 0
            if (duration > 1.51) then
                local time = GetTime()
                local endTime = startTime + duration
                spellCdDurs[id] = duration
                spellCdExps[id] = endTime
                if not (spellCdHandles[id]) then
                    spellCdHandles[id] = timer:ScheduleTimer(SpellCooldownFinished, endTime - time, id)
                end
            end
        end
    end

    function WeakAuras.WatchItemCooldown(id)
        if not (cdReadyFrame) then
            WeakAuras.InitCooldownReady()
        end

        if not id or id == 0 then
            return
        end

        if not (items[id]) then
            items[id] = true
            local startTime, duration = GetItemCooldown(id)
            if (startTime and duration and duration > 1.51) then
                local time = GetTime()
                local endTime = startTime + duration
                itemCdDurs[id] = duration
                itemCdExps[id] = endTime
                if not (itemCdHandles[id]) then
                    itemCdHandles[id] = timer:ScheduleTimer(ItemCooldownFinished, endTime - time, id)
                end
            end
        end
    end

    function WeakAuras.RuneCooldownForce()
        WeakAuras.ScanEvents("COOLDOWN_REMAINING_CHECK")
    end

    function WeakAuras.SpellCooldownForce()
        WeakAuras.ScanEvents("COOLDOWN_REMAINING_CHECK")
    end

    function WeakAuras.ItemCooldownForce()
        WeakAuras.ScanEvents("COOLDOWN_REMAINING_CHECK")
    end
end

-- Weapon Enchants
do
    local mh = GetInventorySlotInfo("MainHandSlot")
    local oh = GetInventorySlotInfo("SecondaryHandSlot")

    local mh_name
    local mh_exp
    local mh_dur
    local mh_icon = GetInventoryItemTexture("player", mh)

    local oh_name
    local oh_exp
    local oh_dur
    local oh_icon = GetInventoryItemTexture("player", oh)

    local tenchFrame
    WeakAuras.frames["Temporary Enchant Handler"] = tenchFrame
    local tenchTip

    function WeakAuras.TenchInit()
        if not (tenchFrame) then
            tenchFrame = CreateFrame("Frame")
            tenchFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")

            tenchFrame.lastMHTime = 0
            tenchFrame.lastOHTime = 0

            tenchTip = WeakAuras.GetHiddenTooltip()

            local function getTenchName(id)
                tenchTip:SetInventoryItem("player", id)
                local lines = {tenchTip:GetRegions()}
                for i, v in ipairs(lines) do
                    if (v:GetObjectType() == "FontString") then
                        local text = v:GetText()
                        if (text) then
                            local _, _, name = text:find("^(.+) %(%d+ [^%)]+%)$")
                            if (name) then
                                return name
                            end
                        end
                    end
                end

                return "Unknown"
            end

            local function tenchUpdate()
                local _, mh_rem, _, _, oh_rem = GetWeaponEnchantInfo()
                local time = GetTime()
                local mh_exp_new = mh_rem and (time + (mh_rem / 1000))
                local oh_exp_new = oh_rem and (time + (oh_rem / 1000))
                if (math.abs((mh_exp or 0) - (mh_exp_new or 0)) > 1) then
                    mh_exp = mh_exp_new
                    mh_dur = mh_rem and mh_rem / 1000
                    mh_name = mh_exp and getTenchName(mh) or "None"
                    mh_icon = GetInventoryItemTexture("player", mh)
                    WeakAuras.ScanEvents("MAINHAND_TENCH_UPDATE")
                end
                if (math.abs((oh_exp or 0) - (oh_exp_new or 0)) > 1) then
                    oh_exp = oh_exp_new
                    oh_dur = oh_rem and oh_rem / 1000
                    oh_name = oh_exp and getTenchName(oh) or "None"
                    oh_icon = GetInventoryItemTexture("player", oh)
                    WeakAuras.ScanEvents("OFFHAND_TENCH_UPDATE")
                end
            end

            tenchFrame:SetScript(
                "OnEvent",
                function(self, event, arg1)
                    if (arg1 == "player") then
                        timer:ScheduleTimer(tenchUpdate, 0.1)
                    end
                end
            )

            tenchFrame:SetScript(
                "OnUpdate",
                function(self)
                    tenchUpdate()
                end
            )
            
            tenchUpdate()
        end
    end

    function WeakAuras.GetMHTenchInfo()
        return mh_exp, mh_dur, mh_name, mh_icon
    end

    function WeakAuras.GetOHTenchInfo()
        return oh_exp, oh_dur, oh_name, oh_icon
    end
end

-- Mount
do
    local mountedFrame
    WeakAuras.frames["Mount Use Handler"] = mountedFrame
    function WeakAuras.WatchForMounts()
        if not (mountedFrame) then
            mountedFrame = CreateFrame("frame")
            mountedFrame:RegisterEvent("COMPANION_UPDATE")
            local elapsed = 0
            local delay = 0.5
            local isMounted = IsMounted()
            local function checkForMounted(self, elaps)
                elapsed = elapsed + elaps
                if (isMounted ~= IsMounted()) then
                    isMounted = IsMounted()
                    WeakAuras.ScanEvents("MOUNTED_UPDATE")
                    mountedFrame:SetScript("OnUpdate", nil)
                end
                if (elapsed > delay) then
                    mountedFrame:SetScript("OnUpdate", nil)
                end
            end
            mountedFrame:SetScript(
                "OnEvent",
                function()
                    elapsed = 0
                    mountedFrame:SetScript("OnUpdate", checkForMounted)
                end
            )
        end
    end
end

-- PET
do
    local petFrame
    WeakAuras.frames["Pet Use Handler"] = petFrame
    function WeakAuras.WatchForPetDeath()
        if not (petFrame) then
            petFrame = CreateFrame("frame")
            petFrame:RegisterUnitEvent("UNIT_HEALTH", "pet")
            petFrame:SetScript(
                "OnEvent",
                function()
                    WeakAuras.ScanEvents("PET_UPDATE")
                end
            )
        end
    end
end

-- Item Count
local itemCountWatchFrame
function WeakAuras.RegisterItemCountWatch()
    if not (itemCountWatchFrame) then
        itemCountWatchFrame = CreateFrame("frame")
        itemCountWatchFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        itemCountWatchFrame:SetScript(
            "OnEvent",
            function()
                timer:ScheduleTimer(WeakAuras.ScanEvents, 0.2, "ITEM_COUNT_UPDATE")
                timer:ScheduleTimer(WeakAuras.ScanEvents, 0.5, "ITEM_COUNT_UPDATE")
            end
        )
    end
end

function GenericTrigger.CanGroupShowWithZero(data)
    return false
end

function GenericTrigger.CanHaveDuration(data, triggernum)
    local trigger
    if (triggernum == 0) then
        trigger = data.trigger
    else
        trigger = data.additional_triggers[triggernum].trigger
    end

    if
        (((trigger.type == "event" or trigger.type == "status") and
            ((trigger.event and WeakAuras.event_prototypes[trigger.event] and
                WeakAuras.event_prototypes[trigger.event].durationFunc) or
                (trigger.unevent == "timed" and trigger.duration)) and
            not trigger.use_inverse) or
            (trigger.type == "custom" and
                ((trigger.custom_type == "event" and trigger.custom_hide == "timed" and trigger.duration) or
                    (trigger.customDuration and trigger.customDuration ~= ""))))
     then
        if
            ((trigger.type == "event" or trigger.type == "status") and trigger.event and
                WeakAuras.event_prototypes[trigger.event] and
                WeakAuras.event_prototypes[trigger.event].durationFunc)
         then
            if (type(WeakAuras.event_prototypes[trigger.event].init) == "function") then
                WeakAuras.event_prototypes[trigger.event].init(trigger)
            end
            local current, maximum, custom = WeakAuras.event_prototypes[trigger.event].durationFunc(trigger)
            current = type(current) ~= "number" and current or 0
            maximum = type(maximum) ~= "number" and maximum or 0
            if (custom) then
                return {current = current, maximum = maximum}
            else
                return "timed"
            end
        elseif trigger.event
            and WeakAuras.event_prototypes[trigger.event]
            and WeakAuras.event_prototypes[trigger.event].canHaveDuration then
            return WeakAuras.event_prototypes[trigger.event].canHaveDuration
        else
            return "timed"
        end
    else
        return false
    end
end

function GenericTrigger.CanHaveAuto(data, triggernum)
    -- Is also called on importing before conversion, so do a few checks
    local trigger
    if (triggernum == 0) then
        trigger = data.trigger
    elseif (data.additional_triggers and data.additional_triggers[triggernum]) then
        trigger = data.additional_triggers[triggernum].trigger
    end

    if (not trigger) then
        return false
    end

    if
        (((trigger.type == "event" or trigger.type == "status") and trigger.event and
            WeakAuras.event_prototypes[trigger.event] and
            (WeakAuras.event_prototypes[trigger.event].iconFunc or WeakAuras.event_prototypes[trigger.event].nameFunc)) or
            (trigger.type == "custom" and
                ((trigger.customName and trigger.customName ~= "") or (trigger.customIcon and trigger.customIcon ~= ""))))
     then
        return true
    else
        return false
    end
end

function GenericTrigger.CanHaveClones(data)
    return false
end

function GenericTrigger.GetNameAndIcon(data, triggernum)
    local trigger
    if (triggernum == 0) then
        trigger = data.trigger
    elseif (data.additional_triggers and data.additional_triggers[triggernum]) then
        trigger = data.additional_triggers[triggernum].trigger
    end
    if (trigger.event and WeakAuras.event_prototypes[trigger.event]) then
        if (WeakAuras.event_prototypes[trigger.event].iconFunc) then
            icon = WeakAuras.event_prototypes[trigger.event].iconFunc(trigger)
        end
        if (WeakAuras.event_prototypes[trigger.event].nameFunc) then
            name = WeakAuras.event_prototypes[trigger.event].nameFunc(trigger)
        end
    end
end

function GenericTrigger.CanHaveTooltip(data)
    local trigger = data.trigger
    if (trigger.type == "event" or trigger.type == "status") then
        if (trigger.event and WeakAuras.event_prototypes[trigger.event]) then
            if (WeakAuras.event_prototypes[trigger.event].hasSpellID) then
                return "spell"
            elseif (WeakAuras.event_prototypes[trigger.event].hasItemID) then
                return "item"
            end
        end
    end
    return false
end

function GenericTrigger.SetToolTip(trigger, state)
    local trigger = data.trigger
    if (trigger.type == "event" or trigger.type == "status") then
        if (trigger.event and WeakAuras.event_prototypes[trigger.event]) then
            if (WeakAuras.event_prototypes[trigger.event].hasSpellID) then
                GameTooltip:SetSpellByID(trigger.spellName)
            elseif (WeakAuras.event_prototypes[trigger.event].hasItemID) then
                GameTooltip:SetHyperlink("item:" .. trigger.itemName .. ":0:0:0:0:0:0:0")
            end
        end
    end
end

function GenericTrigger.GetTriggerConditions(data, triggernum)
    local trigger;
    if (triggernum == 0) then
        trigger = data.trigger;
    else
        trigger = data.additional_triggers[triggernum].trigger;
    end

    if (trigger.type == "event" or trigger.type == "status") then
        if (trigger.event and WeakAuras.event_prototypes[trigger.event]) then
        local result = {};

        local canHaveDuration = GenericTrigger.CanHaveDuration(data, triggernum);
        local timedDuration = canHaveDuration;
        local valueDuration = canHaveDuration;
        if (canHaveDuration == "timed") then
            valueDuration = false;
        elseif (type(canHaveDuration) == "table") then
            timedDuration = false;
        end

        if (timedDuration) then
            result["expirationTime"] = {
            display = L["Remaining Duration"],
            type = "timer",
            }
            result["duration"] = {
            display = L["Total Duration"],
            type = "number",
            }
        end

        if (valueDuration) then
            result["value"] = {
            display = L["Progress Value"],
            type = "number",
            }
            result["total"] = {
            display = L["Progress Total"],
            type = "number",
            }
        end

        if (WeakAuras.event_prototypes[trigger.event].stacksFunc) then
            result["stacks"] = {
            display = L["Stacks"],
            type = "number"
            }
        end

        for _, v in pairs(WeakAuras.event_prototypes[trigger.event].args) do
            if (v.conditionType and v.store and v.name and v.display) then
            local enable = true;
            if (v.enable) then
                enable = v.enable(trigger);
            end

            if (enable) then
                result[v.name] = {
                display = v.display,
                type = v.conditionType
                }
                if (result[v.name].type == "select") then
                if (v.conditionValues) then
                    result[v.name].values = WeakAuras[v.conditionValues];
                else
                    result[v.name].values = WeakAuras[v.values];
                end
                end
                if (v.conditionTest) then
                result[v.name].test = v.conditionTest;
                end
            end
            end
        end

        return result;
        end
    end
    return nil;
end

function GenericTrigger.CreateFallbackState(data, triggernum, state)
    state.show = true
    state.changed = true
    local event = events[data.id][triggernum]
    state.name = event.nameFunc and event.nameFunc(data.trigger) or nil
    state.icon = event.iconFunc and event.iconFunc(data.trigger) or nil
    state.texture = event.textureFunc and event.textureFunc(data.trigger) or nil
    state.stacks = event.stacksFunc and event.stacksFunc(data.trigger) or nil
end

function GenericTrigger.AllAdded()
    -- Remove GTFO options if GTFO isn't enabled and there are no saved GTFO auras
    local hideGTFO = true
    local hideDBM = true
    if (GTFO) then
        hideGTFO = false
    end

    if (DBM and type(DBM.RegisterCallback) == "function") then
        hideDBM = false
    end

    for id, event in pairs(events) do
        for triggernum, data in pairs(event) do
            if (data.trigger.event == "GTFO") then
                hideGTFO = false
            end
            if (data.trigger.event == "DBM Announce" or data.trigger.event == "DBM Timer") then
                hideDBM = false
            end
        end
    end
    if (hideGTFO) then
        WeakAuras.event_types["GTFO"] = nil
    end
    if (hideDBM) then
        WeakAuras.event_types["DBM Announce"] = nil
        WeakAuras.status_types["DBM Timer"] = nil
    end
end

-- DBM
do
    local registeredDBMEvents = {}
    local bars = {}
    local nextExpire  -- time of next expiring timer
    local recheckTimer  -- handle of timer

    local function dbmRecheckTimers()
        --print ("dbmRecheckTimers");
        local now = GetTime()
        local sendUpdate = false -- Do we have a expired timer?
        nextExpire = nil
        local nextMsg = nil
        local toRemove = {}
        for k, v in pairs(bars) do
            if (v.expirationTime < now) then
                sendUpdate = true
                --print ("  Removing:", k, v.message);
                bars[k] = nil
            elseif (nextExpire == nil) then
                nextExpire = v.expirationTime
                nextMsg = v.message
            elseif (v.expirationTime < nextExpire) then
                nextExpire = v.expirationTime
                nextMsg = v.message
            end
        end

        --print ("  nextExpire", nextExpire and nextExpire - now, nextMsg, "  sendUpdate", sendUpdate);

        if (nextExpire) then
            recheckTimer = timer:ScheduleTimer(dbmRecheckTimers, nextExpire - now)
        end
        if (sendUpdate) then
            WeakAuras.ScanEvents("DBM_TimerUpdate")
        end
    end

    local function dbmEventCallback(event, ...)
        -- print ("dbmEventCallback", event, ...);
        if (event == "DBM_TimerStart") then
            local id, msg, duration = ...
            local now = GetTime()
            local expiring = now + duration
            -- print ("  Adding timer, ID:", id, "MSG:", msg, "TimerStr", timerStr, duration)
            bars[id] = timers[id] or {}
            bars[id]["message"] = msg
            bars[id]["expirationTime"] = expiring
            bars[id]["duration"] = duration

            if (nextExpire == nil) then
                -- print ("  Scheduling timer for", expiring - now, msg);
                nextExpire = expiring
                recheckTimer = timer:ScheduleTimer(dbmRecheckTimers, expiring - now)
            elseif (expiring < nextExpire) then
                nextExpire = expiring
                timer:CancelTimer(recheckTimer)
                recheckTimer = timer:ScheduleTimer(dbmRecheckTimers, expiring - now, msg)
            -- print ("  Scheduling timer for", expiring - now);
            end
            WeakAuras.ScanEvents("DBM_TimerUpdate")
        elseif (event == "DBM_TimerStop") then
            local id = ...
            -- print ("  Removing timer with ID:", id);
            bars[id] = nil
            WeakAuras.ScanEvents("DBM_TimerUpdate")
        elseif (event == "kill" or event == "wipe") then
            -- print("  Wipe or kill, removing all timers")
            bars = {}
            WeakAuras.ScanEvents("DBM_TimerUpdate")
        else -- DBM_Announce
            WeakAuras.ScanEvents(event, ...)
        end
    end

    function WeakAuras.GetDbmTimer(id, message, operator)
        --print ("WeakAuras.GetDBMTimers", id, message, operator)
        local duration, expirationTime
        for k, v in pairs(bars) do
            local found = true
            if (id and id ~= k) then
                found = false
            end
            if (found and message and operator) then
                if (operator == "==") then
                    if (v.message ~= message) then
                        found = false
                    end
                elseif (operator == "find('%s')") then
                    if (v.message == nil or not v.message:find(message)) then
                        found = false
                    end
                elseif (operator == "match('%s')") then
                    if (v.message == nil or not v.message:match(message)) then
                        found = false
                    end
                end
            end
            if (found and (expirationTime == nil or v.expirationTime < expirationTime)) then
                -- print ("  using", v.message);
                expirationTime, duration = v.expirationTime, v.duration
            end
        end
        return duration or 0, expirationTime or 0
    end

    function WeakAuras.RegisterDBMCallback(event)
        if (registeredDBMEvents[event]) then
            return
        end
        if (DBM) then
            DBM:RegisterCallback(event, dbmEventCallback)
            registeredDBMEvents[event] = true
        end
    end

    function WeakAuras.GetDBMTimers()
        return bars
    end

    local scheduled_scans = {}

    local function doDbmScan(fireTime)
        WeakAuras.debug("Performing dbm scan at " .. fireTime .. " (" .. GetTime() .. ")")
        scheduled_scans[fireTime] = nil
        WeakAuras.ScanEvents("DBM_TimerUpdate")
    end
    function WeakAuras.ScheduleDbmCheck(fireTime)
        if not (scheduled_scans[fireTime]) then
            scheduled_scans[fireTime] = timer:ScheduleTimer(doDbmScan, fireTime - GetTime() + 0.1, fireTime)
            WeakAuras.debug("Scheduled dbm scan at " .. fireTime)
        end
    end
end

WeakAuras.RegisterTriggerSystem({"event", "status", "custom"}, GenericTrigger)
