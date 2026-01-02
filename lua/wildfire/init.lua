local api = vim.api

local keymap = vim.keymap
local utils = require("wildfire.utils")
local surround = require("wildfire.surround")

local M = {}

M.options = {
    keymaps = {
        init_selection = "<CR>",
        node_incremental = "<CR>",
        node_decremental = "<BS>",
    },
    filetype_exclude = { "qf" },
}

---@type table<integer, table<TSNode|nil>>
local selections = {}
local nodes_all = {}
local count = 1

---Get inner coordinates for a surround node
---@param node TSNode
---@param _ integer? buffer (unused, kept for API compatibility)
---@return boolean is_surround
---@return table {srow, scol, erow, ecol} 1-based vim coordinates
function M.unsurround_coordinates(node, _)
    if surround.is_surround(node) then
        return true, surround.get_inner_range(node)
    end
    return false, { utils.get_range(node) }
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
    local node = vim.treesitter.get_node({ ignore_injections = false })
    if not node then
        -- No treesitter node available, try to handle gracefully
        -- Check if treesitter is available for this filetype
        local buf = api.nvim_get_current_buf()
        local ok, parser = pcall(vim.treesitter.get_parser, buf)
        if not ok or not parser then
            -- No parser available for this filetype
            vim.notify("Wildfire: No treesitter parser available for this filetype", vim.log.levels.WARN)
            return
        end
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
            -- Use native vim.treesitter API to get the parser
            local ok, parser = pcall(vim.treesitter.get_parser, buf)
            if not ok or not parser then
                -- No parser available for this filetype, fallback to visual selection
                return
            end
            local tree = parser:parse()[1]
            if not tree then
                return
            end
            local root = tree:root()
            local node = root:named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
            if node then
                update_selection_by_node(node)
            end
            return
        end

        -- Find a node that changes the current selection.
        local node = nodes[#nodes] ---@type TSNode
        while true do
            local parent = get_parent(node)
            if not parent or parent == node then
                -- Search in parent language tree for injected languages
                local ok, parser = pcall(vim.treesitter.get_parser, buf)
                if not ok or not parser then
                    utils.update_selection(buf, node)
                    return
                end

                local range = { csrow - 1, cscol - 1, cerow - 1, cecol }
                local current_lang_tree = parser:language_for_range(range)
                local parent_lang_tree = current_lang_tree and current_lang_tree:parent()

                if parent_lang_tree then
                    local parent_tree = parent_lang_tree:tree_for_range(range)
                    if parent_tree then
                        local root = parent_tree:root()
                        local candidate = root:named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
                        if candidate then
                            local csr, csc, cer, cec = utils.get_range(candidate)
                            local candidate_range = { csr, csc, cer, cec }
                            local current_range = { csrow, cscol, cerow, cecol }

                            if utils.range_larger(candidate_range, current_range)
                                and not utils.range_match(candidate_range, current_range) then
                                parent = candidate
                            else
                                utils.update_selection(buf, node)
                                return
                            end
                        else
                            utils.update_selection(buf, node)
                            return
                        end
                    else
                        utils.update_selection(buf, node)
                        return
                    end
                else
                    utils.update_selection(buf, node)
                    return
                end
            end
            node = parent
            local nsrow, nscol, nerow, necol = utils.get_range(node)

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

    -- Get the treesitter node at the selection range
    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if not ok or not parser then
        return
    end

    local tree = parser:parse()[1]
    if not tree then
        return
    end

    local root = tree:root()
    local node = root:named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
    if not node then
        return
    end

    local is_surround, selection = M.unsurround_coordinates(node, buf)
    if is_surround then
        utils.update_selection(buf, selection)
    end
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
    for funcname, mapping in pairs(M.options.keymaps) do
        local mode, rhs, opts
        opts = { silent = true, noremap = true, desc = FUNCTION_DESCRIPTIONS[funcname] }
        if funcname == "init_selection" then
            mode = "n"
            rhs = M[funcname]
        else
            mode = "x"
            rhs = string.format(":lua require'wildfire'.%s()<CR>", funcname)
        end
        if mapping then
            local augroup_revert = vim.api.nvim_create_augroup("revert" .. mode .. mapping, {})
            keymap.set(mode, mapping, rhs, opts)
            vim.api.nvim_create_autocmd({ "FileType" }, {
                group = augroup_revert,
                pattern = M.options.filetype_exclude,
                desc = "Revert wildfire's keymapping on filetypes",
                callback = function()
                    keymap.set(mode, mapping, mapping, { buffer = true })
                end,
            })
            vim.api.nvim_create_autocmd({ "CmdwinEnter" }, {
                callback = function()
                    keymap.set(mode, mapping, mapping, { buffer = true })
                end,
            })
        end
    end
end

return M
