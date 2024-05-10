local function dump(o)
  if type(o) == "table" then
    local s = "{ "
    for k, v in pairs(o) do
      if type(k) ~= "number" then k = '"' .. k .. '"' end
      s = s .. "[" .. k .. "] = " .. dump(v) .. ","
    end
    return s .. "} "
  else
    return tostring(o)
  end
end

local base16_colors = {
  { color = "#000000", fg_id = 30, bg_id = 40 },  -- Black
  { color = "#800000", fg_id = 31, bg_id = 41 },  -- Red
  { color = "#008000", fg_id = 32, bg_id = 42 },  -- Green
  { color = "#808000", fg_id = 33, bg_id = 43 },  -- Yellow
  { color = "#000080", fg_id = 34, bg_id = 44 },  -- Blue
  { color = "#800080", fg_id = 35, bg_id = 45 },  -- Magenta
  { color = "#008080", fg_id = 36, bg_id = 46 },  -- Cyan
  { color = "#c0c0c0", fg_id = 37, bg_id = 47 },  -- White
  { color = "#808080", fg_id = 90, bg_id = 100 }, -- Bright Black
  { color = "#ff0000", fg_id = 91, bg_id = 101 }, -- Bright Red
  { color = "#00ff00", fg_id = 92, bg_id = 102 }, -- Bright Green
  { color = "#ffff00", fg_id = 93, bg_id = 103 }, -- Bright Yellow
  { color = "#0000ff", fg_id = 94, bg_id = 104 }, -- Bright Blue
  { color = "#ff00ff", fg_id = 95, bg_id = 105 }, -- Bright Magenta
  { color = "#00ffff", fg_id = 96, bg_id = 106 }, -- Bright Cyan
  { color = "#ffffff", fg_id = 97, bg_id = 107 }, -- Bright White
  { color = nil,       fg_id = 39 },              -- Default fg
  { color = nil,       bg_id = 49 },              -- Default bg
}

local base256_colors = {}

-- Original 16 colors
for i, value in ipairs(base16_colors) do
  base256_colors[i - 1] = value.color
end
-- 216 colors after original 16 colors
for i = 16, 231, 1 do
  local i_offset = i - 16

  local RGB = {
    red = math.floor(i_offset / 36),
    green = math.floor((i_offset % 36) / 6),
    blue = i_offset % 6,
  }

  for color, value in pairs(RGB) do
    if value ~= 0 then
      RGB[color] = value * 40 + 55
    end
  end

  base256_colors[i] = string.format("#%02x%02x%02x", RGB["red"], RGB["green"], RGB["blue"])
end
-- Grey scale colors
for i = 232, 255, 1 do
  local lightness = 10 * (i - 232) + 8
  base256_colors[i] = string.format("#%02x%02x%02x", lightness, lightness, lightness)
end

---Gets the color information from an ANSI color code
---@param color_code string The ANSI color code
-- nil represents reset, -1 represents no-op
local function get_colors_by_escape(color_code)
  local READING_STATE = {
    default = 0,    -- Default state
    pending_fg = 1, -- Deciding if should read a 256 Color or RGB value for the foreground
    pending_bg = 2, -- Deciding if should read a 256 Color or RGB value for the background
    fg_256 = 3,     -- Ready to read a 256 foreground color
    bg_256 = 4,     -- Ready to read a 256 background color
  }
  local fg, bg = -1, -1
  local current_state = READING_STATE.default ---@type integer

  -- Parse all the colors in the escape sequence
  for color_id in string.gmatch(color_code, "([^;]+)") do
    if current_state == READING_STATE.pending_fg then
      if color_id == "5" then
        current_state = READING_STATE.fg_256
      else
        current_state = READING_STATE.default
      end
    elseif current_state == READING_STATE.pending_bg then
      if color_id == "5" then
        current_state = READING_STATE.bg_256
      else
        current_state = READING_STATE.default
      end
    elseif current_state == READING_STATE.fg_256 then
      fg = base256_colors[tonumber(color_id)]
      current_state = READING_STATE.default
    elseif current_state == READING_STATE.bg_256 then
      bg = base256_colors[tonumber(color_id)]
      current_state = READING_STATE.default
    elseif current_state == READING_STATE.default then
      if color_id == "0" then
        fg, bg = nil, nil
      elseif color_id == "38" then
        current_state = READING_STATE.pending_fg
      elseif color_id == "48" then
        current_state = READING_STATE.pending_bg
      else
        for _, base16_color in ipairs(base16_colors) do
          if color_id == tostring(base16_color.fg_id) then
            fg = base16_color.color
          elseif color_id == tostring(base16_color.bg_id) then
            bg = base16_color.color
          end
        end
      end
    end
  end

  return { fg = fg, bg = bg }
end

local function parse_ansi_colors(line, prev_fg, prev_bg)
  local parsed_line = {}
  local remaining_line = line

  while true do
    local escape_start, escape_end, color_code = string.find(remaining_line, "\27%[([%d;]+)m")

    -- Check if escape code was not found
    if not escape_start then
      table.insert(parsed_line, remaining_line)
      break
    end

    local text_before_escape = string.sub(remaining_line, 1, escape_start - 1)
    if text_before_escape ~= "" then
      if prev_fg == nil and prev_bg == nil then
        table.insert(parsed_line, text_before_escape)
      else
        table.insert(parsed_line,
          { text = text_before_escape, fg_color = prev_fg, bg_color = prev_bg })
      end
    end

    -- Parse all the colors in the escape sequence
    local result = get_colors_by_escape(color_code)
    if result.fg ~= -1 then
      prev_fg = result.fg
    end
    if result.bg ~= -1 then
      prev_bg = result.bg
    end

    if prev_fg == nil and prev_bg == nil then
      table.insert(parsed_line, string.sub(remaining_line, escape_start, escape_end))
      remaining_line = string.sub(remaining_line, escape_end + 1)
    else
      local text_start = escape_end + 1
      local text_end = string.find(remaining_line, "\27%[", text_start) or (#remaining_line + 1)
      local text = string.sub(remaining_line, text_start, text_end - 1)

      table.insert(parsed_line,
        { escape_length = escape_end - escape_start + 1, text = text, fg_color = prev_fg, bg_color = prev_bg })

      remaining_line = string.sub(remaining_line, text_end)
    end
  end

  return parsed_line, prev_fg, prev_bg
end

local function highlight_ansi_colors(bufnr)
  -- Parse each line in the buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parsed_lines = {}
  local prev_fg, prev_bg
  for _, line in ipairs(lines) do
    local parsed_line
    parsed_line, prev_fg, prev_bg = parse_ansi_colors(line, prev_fg, prev_bg)

    table.insert(parsed_lines, parsed_line)
  end

  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  for i, parsed_line in ipairs(parsed_lines) do
    local col = 0
    for _, part in ipairs(parsed_line) do
      if type(part) == "table" then
        local text = part.text
        local fg_color = part.fg_color or ""
        local bg_color = part.bg_color or ""
        local escape_length = part.escape_length or 0

        local hl_group = "AnsiColor" .. "fg" .. fg_color:gsub("#", "") .. "bg" .. bg_color:gsub("#", "")

        col = col + escape_length
        vim.api.nvim_set_hl(0, hl_group, { fg = fg_color, bg = bg_color })
        vim.api.nvim_buf_add_highlight(bufnr, -1, hl_group, i - 1, col, col + #text)
        col = col + #text
      else
        col = col + #part
      end
    end
  end
end

local M = {}

function M.highlight_ansi_colors(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  highlight_ansi_colors(bufnr)
end

function M.conceal_ansi_color_codes()
  vim.cmd([[set conceallevel=2]])
  vim.cmd([[syntax match ConcealANSI /[^m]*m/ conceal]])
end

function M.print_256()
  print(dump(base256_colors))
end

return M
