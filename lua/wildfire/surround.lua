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
---@return table|nil {srow, scol, erow, ecol} 1-based vim coordinates
function M.get_inner_range(node)
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
  -- first_end is where content starts, last_start is where content ends
  return {
    first_end_row + 1,
    first_end_col + 1,
    last_start_row + 1,
    last_start_col,  -- 0-based exclusive == 1-based inclusive
  }
end

return M
