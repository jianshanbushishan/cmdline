local config = require("cmdline.config")
local ui = require("cmdline.ui")

local M = {
  options = nil,
}

function M.setup(opts)
  M.options = config.normalize(opts)

  if M.options.enabled ~= false then
    ui.enable(M.options)
  end

  return M
end

function M.enable()
  if not M.options then
    M.options = config.normalize()
  end

  ui.enable(M.options)
end

function M.disable()
  ui.disable()
end

function M.toggle()
  if ui.is_enabled() then
    ui.disable()
  else
    M.enable()
  end
end

function M.is_enabled()
  return ui.is_enabled()
end

return M

