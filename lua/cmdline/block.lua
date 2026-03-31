--- Text block for rendering cmdline content
--- Standalone implementation (no NUI dependency)
local CmdlineLine = require("cmdline.line")
local Class = require("cmdline.class")

---@alias CmdlineContent string|CmdlineLine|CmdlineText|CmdlineBlock

---@class CmdlineBlock
---@field _lines CmdlineLine[]
---@field fix_cr boolean?
local Block = Class.create("CmdlineBlock")

---@param content? CmdlineContent|CmdlineContent[]
---@param highlight? string|table
function Block:init(content, highlight)
  self._lines = {}
  if content then
    self:append(content, highlight)
  end
end

function Block:clear()
  self._lines = {}
end

function Block:content()
  return table.concat(
    vim.tbl_map(
      ---@param line CmdlineLine
      function(line)
        return line:content()
      end,
      self._lines
    ),
    "\n"
  )
end

function Block:width()
  local ret = 0
  for _, line in ipairs(self._lines) do
    ret = math.max(ret, line:width())
  end
  return ret
end

function Block:length()
  local ret = 0
  for _, line in ipairs(self._lines) do
    ret = ret + line:width()
  end
  return ret
end

function Block:height()
  return #self._lines
end

function Block:is_empty()
  return #self._lines == 0
end

--- Highlight all lines in the block
---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr_start? number line number (1-indexed)
function Block:highlight(bufnr, ns_id, linenr_start)
  self:_fix_extmarks()
  linenr_start = linenr_start or 1
  for _, line in ipairs(self._lines) do
    line:highlight(bufnr, ns_id, linenr_start)
    linenr_start = linenr_start + 1
  end
end

function Block:_fix_extmarks()
  for _, line in ipairs(self._lines) do
    for _, text in ipairs(line._texts) do
      if text.extmark then
        text.extmark.id = nil
      end
    end
  end
end

--- Render all lines to buffer
---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr_start? number line number (1-indexed)
---@param linenr_end? number end line number (1-indexed)
---@param start_col? number start display column (0-indexed)
function Block:render(bufnr, ns_id, linenr_start, linenr_end, start_col)
  self:_fix_extmarks()
  linenr_start = linenr_start or 1
  for _, line in ipairs(self._lines) do
    line:render(bufnr, ns_id, linenr_start, linenr_end, start_col)
    linenr_start = linenr_start + 1
    if linenr_end then
      linenr_end = linenr_end + 1
    end
  end
end

---@param content string|CmdlineText|CmdlineLine
---@param highlight? string|table
---@return CmdlineText|CmdlineLine
function Block:_append(content, highlight)
  if #self._lines == 0 then
    table.insert(self._lines, CmdlineLine.new())
  end
  if type(content) == "string" and self.fix_cr ~= false then
    local cr = content:match("^.*()[\r]")
    if cr then
      table.remove(self._lines)
      table.insert(self._lines, CmdlineLine.new())
      content = content:sub(cr + 1)
    end
  end
  return CmdlineLine.append(self._lines[#self._lines], content, highlight)
end

---@param contents CmdlineContent|CmdlineContent[]
---@param highlight? string|table
function Block:append(contents, highlight)
  if type(contents) == "string" then
    contents = { { highlight or 0, contents } }
  end

  if contents._texts or contents._content or contents._lines or type(contents[1]) == "number" then
    contents = { contents }
  end

  ---@cast contents CmdlineContent[]
  for _, content in ipairs(contents) do
    if content._texts then
      ---@cast content CmdlineLine
      for _, t in ipairs(content._texts) do
        self:_append(t)
      end
    elseif content._content then
      ---@cast content CmdlineText
      self:_append(content)
    elseif content._lines then
      ---@cast content CmdlineBlock
      for l, line in ipairs(content._lines) do
        if l == 1 then
          self:append(line)
        else
          table.insert(self._lines, line)
        end
      end
    else
      --- Plain chunk or string
      ---@type string|table|nil, string
      local hl, text
      if type(content[1]) == "number" then
        hl = content[1] ~= 0 and content[1] or nil
        text = content[2]
      else
        hl = content[1]
        text = content[2]
      end

      -- Skip numeric hl attrs (we don't use FFI-based highlight conversion)
      if type(hl) == "number" then
        hl = nil
      end

      while text and text ~= "" do
        local nl = text:find("\n")
        local line_text = nl and text:sub(1, nl - 1) or text
        self:_append(line_text, hl)
        if nl then
          self:newline()
          text = text:sub(nl + 1)
        else
          break
        end
      end
    end
  end
end

function Block:last_line()
  return self._lines[#self._lines]
end

function Block:newline()
  table.insert(self._lines, CmdlineLine.new())
end

return Block
