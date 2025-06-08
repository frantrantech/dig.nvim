local M = {}
local popup = require("plenary.popup")
local PREV_DIR_NAME = ".."
local CURR_DIR_NAME = "."
local COMMENT_CHAR = "#"
local NEW_LINE = "\n"
local FIRST_LS_INDEX = 6
local IS_DIR = 256
local git_ignore_file_name = "./.gitignore"
local ignore_file_name = "./.ignore"

local function split(str, sep)
  local arr = {}
  -- Split by sep and capture the str
  for s in string.gmatch(str, '([^' .. sep .. ']+)')
  do
    table.insert(arr, s)
  end
  return arr
end

local function strip_new_line(str)
  return str:sub(1,string.len(str)-1)
end


-- Take a file name from ls and determine if it is a directory or notify
-- Is a directory
local function file_is_dir(path)
  local is_dir = os.execute('[ -f "' .. path .. '" ]') == IS_DIR
  return is_dir
end

-- Returns the result of calling "ls" on "dir" as an array
local function get_dir_contents(dir)
  local ls_output = io.popen('ls -a ' .. dir .. '', "r")
  local ls = ls_output:read("a")
  local ls_cleaned = ls:sub(FIRST_LS_INDEX)
  local ls_arr = split(ls_cleaned, "\n")
  return ls_arr
end

-- given a directory, update the file and dir arrays. recursively call this for all immediate child dirs
local function get_dir_files(dir, all_files, all_dirs)
  local dir_contents = get_dir_contents(dir)
  local child_dirs = {}

  -- Update global list of files and dirs
  for i=1, table.getn(dir_contents)
    do
      local curr_path = '' .. dir.. '/'.. dir_contents[i] ..''
      if file_is_dir(curr_path)
        then
          table.insert(all_dirs,curr_path)
          table.insert(child_dirs,curr_path)
        else
          table.insert(all_files,curr_path)
        end
    end

  -- Repeat for all child dirs of dir 
  for i=1, table.getn(child_dirs)
    do
      get_dir_files(child_dirs[i],all_files, all_dirs)
    end
end

local function get_all_dirs_files()
  local project_root_pwd = io.popen("pwd")
  local project_root_name = project_root_pwd:read("a")
  local all_files = {}
  local all_dirs = {}
  get_dir_files(strip_new_line(project_root_name), all_files, all_dirs)
  -- vim.print(all_files)
end

local function get_ignore_file_contents()
  io.input(git_ignore_file_name)
  local fileData = io.read("a")
  io.close()
  return fileData
end

-- Returns true if we shouldn't process this ignore
local function pre_process_ignore_line(ignore_line)
  -- Lua str indexing is weird. Basically use a substring to read a character. Here we use a "metatable?"
  -- See metatables: https://www.lua.org/pil/13.html Metatables allow us to change the behavior of a table. For instance, using metatables, we can define how Lua computes the expression a+b, where a and b are tables. Whenever Lua tries to add two tables, it checks whether either of them has a metatable and whether that metatable has an __add field. If Lua finds this field, it calls the corresponding value (the so-called metamethod, which should be a function) to compute the sum.

  -- Ignore if this is a comment
  if ignore_line:sub(1, 1) == COMMENT_CHAR
  then
    return true
  end
  return false
end

local function process_ignore_line(ignore_line)
  local should_skip_line = pre_process_ignore_line(ignore_line)
  if should_skip_line then return end
end

local function process_ignore_file()
  local ignore_file = get_ignore_file_contents()
  local ignore_file_lines = split(ignore_file, "\n")
  local files_in_project = get_all_dirs_files()
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
  end
end

vim.keymap.set('n', '<leader>-', '<Cmd>lua require("dig").toggle_window()<CR>')
return M
