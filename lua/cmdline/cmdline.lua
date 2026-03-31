--- Cmdline event handler and formatter for cmdline.nvim
--- Adapted from noice.nvim's ui/cmdline.lua
local Config = require("cmdline.config")
local CmdlineText = require("cmdline.text")
local Util = require("cmdline.util")

local M = {}

-- Special character used by Neovim for force-redraws.
-- When cmdline_show contains this character, it's an internal redraw, not a real user input.
M.SPECIAL = "Þ"

---@class CmdlineState
---@field content {[1]: integer, [2]: string}[]
---@field pos number
---@field firstc string
---@field prompt string
---@field indent number
---@field level number

---@class CmdlineInstance
---@field state CmdlineState
---@field offset integer
local CmdlineInstance = {}
CmdlineInstance.__index = CmdlineInstance

---@param state CmdlineState
---@return CmdlineInstance
function CmdlineInstance:new(state)
  local instance = setmetatable({}, self)
  instance.state = state or {}
  instance.offset = 0
  return instance
end

--- Get full cmdline text
---@return string
function CmdlineInstance:get()
  return table.concat(
    vim.tbl_map(function(c)
      return c[2]
    end, self.state.content),
    ""
  )
end

--- Determine the format (icon, lang, view) based on cmdline content
---@return table
function CmdlineInstance:get_format()
  -- Check for input() prompt
  if self.state.prompt and self.state.prompt ~= "" then
    local input_fmt = Config.options.format.input
    if input_fmt then
      return input_fmt
    end
  end

  local line = self.state.firstc .. self:get()

  ---@type {offset:number, format:table}[]
  local ret = {}

  for name, fmt in pairs(Config.options.format) do
    if fmt and fmt ~= false and fmt.pattern then
      local patterns = type(fmt.pattern) == "table" and fmt.pattern or { fmt.pattern }
      ---@cast patterns string[]
      for _, pattern in ipairs(patterns) do
        local _, to = line:find(pattern)
 ---@type number?
        if to and self.state.pos >= to - 1 then
          ret[#ret + 1] = {
            offset = to,
            format = vim.tbl_deep_extend("force", { name = name }, fmt),
          }
        end
      end
    end
  end

  table.sort(ret, function(a, b)
    return a.offset > b.offset
  end)

  local matched = ret[1]
  if matched then
    self.offset = matched.format.conceal ~= false and matched.offset or 0
    return matched.format
  end

  self.offset = 0
  return {
    name = self.state.firstc,
    kind = self.state.firstc,
    view = Config.options.view,
  }
end

--- Get cmdline display width
function CmdlineInstance:width()
  return vim.api.nvim_strwidth(self:get())
end

--- Get cmdline byte length
function CmdlineInstance:length()
  return vim.fn.strlen(self:get())
end

---@type table<number, CmdlineInstance>
M.cmdlines = {}
M.active = nil
M.real_cursor = vim.api.nvim__redraw ~= nil
M.position = nil
M.skipped = false

--- Get the last (highest level) cmdline instance
---@return CmdlineInstance?
function M.last()
  local keys = vim.tbl_keys(M.cmdlines)
  if #keys == 0 then
    return nil
  end
  local last_level = math.max(1, unpack(keys))
  return M.cmdlines[last_level]
end

--- Format the cmdline content into a message block
---@param block CmdlineBlock (has :append, :clear, title, kind, fix_cr fields)
function CmdlineInstance:format(block)
  local format = self:get_format()
  block:clear()
  block.title = nil
  block.kind = format.name
  block.fix_cr = false

  local use_input = self.state.prompt ~= ""
    and format.view == "cmdline_input"
    and #self.state.prompt <= 60
    and not self.state.prompt:find("\n")

  -- Add icon
  if format.icon and (format.name ~= "input" or use_input) then
    block:append(CmdlineText.virtual_text(format.icon, format.icon_hl_group))
    block:append(" ")
  end

  -- Add prompt for input()
  if self.state.prompt ~= "" then
    if use_input then
      block.title = " " .. self.state.prompt:gsub("%s*:%s*$", "") .. " "
    else
      block:append(self.state.prompt, "CmdlinePrompt")
    end
  end

  -- Add first character (: / ? !) unless concealed
  if not format.conceal then
    block:append(self.state.firstc)
  end

  -- Add command text after offset
  local cmd = self:get():sub(self.offset)
  block:append(cmd)

  -- Add syntax highlight marker
  if format.lang then
    block:append(CmdlineText.syntax(format.lang, 1, -vim.fn.strlen(cmd)))
  end

  -- Add cursor marker
  local cursor = CmdlineText.cursor(-self:length() + self.state.pos)
  cursor.on_render = M.on_render
  cursor.enabled = not M.real_cursor
  block:append(cursor)
end

--- Handle cmdline_show event
function M.on_show(event, content, pos, firstc, prompt, indent, level)
  local c = CmdlineInstance:new({
    event = event,
    content = content,
    pos = pos,
    firstc = firstc,
    prompt = prompt,
    indent = indent,
    level = level,
  })

  -- Skip force-redraw events triggered by internal Neovim mechanisms.
  -- These contain the SPECIAL character and are not real user input.
  if c:get():find(M.SPECIAL, 1, true) then
    M.skipped = true
    return
  end

  M.skipped = false

  local last = M.cmdlines[level] and M.cmdlines[level].state
  if not vim.deep_equal(c.state, last) then
    M.active = c
    M.cmdlines[level] = c
    M.update()
  end
end

--- Handle cmdline_hide event
function M.on_hide(_, level)
  if M.cmdlines[level] then
    M.cmdlines[level] = nil
    M.active = nil
    M.update()
  end
end

--- Handle cmdline_pos event
function M.on_pos(_, pos, level)
  if M.skipped then
    return
  end
  local c = M.cmdlines[level]
  if c and c.state.pos ~= pos then
    M.cmdlines[level].state.pos = pos
    M.update()
  end
end

--- Handle cmdline_special_char event (no-op)
function M.on_special_char() end

--- Handle cmdline_block events (no-op)
function M.on_block_show() end
function M.on_block_append() end
function M.on_block_hide() end

--- Called when the cmdline is rendered in a buffer
---@param _ CmdlineText
---@param buf number
---@param line number
---@param byte number
function M.on_render(_, buf, line, byte)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end

  -- Force a redraw to ensure cursor position is up-to-date.
  -- This is needed for substitute commands and cmdpreview on Neovim < 0.11.
  M.cmdline_force_redraw()

  local last = M.last()
  if not last then
    return
  end

  local cmdline_start = byte - (last:length() - last.offset)
  local cursor_pos = byte - last:length() + last.state.pos
  local ok, pos = pcall(vim.fn.screenpos, win, line, cmdline_start)
  if not ok then
    return
  end

  M.position = {
    cursor = cursor_pos,
    buf = buf,
    win = win,
    bufpos = {
      row = line,
      col = cmdline_start,
    },
    screenpos = {
      row = pos.row,
      col = pos.col - 1,
    },
  }
  vim.g.ui_cmdline_pos = {
    M.position.screenpos.row,
    M.position.screenpos.col - 1,
  }
  pcall(M.fix_cursor)
end

--- Fix cursor position in the popup window
function M.fix_cursor()
  if not M.position then
    return
  end
  local win = M.position.win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if M.real_cursor then
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(M.position.buf), M.position.cursor })
    pcall(vim.api.nvim__redraw, { cursor = true, win = win, flush = true })
  end
end

--- Force a redraw during substitute/cmdpreview by feeding a special char.
--- Only needed on Neovim < 0.11 where cursor position can become stale.
function M.cmdline_force_redraw()
  if vim.fn.has("nvim-0.11") == 1 then
    -- Not needed on 0.11+
    return
  end
  pcall(vim.api.nvim_feedkeys, M.SPECIAL .. Util.BS, "n", true)
end

--- Get the cmdline window if it's still valid
---@return number?
function M.win()
  return M.position
    and M.position.win
    and vim.api.nvim_win_is_valid(M.position.win)
    and M.position.win
    or nil
end

--- Update the cmdline display (will be overridden by init.lua)
M.update = function() end

return M
