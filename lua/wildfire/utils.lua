local api = vim.api

local ts_utils = require("nvim-treesitter.ts_utils")
local ts = vim.treesitter

local M = {}
function M.get_range(node_or_range)
    local start_row, start_col, end_row, end_col ---@type integer, integer, integer, integer
    if type(node_or_range) == "table" then
        start_row, start_col, end_row, end_col = unpack(node_or_range)
    else
        local buf = api.nvim_get_current_buf()
        start_row, start_col, end_row, end_col = ts_utils.get_vim_range({ ts.get_node_range(node_or_range) }, buf)
    end
    return start_row, start_col, end_row, end_col ---@type integer, integer, integer, integer
end

function M.visual_selection_range()
    local _, csrow, cscol, _ = unpack(vim.fn.getpos("'<")) ---@type integer, integer, integer, integer
    local _, cerow, cecol, _ = unpack(vim.fn.getpos("'>")) ---@type integer, integer, integer, integer

    local start_row, start_col, end_row, end_col ---@type integer, integer, integer, integer

    if csrow < cerow or (csrow == cerow and cscol <= cecol) then
        start_row = csrow
        start_col = cscol
        end_row = cerow
        end_col = cecol
    else
        start_row = cerow
        start_col = cecol
        end_row = csrow
        end_col = cscol
    end

    return start_row, start_col, end_row, end_col
end
function M.range_larger(range1, range2)
    local srow1, scol1, erow1, ecol1 = M.get_range(range1)
    local srow2, scol2, erow2, ecol2 = M.get_range(range2)
    if srow1 < srow2 then
        return true
    elseif srow1 == srow2 and scol1 < scol2 then
        return true
    elseif erow1 > erow2 then
        return true
    elseif erow1 == erow2 and ecol1 > ecol2 then
        return true
    else
        return false
    end
end

function M.range_match(range1, range2)
    if range1 == nil or range2 == nil then
        return false
    end

    local srow1, scol1, erow1, ecol1 = M.get_range(range1)
    local srow2, scol2, erow2, ecol2 = M.get_range(range2)
    return srow1 == srow2 and scol1 == scol2 and erow1 == erow2 and ecol1 == ecol2
end

function M.print_selection(node_or_range)
    local bufnr = api.nvim_get_current_buf()
    local lines
    if type(node_or_range) == "table" then
        local srow, scol, erow, ecol
        srow, scol, erow, ecol = unpack(node_or_range)
        lines = vim.api.nvim_buf_get_text(bufnr, srow - 1, scol - 1, erow - 1, ecol, {})
    else
        lines = ts_utils.get_node_text(node_or_range, bufnr)
    end
    local node_text = table.concat(lines, "\n")
    print(node_text)
end

function M.update_selection(buf, node_or_range, selection_mode)
    local start_row, start_col, end_row, end_col

    if type(node_or_range) == "table" then
        start_row, start_col, end_row, end_col = unpack(node_or_range)
    else
        start_row, start_col, end_row, end_col = ts_utils.get_vim_range({ ts.get_node_range(node_or_range) }, buf)
    end

    local v_table = { charwise = "v", linewise = "V", blockwise = "<C-v>" }
    selection_mode = selection_mode or "charwise"

    -- Normalise selection_mode
    if vim.tbl_contains(vim.tbl_keys(v_table), selection_mode) then
        selection_mode = v_table[selection_mode]
    end

    -- enter visual mode if normal or operator-pending (no) mode
    -- Why? According to https://learnvimscriptthehardway.stevelosh.com/chapters/15.html
    --   If your operator-pending mapping ends with some text visually selected, Vim will operate on that text.
    --   Otherwise, Vim will operate on the text between the original cursor position and the new position.
    local mode = api.nvim_get_mode()
    if mode.mode ~= selection_mode then
        -- Call to `nvim_replace_termcodes()` is needed for sending appropriate command to enter blockwise mode
        selection_mode = vim.api.nvim_replace_termcodes(selection_mode, true, true, true)
        api.nvim_cmd({ cmd = "normal", bang = true, args = { selection_mode } }, {})
    end

    api.nvim_win_set_cursor(0, { start_row, start_col - 1 })
    vim.cmd("normal! o")
    api.nvim_win_set_cursor(0, { end_row, end_col - 1 })
end
function M.unsurround_coordinates(srow, scol, erow, ecol, buf)
    -- local lines = vim.split(s, "\n")
    local lines = vim.api.nvim_buf_get_text(buf, srow - 1, scol - 1, erow - 1, ecol, {})
    local node_text = table.concat(lines, "\n")
    local match_brackets = string.match(node_text, "^%b{}$")
        or string.match(node_text, "^%b()$")
        or string.match(node_text, "^%b[]$")
    if match_brackets == nil then
        return false, { srow, scol, erow, ecol }
    end
    lines[1] = lines[1]:sub(2)
    local nsrow, nscol = 0, 0
    for index, line in ipairs(lines) do
        if line:match("%S") then
            nsrow = index
            nscol = line:len() - line:match("^%s*(.*)"):len()
            break
        end
    end

    lines[#lines] = lines[#lines]:sub(1, -2)
    local nerow, necol = #lines, 0
    for index = #lines, 1, -1 do
        local line = lines[index]
        if line:match("%S") then
            nerow = index
            necol = line:len() - line:match("^(.*%S)%s*$"):len()
            break
        end
    end

    nsrow = srow + nsrow - 1
    nscol = nsrow == srow and scol + nscol + 1 or nscol + 1
    -- nerow = erow - nerow + 1
    nerow = srow + nerow - 1
    necol = nerow == erow and ecol - necol - 1 or lines[nerow - srow + 1]:len() - necol

    return true, { nsrow, nscol, nerow, necol }
end
return M
