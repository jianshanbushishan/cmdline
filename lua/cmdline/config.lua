--- Configuration for cmdline.nvim
local M = {}

M.ns = vim.api.nvim_create_namespace("cmdline")

---@alias CmdlineKind "cmdline"|"search"

---@class CmdlineIcons
---@field cmdline string
---@field search_down string
---@field search_up string

---@class CmdlineConfig
---@field enabled boolean
---@field icons CmdlineIcons
---@field popup table

---@type CmdlineConfig
M.options = {}

M.default_popup = {
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
}

---@type table<string, string>
M.highlights = {
  CmdlineIcon = "DiagnosticSignInfo",
  CmdlineIconSearch = "DiagnosticSignWarn",
  CmdlinePrompt = "Title",
  CmdlinePopup = "Normal",
  CmdlinePopupBorder = "DiagnosticSignInfo",
  CmdlinePopupTitle = "DiagnosticSignInfo",
  CmdlinePopupBorderSearch = "DiagnosticSignWarn",
  CmdlinePopupTitleSearch = "DiagnosticSignWarn",
  CmdlineCursor = "Cursor",
}

function M.defaults()
  return {
    enabled = true,
    icons = {
      cmdline = "",
      search_down = " ",
      search_up = " ",
    },
    popup = vim.deepcopy(M.default_popup),
  }
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

--- Get popup options for the requested cmdline kind
---@param kind CmdlineKind
---@return table
function M.get_popup_options(kind)
  local opts = vim.deepcopy(M.options.popup)
  local border_hl = kind == "search" and "CmdlinePopupBorderSearch" or "CmdlinePopupBorder"
  local title_hl = kind == "search" and "CmdlinePopupTitleSearch" or "CmdlinePopupTitle"

  opts.win_options = opts.win_options or {}
  if type(opts.win_options.winhighlight) == "table" then
    opts.win_options.winhighlight = vim.tbl_deep_extend("force", opts.win_options.winhighlight, {
      FloatBorder = border_hl,
      FloatTitle = title_hl,
    })
  end

  return opts
end

---@param opts? CmdlineConfig
function M.setup(opts)
  opts = opts or {}

  if M._setup_done then
    M.options = vim.tbl_deep_extend("force", M.options, opts)
    M.setup_highlights()
    return
  end
  M._setup_done = true

  M.options = vim.tbl_deep_extend("force", {}, M.defaults(), opts)
  M.setup_highlights()

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("cmdline_highlights", { clear = true }),
    callback = function()
      M.setup_highlights()
    end,
  })
end

return M
