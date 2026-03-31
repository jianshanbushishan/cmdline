--- Text line container for cmdline.nvim
--- Replaces nui.line with a lightweight implementation
local CmdlineText = require("cmdline.text")

local M = {}
M.__index = M

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
function M.render(self, bufnr, ns_id, linenr_start, linenr_end)
  local row_start = linenr_start - 1
  local row_end = linenr_end and linenr_end - 1 or row_start + 1
  local content = self:content()
  vim.api.nvim_buf_set_lines(bufnr, row_start, row_end, false, { content })
  self:highlight(bufnr, ns_id, linenr_start)
end

return M
