vim.opt.rtp:append(vim.fn.getcwd())

local cmdline = require("cmdline")
local ui = require("cmdline.ui")

cmdline.setup({
  enabled = false,
  view = {
    border = "single",
    max_width = 80,
  },
})

ui.test_enable(cmdline.options)

ui.handle("cmdline_show", { { {}, 'echo "hello"', 0 } }, 12, ":", "", 0, 1, 0)
vim.wait(50)

local state = ui.debug_state()
assert(state.cmd_buf and vim.api.nvim_buf_is_valid(state.cmd_buf), "cmdline buffer was not created")
assert(vim.bo[state.cmd_buf].filetype == "vim", "expected vim filetype for ex cmdline")

ui.handle("cmdline_show", { { {}, 'lua print("hello")', 0 } }, 18, ":", "", 0, 1, 0)
vim.wait(50)

state = ui.debug_state()
assert(vim.bo[state.cmd_buf].filetype == "lua", "expected lua filetype for lua cmdline")

ui.handle("cmdline_hide", 1, false)
vim.wait(50)
cmdline.disable()
vim.cmd("qall!")
