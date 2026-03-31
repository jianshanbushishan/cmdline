--- Floating popup window for cmdline.nvim
--- Replaces nui.popup with a native Neovim API implementation
local M = {}
M.__index = M

-- Border characters
local BORDER_STYLES = {
  rounded = { "╭", "─", "╮", "│", "│", "─", "╰", "╯" },
  double = { "╔", "═", "╗", "║", "║", "═", "╚", "╝" },
  single = { "┌", "─", "┐", "│", "│", "─", "└", "┘" },
  solid = { "▛", "▀", "▜", "▌", "▐", "▄", "▙", "▟" },
  shadow = { "", " ", "", " ", "", " ", "", " " },
  none = nil,
}

---@param border_text table|string|nil
---@param width number
---@return string?, number?
local function get_top_title(border_text, width)
  local title = border_text
  if type(border_text) == "table" then
    title = border_text[1] or border_text.text or border_text.content
  end
  if type(title) ~= "string" or title == "" or width <= 0 then
    return nil, nil
  end

  local title_width = vim.api.nvim_strwidth(title)
  if title_width > width then
    local trimmed = ""
    local trimmed_width = 0
    local chars = vim.fn.strchars(title)
    for i = 0, chars - 1 do
      local char = vim.fn.strcharpart(title, i, 1)
      local char_width = vim.api.nvim_strwidth(char)
      if trimmed_width + char_width > width then
        break
      end
      trimmed = trimmed .. char
      trimmed_width = trimmed_width + char_width
    end
    title = trimmed
    title_width = trimmed_width
  end

  return title, title_width
end

---@param winhighlight string|table|nil
---@return string
local function get_border_winhighlight(winhighlight)
  if type(winhighlight) == "string" and winhighlight ~= "" then
    local parts = {}
    local has_normal = false
    local has_search = false
    local has_incsearch = false
    local float_border = winhighlight:match("FloatBorder:([^,]+)")

    for _, part in ipairs(vim.split(winhighlight, ",", { trimempty = true })) do
      local key = part:match("^([^:]+):")
      if key == "Normal" then
        has_normal = true
        if float_border and float_border ~= "" then
          part = "Normal:" .. float_border
        end
      elseif key == "Search" then
        has_search = true
      elseif key == "IncSearch" then
        has_incsearch = true
      end
      parts[#parts + 1] = part
    end

    if not has_normal and float_border and float_border ~= "" then
      parts[#parts + 1] = "Normal:" .. float_border
    end
    if not has_search then
      parts[#parts + 1] = "Search:"
    end
    if not has_incsearch then
      parts[#parts + 1] = "IncSearch:"
    end
    return table.concat(parts, ",")
  end

  if type(winhighlight) == "table" then
    local border_hl = winhighlight.FloatBorder or "CmdlinePopupBorder"
    local title_hl = winhighlight.FloatTitle or "CmdlinePopupTitle"
    return table.concat({
      "Normal:" .. border_hl,
      "FloatBorder:" .. border_hl,
      "FloatTitle:" .. title_hl,
      "Search:",
      "IncSearch:",
    }, ",")
  end

  return "Normal:CmdlinePopupBorder,FloatBorder:CmdlinePopupBorder,FloatTitle:CmdlinePopupTitle,Search:,IncSearch:"
end

---@class CmdlinePopup
---@field bufnr number?
---@field winid number?
---@field border table
---@field _ {mounted:boolean, loading:boolean, win_options:table, buf_options:table, win_config:table}

--- Resolve a position/size value that can be a number, percentage string, or "auto"
---@param val number|string|nil
---@param total number total available space
---@param auto_val number|nil value to use for "auto"
---@return number?
local function resolve_dimension(val, total, auto_val)
  if val == nil then
    return nil
  end
  if type(val) == "string" then
    if val == "auto" then
      return auto_val
    end
    local pct = tonumber(val:match("^(%d+)%%$"))
    if pct then
      return math.floor(total * pct / 100)
    end
    return auto_val
  end
  return val
end

--- Normalize padding to {top, right, bottom, left}
---@param padding table|number|nil
---@return table
local function normalize_padding(padding)
  if not padding then
    return { top = 0, right = 0, bottom = 0, left = 0 }
  end
  if type(padding) == "number" then
    return { top = padding, right = padding, bottom = padding, left = padding }
  end
  if type(padding) == "table" then
    if #padding == 2 then
      return { top = padding[1], right = padding[2], bottom = padding[1], left = padding[2] }
    end
    if #padding == 4 then
      return { top = padding[1], right = padding[2], bottom = padding[3], left = padding[4] }
    end
    return {
      top = padding.top or 0,
      right = padding.right or 0,
      bottom = padding.bottom or 0,
      left = padding.left or 0,
    }
  end
  return { top = 0, right = 0, bottom = 0, left = 0 }
end

--- Create a new popup
---@param opts table popup options
---@return CmdlinePopup
function M.new(opts)
  local self = setmetatable({}, M)

  opts = opts or {}
  opts.buf_options = opts.buf_options or {}
  opts.win_options = opts.win_options or {}
  opts.border = opts.border or {}
  if type(opts.border) == "string" then
    opts.border = { style = opts.border }
  end
  opts.relative = opts.relative or "editor"
  opts.enter = opts.enter or false
  opts.zindex = opts.zindex or 50

  self.bufnr = nil
  self.winid = nil
  self.border = { winid = nil }

  self._ = {
    mounted = false,
    loading = false,
    opts = opts,
    buf_options = opts.buf_options,
    win_options = opts.win_options,
    win_config = {
      relative = type(opts.relative) == "table" and opts.relative.type or opts.relative,
      focusable = opts.focusable ~= false,
      style = "minimal",
      zindex = opts.zindex,
      noautocmd = true,
    },
    border_chars = nil,
    border_padding = normalize_padding(opts.border and opts.border.padding),
    border_text = opts.border and opts.border.text or {},
  }

  -- Resolve border style
  local style = opts.border and opts.border.style
  if style and style ~= "none" then
    self._.border_chars = BORDER_STYLES[style] or (type(style) == "table" and style) or BORDER_STYLES.rounded
  end

  -- For shadow style, set winblend
  if style == "shadow" then
    self._.win_options.winblend = self._.win_options.winblend or 50
  end

  -- Resolve position and size
  self:_resolve_layout()

  return self
end

--- Resolve layout dimensions from options
function M._resolve_layout(self)
  local opts = self._.opts
  local total_w = vim.o.columns
  local total_h = vim.o.lines
  local has_border = self._.border_chars ~= nil
  local pad = self._.border_padding
  local bw = has_border and 2 or 0  -- border adds 2 cols (left + right)
  local bh = has_border and 2 or 0  -- border adds 2 rows (top + bottom)
  local pw = pad.left + pad.right
  local ph = pad.top + pad.bottom

  -- Resolve size
  local size = opts.size or {}
  local width = resolve_dimension(size.width, total_w, 60)
  local height = resolve_dimension(size.height, total_h, 1)
  if size.min_width then
    width = math.max(width or 1, size.min_width)
  end
  if size.max_width then
    width = math.min(width or total_w, size.max_width)
  end
  if size.min_height then
    height = math.max(height or 1, size.min_height)
  end
  if size.max_height then
    height = math.min(height or total_h, size.max_height)
  end

  -- Resolve position
  local position = opts.position or {}
  local row = resolve_dimension(position.row, total_h)
  local col = resolve_dimension(position.col, total_w)

  -- Center percentage positions: "50%" means popup CENTER is at 50% of screen
  if type(position.row) == "string" then
    local pct = tonumber(position.row:match("^(%d+)%%$"))
    if pct then
      row = math.floor(total_h * pct / 100) - math.floor(((height or 1) + ph + bh) / 2)
    end
  end
  if type(position.col) == "string" then
    local pct = tonumber(position.col:match("^(%d+)%%$"))
    if pct then
      col = math.floor(total_w * pct / 100) - math.floor(((width or 1) + pw + bw) / 2)
    end
  end

  -- Handle negative positions
  if type(position.row) == "number" and position.row < 0 then
    row = total_h + position.row - (height or 1) - bh - ph
  end
  if type(position.col) == "number" and position.col < 0 then
    col = total_w + position.col - (width or 1) - bw - pw
  end

  -- Content dimensions (inside border and padding)
  self._.content_width = width
  self._.content_height = height

  -- The content window renders only the actual message area.
  -- Padding is represented by the surrounding border window space.
  self._.win_width = width or 0
  self._.win_height = height or 0

  -- Outer dimensions (content + padding + border)
  self._.outer_width = (width or 0) + pw + bw
  self._.outer_height = (height or 0) + ph + bh

  -- Position of the content window relative to the border window
  self._.content_row = (has_border and 1 or 0) + pad.top
  self._.content_col = (has_border and 1 or 0) + pad.left

  -- Outer position (for the border window or the content window if no border)
  self._.row = row or 0
  self._.col = col or 0

  -- Handle relative=win
  if type(opts.relative) == "table" then
    self._.win_config.relative = opts.relative.type
    if opts.relative.type == "win" then
      self._.win_config.win = opts.relative.winid or 0
    end
  end
end

--- Set buffer options
---@param bufnr number
---@param opts table
local function set_buf_options(bufnr, opts)
  for k, v in pairs(opts) do
    vim.bo[bufnr][k] = v
  end
end

--- Set window options
---@param winid number
---@param opts table
local function set_win_options(winid, opts)
  for k, v in pairs(opts) do
    vim.api.nvim_set_option_value(k, v, { scope = "local", win = winid })
  end
end

--- Create the border window and set border text
---@param border_buf number
---@param border_win number
function M._setup_border(self, border_buf, border_win)
  local chars = self._.border_chars
  if not chars then
    return
  end

  local w = self._.outer_width
  local h = self._.outer_height
  local text = self._.border_text

  -- Build border lines
  local lines = {}
  for i = 1, h do
    if i == 1 then
      lines[i] = chars[1] .. string.rep(chars[2], w - 2) .. chars[3]
    elseif i == h then
      lines[i] = chars[7] .. string.rep(chars[6], w - 2) .. chars[8]
    else
      lines[i] = chars[4] .. string.rep(" ", w - 2) .. chars[5]
    end
  end

  vim.api.nvim_buf_set_lines(border_buf, 0, -1, false, lines)

  -- Set top title
  local title, title_width = get_top_title(text and text.top, w - 2)
  if title and title_width then
    local fill = math.max(0, w - 2 - title_width)
    local left = math.floor(fill / 2)
    local right = fill - left
    lines[1] = chars[1] .. string.rep(chars[2], left) .. title .. string.rep(chars[2], right) .. chars[3]
    vim.api.nvim_buf_set_lines(border_buf, 0, 1, false, { lines[1] })

    local hl = self._.win_options.winhighlight
    if type(hl) == "string" then
      hl = hl:match("FloatTitle:([^,]+)")
    elseif type(hl) == "table" then
      hl = hl.FloatTitle or hl.Normal
    end
    if hl and hl ~= "" then
      local ns = vim.api.nvim_create_namespace("cmdline_border")
      local start_char = 1 + left
      local start_byte = vim.fn.byteidx(lines[1], start_char)
      local end_byte = start_byte + vim.fn.strlen(title)
      vim.api.nvim_buf_clear_namespace(border_buf, ns, 0, -1)
      vim.api.nvim_buf_set_extmark(border_buf, ns, 0, start_byte, {
        end_col = end_byte,
        hl_group = hl,
      })
    end
  end

  vim.bo[border_buf].modifiable = false
end

--- Create a buffer
function M._buf_create(self)
  if not self.bufnr then
    self.bufnr = vim.api.nvim_create_buf(false, true)
    set_buf_options(self.bufnr, self._.buf_options)
  end
end

--- Open the content window
function M._open_window(self)
  if self.winid or not self.bufnr then
    return
  end

  local config = vim.deepcopy(self._.win_config)
  config.width = self._.win_width
  config.height = self._.win_height

  if self._.border_chars then
    -- Position content window relative to border position
    config.row = self._.row + self._.content_row
    config.col = self._.col + self._.content_col
  else
    config.row = self._.row
    config.col = self._.col
  end

  self.winid = vim.api.nvim_open_win(self.bufnr, false, config)
  set_win_options(self.winid, self._.win_options)
end

--- Open the border window
function M._open_border(self)
  if not self._.border_chars then
    return
  end

  -- Close any existing border before creating a new one
  self:_close_border()

  local border_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[border_buf].buftype = "nofile"

  local config = {
    relative = self._.win_config.relative,
    width = self._.outer_width,
    height = self._.outer_height,
    row = self._.row,
    col = self._.col,
    focusable = false,
    style = "minimal",
    zindex = (self._.win_config.zindex or 50) - 1,
    noautocmd = true,
  }
  if self._.win_config.win then
    config.win = self._.win_config.win
  end

  local border_win = vim.api.nvim_open_win(border_buf, false, config)
  set_win_options(border_win, {
    winhighlight = get_border_winhighlight(self._.win_options.winhighlight),
    winblend = 0,
  })

  self.border.winid = border_win
  self.border.bufnr = border_buf

  self:_setup_border(border_buf, border_win)
end

--- Close the content window
function M._close_window(self)
  if self.winid then
    if vim.api.nvim_win_is_valid(self.winid) then
      vim.api.nvim_win_close(self.winid, true)
    end
    self.winid = nil
  end
end

--- Close the border window
function M._close_border(self)
  if self.border.winid then
    if vim.api.nvim_win_is_valid(self.border.winid) then
      vim.api.nvim_win_close(self.border.winid, true)
    end
    self.border.winid = nil
  end
  if self.border.bufnr then
    if vim.api.nvim_buf_is_valid(self.border.bufnr) then
      vim.api.nvim_buf_delete(self.border.bufnr, { force = true })
    end
    self.border.bufnr = nil
  end
end

--- Mount the popup (create buffer, open windows)
function M.mount(self)
  if self._.loading or self._.mounted then
    return
  end

  self._.loading = true
  self:_resolve_layout()
  self:_buf_create()
  self:_open_border()
  self:_open_window()
  self._.loading = false
  self._.mounted = true
end

--- Unmount the popup (close windows, delete buffer)
function M.unmount(self)
  if self._.loading or not self._.mounted then
    return
  end

  self._.loading = true
  self:_close_window()
  self:_close_border()

  if self.bufnr then
    if vim.api.nvim_buf_is_valid(self.bufnr) then
      vim.api.nvim_buf_delete(self.bufnr, { force = true })
    end
    self.bufnr = nil
  end

  self._.loading = false
  self._.mounted = false
end

--- Show the popup (re-open if hidden)
function M.show(self)
  if self._.loading then
    return
  end

  if not self._.mounted then
    return self:mount()
  end

  self._.loading = true
  self:_resolve_layout()
  self:_open_border()
  self:_open_window()
  self._.loading = false
end

--- Hide the popup (close windows but keep state)
function M.hide(self)
  if self._.loading or not self._.mounted then
    return
  end

  self._.loading = true
  self:_close_window()
  self:_close_border()
  self._.loading = false
end

--- Update the popup layout
---@param config table layout config with optional size, position, relative
function M.update_layout(self, config)
  if not config then
    return
  end

  -- Merge new config into opts
  local opts = self._.opts
  if config.size then
    opts.size = vim.tbl_deep_extend("force", opts.size or {}, config.size)
  end
  if config.position then
    opts.position = vim.tbl_deep_extend("force", opts.position or {}, config.position)
  end
  if config.relative then
    opts.relative = config.relative
  end

  self:_resolve_layout()

  -- Update border
  if self.border.winid and vim.api.nvim_win_is_valid(self.border.winid) then
    vim.api.nvim_win_set_config(self.border.winid, {
      width = self._.outer_width,
      height = self._.outer_height,
      row = self._.row,
      col = self._.col,
    })
    if self.border.bufnr and vim.api.nvim_buf_is_valid(self.border.bufnr) then
      vim.bo[self.border.bufnr].modifiable = true
      self:_setup_border(self.border.bufnr, self.border.winid)
    end
  end

  -- Update content window
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    local win_config = {
      width = self._.win_width,
      height = self._.win_height,
    }
    if self._.border_chars then
      win_config.row = self._.row + self._.content_row
      win_config.col = self._.col + self._.content_col
    else
      win_config.row = self._.row
      win_config.col = self._.col
    end
    vim.api.nvim_win_set_config(self.winid, win_config)
  end
end

return M
