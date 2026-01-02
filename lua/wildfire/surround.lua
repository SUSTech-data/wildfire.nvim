local ts = vim.treesitter

local M = {}

---Check if node is a surround type by examining its children
---A surround node has unnamed (anonymous) nodes as first and last children
---These unnamed nodes are typically delimiters like (, ), {, }, ", ', etc.
---@param node TSNode
---@return boolean
function M.is_surround(node)
  local child_count = node:child_count()
  if child_count < 2 then
    return false
  end

  local first = node:child(0)
  local last = node:child(child_count - 1)

  -- Anonymous nodes are delimiters
  return first and last and not first:named() and not last:named()
end

---Get inner range (excluding delimiter nodes)
---@param node TSNode
---@param buf? integer buffer number (needed for edge case handling)
---@return table|nil {srow, scol, erow, ecol} 1-based vim coordinates
function M.get_inner_range(node, buf)
  local child_count = node:child_count()
  if child_count < 2 then
    return nil
  end

  local first = node:child(0)
  local last = node:child(child_count - 1)

  if not first or not last or first:named() or last:named() then
    return nil
  end

  -- Get the end of first delimiter and start of last delimiter
  local first_end_row, first_end_col = first:end_()
  local last_start_row, last_start_col = last:start()

  -- Convert to 1-based vim coordinates
  local srow = first_end_row + 1
  local scol = first_end_col + 1
  local erow = last_start_row + 1
  local ecol = last_start_col  -- 0-based exclusive == 1-based inclusive

  buf = buf or vim.api.nvim_get_current_buf()

  -- Handle edge case: when first delimiter ends at line end,
  -- content starts at next line's beginning
  local first_line = vim.api.nvim_buf_get_lines(buf, srow - 1, srow, false)[1]
  if first_line and scol > #first_line then
    srow = srow + 1
    scol = 1
  end

  -- Handle edge case: when last delimiter is at line start (col 0),
  -- content ends at previous line's end
  if ecol < 1 and erow > srow then
    erow = erow - 1
    local line = vim.api.nvim_buf_get_lines(buf, erow - 1, erow, false)[1]
    ecol = line and #line or 1
  end

  -- Handle empty content: when delimiters are adjacent (e.g., () or {})
  -- Return nil to indicate no inner content
  if srow > erow or (srow == erow and scol > ecol) then
    return nil
  end

  return { srow, scol, erow, ecol }
end

return M
