# cmdline.nvim

`cmdline.nvim` replaces Neovim's built-in command line with a floating popup that supports:

- command kind icons
- per-command popup styles
- syntax highlighting with Treesitter fallback
- zero external UI dependencies

This project is extracted from the cmdline experience in `noice.nvim`, but kept intentionally small and standalone.

## Features

- Native floating windows via `nvim_open_win`
- Configurable views for `:`, `/`, `?`, `input()`, and custom patterns
- Popup border titles and kind-specific highlights
- Treesitter highlighting when a parser exists
- Vim syntax fallback when Treesitter is unavailable
- No `nui.nvim`, no `plenary.nvim`

## Requirements

- Neovim `0.9+`
- Neovim `0.10+` is recommended
- Neovim `0.11+` gets the cleanest cursor/redraw behavior

## Installation

With `lazy.nvim`:

```lua
{
  "your-name/cmdline.nvim",
  config = function()
    require("cmdline").setup()
  end,
}
```

With `vim.pack` or a manual runtimepath setup:

```lua
require("cmdline").setup()
```

The plugin file only sets a load guard. The UI is enabled when `setup()` is called.

## Default Configuration

```lua
require("cmdline").setup({
  enabled = true,
  view = "cmdline_popup",
  opts = {},
  format = {
    cmdline = { pattern = "^:", icon = "", lang = "vim" },
    search_down = { kind = "search", pattern = "^/", icon = " ", lang = "regex" },
    search_up = { kind = "search", pattern = "^%?", icon = " ", lang = "regex" },
    filter = { pattern = "^:%s*!", icon = "$", lang = "bash" },
    lua = {
      pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" },
      icon = "",
      lang = "lua",
    },
    help = { pattern = "^:%s*he?l?p?%s+", icon = "" },
    calculator = { pattern = "^=", icon = "", lang = "vimnormal" },
    input = { view = "cmdline_input", icon = "󰥻 " },
  },
  views = {},
})
```

## Configuration Model

There are three top-level knobs:

- `view`: the default view name used by formats
- `format`: pattern-based cmdline classifiers
- `views`: named popup view definitions and aliases

### Example

```lua
require("cmdline").setup({
  view = "cmdline_popup",
  views = {
    cmdline_popup = {
      position = {
        row = "15%",
        col = "50%",
      },
      size = {
        min_width = 50,
        max_width = 90,
      },
    },
    cmdline_input = {
      view = "cmdline_popup",
      border = {
        style = "double",
        padding = { 0, 1 },
      },
    },
  },
  format = {
    lua = {
      icon = "Lua",
      title = " Lua ",
    },
    search_down = {
      icon = "Find",
    },
  },
})
```

## Custom Formats

Each format entry can define:

- `pattern`: string or string array
- `kind`: highlight family name
- `view`: target view name
- `icon`: prefix icon
- `title`: border title
- `lang`: Treesitter or syntax language
- `conceal`: hide the matched prefix from the rendered body
- `opts`: extra popup overrides merged into the resolved view

Example:

```lua
require("cmdline").setup({
  format = {
    git = {
      pattern = "^:%s*!git%s+",
      icon = "Git",
      title = " Shell ",
      lang = "bash",
    },
  },
})
```

## Views

Built-in views:

- `cmdline_popup`
- `cmdline`
- `cmdline_input`

`cmdline_input` is an alias view that inherits from `cmdline_popup`.

Supported popup options are based on the current native implementation in `lua/cmdline/popup.lua`:

- `relative`
- `focusable`
- `enter`
- `zindex`
- `position`
- `size`
- `border`
- `win_options`
- `buf_options`

`position.row` and `position.col` support numbers and percentage strings like `"50%"`.
`size.width` and `size.height` support numbers and `"auto"`.

## Highlights

Base highlight groups:

- `Cmdline`
- `CmdlineIcon`
- `CmdlinePrompt`
- `CmdlinePopup`
- `CmdlinePopupBorder`
- `CmdlinePopupTitle`
- `CmdlineCursor`

Kind-specific groups are generated automatically, for example:

- `CmdlineIconSearch`
- `CmdlinePopupBorderSearch`
- `CmdlinePopupTitleSearch`

Override them in your colorscheme or after `setup()`:

```lua
vim.api.nvim_set_hl(0, "CmdlinePopupBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "CmdlineIconSearch", { fg = "#e5c07b" })
```

## API

```lua
local cmdline = require("cmdline")

cmdline.setup(opts)
cmdline.enable()
cmdline.disable()
```

Typical usage only needs `setup()`.

## Manual Verification

Minimal headless load check:

```bash
nvim --headless -u NONE -i NONE -n \
  -c "set rtp+=/path/to/cmdline.nvim" \
  -c "lua require('cmdline').setup({ enabled = false })" \
  -c "quit"
```

Smoke script in this repository:

```bash
nvim --headless -u NONE -i NONE -n -S tests/smoke.lua
```

## Notes

- `cmdline_block_*` events are currently accepted but intentionally ignored.
- The implementation assumes a single visible cmdline flow and does not try to present stacked nested cmdlines.
- Older Neovim versions may need extra redraw work during substitute preview.
