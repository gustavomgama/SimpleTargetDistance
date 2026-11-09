local addonName = ...

-- Explicit state machine: elevates UX/DX/AX by making implicit transitions visible
local State = {
    Init = {
        UNINITIALIZED = "UNINITIALIZED",
        INITIALIZING  = "INITIALIZING",
        INITIALIZED   = "INITIALIZED",
    },
    Target = {
        NONE = "NONE",
        HAS  = "HAS",
    },
    Lock = {
        LOCKED   = "LOCKED",
        UNLOCKED = "UNLOCKED",
    },
    Ticker = {
        STOPPED = "STOPPED",
        RUNNING = "RUNNING",
    },
}

local sm = {
    init   = State.Init.UNINITIALIZED,
    target = State.Target.NONE,
    lock   = State.Lock.LOCKED,
    ticker = nil,
}

local frame = CreateFrame("Frame", "SimpleTargetDistanceFrame", UIParent)
frame:SetSize(120, 24)
frame:SetPoint("CENTER", 0, 0)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if sm.lock == State.Lock.UNLOCKED then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
    local p, _, rp, x, y = self:GetPoint()
    SimpleTargetDistanceDB.point = p
    SimpleTargetDistanceDB.relativePoint = rp or "CENTER"
    SimpleTargetDistanceDB.x = x or 0
    SimpleTargetDistanceDB.y = y or 0
end)

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetPoint("CENTER", frame, "CENTER", 0, 0)
local font = text:GetFont()
text:SetFont(font, 18, "OUTLINE")
text:SetTextColor(1, 0.82, 0)
text:SetText("")

frame.locked = true

local rangeLib = nil
local isSecret = issecretvalue or function() return false end

-- Measurement strategy pipeline (explicit)
local function measureUnitDistanceSquared()
    if type(UnitDistanceSquared) ~= "function" then return nil end
    local sq, checked = UnitDistanceSquared("target")
    if isSecret(sq) or isSecret(checked) then return nil end
    if type(sq) ~= "number" or not checked then return nil end
    return math.sqrt(sq)
end

local function measureGuidDistance()
    if type(UnitGUID) ~= "function" then return nil end
    local guid = UnitGUID("target")
    local kind = (guid or ""):match("^(%a+)%-")
    local id = (guid or ""):match("%-(%d+)%-%x*$")
    id = id and tonumber(id)
    if kind == "Creature" and type(ClosestUnitPosition) == "function" and id then
        local ok, _, _, dist = pcall(ClosestUnitPosition, id)
        if ok and type(dist) == "number" and not isSecret(dist) then return dist end
    elseif kind == "GameObject" and type(ClosestGameObjectPosition) == "function" and id then
        local ok, _, _, dist = pcall(ClosestGameObjectPosition, id)
        if ok and type(dist) == "number" and not isSecret(dist) then return dist end
    end
    return nil
end

local function measureUnitPosition()
    if type(UnitPosition) ~= "function" then return nil end
    local py, px, pz, pinst = UnitPosition("player")
    local ty, tx, tz, tinst = UnitPosition("target")
    if type(px) ~= "number" or type(py) ~= "number" or type(tx) ~= "number" or type(ty) ~= "number" then return nil end
    if pinst ~= tinst then return nil end
    if isSecret(px) or isSecret(py) or isSecret(tx) or isSecret(ty) then return nil end
    local dx, dy = px - tx, py - ty
    local dz = (type(pz) == "number" and type(tz) == "number" and not isSecret(pz) and not isSecret(tz)) and (pz - tz) or 0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function ensureRangeLib()
    if rangeLib ~= nil then return rangeLib end
    if type(_G.LibStub) ~= "function" then return nil end
    local ok, lib = pcall(_G.LibStub, "LibRangeCheck-3.0", true)
    if ok and lib then
        rangeLib = lib
        return rangeLib
    end
    return nil
end

local function measureRangeLib()
    local lib = ensureRangeLib()
    if not lib or type(lib.GetRange) ~= "function" then return nil end
    local ok, mn, mx = pcall(lib.GetRange, lib, "target")
    if not ok then return nil end
    if isSecret(mn) or (mx ~= nil and isSecret(mx)) then return nil end
    if mn and mx then return "~" .. math.floor((mn + mx) / 2 + 0.5) end
    if mx then return "<= " .. mx end
    if mn then return ">= " .. mn end
    return nil
end

local function measure()
    if not UnitExists("target") then return "" end
    if UnitIsUnit("target", "player") then return "0.0" end

    local best = measureUnitDistanceSquared()
    if not best then best = measureGuidDistance() end
    if not best then best = measureUnitPosition() end
    if best then return string.format("%.1f", best) end

    local libRes = measureRangeLib()
    if libRes then return libRes end

    return "?"
end

local function startTicker()
    if sm.ticker then return end
    sm.ticker = C_Timer.NewTicker(0.2, function()
        if sm.target ~= State.Target.HAS or not UnitExists("target") then
            text:SetText("")
            if sm.ticker then
                sm.ticker:Cancel()
                sm.ticker = nil
            end
            sm.target = State.Target.NONE
            return
        end
        text:SetText(measure())
    end)
    sm.target = (UnitExists("target") and State.Target.HAS) or State.Target.NONE
end

local function stopTicker()
    if sm.ticker then
        sm.ticker:Cancel()
        sm.ticker = nil
    end
end

local function transitionToTargetHas()
    if sm.target == State.Target.HAS then
        text:SetText(measure())
        if sm.ticker == nil then startTicker() end
        return
    end
    sm.target = State.Target.HAS
    text:SetText(measure())
    startTicker()
end

local function transitionToTargetNone()
    if sm.target == State.Target.NONE and sm.ticker == nil and text:GetText() == "" then
        return
    end
    sm.target = State.Target.NONE
    text:SetText("")
    stopTicker()
end

local function applyLockState(locked)
    if locked then
        sm.lock = State.Lock.LOCKED
        frame.locked = true
        SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
        SimpleTargetDistanceDB.locked = true
        frame:EnableMouse(false)
    else
        sm.lock = State.Lock.UNLOCKED
        frame.locked = false
        SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
        SimpleTargetDistanceDB.locked = false
        frame:EnableMouse(true)
    end
end


frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") then
            transitionToTargetHas()
        else
            transitionToTargetNone()
        end
        return
    end
    if event ~= "ADDON_LOADED" or name ~= addonName then return end
    sm.init = State.Init.INITIALIZING
    SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
    if SimpleTargetDistanceDB.point then
        self:ClearAllPoints()
        self:SetPoint(SimpleTargetDistanceDB.point, UIParent, SimpleTargetDistanceDB.relativePoint or "CENTER", SimpleTargetDistanceDB.x or 0, SimpleTargetDistanceDB.y or 0)
    end
    ensureRangeLib()
    local locked = SimpleTargetDistanceDB.locked
    if locked == nil then locked = true end
    applyLockState(locked)
    print("|cff00ff00SimpleTargetDistance|r loaded  /std unlock|lock|reset")
    if UnitExists("target") then
        transitionToTargetHas()
    else
        transitionToTargetNone()
    end
    sm.init = State.Init.INITIALIZED
    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_SIMPLETARGETDISTANCE1 = "/std"
SlashCmdList["SIMPLETARGETDISTANCE"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    msg = msg and msg:lower() or ""
    SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
    if msg == "lock" then
        applyLockState(true)
        print("STD: locked")
    elseif msg == "unlock" then
        applyLockState(false)
        print("STD: unlocked (drag)")
    elseif msg == "reset" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        SimpleTargetDistanceDB.point = "CENTER"
        SimpleTargetDistanceDB.relativePoint = "CENTER"
        SimpleTargetDistanceDB.x = 0
        SimpleTargetDistanceDB.y = 0
        print("STD: reset")
    else
        print("STD: /std unlock|lock|reset")
    end
end
