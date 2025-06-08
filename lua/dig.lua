---@diagnostic disable: undefined-global
local M = {}
local popup = require("plenary.popup")
local COMMENT_CHAR = "#"
local NEW_LINE = "\n"
local FIRST_LS_INDEX = 6 -- Set to 6 to get rid of ../. Set to 3 to get rid of ./.
local IS_DIR = 256
local git_ignore_file_name = "./.gitignore"
local ignore_file_name = "./.ignore"
local DIR_IS_IGNORED = 100
local DIR_IS_PARTIALLY_IGNORED = 200
local X = "❌"
local Y = "✅"

-- The contents of the ignore file we just read in
IGNORE_FILE = {}
-- Active directory of dig, used to index ALL_FILES.
-- Storing in ALL_FILES so we can incrementaly load the project structure.
CURR_DIR = ""

-- parent : children
ALL_FILES = {}
ALL_DIRS = {}

-- path_to_file: bool
-- If nil then not ignored
IGNORED_FILES = {}
IGNORED_DIRS = {}

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
  return str:sub(1, string.len(str) - 1)
end

-- Take a file name from ls and determine if it is a directory or notify
-- Is a directory
local function path_is_dir(path)
  local is_dir = os.execute('[ -f "' .. path .. '" ]') == IS_DIR
  return is_dir
end

local function filter(arr, filter_fn)
  local result = {}
  for i, v in ipairs(arr) do
    if filter_fn(v, i) then
      table.insert(result, v)
    end
  end
  return result
end



-- Returns the result of calling "ls" on "dir" as an array
local function get_dir_contents(dir)
  local ls_output = io.popen('ls -a ' .. dir .. '', "r")
  if ls_output == nil then return end
  local ls = ls_output:read("a")
  ls_output:close()
  local ls_arr = split(ls, NEW_LINE)
  local ls_filtered = filter(ls_arr, function(path)
    return path ~= ".." and path ~= "."
  end)
  return ls_filtered
end

local function dir_is_in_ignore_file(dir_path)
  for i = 1, #IGNORED_DIRS
  do
    local ignore_line = IGNORED_DIRS[i]
  end
end
local function file_is_in_ignore_file(file_path)

end

-- local function set_dir_partially_ignored(dir_path, is_partially_ignored)
--   if is_partially_ignored then IGNORED_DIRS[dir_path] = DIR_IS_PARTIALLY_IGNORED
-- end
--
local function set_dir_ignored(dir_path, is_ignored)
  if is_ignored then IGNORED_DIRS[dir_path] = DIR_IS_IGNORED end
end
local function set_file_ignored(path, is_ignored)
  IGNORED_FILES[path] = is_ignored
end

-- Given a directory, update the file and dir arrays. Update the ignored table.
-- CURR_DIR is global state that represents our cwd
--
-- If we have already ran this function on "dir" then we skip.
--  TODO: Add a way to check if we should update the contents of dir.
--    Maintain a set of (need to update) so that we can check
--      if dir in seen and dir not in need_to_update then skip
local function update_dir(dir)
  CURR_DIR = dir
  -- If we've alrady seen this dir, don't look at this dir anymore
  if ALL_DIRS[CURR_DIR]
  then
    return
  end

  local dir_contents = get_dir_contents(dir)
  local curr_files = {}
  local curr_child_dirs = {}

  -- Update list of files and dirs
  for i = 1, #dir_contents
  do
    local curr_path = '' .. dir .. '/' .. dir_contents[i] .. ''
    if path_is_dir(curr_path)
    then
      table.insert(curr_child_dirs, curr_path)
      set_dir_ignored(curr_path, dir_is_in_ignore_file(curr_path))
    else
      table.insert(curr_files, curr_path)
      set_file_ignored(curr_path, file_is_in_ignore_file(curr_path))
    end
  end

  ALL_FILES[dir] = curr_files
  ALL_DIRS[dir] = curr_child_dirs

  return {
    files = curr_files,
    dirs = child_dirs
  }
end

local function update_root_dirs_files()
  local project_root_pwd = io.popen("pwd")
  local project_root_name = project_root_pwd:read("a")
  update_dir(strip_new_line(project_root_name))
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
  -- See metatables: https://www.lua.org/pil/13.html Metatables allow us to change the behavior of a table.

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
  local ignore_file_contents = get_ignore_file_contents()
  IGNORE_FILE = split(ignore_file_contents, NEW_LINE)
  for i = 1, #IGNORE_FILE
  do
    process_ignore_line(IGNORE_FILE[i])
  end
  local files_in_project = update_root_dirs_files()
end

-- Check a dir path to see if it has some ignored items or not
local function get_dir_is_partially_ignored(dir_path)
  local ignored_status = IGNORED_DIRS[dir_path]
  return ignored_status == DIR_IS_PARTIALLY_IGNORED
end

local function get_dir_is_ignored(dir_path)
  local ignored_status = IGNORED_DIRS[dir_path]
  return not (ignored_status ~= nil and ignored_status == DIR_IS_IGNORED)
end

local function get_file_is_ignored(path)
  local ignored_status = IGNORED_FILES[path]
  return not (ignored_status ~= nil and ignored_status == true)
end

Dig_window = nil
Dig_window_id = nil

-- Creates a window, sets Dig_window_id to be used by close_window()
-- Returns the window_id and window to ensure that toggle() works correctly
local function create_window()
  local window_buffer = vim.api.nvim_create_buf(false, false)

  -- Stops buffer from trying to save
  vim.api.nvim_buf_set_option(window_buffer, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(window_buffer, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(window_buffer, 'swapfile', false)

  local width = 70
  local height = 20
  local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }
  Dig_window_id, Dig_window = popup.create(window_buffer, {
    title = "Diging Through: " .. CURR_DIR,
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

local function update_dig_window(win_buf)
  local dirs = ALL_DIRS[CURR_DIR]
  local files = ALL_FILES[CURR_DIR]

  vim.api.nvim_buf_set_lines(win_buf, 0, -1, false, {})

  -- Set Dirs
  local last_line_idx = 1
  for i = 1, #dirs
  do
    local dir_is_ignored = get_dir_is_ignored(dirs[i])
    local dir_is_partially_ignored = get_dir_is_partially_ignored(dirs[i])
    -- local icon = Y
    -- if dir_is_ignored then icon = X end
    -- local dir_display = '' .. icon .. ' ' .. dirs[i]
    local dir_display = dirs[i]
    vim.api.nvim_buf_set_lines(win_buf, last_line_idx, last_line_idx, true, { dir_display })
    last_line_idx = last_line_idx + 1
  end

  -- Set Files
  vim.api.nvim_buf_set_lines(win_buf, last_line_idx, last_line_idx, true, { "FILES" })
  last_line_idx = last_line_idx + 1
  for i = 1, #files
  do
    local file_is_ignored = get_file_is_ignored(files[i])
    -- local icon = Y
    -- if file_is_ignored then icon = X end
    -- path_str = '' .. icon .. ' ' .. files[i]
    local path_str = files[i]
    vim.api.nvim_buf_set_lines(win_buf, last_line_idx, last_line_idx, true, { path_str })
    last_line_idx = last_line_idx + 1
  end
end

function M.add_to_ignores(win_buf)
  local path = vim.api.nvim_get_current_line()
end

function M.remove_from_ignores(win_buf)
  local path = vim.api.nvim_get_current_line()
end

-- User has just tried to enter a path.
-- If dir -> update CURR_DIR
-- If file -> do nothing?
function M.enter_path(win_buf)
  local path = vim.api.nvim_get_current_line()
  if path_is_dir(path)
  then
    update_dir(path)
    update_dig_window(win_buf)
  else
  end
end

--Dig_window_id should be non null here
local function close_window()
  vim.api.nvim_win_close(Dig_window_id, true)
end

-- Closes window and returns if window is open
-- Creates a window if it isn't open.
-- Add <ESC> command in the new buffer to toggle (close) the window
function M.toggle_window()
  -- vim.notify("toggling")

  local window_is_open = Dig_window_id ~= nil and vim.api.nvim_win_is_valid(Dig_window_id)
  if window_is_open then
    close_window()
    return
  else
    process_ignore_file()
    local win = create_window()
    local win_buf = win.win_buf

    -- Leave Dig Window
    vim.api.nvim_buf_set_keymap(win_buf, 'n', 'q', '<Cmd>lua require("dig").toggle_window()<CR>',
      { silent = true })
    vim.api.nvim_buf_set_keymap(win_buf, 'n', '<ESC>', '<Cmd>lua require("dig").toggle_window()<CR>',
      { silent = true })

    -- Attempt to enter a directory
    vim.api.nvim_buf_set_keymap(win_buf, 'n', '<CR>', '<Cmd>lua require("dig").enter_path(' .. win_buf .. ')<CR>',
      { silent = true })

    -- Exclude file / dir
    vim.api.nvim_buf_set_keymap(win_buf, 'n', 'E', '<Cmd>lua require("dig").add_to_ignores(' .. win_buf .. ')<CR>',
      { silent = true })

    -- Include file / dir
    vim.api.nvim_buf_set_keymap(win_buf, 'n', 'C', '<Cmd>lua require("dig").remove_from_ignores(' .. win_buf .. ')<CR>',
      { silent = true })

    -- 0 Based indexing in nvim api
    -- 1 based indexing with native lua
    update_dig_window(win_buf)
    -- vim.api.nvim_buf_set_lines(win_buf,0,0,true,{all_files[1]})
    -- vim.api.nvim_buf_set_lines(win_buf,1,1,true,{"Hello World2"})
    -- local line_ct = vim.api.nvim_buf_line_count(win_buf)
    -- local line1 = vim.api.nvim_buf_get_lines(win_buf, 1, 2, true)
  end
end

vim.keymap.set('n', '<leader>-', '<Cmd>lua require("dig").toggle_window()<CR>')
return M
