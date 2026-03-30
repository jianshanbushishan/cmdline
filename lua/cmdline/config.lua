local M = {}

M.defaults = {
  enabled = true,
  view = {
    border = "rounded",
    min_width = 40,
    max_width = 0.7,
    padding = {
      left = 1,
      right = 1,
    },
    position = {
      row = "bottom",
      col = "center",
      margin_bottom = 1,
      margin_right = 2,
    },
    winblend = 0,
    zindex = 250,
  },
  highlight = {
    normal = "CmdlinePopup",
    border = "CmdlineBorder",
    icon = "CmdlineIcon",
    label = "CmdlinePrompt",
    cursor = "CmdlineCursor",
    block = "CmdlineBlock",
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
}

function M.normalize(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})

  if opts and opts.formats then
    config.formats = opts.formats
  end

  for _, format in ipairs(config.formats or {}) do
    if not format.icon and format.name and config.icons[format.name] then
      format.icon = config.icons[format.name]
    end
  end

  return config
end

return M
