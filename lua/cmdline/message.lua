--- Simple message content block for cmdline rendering
local Block = require("cmdline.block")

local _id = 0

---@class CmdlineMessage: CmdlineBlock
---@field id number
---@field title? string
local Message = Block:extend("CmdlineMessage")

function Message:init()
  _id = _id + 1
  self.id = _id
  self.title = nil
  Block.init(self)
end

return Message
