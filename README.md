# cmdline.nvim

`cmdline.nvim` 用一个浮动窗口替换 Neovim 内置命令行，专注提供一件事：更清晰地展示命令和搜索。

这个项目提取自 `noice.nvim` 的 cmdline 体验，但实现上保持独立、轻量、零外部依赖。

## 特性

- 基于 `nvim_open_win` 的原生浮动窗口
- 主要区分两类场景：命令行 `:` 和搜索 `/`、`?`
- 命令默认使用 Vim 语法高亮，搜索使用 regex 高亮
- 内置一个最小化的 `:lua` 特判，保留 Lua 输入体验
- 有 Treesitter parser 时优先使用 Treesitter，高亮不可用时回退到 Vim syntax
- 不依赖 `nui.nvim`
- 不依赖 `plenary.nvim`

除 `/`、`?` 和内置的 `:lua` 特判外，其余 cmdline 事件都会按普通命令样式渲染，不再提供按 pattern 扩展格式、切换视图别名或为特定命令单独定制样式的能力。

## 要求

- 推荐 Neovim `0.11+`
- Neovim `0.11+` 的光标与 redraw 行为最稳定

## 安装

`lazy.nvim` 示例：

```lua
{
  "jianshanbushishan/cmdline.nvim",
  config = function()
    require("cmdline").setup()
  end,
}
```

## 默认配置

```lua
require("cmdline").setup({
  enabled = true,
  icons = {
    cmdline = "",
    search_down = " ",
    search_up = " ",
  },
  popup = {
    relative = "editor",
    focusable = false,
    enter = false,
    zindex = 200,
    position = {
      row = "20%",
      col = "50%",
    },
    size = {
      min_width = 60,
      width = "auto",
      height = "auto",
    },
    border = {
      style = "rounded",
      padding = { 0, 1 },
    },
    win_options = {
      winhighlight = {
        Normal = "CmdlinePopup",
        FloatTitle = "CmdlinePopupTitle",
        FloatBorder = "CmdlinePopupBorder",
        IncSearch = "",
        CurSearch = "",
        Search = "",
      },
      winbar = "",
      foldenable = false,
      cursorline = false,
    },
  },
})
```

## 配置说明

当前只保留两组顶层配置：

- `icons`：命令、向下搜索、向上搜索的前缀图标
- `popup`：浮动窗口布局与窗口选项

示例：

```lua
require("cmdline").setup({
  icons = {
    cmdline = ">",
    search_down = "/",
    search_up = "?",
  },
  popup = {
    position = {
      row = "15%",
      col = "50%",
    },
    size = {
      min_width = 50,
      max_width = 90,
    },
    border = {
      style = "double",
      padding = { 0, 1 },
    },
  },
})
```

`popup` 支持的主要选项见 `lua/cmdline/popup.lua`：

- `relative`
- `focusable`
- `enter`
- `zindex`
- `position`
- `size`
- `border`
- `win_options`
- `buf_options`

补充说明：

- `position.row` 和 `position.col` 支持数字，也支持 `"50%"` 这类百分比字符串
- `size.width` 和 `size.height` 支持数字，也支持 `"auto"`

## 内置特判

为了保留常用体验，当前实现只额外内置了一条 Lua 规则，不对外开放扩展配置：

- `:lua ...`
- `:lua = ...`
- `:= ...`

命中后会隐藏前缀，并对后续内容使用 Lua 语法高亮。

## 高亮组

- `CmdlineIcon`
- `CmdlineIconSearch`
- `CmdlinePrompt`
- `CmdlinePopup`
- `CmdlinePopupBorder`
- `CmdlinePopupTitle`
- `CmdlinePopupBorderSearch`
- `CmdlinePopupTitleSearch`
- `CmdlineCursor`

可以在 colorscheme 中，或者 `setup()` 之后覆盖它们：

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

一般情况下只需要调用 `setup()`。

## 手动验证

最小 headless 加载检查：

```bash
nvim --headless -u NONE -i NONE -n \
  -c "set rtp+=/path/to/cmdline.nvim" \
  -c "lua require('cmdline').setup({ enabled = false })" \
  -c "quit"
```

仓库内自带的 smoke 脚本：

```bash
nvim --headless -u NONE -i NONE -n -S tests/smoke.lua
```

## 说明

- `cmdline_block_*` 事件当前仍会被接收，但实现上刻意忽略
- 当前实现按“单一可见 cmdline 流”设计，不处理堆叠式多层 cmdline 展示
- 在较老版本的 Neovim 上，替换/预览场景可能仍需要额外 redraw 才能保持光标同步
