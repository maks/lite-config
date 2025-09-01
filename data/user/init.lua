-- put user settings here this module will be loaded after everything else when
-- the application starts
local keymap = require "core.keymap"
local config = require "core.config"
local style = require "core.style"
--
-- light theme: require "user.colors.summer"
--
-- alt dark theme require "user.colors.fall"

-- Key bindings

-- bind ctrl+X for first 9 tabs
for i = 1, 9 do
  keymap.add { ["ctrl+" .. i] = "root:switch-to-tab-" .. i }
end

keymap.add { ["ctrl+q"] = "core:quit" }
keymap.add { ["ctrl+d"] = "doc:duplicate-lines" }

