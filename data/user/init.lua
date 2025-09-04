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
-- bind ctrl+[Num] for first 9 tabs
for i = 1, 9 do
  keymap.add { ["ctrl+" .. i] = "root:switch-to-tab-" .. i }
end

keymap.add { ["ctrl+q"] = "core:quit" }
keymap.add { ["ctrl+d"] = "doc:duplicate-lines" }
keymap.add { ["ctrl+shift+z"] = "doc:redo" }


config.ollama = {
  model = "qwen3-coder:latest",
  url = "http://192.168.1.148:11434", -- base url
  fim_model = "qwen2.5-coder:1.5b-base", -- A different model for FIM
  include_file_context = false, -- Set to true to enable context from other tabs
  custom_prompts =  {
    { text = "Summarize",  prompt = "Summarize the following text:\n\n{input}" },
    { text = "Explain Code",    prompt = "Explain the following code:\n\n{input}" },
    { text = "Tell About",    prompt = "Tell me about:\n\n{input}" },
    { text = "Review",     prompt = "Review the following code and make concise suggestions:\n\n{input}" },
    { text = "Fix Grammar", prompt = "Fix the grammar and spelling in the following text:\n\n```{input}```" },
    { text = "Better wording", prompt = "Modify the following text to improve grammar and spelling:\n{input}"},
    { text = "Make Concise", prompt = "Modify the following text to make it as simple and concise as possible:\n{input}"},
    { text = "Make List", prompt = "Render the following text as a markdown list:\n{input}"},
    { text = "Make Table", prompt = "Render the following text as a markdown table::\n{input}"},
  }
}
