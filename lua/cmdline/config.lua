--- Configuration for cmdline.nvim
--- Adapted from noice.nvim's config/init.lua, config/views.lua, config/highlights.lua, config/cmdline.lua
local Util = require("cmdline.util")

local M = {}

M.ns = vim.api.nvim_create_namespace("cmdline")

---@class CmdlineFormat
---@field name string
---@field kind string
---@field pattern? string|string[]
---@field view string
---@field conceal? boolean
---@field icon? string
---@field icon_hl_group? string
---@field opts? table
---@field title? string
---@field lang? string

---@class CmdlineConfig
---@field enabled boolean
---@field view string
---@field opts table
---@field format table<string, CmdlineFormat>
---@field views table<string, table>

---@type CmdlineConfig
M.options = {}

function M.defaults()
  return {
    enabled = true,
    view = "cmdline_popup",
    opts = {},
    ---@type table<string, CmdlineFormat>
    format = {
      cmdline = { pattern = "^:", icon = "", lang = "vim" },
      search_down = { kind = "search", pattern = "^/", icon = " ", lang = "regex" },
      search_up = { kind = "search", pattern = "^%?", icon = " ", lang = "regex" },
      filter = { pattern = "^:%s*!", icon = "$", lang = "bash" },
      lua = { pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" }, icon = "", lang = "lua" },
      help = { pattern = "^:%s*he?l?p?%s+", icon = "" },
      calculator = { pattern = "^=", icon = "", lang = "vimnormal" },
      input = { view = "cmdline_input", icon = "󰥻 " },
    },
    views = {},
  }
end

--- Default view definitions
M.default_views = {
  cmdline_popup = {
    backend = "popup",
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
  cmdline = {
    backend = "popup",
    relative = "editor",
    position = {
      row = "100%",
      col = 0,
    },
    size = {
      height = "auto",
      width = "100%",
    },
    border = {
      style = "none",
    },
    win_options = {
      winhighlight = {
        Normal = "Cmdline",
        IncSearch = "",
        CurSearch = "",
        Search = "",
      },
    },
  },
  cmdline_input = {
    view = "cmdline_popup",
    border = {
      style = "rounded",
      padding = { 0, 1 },
    },
  },
}

--- Highlight group definitions
---@type table<string, string>
M.highlights = {
  Cmdline = "MsgArea",
  CmdlineIcon = "DiagnosticSignInfo",
  CmdlineIconSearch = "DiagnosticSignWarn",
  CmdlinePrompt = "Title",
  CmdlinePopup = "Normal",
  CmdlinePopupBorder = "DiagnosticSignInfo",
  CmdlinePopupTitle = "DiagnosticSignInfo",
  CmdlinePopupBorderSearch = "DiagnosticSignWarn",
  CmdlineCursor = "Cursor",
}

---@param hl_group string
---@param link string
function M.add_highlight(hl_group, link)
  if not M.highlights[hl_group] then
    M.highlights[hl_group] = link
  end
end

--- Setup highlight groups
function M.setup_highlights()
  for hl, link in pairs(M.highlights) do
    if link ~= "none" then
      vim.api.nvim_set_hl(0, hl, { link = link, default = true })
    end
  end
  vim.api.nvim_set_hl(0, "CmdlineHiddenCursor", { blend = 100, nocombine = true })
end

--- Setup cmdline format entries with highlight groups and view options
function M.setup_formats()
  local formats = M.options.format
  for name, format in pairs(formats) do
    if format == false then
      formats[name] = nil
    else
      local kind = format.kind or name
      local kind_cc = kind:sub(1, 1):upper() .. kind:sub(2)

      -- Create per-kind highlight groups
      local hl_group_icon = "CmdlineIcon" .. kind_cc
      M.add_highlight(hl_group_icon, "CmdlineIcon")

      local hl_group_border = "CmdlinePopupBorder" .. kind_cc
      M.add_highlight(hl_group_border, "CmdlinePopupBorder")

      local hl_group_title = "CmdlinePopupTitle" .. kind_cc
      M.add_highlight(hl_group_title, hl_group_border)

      -- Extend format with computed fields
      format = vim.tbl_deep_extend("force", {
        name = name,
        conceal = format.conceal ~= false,
        kind = name,
        icon_hl_group = hl_group_icon,
        view = M.options.view,
        lang = format.lang,
        opts = {
          border = {
            text = {
              top = format.title or (" " .. kind_cc .. " "),
            },
          },
          win_options = {
            winhighlight = {
              FloatBorder = hl_group_border,
              FloatTitle = hl_group_title,
            },
          },
        },
      }, { opts = vim.deepcopy(M.options.opts) }, format)
      formats[name] = format
    end
  end
end

--- Get resolved view options for a given view name
---@param view string view name
---@return table
function M.get_view_options(view)
  local opts = { view = view }

  local done = {}
  while opts.view and not done[opts.view] do
    done[opts.view] = true
    local view_opts = vim.deepcopy(M.options.views[opts.view] or M.default_views[opts.view] or {})
    opts = vim.tbl_deep_extend("keep", opts, view_opts)
    opts.view = view_opts.view -- follow view aliases (e.g., cmdline_input -> cmdline_popup)
  end

  return opts
end

---@param opts? CmdlineConfig
function M.setup(opts)
  opts = opts or {}

  -- Guard: if already configured, merge new opts into existing options
  -- instead of resetting to defaults (preserves user config on re-setup)
  if M._setup_done then
    M.options = vim.tbl_deep_extend("force", M.options, opts)
    M.setup_formats()
    M.setup_highlights()
    return
  end
  M._setup_done = true

  M.options = vim.tbl_deep_extend("force", {}, M.defaults(), {
    views = vim.deepcopy(M.default_views),
  })
  M.options = vim.tbl_deep_extend("force", M.options, opts)

  M.setup_formats()
  M.setup_highlights()

  -- Re-setup highlights on colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("cmdline_highlights", { clear = true }),
    callback = function()
      M.setup_highlights()
    end,
  })
end

return M
