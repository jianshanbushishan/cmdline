if vim.g.loaded_cmdline_nvim == 1 then
  return
end

vim.g.loaded_cmdline_nvim = 1

vim.api.nvim_create_user_command("CmdlineEnable", function()
  require("cmdline").enable()
end, {})

vim.api.nvim_create_user_command("CmdlineDisable", function()
  require("cmdline").disable()
end, {})

vim.api.nvim_create_user_command("CmdlineToggle", function()
  require("cmdline").toggle()
end, {})

