--- cmdline.nvim - Standalone cmdline replacement with icons and syntax highlighting
--- Extracted from noice.nvim by folke
---@module 'cmdline'
local Config = require("cmdline.config")
local Cmdline = require("cmdline.cmdline")
local View = require("cmdline.view")
local Message = require("cmdline.message")
local Util = require("cmdline.util")

local M = {}

M._attached = false

--- Cmdline message singleton
local message = Message:new()

--- Update the cmdline display
function M.update()
  local c = Cmdline.active
  local view = View.get()

  if c then
    message:clear()
    message.fix_cr = false
    message.title = nil

    -- Format the cmdline content into the message block
    c:format(message)

    -- Show in the popup view
    local format = c:get_format()
    view:show(message, format.kind)

    -- Hide real cursor on older Neovim
    if not Cmdline.real_cursor then
      M._hide_cursor()
    end
  else
    -- Hide the popup
    view:hide()

    -- Restore real cursor on older Neovim
    if not Cmdline.real_cursor then
      M._show_cursor()
    end
  end

  Util.redraw()
end

-- Set the update function reference in cmdline module
Cmdline.update = M.update

-- Cursor management for older Neovim
M._guicursor = nil

function M._hide_cursor()
  if M._guicursor == nil then
    M._guicursor = vim.go.guicursor
  end
  vim.schedule(function()
    if M._guicursor then
      vim.go.guicursor = "a:CmdlineHiddenCursor"
    end
  end)
end

function M._show_cursor()
  if M._guicursor then
    if not Util.is_exiting() then
      vim.schedule(function()
        if M._guicursor and not Util.is_exiting() then
          vim.go.guicursor = "a:"
          vim.cmd.redrawstatus()
          vim.go.guicursor = M._guicursor
          M._guicursor = nil
        end
      end)
    end
  end
end

--- Handle cmdline events from vim.ui_attach
local function on_cmdline(event, ...)
  if Util.is_exiting() then
    return
  end

  local handlers = {
    cmdline_show = function(content, pos, firstc, prompt, indent, level)
      Cmdline.on_show(event, content, pos, firstc, prompt, indent, level)
    end,
    cmdline_hide = function(level)
      Cmdline.on_hide(event, level)
    end,
    cmdline_pos = function(pos, level)
      Cmdline.on_pos(event, pos, level)
    end,
    cmdline_special_char = function()
      Cmdline.on_special_char(event)
    end,
    cmdline_block_show = function()
      Cmdline.on_block_show(event)
    end,
    cmdline_block_append = function()
      Cmdline.on_block_append(event)
    end,
    cmdline_block_hide = function()
      Cmdline.on_block_hide(event)
    end,
  }

  local handler = handlers[event]
  if handler then
    Util.try(handler, ...)
    return true -- we handled this event
  end
end

--- Enable the cmdline replacement
function M.enable()
  if M._attached then
    return
  end

  M._attached = true

  ---@diagnostic disable-next-line: redundant-parameter
  vim.ui_attach(Config.ns, { ext_cmdline = true }, function(event, ...)
    if Util.is_exiting() then
      return
    end
    return on_cmdline(event, ...)
  end)

  -- Fix incsearch on older Neovim
  if vim.fn.has("nvim-0.10") == 0 then
    local conceallevel
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      group = vim.api.nvim_create_augroup("cmdline_incsearch", { clear = true }),
      callback = function(e)
        if e.match == "/" or e.match == "?" then
          conceallevel = vim.wo.conceallevel
          vim.opt_local.conceallevel = 0
        end
      end,
    })
    vim.api.nvim_create_autocmd("CmdlineLeave", {
      group = vim.api.nvim_create_augroup("cmdline_incsearch_leave", { clear = true }),
      callback = function(e)
        if conceallevel and (e.match == "/" or e.match == "?") then
          vim.opt_local.conceallevel = conceallevel
          conceallevel = nil
        end
      end,
    })
  end

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("cmdline_cleanup", { clear = true }),
    callback = function()
      if M._attached then
        pcall(M.disable)
      end
    end,
  })
end

--- Disable the cmdline replacement
function M.disable()
  if not M._attached then
    return
  end
  M._attached = false

  -- Restore cursor if hidden
  if M._guicursor then
    pcall(function()
      vim.go.guicursor = "a:"
      vim.cmd.redrawstatus()
      vim.go.guicursor = M._guicursor
      M._guicursor = nil
    end)
  end

  -- Hide the popup
  View.get():hide()

  -- Detach from UI events
  vim.ui_detach(Config.ns)

  -- Clear augroups
  pcall(vim.api.nvim_del_augroup_by_name, "cmdline_incsearch")
  pcall(vim.api.nvim_del_augroup_by_name, "cmdline_incsearch_leave")
  pcall(vim.api.nvim_del_augroup_by_name, "cmdline_cleanup")
end

--- Setup the plugin
---@param opts? CmdlineConfig
function M.setup(opts)
  Config.setup(opts)

  if not Config.options.enabled then
    return
  end

  -- Schedule loading after VimEnter
  if vim.v.vim_did_enter == 0 then
    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        M.enable()
      end,
    })
  else
    vim.schedule(M.enable)
  end
end

return M
