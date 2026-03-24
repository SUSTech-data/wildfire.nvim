--- Pluggable checkpoint protocol for selection history.
---
---@class wildfire.Checkpoint
---@field save fun(self, buf: integer, selection: TSNode|integer[])
---@field restore fun(self, buf: integer): TSNode|integer[]|nil
---@field reset fun(self, buf: integer)
---@field selection fun(self, buf: integer): TSNode|integer[]|nil
---@field has_state fun(self, buf: integer): boolean

---@class wildfire.StackCheckpoint: wildfire.Checkpoint
---@field private _trail table<integer, (TSNode|integer[])[]>
local StackCheckpoint = {}
StackCheckpoint.__index = StackCheckpoint

---@return wildfire.StackCheckpoint
function StackCheckpoint.new()
    return setmetatable({ _trail = {} }, StackCheckpoint)
end

function StackCheckpoint:reset(buf)
    self._trail[buf] = {}
end

function StackCheckpoint:save(buf, selection)
    if not self._trail[buf] then
        self._trail[buf] = {}
    end
    table.insert(self._trail[buf], selection)
end

function StackCheckpoint:restore(buf)
    local trail = self._trail[buf]
    if not trail or #trail < 2 then return nil end
    table.remove(trail)
    return trail[#trail]
end

function StackCheckpoint:selection(buf)
    local trail = self._trail[buf]
    return trail and trail[#trail]
end

function StackCheckpoint:has_state(buf)
    local trail = self._trail[buf]
    return trail ~= nil and #trail > 0
end

return { new = StackCheckpoint.new }
