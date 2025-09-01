-- data/plugins/ollama.lua
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"


-- Escapes a string for use within a shell command's single quotes
local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end


-- Escapes a string into a valid JSON string literal (using double quotes)
local function json_escape(text)
  local escapes = {
    ["\\"] = "\\\\", ["\""] = "\\\"", ["\n"] = "\\n",
    ["\r"] = "\\r",  ["\t"] = "\\t",  ["\b"] = "\\b", ["\f"] = "\\f"
  }
  return '"' .. text:gsub('[\\"%c]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end


-- A simple JSON decoder to extract the "response" field
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


local function run_ollama_command(doc, selected_text, line, col)
  -- Show a status message that we're starting the process
  core.status_view:show_message("Ollama", style.text, "Generating response...")

  -- Create a new thread to run the command without blocking the UI
  core.add_thread(function()
    -- 1. Create a temporary file to store the command's output
    local temp_file = core.temp_filename()

    -- 2. Build the JSON payload and the full curl command with redirection
    local model_name = "qwen3-coder:latest"
    -- FIX #1: Corrected the port number from 1434 to 11434
    local endpoint = "http://192.168.1.148:11434/api/generate"
    local json_payload = string.format(
      '{"model": "%s", "prompt": %s, "stream": false}',
      model_name,
      json_escape(selected_text)
    )
    -- We keep "2>/dev/null" to hide curl's progress meter, but now the command should succeed
    local curl_command = string.format(
      "curl -s -X POST %s -d %s > %q 2>/dev/null",
      endpoint,
      shell_escape(json_payload),
      temp_file
    )

    -- 3. Execute the command. system.exec is non-blocking.
    system.exec(curl_command)

    -- 4. Poll for the result. This is the key to not freezing.
    local start_time = system.get_time()
    local timeout = 60 -- 60 second timeout
    while system.get_time() - start_time < timeout do
      local info = system.get_file_info(temp_file)
      if info and info.size > 0 then
        coroutine.yield(0.1)
        break
      end
      coroutine.yield(0.1)
    end

    -- 5. Read the result from the temporary file
    local fp = io.open(temp_file)
    if not fp then
      core.error("Ollama: Could not open temporary output file.")
      return
    end
    local result = fp:read("*a")
    fp:close()
    -- FIX #2: Removed os.remove(temp_file) to avoid potential sandbox errors.
    -- Lite will clean up temp files created with core.temp_filename() on exit.

    -- 6. Parse the response and insert it into the document
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

keymap.add {
  ["ctrl+o"] = "ollama:generate",
}
