-- data/core/logview.lua (Corrected minimal version)
local core = require "core"
local style = require "core.style"
local View = require "core.view"
local command = require "core.command"
local keymap = require "core.keymap"


local LogView = View:extend()


function LogView:new()
  LogView.super.new(self)
  self.last_item = core.log_items[#core.log_items]
  self.scrollable = true
  self.yoffset = 0
  self.selected_item = nil
end


function LogView:get_name()
  return "Log"
end


function LogView:update()
  local item = core.log_items[#core.log_items]
  if self.last_item ~= item then
    self.last_item = item
    self.scroll.to.y = 0
    self.yoffset = -(style.font:get_height() + style.padding.y)
  end

  self:move_towards("yoffset", 0)

  LogView.super.update(self)
end


local function draw_text_multiline(font, text, x, y, color)
  local th = font:get_height()
  local resx = x
  for line in text:gmatch("[^\n]+") do
    resx = renderer.draw_text(style.font, line, x, y, color)
    y = y + th
  end
  return resx, y
end


function LogView:on_mouse_pressed(button, x, y, clicks)
  local ox, oy = self:get_content_offset()
  local th = style.font:get_height()
  local current_y = oy + style.padding.y + self.yoffset

  for i = #core.log_items, 1, -1 do
    local item = core.log_items[i]
    local text_lines = 1 + select(2, item.text:gsub("\n", ""))
    local info_lines = item.info and (1 + select(2, item.info:gsub("\n", ""))) or 0
    local item_height = (text_lines + info_lines) * th + style.padding.y

    if y >= current_y and y < current_y + item_height then
      self.selected_item = i
      return
    end
    current_y = current_y + item_height
  end
end


function LogView:draw()
  self:draw_background(style.background)

  local ox, oy = self:get_content_offset()
  local th = style.font:get_height()
  local y = oy + style.padding.y + self.yoffset

  for i = #core.log_items, 1, -1 do
    local start_y = y
    local x = ox + style.padding.x
    local item = core.log_items[i]
    local time = os.date(nil, item.time)

    local text_lines = 1 + select(2, item.text:gsub("\n", ""))
    local info_lines = item.info and (1 + select(2, item.info:gsub("\n", ""))) or 0
    local item_height = (text_lines + info_lines) * th + style.padding.y

    if self.selected_item == i then
      renderer.draw_rect(ox, start_y, self.size.x, item_height, style.selection)
    end

    x = renderer.draw_text(style.font, time, x, y, style.dim)
    x = x + style.padding.x
    local subx = x
    local new_x, new_y = draw_text_multiline(style.font, item.text, x, y, style.text)
    renderer.draw_text(style.font, " at " .. item.at, new_x, new_y - th, style.dim)
    if item.info then
      draw_text_multiline(style.font, item.info, subx, new_y, style.dim)
    end
    y = start_y + item_height
  end
end


command.add(LogView, {
  ["log:copy-selection"] = function()
    local view = core.active_view
    if not (view and view:is(LogView) and view.selected_item) then return end

    local item = core.log_items[view.selected_item]
    local time = os.date(nil, item.time)
    local text = string.format("%s at %s: %s", time, item.at, item.text)
    if item.info then
      text = text .. "\n" .. item.info
    end

    system.set_clipboard(text)
    core.log("Log: Copied item to clipboard.")
    view.selected_item = nil
  end
})


keymap.add {
  ["ctrl+c"] = "log:copy-selection"
}


return LogView
