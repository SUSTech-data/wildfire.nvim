local api = vim.api

local ts_utils = require("nvim-treesitter.ts_utils")
local locals = require("nvim-treesitter.locals")
local parsers = require("nvim-treesitter.parsers")
local queries = require("nvim-treesitter.query")
local utils = require("wildfire.utils")

local M = {}

---@type table<integer, table<TSNode|nil>>
local selections = {}
local nodes_all = {}

local function inner_node(node, buf)
    local srow, scol, erow, ecol = ts_utils.get_vim_range({ node:range() })
    return utils.unsurround_coordinates(srow, scol, erow, ecol, buf)
end
local function update_selection_by_node(node)
    local buf = api.nvim_get_current_buf()
    local node_has_brackets, current_selction = inner_node(node, buf)
    local local_selections = selections[buf]
    local last_selection = local_selections[#local_selections]
    local use_node = utils.range_match(last_selection, current_selction) or not node_has_brackets
    utils.update_selection(buf, use_node and node or current_selction)
    if use_node then
        table.insert(nodes_all[buf], node)
        table.insert(local_selections, node)
    else
        table.insert(local_selections, current_selction)
    end
end
local function init_by_node(node)
    local buf = api.nvim_get_current_buf()

    selections[buf] = {}
    nodes_all[buf] = {}
    -- utils.update_selection(buf, node)
    update_selection_by_node(node)
    -- if vim.tbl_isempty(nodes_all[buf]) and not vim.tbl_isempty(selections[buf]) then
    -- 	nodes_all[buf] = { node }
    -- end
end
function M.init_selection()
    local node = ts_utils.get_node_at_cursor()
    init_by_node(node)
end

-- Get the range of the current visual selection.
--
-- The range starts with 1 and the ending is inclusive.
---@return integer, integer, integer, integer

---@param get_parent fun(node: TSNode): TSNode|nil
---@return fun():nil
local function select_incremental(get_parent)
    return function()
        local buf = api.nvim_get_current_buf()
        local nodes = nodes_all[buf]

        local csrow, cscol, cerow, cecol = utils.visual_selection_range()
        -- Initialize incremental selection with current selection
        if not nodes or #nodes == 0 then
            local root = parsers.get_parser():parse()[1]:root()
            local node = root:named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
            update_selection_by_node(node)
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

            local larger_range = utils.range_larger({ nsrow, nscol, nerow, necol }, { csrow, cscol, cerow, cecol })

            if larger_range then
                update_selection_by_node(node)
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
    local nodes = nodes_all[buf]
    if not nodes or #nodes < 2 then
        return
    end

    local local_selections = selections[buf]
    table.remove(local_selections)
    local last_selection = local_selections[#local_selections]

    utils.update_selection(buf, last_selection)
    if type(last_selection) ~= "table" then
        table.remove(nodes)
    end
end

function M.visual_inner()
    local buf = api.nvim_get_current_buf()
    local csrow, cscol, cerow, cecol = utils.visual_selection_range()
    local _, srow, scol, erow, ecol = utils.unsurround_coordinates(csrow, cscol, cerow, cecol, buf)
    utils.update_selection(buf, { srow, scol, erow, ecol })
end
return M
