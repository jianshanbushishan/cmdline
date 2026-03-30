# cmdline.nvim

一个专注于 Neovim 命令行体验的最小插件，只实现两件事：

- 可自定义、带图标的 cmdline UI
- cmdline 上的 Vim / Lua 语法高亮

灵感来自 [folke/noice.nvim](https://github.com/folke/noice.nvim)，但实现刻意保持轻量，不依赖 `nui.nvim` 或 `nvim-notify`。

## 特性

- 使用 `vim.ui_attach(..., { ext_cmdline = true }, ...)` 接管命令行渲染
- 通过规则匹配不同命令类型，并显示自定义图标/标签
- 对普通 Ex 命令启用 Vim 高亮
- 对 `:lua ...` 命令启用 Lua 高亮
- 支持嵌套 cmdline
- 支持最小的 block cmdline 展示

## 要求

- Neovim >= 0.11，推荐 0.12+
- 想要更好的高亮效果时，建议安装对应 parser：
  - `vim`
  - `lua`

## 安装

`lazy.nvim`

```lua
{
  dir = "D:/private/temp/cmdline",
  config = function()
    require("cmdline").setup()
  end,
}
```

## 默认配置

```lua
require("cmdline").setup({
  enabled = true,
  view = {
    border = "rounded",
    min_width = 40,
    max_width = 0.7,
    padding = { left = 1, right = 1 },
    position = {
      row = "bottom",
      col = "center",
      margin_bottom = 1,
      margin_right = 2,
    },
    winblend = 0,
    zindex = 250,
  },
  icons = {
    cmdline = "",
    lua = "",
    search_down = "",
    search_up = "",
    input = "󰥻",
  },
  formats = {
    {
      name = "lua",
      pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*" },
      icon = "",
      label = "lua",
      lang = "lua",
      trim = {
        content_prefix = "^%s*lua%s*=?%s*",
      },
    },
    {
      name = "search_down",
      pattern = "^/",
      icon = "",
      label = "/",
    },
    {
      name = "search_up",
      pattern = "^%?",
      icon = "",
      label = "?",
    },
    {
      name = "input",
      when = function(ctx)
        return ctx.prompt ~= ""
      end,
      icon = "󰥻",
      label = function(ctx)
        return ctx.prompt
      end,
    },
    {
      name = "cmdline",
      pattern = "^:",
      icon = "",
      label = ":",
      lang = "vim",
    },
  },
})
```

## 自定义示例

```lua
require("cmdline").setup({
  icons = {
    cmdline = ">",
    lua = "lua",
  },
  formats = {
    {
      name = "lua",
      pattern = "^:%s*lua%s+",
      icon = "lua",
      label = "script",
      lang = "lua",
      trim = { content_prefix = "^%s*lua%s*=?%s*" },
    },
    {
      name = "cmdline",
      pattern = "^:",
      icon = ">",
      label = ":",
      lang = "vim",
    },
  },
})
```

## 命令

- `:CmdlineEnable`
- `:CmdlineDisable`
- `:CmdlineToggle`

## 本地 smoke test

```powershell
nvim --clean --headless -u NONE `
  -c "set rtp+=D:/private/temp/cmdline" `
  -c "luafile D:/private/temp/cmdline/tests/smoke.lua"
```
