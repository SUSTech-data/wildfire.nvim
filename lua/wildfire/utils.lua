local api = vim.api
local ts = vim.treesitter

local M = {}

function M.get_range(node_or_range)
    if type(node_or_range) == "table" then
        return unpack(node_or_range)
    end
    local sr, sc, er, ec = ts.get_node_range(node_or_range)
    -- 0-based → 1-based; end_col exclusive→inclusive cancels out
    return sr + 1, sc + 1, er + 1, ec
end

function M.visual_selection_range()
    local mode = api.nvim_get_mode().mode
    local pos1, pos2
    if mode == "v" or mode == "V" or mode == "\22" then
        pos1 = vim.fn.getpos("v")
        pos2 = vim.fn.getpos(".")
    else
        pos1 = vim.fn.getpos("'<")
        pos2 = vim.fn.getpos("'>")
    end
    local sr, sc, er, ec = pos1[2], pos1[3], pos2[2], pos2[3]
    if sr > er or (sr == er and sc > ec) then
        return er, ec, sr, sc
    end
    return sr, sc, er, ec
end

function M.range_larger(range1, range2)
    local sr1, sc1, er1, ec1 = M.get_range(range1)
    local sr2, sc2, er2, ec2 = M.get_range(range2)
    if sr1 < sr2 then return true end
    if sr1 == sr2 and sc1 < sc2 then return true end
    if er1 > er2 then return true end
    if er1 == er2 and ec1 > ec2 then return true end
    return false
end

function M.range_match(range1, range2)
    if range1 == nil or range2 == nil then return false end
    local sr1, sc1, er1, ec1 = M.get_range(range1)
    local sr2, sc2, er2, ec2 = M.get_range(range2)
    return sr1 == sr2 and sc1 == sc2 and er1 == er2 and ec1 == ec2
end

function M.update_selection(buf, node_or_range, selection_mode)
    local start_row, start_col, end_row, end_col = M.get_range(node_or_range)

    local line_count = api.nvim_buf_line_count(buf)
    if start_row < 1 or end_row < 1 or start_row > line_count or end_row > line_count then
        return
    end
    if start_col < 1 or end_col < 0 then
        return
    end

    local start_line = api.nvim_buf_get_lines(buf, start_row - 1, start_row, false)[1] or ""
    local end_line = api.nvim_buf_get_lines(buf, end_row - 1, end_row, false)[1] or ""

    -- 1-based → 0-based for nvim_win_set_cursor, clamped to line length
    start_col = math.max(0, math.min(start_col - 1, #start_line))
    end_col = math.max(0, math.min(end_col - 1, #end_line))

    local v_table = { charwise = "v", linewise = "V", blockwise = "<C-v>" }
    selection_mode = v_table[selection_mode or "charwise"] or selection_mode

    local mode = api.nvim_get_mode()
    if mode.mode ~= selection_mode then
        selection_mode = api.nvim_replace_termcodes(selection_mode, true, true, true)
        api.nvim_cmd({ cmd = "normal", bang = true, args = { selection_mode } }, {})
    end

    api.nvim_win_set_cursor(0, { start_row, start_col })
    vim.cmd("normal! o")
    api.nvim_win_set_cursor(0, { end_row, end_col })
end

return M
