local api = vim.api

local M = {}

local ESC = api.nvim_replace_termcodes("<Esc>", true, true, true)

local CANDIDATES = {
    "iw", "aw", "iW", "aW",
    'i"', 'a"', "i'", "a'", "i`", "a`",
    "i)", "a)", "i]", "a]", "i}", "a}", "i>", "a>",
    "is", "as", "ip", "ap",
}

--- Execute one text object from (row, col) and return 1-based {sr, sc, er, ec} or nil.
---@param obj string
---@param row integer 1-based
---@param col integer 1-based
---@return integer[]|nil
local function try_textobj(obj, row, col)
    api.nvim_win_set_cursor(0, { row, col - 1 })
    pcall(vim.cmd, "normal! v" .. obj)
    local mode = api.nvim_get_mode().mode
    if mode ~= "v" then
        if mode == "V" or mode == "\22" then
            api.nvim_cmd({ cmd = "normal", bang = true, args = { ESC } }, {})
        end
        return nil
    end
    local s = vim.fn.getpos("v")
    local e = vim.fn.getpos(".")
    api.nvim_cmd({ cmd = "normal", bang = true, args = { ESC } }, {})
    local sr, sc, er, ec = s[2], s[3], e[2], e[3]
    if sr > er or (sr == er and sc > ec) then
        sr, sc, er, ec = er, ec, sr, sc
    end
    return { sr, sc, er, ec }
end

local function strictly_contains(outer, inner)
    local start_ok = outer[1] < inner[1] or (outer[1] == inner[1] and outer[2] <= inner[2])
    local end_ok = outer[3] > inner[3] or (outer[3] == inner[3] and outer[4] >= inner[4])
    local neq = outer[1] ~= inner[1] or outer[2] ~= inner[2] or outer[3] ~= inner[3] or outer[4] ~= inner[4]
    return start_ok and end_ok and neq
end

local function range_size(r)
    return (r[3] - r[1]) * 10000 + (r[4] - r[2])
end

--- Find the smallest text object range strictly larger than the current selection.
---@param _buf integer
---@param sr integer 1-based start row
---@param sc integer 1-based start col
---@param er integer 1-based end row
---@param ec integer 1-based end col
---@return integer[]|nil
function M.expand(_buf, sr, sc, er, ec)
    local current = { sr, sc, er, ec }
    -- Exit visual mode for text object probing
    local mode = api.nvim_get_mode().mode
    if mode == "v" or mode == "V" or mode == "\22" then
        api.nvim_cmd({ cmd = "normal", bang = true, args = { ESC } }, {})
    end

    local best, best_size = nil, math.huge
    for _, obj in ipairs(CANDIDATES) do
        local range = try_textobj(obj, sr, sc)
        if range and strictly_contains(range, current) then
            local s = range_size(range)
            if s < best_size then
                best, best_size = range, s
            end
        end
    end
    return best
end

--- Select initial text object (iw) at current cursor position.
---@return integer[]|nil
function M.init()
    local pos = api.nvim_win_get_cursor(0)
    return try_textobj("iw", pos[1], pos[2] + 1)
end

return M
