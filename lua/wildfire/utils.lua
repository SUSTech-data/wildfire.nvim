local api = vim.api

local ts = vim.treesitter

local M = {}
function M.get_range(node_or_range)
    local start_row, start_col, end_row, end_col ---@type integer, integer, integer, integer
    if type(node_or_range) == "table" then
        start_row, start_col, end_row, end_col = unpack(node_or_range)
    else
        start_row, start_col, end_row, end_col = ts.get_node_range(node_or_range)
        -- Convert 0-based to 1-based indexing to match vim coordinates
        -- Note: treesitter end_col is exclusive, but vim coordinates are inclusive
        start_row = start_row + 1
        start_col = start_col + 1
        end_row = end_row + 1
        -- end_col is already exclusive in treesitter (0-based), converting to 1-based inclusive means no change needed
        -- because: 0-based exclusive position == 1-based inclusive position
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
    local node_text
    if type(node_or_range) == "table" then
        local srow, scol, erow, ecol
        srow, scol, erow, ecol = unpack(node_or_range)
        local lines = vim.api.nvim_buf_get_text(bufnr, srow - 1, scol - 1, erow - 1, ecol, {})
        node_text = table.concat(lines, "\n")
    else
        node_text = vim.treesitter.get_node_text(node_or_range, bufnr)
    end
    print(node_text)
end

function M.update_selection(buf, node_or_range, selection_mode)
    local start_row, start_col, end_row, end_col

    if type(node_or_range) == "table" then
        start_row, start_col, end_row, end_col = unpack(node_or_range)
    else
        start_row, start_col, end_row, end_col = ts.get_node_range(node_or_range)
        -- Convert 0-based to 1-based indexing to match vim coordinates
        -- Note: treesitter end_col is exclusive, but vim coordinates are inclusive
        start_row = start_row + 1
        start_col = start_col + 1
        end_row = end_row + 1
        -- end_col is already exclusive in treesitter (0-based), converting to 1-based inclusive means no change needed
        -- because: 0-based exclusive position == 1-based inclusive position
    end

    -- Validate buffer bounds to prevent cursor position errors
    local line_count = api.nvim_buf_line_count(buf)
    if start_row < 1 or end_row < 1 or start_row > line_count or end_row > line_count then
        -- Invalid row range, cannot update selection
        return
    end

    -- Validate column bounds
    if start_col < 1 or end_col < 0 then
        -- Invalid column range, cannot update selection
        return
    end

    -- Get the actual line lengths to validate column positions
    local start_line_text = api.nvim_buf_get_lines(buf, start_row - 1, start_row, false)[1] or ""
    local end_line_text = api.nvim_buf_get_lines(buf, end_row - 1, end_row, false)[1] or ""
    local start_line_len = #start_line_text
    local end_line_len = #end_line_text

    -- Clamp column positions to valid ranges (0-indexed for nvim_win_set_cursor)
    start_col = math.max(0, math.min(start_col - 1, start_line_len))
    end_col = math.max(0, math.min(end_col - 1, end_line_len))

    local v_table = { charwise = "v", linewise = "V", blockwise = "<C-v>" }
    selection_mode = selection_mode or "charwise"

    -- Normalise selection_mode
    if v_table[selection_mode] then
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

    api.nvim_win_set_cursor(0, { start_row, start_col })
    vim.cmd("normal! o")
    api.nvim_win_set_cursor(0, { end_row, end_col })
end
return M
