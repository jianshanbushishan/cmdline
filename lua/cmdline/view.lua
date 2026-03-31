--- Popup view for cmdline.nvim
local Config = require("cmdline.config")
local Popup = require("cmdline.popup")
local Util = require("cmdline.util")

local M = {}

---@class CmdlineView
---@field _popup? CmdlinePopup
---@field _visible boolean
---@field _loading boolean
---@field _opts table
local View = {}
View.__index = View

--- Create a new view
---@param opts? table view options
---@return CmdlineView
function View.new(opts)
  local self = setmetatable({}, View)
  self._opts = opts or {}
  self._visible = false
  self._loading = false
  return self
end

--- Check if the popup is mounted and valid
---@return boolean
function View:is_mounted()
  if not self._popup then
    return false
  end
  if self._popup.bufnr and not vim.api.nvim_buf_is_valid(self._popup.bufnr) then
    self._popup.bufnr = nil
  end
  if self._popup.winid and not vim.api.nvim_win_is_valid(self._popup.winid) then
    self._popup.winid = nil
  end
  if self._popup._.mounted and not self._popup.bufnr then
    self._popup._.mounted = false
  end
  return self._popup._.mounted and self._popup.bufnr ~= nil
end

--- Calculate layout based on message dimensions
---@param width number
---@param height number
---@return table
function View:get_layout(width, height)
  local dim = { width = width, height = height }
  return Util.get_layout(dim, self._opts)
end

--- Create the popup
function View:create()
  if self._loading then
    return
  end
  self._loading = true
  local opts = vim.deepcopy(self._opts)
  self._popup = Popup.new(opts)
  self._popup:mount()
  self._loading = false
end

--- Set window options
---@param win number
function View:set_win_options(win)
  if self._opts.win_options then
    Util.wo(win, self._opts.win_options)
  end
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

--- Tag the buffer for debugging
function View:tag()
  if self._popup and self._popup.bufnr then
    Util.ignore_events(function()
      vim.bo[self._popup.bufnr].filetype = "cmdline"
    end)
  end
end

--- Fix border highlights (hide search highlights in border)
function View:fix_border()
  if
    self._popup
    and self._popup.border
    and self._popup.border.winid
    and vim.api.nvim_win_is_valid(self._popup.border.winid)
  then
    local winhl = vim.api.nvim_win_get_option(self._popup.border.winid, "winhighlight") or ""
    if not winhl:find("IncSearch") then
      local hl = vim.split(winhl, ",")
      hl[#hl + 1] = "Search:"
      hl[#hl + 1] = "IncSearch:"
      winhl = table.concat(hl, ",")
      vim.api.nvim_win_set_option(self._popup.border.winid, "winhighlight", winhl)
    end
  end
end

--- Render message content to the popup buffer
---@param message table CmdlineMessage/block with :render method
function View:render(message)
  if not self._popup or not self._popup.bufnr then
    return
  end
  local buf = self._popup.bufnr

  -- Set buffer options
  Util.ignore_events(function()
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = "cmdline"
    vim.bo[buf].modifiable = true
  end)

  -- Clear namespace extmarks
  vim.api.nvim_buf_clear_namespace(buf, Config.ns, 0, -1)

  -- Clear existing lines
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  -- Render message content
  message:render(buf, Config.ns, 1)

  -- Make buffer unmodifiable
  vim.bo[buf].modifiable = false
end

--- Show the view with a message
---@param message table CmdlineMessage
---@param kind? CmdlineKind
function View:show(message, kind)
  if self._loading then
    return
  end

  -- Build new opts
  local new_opts = vim.tbl_deep_extend("force", {
    buf_options = {
      buftype = "nofile",
      filetype = "cmdline",
    },
    win_options = {
      wrap = false,
      foldenable = false,
      scrolloff = 0,
      sidescrolloff = 0,
    },
  }, Config.get_popup_options(kind or "cmdline"))

  -- Normalize winhighlight
  if new_opts.win_options and new_opts.win_options.winhighlight then
    if type(new_opts.win_options.winhighlight) == "table" then
      new_opts.win_options.winhighlight = Util.get_win_highlight(new_opts.win_options.winhighlight)
    end
  end

  -- Handle title from message
  if message.title then
    new_opts.border = new_opts.border or {}
    new_opts.border.text = new_opts.border.text or {}
    new_opts.border.text.top = message.title
  end

  -- Calculate layout
  local layout = self:get_layout(message:width(), message:height())
  new_opts = vim.tbl_deep_extend("force", new_opts, layout)

  -- Decide whether to reuse or recreate the popup
  local need_recreate = false
  if self._popup then
    -- Check if structural options changed (border, position type, etc.)
    local old_border_style = self._opts.border and self._opts.border.style
    local new_border_style = new_opts.border and new_opts.border.style
    local old_relative = self._opts.relative
    local new_relative = new_opts.relative
    -- Also check border text changes (title)
    local old_border_text = self._opts.border and self._opts.border.text and self._opts.border.text.top
    local new_border_text = new_opts.border and new_opts.border.text and new_opts.border.text.top
    if old_border_style ~= new_border_style
      or not vim.deep_equal(old_relative, new_relative)
      or old_border_text ~= new_border_text
    then
      need_recreate = true
    end
  end

  if need_recreate then
    pcall(function()
      if self._popup then
        self._popup:unmount()
      end
    end)
    self._popup = nil
    self._visible = false
  end

  self._opts = new_opts

  -- Create popup if needed
  if not self._popup then
    self:create()
  end

  if not self:is_mounted() then
    pcall(function()
      self._popup:mount()
    end)
  end

  -- Render content
  self:render(message)

  -- Show popup and configure window
  if self:is_mounted() then
    self._popup:show()
    if self._popup.winid then
      self:tag()
      self:set_win_options(self._popup.winid)
      -- Update layout with actual dimensions (also updates border text)
      local layout_opts = Util.get_layout(
        { width = message:width(), height = message:height() },
        self._opts
      )
      pcall(function()
        self._popup:update_layout(layout_opts)
      end)
    end

    self:fix_border()
    self._visible = true
  end
end

--- Hide the view
function View:hide()
  if self._popup then
    self._visible = false
    pcall(function()
      self._popup:unmount()
    end)
    if self._popup and self._popup._ then
      self._popup._.loading = false
    end
    self._popup = nil
  end
end

-- Module-level singleton view instance
M._view = nil

--- Get or create the singleton view
---@return CmdlineView
function M.get()
  if not M._view then
    M._view = View.new()
  end
  return M._view
end

return M
