local api = vim.api

local ts_utils = require("nvim-treesitter.ts_utils")
local parsers = require("nvim-treesitter.parsers")
local utils = require("wildfire.utils")

local M = {}

M.options = {
    surrounds = {
        { "(", ")" },
        { "{", "}" },
        { "<", ">" },
        { "[", "]" },
    },
    keymaps = {
        init_selection = "<CR>",
        node_incremental = "<CR>",
        node_decremental = "<BS>",
    },
}

---@type table<integer, table<TSNode|nil>>
local selections = {}
local nodes_all = {}
local count = 1

function M.unsurround_coordinates(node_or_range, buf)
    -- local lines = vim.split(s, "\n")
    local srow, scol, erow, ecol = utils.get_range(node_or_range)
    local lines = vim.api.nvim_buf_get_text(buf, srow - 1, scol - 1, erow - 1, ecol, {})
    local node_text = table.concat(lines, "\n")
    local match_brackets = nil
    for _, pair in ipairs(M.options.surrounds) do
        local pattern = "^%" .. pair[1] .. ".*%" .. pair[2] .. "$"
        match_brackets = string.match(node_text, pattern)
        if match_brackets then
            break
        end
    end
    -- local match_brackets = string.match(node_text, "^%b{}$")
    --     or string.match(node_text, "^%b()$")
    --     or string.match(node_text, "^%b[]$")
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
local function update_selection_by_node(node)
    local buf = api.nvim_get_current_buf()
    local node_has_brackets, current_selction = M.unsurround_coordinates(node, buf)
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
    count = vim.v.count1
    local node = ts_utils.get_node_at_cursor()
    if not node then
      return
    end
    init_by_node(node)
    if count > 1 then
        for i = 1, count - 1 do
            M.node_incremental()
        end
    end
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
        local csrow, cscol, cerow, cecol
        if count <= 1 then
            csrow, cscol, cerow, cecol = utils.visual_selection_range()
        else
            csrow, cscol, cerow, cecol = utils.get_range(selections[buf][#selections[buf]])
        end

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
    local _, selection = M.unsurround_coordinates({ csrow, cscol, cerow, cecol }, buf)
    utils.update_selection(buf, selection)
end

local FUNCTION_DESCRIPTIONS = {
    init_selection = "Start selecting nodes with nvim-treesitter",
    node_incremental = "Increment selection to named node",
    node_decremental = "Shrink selection to previous named node",
}
function M.setup(options)
    if type(options) == "table" then
        M.options = vim.tbl_deep_extend("force", M.options, options)
    end
    local mode, rhs
    for funcname, mapping in pairs(M.options.keymaps) do
        if funcname == "init_selection" then
            mode = "n"
            rhs = M[funcname]
        else
            mode = "x"
            rhs = string.format(":lua require'wildfire'.%s()<CR>", funcname)
        end
        if mapping then
            vim.keymap.set(
                mode,
                mapping,
                rhs,
                { silent = true, noremap = true, desc = FUNCTION_DESCRIPTIONS[funcname] }
            )
        end
    end
end

return M
