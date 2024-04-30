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
local ansicolors_fg = {
  [30] = '#000000',
  [31] = '#CC0000',
  [32] = '#4E9A06',
  [33] = '#C4A000',
  [34] = '#729FCF',
  [35] = '#75507B',
  [36] = '#06989A',
  [37] = '#D3D7CF',
  [39] = string.format('#%06X', default_colors['fg']),
}
local ansicolors_bg = {
  [40] = '#000000',
  [41] = '#CC0000',
  [42] = '#4E9A06',
  [43] = '#C4A000',
  [44] = '#729FCF',
  [45] = '#75507B',
  [46] = '#06989A',
  [47] = '#D3D7CF',
  [49] = string.format('#%06X', default_colors['bg']),
}

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

    local fg_color = ansicolors_fg[tonumber(color_code)]
    local bg_color = ansicolors_bg[tonumber(color_code)]

    if fg_color == nil and bg_color == nil then
      table.insert(parsed_line, string.sub(remaining_line, escape_start, escape_end))
      remaining_line = string.sub(remaining_line, escape_end + 1)
    else
      local text_start = escape_end + 1
      local text_end = string.find(remaining_line, '\27%[', text_start) or #remaining_line
      local text = string.sub(remaining_line, text_start, text_end - 1)

      if fg_color then
        table.insert(parsed_line, { escape_length = escape_end - escape_start + 1, text = text, fg_color = fg_color })
      end
      if bg_color then
        table.insert(parsed_line, { escape_length = escape_end - escape_start + 1, text = text, bg_color = bg_color })
      end

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
