vim.opt.rtp:append(vim.fn.getcwd())

local cmdline = require("cmdline")
local util = require("cmdline.util")

cmdline.setup({
  enabled = false,
})

local restored = false
local ok = pcall(function()
  util.ignore_events(function()
    error("boom")
  end)
end)

assert(not ok, "ignore_events should rethrow callback errors")
assert(vim.go.eventignore == "", "ignore_events should always restore eventignore")

restored = true
assert(restored, "smoke test should continue after ignore_events failure")

vim.cmd("quitall!")
