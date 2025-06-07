local M = {}
local popup = require("plenary.popup")
local git_ignore_file_name = "./.gitignore"
local ignore_file_name = "./.ignore"

local function split(ignore_file, sep)
  local arr = {}
  -- Group 
  for str in string.gmatch(ignore_file, '([^' .. sep .. ']+)')
  do
    table.insert(arr, str)
  end
  return arr
end

-- Logic for reading in .ignore
local function get_ignore_file()
  -- io.input(ignore_file_name)
  io.input(git_ignore_file_name)
  -- local fileData = io.read("*all")
  local fileData = io.read("a")
  return fileData
end

local function process_ignore_line(ignore_line)
  vim.notify(ignore_line)
end

local function process_ignore_file()
  local ignore_file = get_ignore_file()
  local ignore_file_lines = split(ignore_file, "\n")
  for i = 1, table.getn(ignore_file_lines)
  do
    process_ignore_line(ignore_file_lines[i])
  end
end

Dig_window = nil
Dig_window_id = nil

-- Creates a window, sets Dig_window_id to be used by close_window()
-- Returns the window_id and window to ensure that toggle() works correctly
local function create_window()
  local window_buffer = vim.api.nvim_create_buf(false, false)
  local width = 70
  local height = 20
  local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }
  Dig_window_id, Dig_window = popup.create(window_buffer, {
    title = "Dig",
    highlight = "DigWindow",
    line = math.floor(((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    minwidth = width,
    minheight = height,
    borderchars = borderchars,
  })
  vim.api.nvim_win_set_option(
    Dig_window.border.win_id,
    "winhl", -- Highlights
    "Normal:DigBorder"
  )

  return {
    win_buf = window_buffer,
    win_id = Dig_window_id
  }
end

--Dig_window_id should be non null here
local function close_window()
  vim.api.nvim_win_close(Dig_window_id, true)
end

-- Closes window and returns if window is open
--
-- Creates a window if it isn't open.
-- Add <ESC> command in the new buffer to toggle (close) the window
function M.toggle_window()
  -- vim.notify("toggling")
  process_ignore_file()

  local window_is_open = Dig_window_id ~= nil and vim.api.nvim_win_is_valid(Dig_window_id)
  if window_is_open then
    -- close_window()
    -- return
  else
    -- local win = create_window()
    -- local win_buf = win.win_buf
    -- vim.api.nvim_buf_set_keymap(win_buf, 'n', '<ESC>', '<Cmd>lua require("dig").toggle_window()<CR>',
    --   { silent = true })

    -- 0 Based indexing in nvim api
    -- 1 based indexing with native lua
    -- vim.api.nvim_buf_set_lines(win_buf,0,0,true,{"Hello World"})
    -- vim.api.nvim_buf_set_lines(win_buf,1,1,true,{"Hello World2"})
    -- local line_ct = vim.api.nvim_buf_line_count(win_buf)
    -- local line1 = vim.api.nvim_buf_get_lines(win_buf, 1, 2, true)
    -- print(line1[1])
  end
end

vim.keymap.set('n', '<leader>-', '<Cmd>lua require("dig").toggle_window()<CR>')
return M
