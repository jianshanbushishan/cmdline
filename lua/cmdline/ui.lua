local M = {}

local state = {
  ns = vim.api.nvim_create_namespace("cmdline.nvim"),
  attached = false,
  config = nil,
  levels = {},
  block_lines = {},
  cmd_buf = nil,
  cmd_win = nil,
  cmd_lang = nil,
  block_buf = nil,
  block_win = nil,
  render_pending = false,
  augroup = nil,
}

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function set_default_highlights(config)
  vim.api.nvim_set_hl(0, config.highlight.normal, { default = true, link = "NormalFloat" })
  vim.api.nvim_set_hl(0, config.highlight.border, { default = true, link = "FloatBorder" })
  vim.api.nvim_set_hl(0, config.highlight.icon, { default = true, link = "Special" })
  vim.api.nvim_set_hl(0, config.highlight.label, { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, config.highlight.block, { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, config.highlight.cursor, { default = true, link = "Cursor" })
end

local function flatten_chunks(chunks)
  local parts = {}

  for _, chunk in ipairs(chunks or {}) do
    parts[#parts + 1] = chunk[2] or ""
  end

  return table.concat(parts)
end

local function flatten_block(lines)
  local result = {}

  for _, line in ipairs(lines or {}) do
    result[#result + 1] = flatten_chunks(line)
  end

  return result
end

local function highest_level()
  local max_level = nil

  for level in pairs(state.levels) do
    if not max_level or level > max_level then
      max_level = level
    end
  end

  return max_level
end

local function schedule_render()
  if state.render_pending then
    return
  end

  state.render_pending = true

  vim.schedule(function()
    state.render_pending = false
    M.render()
  end)
end

local function ensure_buffer(kind)
  local key = kind .. "_buf"

  if is_valid_buf(state[key]) then
    return state[key]
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  state[key] = buf
  return buf
end

local function ensure_window(kind, config)
  local buf = ensure_buffer(kind)
  local win_key = kind .. "_win"

  if not is_valid_win(state[win_key]) then
    state[win_key] = vim.api.nvim_open_win(buf, false, config)
  else
    vim.api.nvim_win_set_buf(state[win_key], buf)
    vim.api.nvim_win_set_config(state[win_key], config)
  end

  vim.api.nvim_set_option_value(
    "winhl",
    ("Normal:%s,FloatBorder:%s"):format(state.config.highlight.normal, state.config.highlight.border),
    { win = state[win_key] }
  )
  vim.api.nvim_set_option_value("winblend", state.config.view.winblend, { win = state[win_key] })
  vim.api.nvim_set_option_value("wrap", false, { win = state[win_key] })
  vim.api.nvim_set_option_value("cursorline", false, { win = state[win_key] })

  return state[win_key], buf
end

local function close_window(kind)
  local win_key = kind .. "_win"

  if is_valid_win(state[win_key]) then
    vim.api.nvim_win_close(state[win_key], true)
  end

  state[win_key] = nil
end

local function resolve(value, ctx)
  if type(value) == "function" then
    return value(ctx)
  end

  return value
end

local function matches(pattern, text)
  if type(pattern) == "string" then
    return text:match(pattern) ~= nil
  end

  if type(pattern) == "table" then
    for _, item in ipairs(pattern) do
      if text:match(item) then
        return true
      end
    end
  end

  return false
end

local function select_format(entry)
  local ctx = {
    raw = (entry.firstc or "") .. entry.content,
    content = entry.content,
    pos = entry.pos or 0,
    prompt = entry.prompt or "",
    firstc = entry.firstc or "",
    indent = entry.indent or 0,
    level = entry.level,
  }

  for _, format in ipairs(state.config.formats or {}) do
    if format ~= false then
      local ok = false

      if format.when then
        ok = resolve(format.when, ctx) and true or false
      elseif format.pattern then
        ok = matches(format.pattern, ctx.raw)
      end

      if ok then
        return format, ctx
      end
    end
  end

  return {
    name = "fallback",
    icon = state.config.icons.cmdline,
    label = ctx.prompt ~= "" and ctx.prompt or ctx.firstc,
  }, ctx
end

local function trim_content(body, cursor, format)
  local trim = format.trim or {}

  if trim.content_prefix then
    local prefix = body:match(trim.content_prefix)

    if prefix then
      body = body:sub(#prefix + 1)
      cursor = math.max(0, cursor - #prefix)
    end
  end

  return body, cursor
end

local function decorate_special_char(body, cursor, special)
  if not special or special.c == nil then
    return body
  end

  local index = math.max(0, math.min(cursor, #body))
  local left = body:sub(1, index)
  local right = special.shift and body:sub(index + 1) or body:sub(index + 2)

  return left .. special.c .. right
end

local function prepare_display(entry)
  local format, ctx = select_format(entry)
  local body = entry.content
  local cursor = entry.pos or 0

  body, cursor = trim_content(body, cursor, format)
  body = decorate_special_char(body, cursor, entry.special)

  local padding_left = math.max(0, (state.config.view.padding.left or 0) + (entry.indent or 0))
  local padding_right = math.max(1, state.config.view.padding.right or 1)
  local label = resolve(format.label, ctx)
  local prefix_chunks = {}
  local prefix_text = ""

  if format.icon and format.icon ~= "" then
    prefix_chunks[#prefix_chunks + 1] = { format.icon, state.config.highlight.icon }
    prefix_text = format.icon
  end

  if label and label ~= "" then
    if prefix_text ~= "" then
      prefix_chunks[#prefix_chunks + 1] = { " ", state.config.highlight.normal }
      prefix_text = prefix_text .. " "
    end

    prefix_chunks[#prefix_chunks + 1] = { label, state.config.highlight.label }
    prefix_text = prefix_text .. label
  end

  if prefix_text ~= "" then
    prefix_chunks[#prefix_chunks + 1] = { " ", state.config.highlight.normal }
    prefix_text = prefix_text .. " "
  end

  local line = string.rep(" ", padding_left) .. body .. string.rep(" ", padding_right)
  local cursor_col = padding_left + math.max(0, math.min(cursor, #body))
  local max_cursor = math.max(0, #line - 1)

  if cursor_col > max_cursor then
    cursor_col = max_cursor
  end

  return {
    line = line,
    filetype = format.lang,
    prefix_chunks = prefix_chunks,
    prefix_text = prefix_text,
    prefix_col = padding_left,
    cursor_col = cursor_col,
    width = vim.fn.strdisplaywidth(prefix_text .. line),
  }
end

local function resolve_width(limit, total)
  if type(limit) == "number" and limit > 0 and limit <= 1 then
    return math.max(1, math.floor(total * limit))
  end

  return math.max(1, math.floor(limit))
end

local function resolve_col(width)
  local position = state.config.view.position
  local margin_right = position.margin_right or 0

  if type(position.col) == "number" then
    return math.max(0, position.col)
  end

  if position.col == "left" then
    return 0
  end

  if position.col == "right" then
    return math.max(0, vim.o.columns - width - margin_right)
  end

  return math.max(0, math.floor((vim.o.columns - width) / 2))
end

local function resolve_row(height, border_rows)
  local position = state.config.view.position
  local margin_bottom = position.margin_bottom or 0

  if type(position.row) == "number" then
    return math.max(0, position.row)
  end

  if position.row == "top" then
    return 0
  end

  return math.max(0, vim.o.lines - height - border_rows - margin_bottom - 2)
end

local function border_rows()
  return state.config.view.border and state.config.view.border ~= "none" and 2 or 0
end

local function set_buffer_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function set_cmd_filetype(buf, filetype)
  if state.cmd_lang == filetype then
    return
  end

  if state.cmd_lang then
    pcall(vim.treesitter.stop, buf)
  end

  state.cmd_lang = filetype

  if filetype and filetype ~= "" then
    vim.bo[buf].filetype = filetype
    pcall(vim.treesitter.start, buf, filetype)
  else
    vim.bo[buf].filetype = ""
  end
end

local function render_cmdline()
  local level = highest_level()

  if not level then
    state.cmd_lang = nil
    close_window("cmd")
    return
  end

  local entry = state.levels[level]
  local display = prepare_display(entry)
  local min_width = state.config.view.min_width or 1
  local max_width = resolve_width(state.config.view.max_width or 1, vim.o.columns)
  local width = math.max(min_width, math.min(max_width, display.width))
  local config = {
    relative = "editor",
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = state.config.view.zindex,
    border = state.config.view.border,
    width = width,
    height = 1,
    row = resolve_row(1, border_rows()),
    col = resolve_col(width),
  }

  local _, buf = ensure_window("cmd", config)
  set_buffer_lines(buf, { display.line })
  set_cmd_filetype(buf, display.filetype)
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)

  if #display.prefix_chunks > 0 then
    vim.api.nvim_buf_set_extmark(buf, state.ns, 0, display.prefix_col, {
      virt_text = display.prefix_chunks,
      virt_text_pos = "inline",
    })
  end

  vim.api.nvim_buf_set_extmark(buf, state.ns, 0, display.cursor_col, {
    end_row = 0,
    end_col = display.cursor_col + 1,
    hl_group = state.config.highlight.cursor,
  })
end

local function render_block()
  if vim.tbl_isempty(state.block_lines) then
    close_window("block")
    return
  end

  local lines = {}
  local width = 0
  local padding_left = math.max(0, state.config.view.padding.left or 0)
  local padding_right = math.max(1, state.config.view.padding.right or 1)

  for _, line in ipairs(state.block_lines) do
    local rendered = string.rep(" ", padding_left) .. line .. string.rep(" ", padding_right)
    lines[#lines + 1] = rendered
    width = math.max(width, vim.fn.strdisplaywidth(rendered))
  end

  local cmd_config = is_valid_win(state.cmd_win) and vim.api.nvim_win_get_config(state.cmd_win) or nil
  local height = #lines
  local border = border_rows()
  local row
  local col

  if cmd_config then
    row = math.max(0, cmd_config.row - height - border)
    col = cmd_config.col
  else
    row = resolve_row(height, border)
    col = resolve_col(width)
  end

  local config = {
    relative = "editor",
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = state.config.view.zindex - 1,
    border = state.config.view.border,
    width = math.max(state.config.view.min_width or 1, width),
    height = height,
    row = row,
    col = col,
  }

  local _, buf = ensure_window("block", config)
  set_buffer_lines(buf, lines)
  vim.bo[buf].filetype = ""
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)

  for index = 0, height - 1 do
    vim.api.nvim_buf_add_highlight(buf, state.ns, state.config.highlight.block, index, 0, -1)
  end
end

function M.render()
  if not state.attached or not state.config then
    return
  end

  render_cmdline()
  render_block()
end

function M.handle(event, ...)
  if not state.attached then
    return false
  end

  if event == "cmdline_show" then
    local content, pos, firstc, prompt, indent, level, hl_id = ...
    state.levels[level] = {
      content = flatten_chunks(content),
      pos = pos,
      firstc = firstc or "",
      prompt = prompt or "",
      indent = indent or 0,
      level = level,
      hl_id = hl_id,
      special = nil,
    }
    schedule_render()
    return true
  end

  if event == "cmdline_pos" then
    local pos, level = ...
    if state.levels[level] then
      state.levels[level].pos = pos
      schedule_render()
    end
    return true
  end

  if event == "cmdline_special_char" then
    local char, shift, level = ...
    if state.levels[level] then
      state.levels[level].special = {
        c = char,
        shift = shift,
      }
      schedule_render()
    end
    return true
  end

  if event == "cmdline_hide" then
    local level = ...
    state.levels[level] = nil
    schedule_render()
    return true
  end

  if event == "cmdline_block_show" then
    local lines = ...
    state.block_lines = flatten_block(lines)
    schedule_render()
    return true
  end

  if event == "cmdline_block_append" then
    local line = ...
    state.block_lines[#state.block_lines + 1] = flatten_chunks(line)
    schedule_render()
    return true
  end

  if event == "cmdline_block_hide" then
    state.block_lines = {}
    schedule_render()
    return true
  end

  return false
end

function M.enable(config)
  state.config = config
  set_default_highlights(config)

  if state.attached then
    schedule_render()
    return
  end

  state.attached = true
  state.augroup = vim.api.nvim_create_augroup("CmdlineNvim", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = state.augroup,
    callback = function()
      set_default_highlights(state.config)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      schedule_render()
    end,
  })

  vim.ui_attach(state.ns, { ext_cmdline = true }, function(event, ...)
    return M.handle(event, ...)
  end)
end

function M.test_enable(config)
  state.config = config
  state.attached = true
  set_default_highlights(config)
end

function M.disable()
  if not state.attached then
    return
  end

  pcall(vim.ui_detach, state.ns)

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end

  state.attached = false
  state.levels = {}
  state.block_lines = {}
  state.cmd_lang = nil
  state.augroup = nil

  close_window("cmd")
  close_window("block")
end

function M.is_enabled()
  return state.attached
end

function M.debug_state()
  return {
    cmd_buf = state.cmd_buf,
    cmd_win = state.cmd_win,
    block_buf = state.block_buf,
    block_win = state.block_win,
    cmd_lang = state.cmd_lang,
  }
end

return M
