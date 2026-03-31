--- Utility functions for cmdline.nvim
--- Standalone implementation (no NUI dependency)
local M = {}

M.islist = vim.islist or vim.tbl_islist

function M.t(str)
  return vim.api.nvim_replace_termcodes(str, true, true, true)
end

M.CR = M.t("<cr>")
M.ESC = M.t("<esc>")
M.BS = M.t("<bs>")

---@param win window
---@param options table<string, any>
function M.wo(win, options)
  for k, v in pairs(options) do
    vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
  end
end

---@generic F: fun()
---@param fn F
---@param opts? {catch?:fun(err:string), msg?:string}
---@return F
function M.protect(fn, opts)
  opts = opts or {}
  return function(...)
    local args = vim.F.pack_len(...)
    local ok, result = xpcall(function()
      return fn(vim.F.unpack_len(args))
    end, function(err)
      if opts.catch then
        pcall(opts.catch, err)
      end
      vim.schedule(function()
        vim.notify(err, vim.log.levels.ERROR, { title = "cmdline.nvim" })
      end)
      return err
    end)
    return ok and result or nil
  end
end

function M.try(fn, ...)
  return M.protect(fn)(...)
end

function M.redraw()
  if vim.api.nvim__redraw then
    vim.api.nvim__redraw({ flush = true })
  else
    vim.cmd.redraw()
  end
end

function M.is_exiting()
  return vim.v.exiting ~= vim.NIL
end

---@generic T
---@param fn fun():T
---@return T
function M.ignore_events(fn)
  local ei = vim.go.eventignore
  vim.go.eventignore = "all"
  local ok, ret = xpcall(fn, debug.traceback)
  vim.go.eventignore = ei
  if not ok then
    error(ret)
  end
  return ret
end

--- Normalize padding to {top, right, bottom, left}
---@param opts table|nil
---@return table
function M.normalize_padding(opts)
  opts = opts or {}
  if type(opts) == "string" then
    opts = { style = opts }
  end
  if M.islist(opts.padding) then
    if #opts.padding == 2 then
      return {
        top = opts.padding[1],
        bottom = opts.padding[1],
        left = opts.padding[2],
        right = opts.padding[2],
      }
    elseif #opts.padding == 4 then
      return {
        top = opts.padding[1],
        right = opts.padding[2],
        bottom = opts.padding[3],
        left = opts.padding[4],
      }
    end
  end
  return vim.tbl_deep_extend("force", {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  }, opts.padding or {})
end

--- Normalize layout options (percentage positions resolved in get_layout for centering)
---@param opts table
---@return table
local function normalize_layout_options(opts)
  return opts
end

function M.normalize_popup_options(opts)
  opts = vim.deepcopy(opts or {})
  opts = normalize_layout_options(opts)
  local border = opts.border
  if type(border) == "string" then
    opts.border = { style = border }
  end
  if opts.border then
    opts.border.padding = M.normalize_padding(opts.border)
  end
  if opts.border and (not opts.border.style or opts.border.style == "none" or opts.border.style == "shadow") then
    opts.border.text = nil
  end
  return opts
end

function M.get_win_highlight(hl)
  if type(hl) == "string" then
    return hl
  end
  local ret = {}
  for key, value in pairs(hl) do
    table.insert(ret, key .. ":" .. value)
  end
  return table.concat(ret, ",")
end

---@param dim {width: number, height:number}
---@param _opts table
function M.get_layout(dim, _opts)
  local opts = M.normalize_popup_options(_opts)
  local position = vim.deepcopy(opts.position)
  local size = vim.deepcopy(opts.size) or {}

  local function minmax(min, max, value)
    return math.max(min or 1, math.min(value, max or 1000))
  end

  if opts.relative == "editor" or (type(opts.relative) == "table" and opts.relative.type == "editor") then
    size.max_width = size.max_width or vim.o.columns - 4
    size.max_height = size.max_height or vim.o.lines - 4
  end
  if size.width == "auto" then
    size.width = minmax(size.min_width, size.max_width, dim.width)
    dim.width = size.width
  end
  if size.height == "auto" then
    size.height = minmax(size.min_height, size.max_height, dim.height)
    dim.height = size.height
  end

  if position then
    if type(position.col) == "number" and position.col < 0 then
      position.col = vim.o.columns + position.col - dim.width
    end
    if type(position.row) == "number" and position.row < 0 then
      position.row = vim.o.lines + position.row - dim.height
    end
  end

  return { size = size, position = position, relative = opts.relative }
end

return M
