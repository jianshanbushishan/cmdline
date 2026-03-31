--- Minimal OOP class system for cmdline.nvim
--- Replaces nui.object with a lightweight implementation
local M = {}

---@param name string class name
---@return table
function M.create(name)
  local Class = {}
  Class.name = name
  Class.super = nil
  Class.__index = Class

  ---@return table
  function Class:new(...)
    local instance = setmetatable({}, self)
    instance:init(...)
    return instance
  end

  function Class:init() end

  ---@param subname string subclass name
  ---@return table
  function Class:extend(subname)
    local SubClass = {}
    SubClass.name = subname
    SubClass.super = self
    SubClass.__index = SubClass

    ---@return table
    function SubClass:new(...)
      local instance = setmetatable({}, self)
      instance:init(...)
      return instance
    end

    -- Copy parent methods
    for key, value in pairs(self) do
      if SubClass[key] == nil and type(value) == "function" then
        SubClass[key] = value
      end
    end

    return SubClass
  end

  return Class
end

return M
