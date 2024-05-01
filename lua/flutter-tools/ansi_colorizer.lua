local function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k, v in pairs(o) do
      if type(k) ~= 'number' then k = '"' .. k .. '"' end
      s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

local default_colors = vim.api.nvim_get_hl(0, { name = "Normal" })
local default_fg = string.format('#%06X', default_colors['fg'])
local default_bg = string.format('#%06X', default_colors['bg'])

local base16_colors = {
  { color = "#2e3436",  fg_id = 30, bg_id = 40 },  -- Black
  { color = "#cc0000",  fg_id = 31, bg_id = 41 },  -- Red
  { color = "#4e9a06",  fg_id = 32, bg_id = 42 },  -- Green
  { color = "#c4a000",  fg_id = 33, bg_id = 43 },  -- Yellow
  { color = "#729fcf",  fg_id = 34, bg_id = 44 },  -- Blue
  { color = "#75507b",  fg_id = 35, bg_id = 45 },  -- Magenta
  { color = "#06989a",  fg_id = 36, bg_id = 46 },  -- Cyan
  { color = "#d3d7cf",  fg_id = 37, bg_id = 47 },  -- White
  { color = "#555753",  fg_id = 90, bg_id = 100 }, -- Bright Black
  { color = "#ef2929",  fg_id = 91, bg_id = 101 }, -- Bright Red
  { color = "#8ae234",  fg_id = 92, bg_id = 102 }, -- Bright Green
  { color = "#fce94f",  fg_id = 93, bg_id = 103 }, -- Bright Yellow
  { color = "#32afff",  fg_id = 94, bg_id = 104 }, -- Bright Blue
  { color = "#ad7fa8",  fg_id = 95, bg_id = 105 }, -- Bright Magenta
  { color = "#34e2e2",  fg_id = 96, bg_id = 106 }, -- Bright Cyan
  { color = "#eeeeec",  fg_id = 97, bg_id = 107 }, -- Bright White
  { color = default_fg, fg_id = 39 },              -- Default fg
  { color = default_bg, bg_id = 49 },              -- Default bg
}

-- Retrieves the type (foreground or background) and the hexadecimal representation of a color corresponding to the provided ID.
-- It returns two values: a string indicating the color type ("fg" for foreground or "bg" for background),
-- and the corresponding color value.
-- If no match is found, it returns nil.
local function get_colors_by_id(id)
  for _, base16_color in ipairs(base16_colors) do
    if id == base16_color.fg_id then
      return "fg", base16_color.color
    elseif id == base16_color.bg_id then
      return "bg", base16_color.color
    end
  end

  return nil
end

local function parse_ansi_colors(line)
  local parsed_line = {}
  local remaining_line = line

  while true do
    local escape_start, escape_end, color_code = string.find(remaining_line, '\27%[([%d;]+)m')

    -- Check if escape code was not found
    if not escape_start then
      table.insert(parsed_line, remaining_line)
      break
    end

    local text_before_escape = string.sub(remaining_line, 1, escape_start - 1)
    if text_before_escape ~= '' then
      table.insert(parsed_line, text_before_escape)
    end

    local parsed_token = {}

    -- Parse all the colors in the escape sequence
    for color_id in string.gmatch(color_code, "([^;]+)") do
      local type, color = get_colors_by_id(tonumber(color_id))
      if type == 'fg' then
        parsed_token.fg_color = color
      elseif type == 'bg' then
        parsed_token.bg_color = color
      end
    end

    if parsed_token.fg_color == nil and parsed_token.bg_color == nil then
      table.insert(parsed_line, string.sub(remaining_line, escape_start, escape_end))
      remaining_line = string.sub(remaining_line, escape_end + 1)
    else
      local text_start = escape_end + 1
      local text_end = string.find(remaining_line, '\27%[', text_start) or #remaining_line
      local text = string.sub(remaining_line, text_start, text_end - 1)

      parsed_token.escape_length = escape_end - escape_start + 1
      parsed_token.text = text
      table.insert(parsed_line, parsed_token)

      remaining_line = string.sub(remaining_line, text_end)
    end
  end

  return parsed_line
end

local function highlight_ansi_colors(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parsed_lines = {}
  for _, line in ipairs(lines) do
    local parsed_line = parse_ansi_colors(line)
    table.insert(parsed_lines, parsed_line)
  end

  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  for i, parsed_line in ipairs(parsed_lines) do
    local line_start = vim.api.nvim_buf_get_offset(bufnr, i - 1)
    local col = 0
    for _, part in ipairs(parsed_line) do
      if type(part) == 'table' then
        local text = part.text
        local fg_color = part.fg_color or ""
        local bg_color = part.bg_color or ""
        local escape_length = part.escape_length
        local hl_group = 'AnsiColor' .. 'fg' .. fg_color:gsub("#", "") .. 'bg' .. bg_color:gsub("#", "")

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

return M
