-- data/plugins/ollama.lua
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"
local config = require "core.config"
local json = require "plugins.json"

-- #############################################################################
-- # FIM Prompt Templates
-- #############################################################################

local FIM_TEMPLATES = {
  -- Based on twinny's advanced template for Qwen and similar models.
  -- Arguments: 1=file_context, 2=heading, 3=prefix, 4=suffix
  qwen_context = "<|file_sep|>%s\n\n<|file_sep|>%s<|fim_prefix|>%s<|fim_suffix|>%s<|fim_middle|>",
  -- Simple template for when file context is disabled
  qwen_simple = "<|fim_prefix|>%s<|fim_suffix|>%s<|fim_middle|>"
}

-- #############################################################################
-- # Custom Prompts
-- #############################################################################

-- Users can add their own prompts here or override in their user/init.lua file.
-- Example for user/init.lua:
-- config.ollama.custom_prompts = {
--   { text = "Translate to French", prompt = "Translate the following to French:\n\n{input}" }
-- }
local CUSTOM_PROMPTS = {
  { text = "Summarize",   prompt = "Summarize the following text:\n\n{input}" },
  { text = "Explain",     prompt = "Explain the following code:\n\n{input}" },
  { text = "Fix Grammar", prompt = "Fix the grammar and spelling in the following text:\n\n{input}" }
}

-- #############################################################################
-- # Helper Functions
-- #############################################################################

local function shell_escape(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function json_decode_response(json_string)
  if not json_string or json_string == "" then return nil end
  local data = json.decode(json_string)
  return data and data.response
end

-- This function correctly returns a list of tables for the command view
local function json_decode_tags(json_string)
  if not json_string or json_string == "" then return {} end
  local data = json.decode(json_string)
  local models = {}
  if data and data.models then
    for _, model_info in ipairs(data.models) do
      table.insert(models, { text = model_info.name })
    end
  end
  return models
end


-- #############################################################################
-- # Status Bar Progress Indicator
-- #############################################################################

local ollama_status = { start_time = nil }

local old_get_items = StatusView.get_items
function StatusView:get_items()
  local left, right = old_get_items(self)
  if ollama_status.start_time then
    local elapsed = math.floor(system.get_time() - ollama_status.start_time)
    table.insert(right, 1, style.dim)
    table.insert(right, 2, self.separator)
    table.insert(right, 3, style.accent)
    table.insert(right, 4, string.format("Ollama:%ds", elapsed))
  end
  return left, right
end

-- #############################################################################
-- # Main Command Logic
-- #############################################################################

local function build_fim_prompt(doc)
  local use_context = (config.ollama and config.ollama.include_file_context) or false
  local line, col = doc:get_selection()
  local text = table.concat(doc.lines, "")

  local byte_offset = 0
  for i = 1, line - 1 do byte_offset = byte_offset + #doc.lines[i] end
  byte_offset = byte_offset + col - 1

  local prefix = text:sub(1, byte_offset)
  local suffix = text:sub(byte_offset + 1)

    -- 2. Check if we should include context from other files
  if not use_context then
    return string.format(FIM_TEMPLATES.qwen_simple, prefix, suffix)
  end

  -- 3. Build the file context from other open tabs
  local file_context_parts = {}
  for _, other_doc in ipairs(core.docs) do
    if other_doc ~= doc and other_doc.filename then
      table.insert(file_context_parts, other_doc.filename)
    end
  end
  local file_context = table.concat(file_context_parts, "\n")

  -- 4. Get language and assemble the heading for the current file
  local language = doc.highlighter.syntax.name or "text"
  local heading = string.format("--- Path: %s Language: %s ---", doc.filename or "untitled", language)
  return string.format(FIM_TEMPLATES.qwen_context, file_context, heading, prefix, suffix)
end

local function run_ollama_command(doc, prompt, model_name, line, col)
  if ollama_status.start_time then
    core.log("Ollama: A request is already in progress.")
    return
  end

  local base_url = (config.ollama and config.ollama.url) or "http://localhost:11434"
  local url = base_url .. "/api/generate"
  ollama_status.start_time = system.get_time()

  core.add_thread(function()
    local temp_file = core.temp_filename()

    --  Use a Lua table for the payload
    local payload_table = {
      model = model_name,
      prompt = prompt,
      stream = false
    }
    -- Encode the table into a JSON string using the library
    local json_payload = json.encode(payload_table)

    local curl_command = string.format("curl -s -X POST %s -d %s > %q 2>/dev/null", url, shell_escape(json_payload), temp_file)

    core.log("Ollama executing for model '%s'", model_name)
    system.exec(curl_command)

    local timeout = 120
    while system.get_time() - ollama_status.start_time < timeout do
      local info = system.get_file_info(temp_file)
      if info and info.size > 0 then coroutine.yield(0.1); break end
      coroutine.yield(0.1)
    end

    ollama_status.start_time = nil

    local fp = io.open(temp_file)
    if not fp then core.error("Ollama: Could not open temporary file."); return end
    local result = fp:read("*a"); fp:close()

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
    local model = (config.ollama and config.ollama.model) or "qwen3-coder:latest"
    local fim_model = (config.ollama and config.ollama.fim_model) or model
    local use_context = (config.ollama and config.ollama.include_file_context) or false

    if doc:has_selection() then
      -- Mode 1: Use selected text as a direct prompt
      local selection
      doc:replace(function(text) selection = text; return text end)
      local _, _, l2, c2 = doc:get_selection(true)
      run_ollama_command(doc, selection, model, l2, c2)
    else
      -- Mode 2: No selection, use FIM for code completion
      local prompt = build_fim_prompt(doc, use_context)
      local line, col = doc:get_selection()
      run_ollama_command(doc, prompt, fim_model, line, col)
    end
  end,

  -- Command for handling custom prompts
  ["ollama:custom-prompt"] = function()
    local doc = core.active_view.doc
    local model = (config.ollama and config.ollama.model) or "llama3.1:latest"
    local prompts = (config.ollama and config.ollama.custom_prompts) or CUSTOM_PROMPTS

    -- Phase 1: Let the user choose a prompt template
    local function on_prompt_select(text, item)
      if not item or not item.prompt then return end
      local template = item.prompt

      -- Phase 2: Get user input for the {input} placeholder
      local function on_input_done(text)
        local input = text
        -- If the user didn't type anything, use the current selection
        if input == "" and doc:has_selection() then
          doc:replace(function(sel_text) input = sel_text; return sel_text end)
        end

        if input == "" then
          core.error("Ollama: No input provided for the prompt.")
          return
        end

        -- snsure properly escaped input text
        input = input:gsub("%%", "%%%%")

        -- Construct the final prompt and run the command
        local final_prompt = template:gsub("{input}", input)

        -- Create a new doc for the response
        local new_doc = core.open_doc()
        core.root_view:open_doc(new_doc)

        run_ollama_command(new_doc, final_prompt, model, 1, 1)
      end

      -- Show the input prompt in the command view
      core.command_view:enter(item.text .. ": ", on_input_done)
    end

    -- Show the list of custom prompts in the command view
    core.command_view:enter("Custom Prompt", on_prompt_select, function() return prompts end)
  end,
})

command.add(nil, {
  ["ollama:list-models"] = function()
    local base_url = (config.ollama and config.ollama.url) or "http://localhost:11434"
    local url = base_url .. "/api/tags"
    core.log("Ollama: Fetching model list...")

    core.add_thread(function()
      local temp_file = core.temp_filename()
      local curl_command = string.format("curl -s %s > %q 2>/dev/null", url, temp_file)
      system.exec(curl_command)
      coroutine.yield(2)

      local fp = io.open(temp_file)
      if not fp then core.error("Ollama: Could not open temp file for tags."); return end
      local result = fp:read("*a"); fp:close()

      local models = json_decode_tags(result)

      if models and #models > 0 then
        -- This is the correct callback implementation to show the list in the command pane
        local function on_model_select(text, item)
          if item and item.text then
            system.set_clipboard(item.text)
            core.log("Ollama: Copied '%s' to clipboard.", item.text)
          end
        end
        core.command_view:enter("Ollama Models", on_model_select, function() return models end)
      else
        core.error("Ollama: No models found or failed to parse tags response.")
        core.log("Full Response: " .. tostring(result))
      end
    end)
  end
})

-- #############################################################################
-- # Keybindings
-- #############################################################################

keymap.add {
  ["alt+\\"] = "ollama:generate"
}
