--ollama.lua
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"

-- This function to escape shell arguments remains the same.
local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- This simple JSON parser also remains the same.
local function json_decode(json_string)
  if not json_string or json_string == "" then return nil end
  local response_value = json_string:match('"response":"(.-)"')
  if response_value then
    response_value = response_value:gsub('\\"', '"')
    response_value = response_value:gsub('\\n', '\n')
    response_value = response_value:gsub('\\t', '\t')
    response_value = response_value:gsub('\\\\', '\\')
    return { response = response_value }
  end
  return nil
end

command.add("core.docview", {
  ["ollama:generate"] = function()
    local doc = core.active_view.doc
    if not doc:has_selection() then return end

    -- Declare all local variables at the top of the function
    local selected_text
    local line2, col2

    doc:replace(function(text)
      selected_text = text
      return text
    end)
    -- Assign values to the already-declared local variables
    _, _, line2, col2 = doc:get_selection()

    local model_name = "llama2"
    local endpoint = "http://localhost:11434/api/generate"

    local json_payload = string.format(
      '{"model": "%s", "prompt": %s, "stream": false}',
      model_name,
      shell_escape(selected_text)
    )

    local temp_file = os.tmpname()
    local curl_command = string.format(
      "curl -s -X POST %s -d %s > %s 2>/dev/null",
      endpoint,
      shell_escape(json_payload),
      temp_file
    )

    local ok = os.execute(curl_command)

    if ok then
      local f = io.open(temp_file, "rb")
      if f then
        local result = f:read("*a")
        f:close()
        os.remove(temp_file)

        local data = json_decode(result)
        if data and data.response then
          doc:insert(line2, col2, "\n" .. data.response)
        else
          core.log_error("Ollama: Received an invalid response from the API.")
          core.log_error("Response: " .. tostring(result))
        end
      end
    else
      core.log_error("Ollama: Failed to execute curl command.")
      os.remove(temp_file)
    end
  end,
})

keymap.add {
  ["ctrl+o"] = "ollama:generate",
}
