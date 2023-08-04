local api = vim.api

local ts_utils = require("nvim-treesitter.ts_utils")
local locals = require("nvim-treesitter.locals")
local parsers = require("nvim-treesitter.parsers")
local queries = require("nvim-treesitter.query")
local utils = require("wildfire.utils")

local M = {}

---@type table<integer, table<TSNode|nil>>
local selections = {}

local function inner_node(node, buf)
  local srow, scol, erow, ecol = ts_utils.get_vim_range({ node:range() })
  return utils.unsurround_coordinates(srow, scol, erow, ecol, buf)
end

function M.init_selection()
  local buf = api.nvim_get_current_buf()
  local node = ts_utils.get_node_at_cursor()
  local node_has_brackets, srow, scol, erow, ecol = inner_node(node, buf)

  if not node_has_brackets then
    selections[buf] = { [1] = node }
  else
    selections[buf] = {}
  end

  utils.update_selection(buf, { srow, scol, erow, ecol })
end

-- Get the range of the current visual selection.
--
-- The range starts with 1 and the ending is inclusive.
---@return integer, integer, integer, integer
local function visual_selection_range()
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

---@param get_parent fun(node: TSNode): TSNode|nil
---@return fun():nil
local function select_incremental(get_parent)
  return function()
    local buf = api.nvim_get_current_buf()
    local nodes = selections[buf]

    local csrow, cscol, cerow, cecol = visual_selection_range()
    -- Initialize incremental selection with current selection
    if not nodes or #nodes == 0 then
      local root = parsers.get_parser():parse()[1]:root()
      local node = root:named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
      utils.update_selection(buf, node)
      if nodes and #nodes > 0 then
        table.insert(selections[buf], node)
      else
        selections[buf] = { [1] = node }
      end
      return
    end

    -- Find a node that changes the current selection.
    local node = nodes[#nodes] ---@type TSNode
    while true do
      local parent = get_parent(node)
      if not parent or parent == node then
        -- Keep searching in the main tree
        -- TODO: we should search on the parent tree of the current node.
        local root = parsers.get_parser():parse()[1]:root()
        parent = root:named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
        if not parent or root == node or parent == node then
          utils.update_selection(buf, node)
          return
        end
      end
      node = parent
      local nsrow, nscol, nerow, necol = ts_utils.get_vim_range({ node:range() })
      local node_has_brackets, srow, scol, erow, ecol = utils.unsurround_coordinates(nsrow, nscol, nerow, necol, buf)

      local larger_range = utils.range_larger({ srow, scol, erow, ecol }, { csrow, cscol, cerow, cecol })

      if larger_range then
        if not node_has_brackets then
          table.insert(selections[buf], node)
        end
        utils.update_selection(buf, { srow, scol, erow, ecol })
        return
      end

      if not larger_range and utils.range_larger({ nsrow, nscol, nerow, necol }, { csrow, cscol, cerow, cecol }) then
        table.insert(selections[buf], node)
        utils.update_selection(buf, { nsrow, nscol, nerow, necol })
        return
      end
    end
  end
end

M.node_incremental = select_incremental(function(node)
  return node:parent() or node
end)

M.scope_incremental = select_incremental(function(node)
  local lang = parsers.get_buf_lang()
  if queries.has_locals(lang) then
    return locals.containing_scope(node:parent() or node)
  else
    return node
  end
end)

function M.node_decremental()
  local buf = api.nvim_get_current_buf()
  local nodes = selections[buf]
  if not nodes or #nodes < 2 then
    return
  end

  table.remove(selections[buf])
  local node = nodes[#nodes] ---@type TSNode
  utils.update_selection(buf, node)
end

function M.visual_inner()
  local buf = api.nvim_get_current_buf()
  local csrow, cscol, cerow, cecol = visual_selection_range()
  local _, srow, scol, erow, ecol = utils.unsurround_coordinates(csrow, cscol, cerow, cecol, buf)
  utils.update_selection(buf, { srow, scol, erow, ecol })
end
return M
