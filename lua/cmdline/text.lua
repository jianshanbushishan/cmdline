--- Extended text with syntax highlighting and virtual text support
--- Standalone implementation (no NUI dependency)
local Syntax = require("cmdline.syntax")
local Treesitter = require("cmdline.treesitter")

---@class CmdlineExtmark
---@field col? number
---@field end_col? number
---@field id? number
---@field hl_group? string
---@field virt_self_win_col? number
---@field relative? boolean
---@field lang? string
---@field lines? number
---@field virt_text? table
---@field virt_text_win_col? number
---@field conceal? string

---@class CmdlineText
---@field _content string
---@field _length number
---@field _width number
---@field extmark? CmdlineExtmark
---@field enabled? boolean
---@field on_render? fun(text: CmdlineText, buf:number, line:number, byte:number, col:number)
local M = {}
M.__index = M

--- Create a new CmdlineText
---@param content string text content
---@param highlight? string|CmdlineExtmark highlight group or extmark options
---@return CmdlineText
function M.new(content, highlight)
  local self = setmetatable({}, M)
  self._content = content or ""
  self._length = vim.fn.strlen(self._content)
  self._width = vim.api.nvim_strwidth(self._content)

  if highlight then
    if type(highlight) == "string" then
      self.extmark = { hl_group = highlight }
    else
      self.extmark = vim.deepcopy(highlight)
    end
  else
    self.extmark = nil
  end

  return self
end

-- Allow calling as CmdlineText("text", "hl") instead of CmdlineText.new(...)
setmetatable(M, {
  __call = function(_, ...)
    return M.new(...)
  end,
})

--- Get text content
---@return string
function M.content(self)
  return self._content
end

--- Get byte length
---@return number
function M.length(self)
  return self._length
end

--- Get display width
---@return number
function M.width(self)
  return self._width
end

--- Create a virtual text icon at column 0
---@param text string icon text
---@param hl_group? string highlight group
---@return CmdlineText
function M.virtual_text(text, hl_group)
  local content = (" "):rep(vim.api.nvim_strwidth(text))
  return M.new(content, {
    virt_text = { { text, hl_group } },
    virt_text_win_col = 0,
    relative = true,
  })
end

--- Create a cursor marker
---@param col number relative column offset
---@return CmdlineText
function M.cursor(col)
  return M.new(" ", {
    hl_group = "CmdlineCursor",
    col = col,
    relative = true,
  })
end

--- Create a syntax highlight marker
---@param lang string treesitter/vim language
---@param lines number number of lines to highlight (usually 1)
---@param col? number starting column offset
---@return CmdlineText
function M.syntax(lang, lines, col)
  return M.new("", {
    lang = lang,
    col = col,
    lines = lines,
  })
end

--- Apply base extmark highlighting (replaces NuiText.super.highlight)
---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr number line number (1-indexed)
---@param byte_start number start byte position (0-indexed)
function M._base_highlight(self, bufnr, ns_id, linenr, byte_start)
  if not self.extmark then
    return
  end

  local extmark = vim.deepcopy(self.extmark)
  extmark.id = nil  -- always create fresh extmark

  extmark.end_col = byte_start + self._length

  -- Remove non-extmark fields
  extmark.relative = nil
  extmark.lang = nil
  extmark.lines = nil

  -- Only set extmark if there's something to highlight
  if extmark.hl_group or extmark.virt_text or extmark.conceal then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, linenr - 1, byte_start, extmark)
  end
end

--- Highlight this text in a buffer
---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr number line number (1-indexed)
---@param byte_start number start byte position (0-indexed)
function M.highlight(self, bufnr, ns_id, linenr, byte_start)
  if not self.extmark then
    return
  end

  -- Handle syntax highlighting
  if self.extmark.lang then
    local range = { linenr - self.extmark.lines, 0, linenr, byte_start + 1 }
    if self.extmark.col then
      range[2] = byte_start + self.extmark.col - 1
    end
    if Treesitter.has_lang(self.extmark.lang) then
      Treesitter.highlight(bufnr, ns_id, range, self.extmark.lang)
    else
      Syntax.highlight(bufnr, ns_id, range, self.extmark.lang)
    end
    return
  end

  local byte_start_orig = byte_start

  ---@type CmdlineExtmark
  local orig = vim.deepcopy(self.extmark)
  local extmark = self.extmark

  local col_start = 0

  if extmark.relative or self.on_render then
    ---@type string
    local line = vim.api.nvim_buf_get_text(bufnr, linenr - 1, 0, linenr - 1, byte_start, {})[1]
    col_start = vim.api.nvim_strwidth(line)
  end

  if extmark.relative then
    if extmark.virt_text_win_col then
      extmark.virt_text_win_col = extmark.virt_text_win_col + col_start
    end
    if extmark.col then
      extmark.col = extmark.col + byte_start
    end
    extmark.relative = nil
  end

  local length = self._length
  if extmark.length then
    self._length = extmark.length
    extmark.length = nil
  end

  if extmark.col then
    ---@type number
    byte_start = extmark.col
    extmark.col = nil
  end

  if self.enabled ~= false then
    self:_base_highlight(bufnr, ns_id, linenr, byte_start)
  end

  if self.on_render then
    self.on_render(self, bufnr, linenr, byte_start_orig, col_start)
  end

  self._length = length
  self.extmark = orig
end

--- Render text to buffer and apply highlighting
---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr_start number start line number (1-indexed)
---@param byte_start number start byte position (0-indexed)
---@param linenr_end? number end line number (1-indexed)
---@param byte_end? number end byte position (0-indexed)
function M.render(self, bufnr, ns_id, linenr_start, byte_start, linenr_end, byte_end)
  local row_start = linenr_start - 1
  local row_end = linenr_end and linenr_end - 1 or row_start

  local col_start = byte_start
  local col_end = byte_end or byte_start + self._length

  vim.api.nvim_buf_set_text(bufnr, row_start, col_start, row_end, col_end, { self._content })
  self:highlight(bufnr, ns_id, linenr_start, byte_start)
end

return M
