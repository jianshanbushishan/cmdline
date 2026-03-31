--- Text line container for cmdline.nvim
--- Replaces nui.line with a lightweight implementation
local CmdlineText = require("cmdline.text")

local M = {}
M.__index = M

---@param text string
---@param display_col number
---@return number
local function display_col_to_byte(text, display_col)
  if display_col <= 0 or text == "" then
    return 0
  end

  local byte = 0
  local width = 0
  local chars = vim.fn.strchars(text)
  for i = 0, chars - 1 do
    local char = vim.fn.strcharpart(text, i, 1)
    local char_width = vim.api.nvim_strwidth(char)
    if width + char_width > display_col then
      break
    end
    width = width + char_width
    byte = byte + vim.fn.strlen(char)
    if width >= display_col then
      break
    end
  end

  return byte
end

---@class CmdlineLine
---@field _texts CmdlineText[]

--- Create a new line
---@param texts? CmdlineText[]
---@return CmdlineLine
function M.new(texts)
  local self = setmetatable({}, M)
  self._texts = texts or {}
  return self
end

--- Append content to the line
---@param content string|CmdlineText|CmdlineLine
---@param highlight? string|table highlight group or extmark options
---@return CmdlineText|CmdlineLine
function M.append(self, content, highlight)
  if type(content) == "string" then
    content = CmdlineText(content, highlight)
  end
  if content._texts then
    ---@cast content CmdlineLine
    for _, text in ipairs(content._texts) do
      table.insert(self._texts, text)
    end
  else
    ---@cast content CmdlineText
    table.insert(self._texts, content)
  end
  return content
end

--- Get the concatenated text content
---@return string
function M.content(self)
  return table.concat(vim.tbl_map(function(text)
    return text:content()
  end, self._texts))
end

--- Get the total display width
---@return number
function M.width(self)
  local width = 0
  for _, text in ipairs(self._texts) do
    width = width + text:width()
  end
  return width
end

--- Highlight all texts in the line at correct byte offsets
---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr number line number (1-indexed)
---@param byte_start? number start byte position (0-indexed)
function M.highlight(self, bufnr, ns_id, linenr, byte_start)
  local current_byte_start = byte_start or 0
  for _, text in ipairs(self._texts) do
    text:highlight(bufnr, ns_id, linenr, current_byte_start)
    current_byte_start = current_byte_start + text:length()
  end
end

--- Render the line content to a buffer and apply highlights
---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr_start number start line number (1-indexed)
---@param linenr_end? number end line number (1-indexed)
---@param start_col? number start display column (0-indexed)
function M.render(self, bufnr, ns_id, linenr_start, linenr_end, start_col)
  local row_start = linenr_start - 1
  local display_col_start = start_col or 0
  local content = self:content()
  local current = vim.api.nvim_buf_get_lines(bufnr, row_start, row_start + 1, false)[1] or ""
  local col_start = display_col_to_byte(current, display_col_start)
  local col_end = display_col_to_byte(current, display_col_start + vim.api.nvim_strwidth(content))
  vim.api.nvim_buf_set_text(bufnr, row_start, col_start, row_start, col_end, { content })
  self:highlight(bufnr, ns_id, linenr_start, col_start)
end

return M
