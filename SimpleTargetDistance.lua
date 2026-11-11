local addonName = ...

local frame = CreateFrame("Frame", "SimpleTargetDistanceFrame", UIParent)
frame:SetSize(120, 24)
frame:SetPoint("CENTER", 0, 0)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if not frame.locked then self:StartMoving() end
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
text:SetText(""); updateExtras("")

local extraTexts = { targetFrame = nil, nameplate = nil }

local function ensureTargetFrameText()
    if extraTexts.targetFrame then return extraTexts.targetFrame end
    if type(TargetFrame) ~= "table" then return nil end
    local fs = TargetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", TargetFrame, "RIGHT", 4, 0)
    fs:SetFont(font, 14, "OUTLINE")
    extraTexts.targetFrame = fs
    return fs
end

local function ensureNameplateText()
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return nil end
    local np = C_NamePlate.GetNamePlateForUnit("target")
    if not np then return nil end
    if np._stdText then return np._stdText end
    local fs = np:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", np, "RIGHT", 4, 0)
    fs:SetFont(font, 12, "OUTLINE")
    np._stdText = fs
    return fs
end

local function updateExtras(d)
    local tf = ensureTargetFrameText()
    if tf then tf:SetText(d or "") end
    local np = ensureNameplateText()
    if np then np:SetText(d or "") end
end

frame.locked = true

local isSecret = issecretvalue or function() return false end
local rangeLib = nil
local lastExact, lastExactTime, lastSwingTime = nil, 0, 0
local hasTarget, ticker = false, nil
local smooth, smoothVel, smoothTime = nil, 0, 0

local function measureUnitDistanceSquared()
    if type(UnitDistanceSquared) ~= "function" then return nil end
    local sq, checked = UnitDistanceSquared("target")
    if isSecret(sq) or isSecret(checked) then return nil end
    if type(sq) ~= "number" or not checked then return nil end
    return math.sqrt(sq)
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

local function measureGuidDistance()
    if type(UnitGUID) ~= "function" then return nil end
    local guid = UnitGUID("target")
    local kind = (guid or ""):match("^(%a+)%-")
    local id = tonumber((guid or ""):match("%-(%d+)%-%x*$"))
    if kind == "Creature" and id and type(ClosestUnitPosition) == "function" then
        local ok, _, _, dist = pcall(ClosestUnitPosition, id)
        if ok and type(dist) == "number" and not isSecret(dist) then return dist end
    elseif kind == "GameObject" and id and type(ClosestGameObjectPosition) == "function" then
        local ok, _, _, dist = pcall(ClosestGameObjectPosition, id)
        if ok and type(dist) == "number" and not isSecret(dist) then return dist end
    end
    return nil
end

local function measureExact()
    local v = measureUnitDistanceSquared()
    if v then return v end
    v = measureUnitPosition()
    if v then return v end
    return measureGuidDistance()
end

local function ensureRangeLib()
    if rangeLib then return rangeLib end
    if type(_G.LibStub) ~= "table" and type(_G.LibStub) ~= "function" then return nil end
    local ok, lib = pcall(_G.LibStub, "LibRangeCheck-3.0", true)
    if ok and lib then rangeLib = lib end
    return rangeLib
end

local function measureRangeLib()
    local lib = ensureRangeLib()
    if not lib or type(lib.GetRange) ~= "function" then return nil end
    local ok, mn, mx = pcall(lib.GetRange, lib, "target")
    if not ok or isSecret(mn) or (mx ~= nil and isSecret(mx)) then return nil end
    if mx then return tostring(mx) end
    if mn then return ">=" .. mn end
    return nil
end

local function interactBucket()
    if type(CheckInteractDistance) ~= "function" then return nil end
    local function cid(idx)
        local ok, res = pcall(CheckInteractDistance, "target", idx)
        if not ok or isSecret(res) then return nil end
        return res == true or res == 1
    end
    if cid(3) == true then return "<=7" end
    if cid(2) == true then return "<=8" end
    if cid(1) == true or cid(4) == true then return "<=28" end
    if cid(1) == false then return ">28" end
    return nil
end

local function bucketValue(b)
    if not b then return nil end
    local n = b:match("(%d+)")
    return n and tonumber(n) or nil
end

local function kalmanUpdate(z)
    local now = GetTime()
    if not smooth then
        smooth, smoothVel, smoothTime = z, 0, now
        return smooth
    end
    local dt = now - smoothTime
    if dt < 0.1 then dt = 0.1 end
    if dt > 1 then dt = 1 end
    smooth = smooth + smoothVel * dt
    local K = 0.25
    smooth = smooth + K * (z - smooth)
    smoothVel = smoothVel + 0.08 * (z - smooth) / dt
    smoothTime = now
    return smooth
end

local function measure()
    if not UnitExists("target") then return "" end
    if UnitIsUnit("target", "player") then return "0.0" end

    local exact = measureExact()
    if exact then
        lastExact, lastExactTime = exact, GetTime()
        smooth, smoothVel, smoothTime = nil, 0, 0
        return string.format("%.1f", exact)
    end
    if lastExact and GetTime() - lastExactTime < 5 then
        return string.format("%.1f (stale)", lastExact)
    end

    local libRes = measureRangeLib()
    local z = libRes and tonumber(libRes:match("%d+")) or nil
    if not z then
        local b = interactBucket()
        z = b and bucketValue(b) or nil
        if z and b and b:sub(1,1) == ">" then z = z end
    end
    if z then
        local est = kalmanUpdate(z)
        return string.format("%.0f", est)
    end

    local bucket = interactBucket()
    if bucket then return bucket end

    if GetTime() - lastSwingTime < 2 then return "melee" end
    return "?"
end

local function refreshAll()
    local d = measure()
    text:SetText(d)
    updateExtras(d)
end

local function stopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.2, function()
        if not hasTarget or not UnitExists("target") then
            text:SetText(""); updateExtras("")
            stopTicker()
            hasTarget = false
            return
        end
        refreshAll()
    end)
end

local function applyLock(locked)
    frame.locked = locked
    SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
    SimpleTargetDistanceDB.locked = locked
    frame:EnableMouse(not locked)
end

frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_SWING")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_SWING" then
        lastSwingTime = GetTime()
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        if name == "target" or (type(UnitIsUnit) == "function" and UnitIsUnit(name, "target")) then
            -- recreate nameplate text on next refresh
            extraTexts.nameplate = nil
            if hasTarget then refreshAll() end
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        lastExact, lastExactTime = nil, 0
        smooth, smoothVel, smoothTime = nil, 0, 0
        if UnitExists("target") then
            hasTarget = true
            refreshAll()
            startTicker()
        else
            hasTarget = false
            text:SetText(""); updateExtras("")
            stopTicker()
        end
        return
    end
    if event ~= "ADDON_LOADED" or name ~= addonName then return end
    SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
    if SimpleTargetDistanceDB.point then
        self:ClearAllPoints()
        self:SetPoint(SimpleTargetDistanceDB.point, UIParent, SimpleTargetDistanceDB.relativePoint or "CENTER", SimpleTargetDistanceDB.x or 0, SimpleTargetDistanceDB.y or 0)
    end
    ensureRangeLib()
    applyLock(SimpleTargetDistanceDB.locked ~= false)
    print("|cff00ff00SimpleTargetDistance|r loaded  /std unlock|lock|reset")
    if UnitExists("target") then
        hasTarget = true
        refreshAll()
        startTicker()
    else
        hasTarget = false
        text:SetText(""); updateExtras("")
        stopTicker()
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_SIMPLETARGETDISTANCE1 = "/std"
SlashCmdList["SIMPLETARGETDISTANCE"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    msg = msg and msg:lower() or ""
    SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
    if msg == "lock" then
        applyLock(true)
        print("STD: locked")
    elseif msg == "unlock" then
        applyLock(false)
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