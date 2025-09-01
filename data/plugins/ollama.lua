-- data/plugins/ollama.lua
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"
local config = require "core.config"

-- Helper Functions
local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function json_escape(text)
  local escapes = {
    ["\\"] = "\\\\", ["\""] = "\\\"", ["\n"] = "\\n",
    ["\r"] = "\\r",  ["\t"] = "\\t",  ["\b"] = "\\b", ["\f"] = "\\f"
  }
  return '"' .. text:gsub('[\\"%c]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function json_decode_response(json_string)
  if not json_string or json_string == "" then return nil end
  local response_value = json_string:match('"response":s*"(.-)"s*,"done":')
  if response_value then
    response_value = response_value:gsub('\\"', '"')
    response_value = response_value:gsub('\\n', '\n')
    response_value = response_value:gsub('\\t', '\t')
    response_value = response_value:gsub('\\\\', '\\')
    return response_value
  end
  return nil
end

-- Status & Progress Indicator
local ollama_status = { start_time = nil }
local old_get_items = StatusView.get_items
function StatusView:get_items()
  local left, right = old_get_items(self)
  if ollama_status.start_time then
    local elapsed = math.floor(system.get_time() - ollama_status.start_time)
    table.insert(right, 1, style.accent)
    table.insert(right, 2, string.format("ollama:%ds", elapsed))
    table.insert(right, 3, self.separator)
    table.insert(right, 4, style.dim)
  end
  return left, right
end

-- Main Command Logic
local function run_ollama_command(doc, selected_text, line, col)
  if ollama_status.start_time then
    core.log("Ollama: A request is already in progress.")
    return
  end

  -- Use user's config if available, otherwise fall back to these defaults
  if not config.ollama then
    core.log("Ollama: Using default settings. Set config.ollama in user module to override.")
  end
  local model = (config.ollama and config.ollama.model) or "llama3.1:latest"
  local url = (config.ollama and config.ollama.url) or "http://localhost:11434/api/generate"

  ollama_status.start_time = system.get_time()

  core.add_thread(function()
    local temp_file = core.temp_filename()

    local json_payload = string.format(
      '{"model": "%s", "prompt": %s, "stream": false}',
      model,
      json_escape(selected_text)
    )

    local curl_command = string.format(
      "curl -s -X POST %s -d %s > %q 2>/dev/null",
      url,
      shell_escape(json_payload),
      temp_file
    )

    core.log("Ollama executing command: %s", curl_command)
    system.exec(curl_command)

    local timeout = 120
    while system.get_time() - ollama_status.start_time < timeout do
      local info = system.get_file_info(temp_file)
      if info and info.size > 0 then
        coroutine.yield(0.1)
        break
      end
      coroutine.yield(0.1)
    end

    ollama_status.start_time = nil

    local fp = io.open(temp_file)
    if not fp then
      core.error("Ollama: Could not open temporary output file.")
      return
    end

    local result = fp:read("*a")
    fp:close()

    local response_text = json_decode_response(result)
    if response_text then
      doc:insert(line, col, "\n" .. response_text)
      core.log("Ollama: Response inserted.")
    else
      core.error("Ollama: Could not parse response from API.")
      core.log("Full Response: " .. tostring(result))
    end
  end)
end

command.add("core.docview", {
  ["ollama:generate"] = function()
    local doc = core.active_view.doc
    if not doc:has_selection() then
      core.log("Ollama: Please select some text to use as a prompt.")
      return
    end

    local selected_text
    local line1, col1, line2, col2

    doc:replace(function(text) selected_text = text; return text end)
    line1, col1, line2, col2 = doc:get_selection(true)

    run_ollama_command(doc, selected_text, line2, col2)
  end,
})

-- Keybinding
keymap.add {
  ["alt+\\"] = "ollama:generate",
}
