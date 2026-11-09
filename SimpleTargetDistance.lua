local addonName = ...

local frame = CreateFrame("Frame", "SimpleTargetDistanceFrame", UIParent)
frame:SetSize(120, 24)
frame:SetPoint("CENTER", 0, 0)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) if not self.locked then self:StartMoving() end end)
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

local function guidDist(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local guid = UnitGUID(unit)
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

local function measure()
    if not UnitExists("target") then return "" end
    if UnitIsUnit("target", "player") then return "0.0" end

    local best = nil
    if type(UnitDistanceSquared) == "function" then
        local sq, checked = UnitDistanceSquared("target")
        if not (isSecret(sq) or isSecret(checked)) and type(sq) == "number" and checked then
            best = math.sqrt(sq)
        end
    end
    if not best then best = guidDist("target") end
    if not best and type(UnitPosition) == "function" then
        local py, px, pz, pinst = UnitPosition("player")
        local ty, tx, tz, tinst = UnitPosition("target")
        if type(px) == "number" and type(py) == "number" and type(tx) == "number" and type(ty) == "number" and pinst == tinst
            and not (isSecret(px) or isSecret(py) or isSecret(tx) or isSecret(ty)) then
            local dx, dy = px - tx, py - ty
            local dz = (type(pz) == "number" and type(tz) == "number") and (pz - tz) or 0
            best = math.sqrt(dx * dx + dy * dy + dz * dz)
        end
    end
    if best then return string.format("%.1f", best) end

    if rangeLib == nil and _G.LibStub then
        local ok, lib = pcall(_G.LibStub, "LibRangeCheck-3.0", true)
        if ok then rangeLib = lib end
    end
    if rangeLib and type(rangeLib.GetRange) == "function" then
        local ok, mn, mx = pcall(rangeLib.GetRange, rangeLib, "target")
        if ok and not (isSecret(mn) or (mx ~= nil and isSecret(mx))) then
            if mn and mx then return "~" .. math.floor((mn + mx) / 2 + 0.5) end
            if mx then return "<= " .. mx end
            if mn then return ">= " .. mn end
        end
    end

    return "?"
end

local ticker = nil

local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.2, function()
        if not UnitExists("target") then
            text:SetText("")
            return
        end
        text:SetText(measure())
    end)
end

local function stopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end


frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") then
            text:SetText(measure())
            startTicker()
        else
            text:SetText("")
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
    if _G.LibStub then
        local ok, lib = pcall(_G.LibStub, "LibRangeCheck-3.0", true)
        if ok then rangeLib = lib end
    end
    self.locked = SimpleTargetDistanceDB.locked
    if self.locked == nil then self.locked = true end
    SimpleTargetDistanceDB.locked = self.locked
    self:EnableMouse(not self.locked)
    print("|cff00ff00SimpleTargetDistance|r loaded  /std unlock|lock|reset")
    if UnitExists("target") then
        text:SetText(measure())
        startTicker()
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_SIMPLETARGETDISTANCE1 = "/std"
SlashCmdList["SIMPLETARGETDISTANCE"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$"):lower()
    SimpleTargetDistanceDB = SimpleTargetDistanceDB or {}
    if msg == "lock" then
        frame.locked = true
        SimpleTargetDistanceDB.locked = true
        frame:EnableMouse(false)
        print("STD: locked")
    elseif msg == "unlock" then
        frame.locked = false
        SimpleTargetDistanceDB.locked = false
        frame:EnableMouse(true)
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
