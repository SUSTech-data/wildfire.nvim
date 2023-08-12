# 🔥Wildfire.nvim: Wildfire burns treesitter🌲

A modern successor to
[wildfire.vim](https://github.com/gcmt/wildfire.vim), empowered with the
superpower of treesitter.

<div>

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<tbody>
<tr class="odd">
<td style="text-align: center;"><div width="100.0%"
data-layout-align="center" data-fig.extended="false">
<p><a href="https://asciinema.org/a/TKD1XZ85IAtN0m5JwlvinRIZP"><img
src="https://asciinema.org/a/TKD1XZ85IAtN0m5JwlvinRIZP.svg"
data-fig.extended="false" /></a></p>
<p>Incremental and decremental selection</p>
</div></td>
</tr>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 50%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr class="odd">
<td style="text-align: center;"><div width="50.0%"
data-layout-align="center">
<p><img src="assets/count.gif" data-fig.extended="false"
alt="Accelerate selection with count prefix" /></p>
</div></td>
<td style="text-align: center;"><div width="50.0%"
data-layout-align="center">
<p><img src="assets/quick.gif" data-fig.extended="false"
alt="Quick selection (leverage by treehopper)" /></p>
</div></td>
</tr>
</tbody>
</table>

</div>

## Highlights

- ⚡ Smartly select the **inner** part of texts
- ⚫ **count prefix**
- 🌳 **Treesitter Integration**

## Motivation

I’ve found that treesitter’s incremental_selection is particularly handy
for text selection. It often allows for selecting the desired text with
fewer keystrokes compared to a well-configured wildfire.vim, all without
the need to set up intricate text objects.

However, since treesitter relies solely on AST for incremental
selection, it tends to be overly aggressive for surrounds. In such case,
I havt to revert to using text objects for selection, which is annoyed
and tripped me up in practical use. On the other hand, treesitter
doesn’t support the ‘count prefix’, which can make it somewhat
cumbersome when dealing with longer ranges.”

## Installation

``` lua
{
    "sustech-data/wildfire.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
        require("wildfire").setup()
    end,
}
```

## Configuration

Currently you can only set unit width surround, refer to the default
settings below.

``` lua
{
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
```

## Roadmap

- [x] init with count prefix
- [ ] Native quick selection support
- [ ] Advanced surround support (Any length)
- [ ] Handle surround in node
