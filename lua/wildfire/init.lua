local api = vim.api
local keymap = vim.keymap
local utils = require("wildfire.utils")
local surround = require("wildfire.surround")
local ts_select = require("vim.treesitter._select")

local M = {}

M.options = {
    keymaps = {
        init_selection = "<CR>",
        node_incremental = "<CR>",
        node_decremental = "<BS>",
    },
    filetype_exclude = { "qf" },
}

---@type wildfire.Checkpoint
local checkpoint = require("wildfire.checkpoint").new()

---@param node TSNode
---@param buf integer?
---@return boolean, integer[]
function M.unsurround_coordinates(node, buf)
    if surround.is_surround(node) then
        local inner = surround.get_inner_range(node, buf)
        if inner then return true, inner end
    end
    return false, { utils.get_range(node) }
end

local function update_selection_by_node(node)
    local buf = api.nvim_get_current_buf()
    local is_surr, inner_range = M.unsurround_coordinates(node, buf)
    local last = checkpoint:selection(buf)
    if is_surr and not utils.range_match(last, inner_range) then
        utils.update_selection(buf, inner_range)
        checkpoint:save(buf, inner_range)
    else
        utils.update_selection(buf, node)
        checkpoint:save(buf, node)
    end
end

--- Find TS node at a 1-based range, searching through language trees
local function find_node_at_range(buf, sr, sc, er, ec)
    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if not ok or not parser then return nil end
    parser:parse({ sr - 1, er })
    local range_0 = { sr - 1, sc - 1, er - 1, ec }
    local lang_tree = parser:language_for_range(range_0)
    if not lang_tree then return nil end
    for _, tree in ipairs(lang_tree:trees()) do
        local node = tree:root():named_descendant_for_range(unpack(range_0))
        if node then return node end
    end
end

function M.init_selection()
    local node = vim.treesitter.get_node({ ignore_injections = false })
    if not node then return end
    local buf = api.nvim_get_current_buf()
    checkpoint:reset(buf)
    update_selection_by_node(node)
    for _ = 1, vim.v.count1 - 1 do
        M.node_incremental()
    end
end

function M.node_incremental()
    local buf = api.nvim_get_current_buf()

    -- Initialize from current visual selection when no prior state
    if not checkpoint:has_state(buf) then
        local csrow, cscol, cerow, cecol = utils.visual_selection_range()
        local ok, parser = pcall(vim.treesitter.get_parser, buf)
        if not ok or not parser then return end
        local tree = parser:parse()[1]
        if not tree then return end
        local node = tree:root():named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
        if node then update_selection_by_node(node) end
        return
    end

    local csrow, cscol, cerow, cecol = utils.visual_selection_range()
    ts_select.select_parent(1)
    local nsr, nsc, ner, nec = utils.visual_selection_range()

    -- No change → at tree root
    if nsr == csrow and nsc == cscol and ner == cerow and nec == cecol then
        return
    end

    local node = find_node_at_range(buf, nsr, nsc, ner, nec)
    if node then
        update_selection_by_node(node)
    else
        utils.update_selection(buf, { nsr, nsc, ner, nec })
        checkpoint:save(buf, { nsr, nsc, ner, nec })
    end
end

function M.node_decremental()
    local buf = api.nvim_get_current_buf()
    local prev = checkpoint:restore(buf)
    if prev then
        utils.update_selection(buf, prev)
    end
end

function M.visual_inner()
    local buf = api.nvim_get_current_buf()
    local csrow, cscol, cerow, cecol = utils.visual_selection_range()
    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if not ok or not parser then return end
    local tree = parser:parse()[1]
    if not tree then return end
    local node = tree:root():named_descendant_for_range(csrow - 1, cscol - 1, cerow - 1, cecol)
    if not node then return end
    local is_surr, selection = M.unsurround_coordinates(node, buf)
    if is_surr then
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
        local mode = funcname == "init_selection" and "n" or "x"
        if mapping then
            local opts = { silent = true, noremap = true, desc = FUNCTION_DESCRIPTIONS[funcname] }
            local augroup = api.nvim_create_augroup("revert" .. mode .. mapping, {})
            keymap.set(mode, mapping, M[funcname], opts)
            api.nvim_create_autocmd({ "FileType" }, {
                group = augroup,
                pattern = M.options.filetype_exclude,
                callback = function()
                    keymap.set(mode, mapping, mapping, { buffer = true })
                end,
            })
            api.nvim_create_autocmd({ "CmdwinEnter" }, {
                callback = function()
                    keymap.set(mode, mapping, mapping, { buffer = true })
                end,
            })
        end
    end
end

return M
