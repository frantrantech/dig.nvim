---@diagnostic disable: undefined-global
local M = {}
local popup = require("plenary.popup")
local COMMENT_CHAR = "#"
local NEW_LINE = "\n"
local SLASH = "/"
local PREV_DIR = ".."
local FIRST_LS_INDEX = 6 -- Set to 6 to get rid of ../. Set to 3 to get rid of ./.
local IS_DIR = 256
local git_ignore_file_name = "./.gitignore"
local ignore_file_name = "./.ignore"
local DIR_IS_IGNORED = 100
local DIR_IS_PARTIALLY_IGNORED = 200

-- local DIR_ROOT_IGNORE_CASE = 10
-- local DIR_ROOT_IGNORE_NO_FILE_CASE = 11
-- local FILE_ROOT_IGNORE_CASE = 20
-- local FILE_IGNORE_ANYWHERE_CASE = 21
-- local FILE_IGNORE_EXTENSION_CASE = 22
-- local DEFAULT_ROOT_CASE = 23

local DIR_BASIC_CASE = "DIR_BASIC_CASE"
local DIR_IGNORE_NO_FILE_CASE = "DIR_IGNORE_NO_FILE_CASE"
local DIR_NO_EXT_NO_SLASH_CASE = "DIR_NO_EXT_NO_SLASH_CASE"
local FILE_BASIC_CASE = "FILE_BASIC_CASE"
local FILE_IGNORE_ANYWHERE_CASE = "FILE_IGNORE_ANYWHERE_CASE"
local FILE_IGNORE_EXTENSION_CASE = "FILE_IGNORE_EXTENSION_CASE"

ROOT_DIR = ""
-- The contents of the ignore file we just read in
IGNORE_FILE = {}
-- Ignored dirs from the ignore file
IGNORE_FILE_DIRS = {}
-- Ignored files from the ignore file
IGNORE_FILE_FILES = {}
-- Active directory of dig, used to index ALL_FILES.
-- Storing in ALL_FILES so we can incrementaly load the project structure.
CURR_DIR = ""

-- parent : children
ALL_FILES = {}
ALL_DIRS = {}

-- Track state of what files/dirs are ignored
-- path_to_file: bool
-- If nil then not ignored
IGNORED_FILES = {}
IGNORED_DIRS = {}

-- Maps an ingore line to the case
-- I.E */.py -> IGNORE_EXTENSION
IGNORE_FILE_CASES = {}

IGNORED_EXTENSIONS = {}
IGNORED_GLOBAL_FILES = {}

local function filter(arr, filter_fn)
  local result = {}
  for i, v in ipairs(arr) do
    if filter_fn(v, i) then
      table.insert(result, v)
    end
  end
  return result
end

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

local function dir_path_has_end_slash(path)
  local last_char = string.char(path:byte(-1))
  return last_char == SLASH
end

-- Transforms /foo/fum/ to /foo
local function remove_last_dir_from_path(path)
  local last_char_pos = #path
  for i = #path, 1, -1 do
    local curr_char = path:sub(i, i)
    if curr_char == SLASH
    then
      last_char_pos = i
      return path:sub(1, last_char_pos - 1)
    end
  end
  return path
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

function CASE_TO_STRING_MAPPER(case)
  if case == DIR_BASIC_CASE then print("Dir Root Ignore") end
  if case == DIR_IGNORE_NO_FILE_CASE then print("Dir Root Ignore No File") end
  if case == FILE_BASIC_CASE then print("File Root Ignore") end
  if case == FILE_IGNORE_ANYWHERE_CASE then print("File Ingore anywhere") end
  if case == FILE_IGNORE_EXTENSION_CASE then print("File Ignore Extension") end
end

--[[
--    Case 1: / Seperator case
        3.a: / in start or middle
            Pattern must match; relative to .ignore
        3.b: / at end
            Pattern can match any level below .ignore
    Case 2: * Asterisk case ->  Match anything
        2.a: ? Question case ->  Match 1 char (not /)
    Case 3: ** Double Asterisk Case -> Special cases
        3.a: Leading ** case -> Match all dirs
            **/foo -> matches file or dir named foo everywhere
            **/foo/bar -> matches bar files and dirs under all dirs named foo
        3.b: Ending ** case -> Match in everything inside
            foo/bar/** -> Match all files inside foo/bar
        3.c: Middle ** case -> Match 1 or more dirs
            foo/**/bar -> Match all files in foo/x/bar, foo/y/bar, etc
    Case 4: ! case: Negates the pattern; Any matching file excluded by a prev pattern will become included again.
        This needs to have a \ infront of the !
        Important:  It is not possible to re-include a file if a parent directory of that file is excluded.
--]]

-- Need a seperate function to see if a path from ignore is file or function
local function ignore_path_is_dir(path)
  local ends_with_slash = path:sub(-1, -1) == SLASH
  if ends_with_slash then return true end
  local is_dot_file = path:match("^%.[%w_]") -- Match from start of string; Escape . ; words or _
  if is_dot_file then return false end
  local ends_with_extension = path:match("%.[%w]+$") or
      path:match("%*%.[%w]+") --Escape to find . ; any number of word characters; EoS
  if ends_with_extension then return false end
  -- No end slash, is not dot file, no  extension, default this to dir
  return true
end

-- Returns true if this dir is a basic ignore
-- Basic: No *, ?,!
-- Is basic if our first_slash is not the last character
local function is_basic_ignore(path)
  local last_char = path:sub(-1, -1)
  local first_slash_pos = string.find(path, "/", 1)
  return first_slash_pos and first_slash_pos < #path and last_char ~= SLASH
end

-- Returns true if we this path is meant to ignore dirs with files
local function is_dir_root_ignore_without_file(path)
  local last_char = path:sub(-1, -1)
  return last_char == SLASH
end

-- Returns true if this file is a basic ignore
-- Basic: No *, ?, !
-- Is basic if it doesn't have one of the above cases
local function is_basic_file_ignore_case(path)
  local is_dot_file = path:match("^%.[%w_]+$")
  local path_has_extension = path:match("%.[%w]+$") or path:match("%*%.[%w]+")
  local path_has_asterisk_dot_extension = string.match(path, "%*") ~= nil
  -- local starts_with_slash = path:sub(1, 1) == SLASH
  -- local ends_with_slash = string.find(path, SLASH, 1, true) == nil
  return (is_dot_file or path_has_extension) and not path_has_asterisk_dot_extension
end

local function is_file_ignore_anywhere_case(path)
  local double_asterisks_pos = string.find(path, "%*%*")
  if double_asterisks_pos == nil then return false end
  return double_asterisks_pos
end

local function file_ignore_extension_path(path)
  local path_extension_pos = string.find(path, "/%.[%w]+$")
  if path_extension_pos == nil then return false end
  return path_extension_pos
end

-- Given a line from an ignore file, update our state for what we should be ignoring
-- Given a line from an ignore file, determine what case it is.
local function process_ignore_case(path)
  if ignore_path_is_dir(path) then
    local is_root_ignore = is_basic_ignore(path)
    if is_root_ignore then return DIR_BASIC_CASE end
    local path_is_root_ignore_no_files = is_dir_root_ignore_without_file(path)
    if path_is_root_ignore_no_files then return DIR_IGNORE_NO_FILE_CASE end
    return DIR_NO_EXT_NO_SLASH_CASE
  else
    local is_root_ignore = is_basic_file_ignore_case(path)
    if is_root_ignore then return FILE_BASIC_CASE end
    local ignore_anywhere_pos = is_file_ignore_anywhere_case(path)
    if ignore_anywhere_pos then
      table.insert(IGNORED_GLOBAL_FILES,path:sub(ignore_anywhere_pos+3,#path))
      return FILE_IGNORE_ANYWHERE_CASE
    end
    local extension_pos = file_ignore_extension_path(path)
    if extension_pos then
      table.insert(IGNORED_EXTENSIONS,path:sub(extension_pos+1,#path))
      return FILE_IGNORE_EXTENSION_CASE
    end
    return 5000
  end
end

-- Returns true if the given dir_path is supposed to be ignored
-- @dir_path is an abs path to a dir
local function dir_is_in_ignore_file(dir_path)
  for i = 1, #IGNORE_FILE_DIRS
  do
    local ignore_dir_line = IGNORE_FILE_DIRS[i]
    local end_slash_case = dir_path_has_end_slash(ignore_dir_line)
    if end_slash_case then
      ignore_dir_line = string.sub(ignore_dir_line, 1, -2)
    end
    local dir_path_is_in_ignore = string.find(dir_path, ignore_dir_line, 1, true)
    if dir_path_is_in_ignore then
      return true
    end
  end
  return false
end

local function file_is_in_ignore_file(file_path)
  for i = 1, #IGNORE_FILE_FILES
  do
    local ignore_file_line = IGNORE_FILE_FILES[i]
    local file_path_is_in_ignore = string.find(file_path, ignore_file_line, 1, true)
    if file_path_is_in_ignore then
      return true
    end
  end
  return false
end

-- local function set_dir_partially_ignored(dir_path, is_partially_ignored)
--   if is_partially_ignored then IGNORED_DIRS[dir_path] = DIR_IS_PARTIALLY_IGNORED
--   end
-- end

local function set_dir_ignored(dir_path, is_ignored)
  if is_ignored then IGNORED_DIRS[dir_path] = DIR_IS_IGNORED end
end
local function set_file_ignored(path, is_ignored)
  IGNORED_FILES[path] = is_ignored
end

-- If we have already ran this function on "dir" then we skip.
--  TODO: Add a way to check if we should update the contents of dir.
--    Maintain a set of (need to update) so that we can check
--      if dir in seen and dir not in need_to_update then skip
--
-- Given a directory, update the file and dir arrays. Update the ignored table.
-- CURR_DIR is global state that represents our cwd
local function update_dir(dir)
  CURR_DIR = dir
  -- If we've alrady seen this dir, don't look at this dir anymore
  if ALL_DIRS[CURR_DIR] then
    return
  end

  local dir_contents = get_dir_contents(dir)
  local curr_files = {}
  local curr_child_dirs = {}

  -- Update list of files and dirs
  for i = 1, #dir_contents
  do
    local curr_path = '' .. dir .. '/' .. dir_contents[i] .. ''
    if path_is_dir(curr_path) then
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

-- Called once on window open; Sets initial dir state on root
local function update_root_dirs_files()
  local project_root_pwd = io.popen("pwd")
  local project_root_name = project_root_pwd:read("a")
  local root_dir = strip_new_line(project_root_name)
  ROOT_DIR = root_dir
  update_dir(strip_new_line(project_root_name))
end

-- Get contents of our specified ignore file
local function get_ignore_file_contents()
  io.input(git_ignore_file_name)
  local fileData = io.read("a")
  io.close()
  return fileData
end

-- Reads ignore file
-- Update IGNORE_FILE, IGNORE_FILE_DIRS, IGNORE_FILE_FILES
-- Calls update_root_dir_files
local function process_ignore_file()
  local ignore_file_contents = get_ignore_file_contents()
  local ignore_arr = split(ignore_file_contents, NEW_LINE)

  IGNORE_FILE = filter(ignore_arr, function(ignore_line)
    return ignore_line:sub(1, 1) ~= COMMENT_CHAR
  end)

  for i = 1, #IGNORE_FILE
  do
    IGNORE_FILE_CASES[IGNORE_FILE[i]] = process_ignore_case(IGNORE_FILE[i])
    if ignore_path_is_dir(IGNORE_FILE[i]) then
      table.insert(IGNORE_FILE_DIRS, IGNORE_FILE[i])
    else
      table.insert(IGNORE_FILE_FILES, IGNORE_FILE[i])
    end
  end

  print(vim.inspect(IGNORE_FILE_CASES))
  print(vim.inspect(IGNORED_EXTENSIONS))
  print(vim.inspect(IGNORED_GLOBAL_FILES))

  -- once IGNORE_FILE is set, we can read through our file structure to see which files are ignored
  update_root_dirs_files()
end

-- Check a dir path to see if it has some ignored items or not
local function get_dir_is_partially_ignored(dir_path)
  local ignored_status = IGNORED_DIRS[dir_path]
  return ignored_status == DIR_IS_PARTIALLY_IGNORED
end

local function get_dir_is_ignored(dir_path)
  local ignored_status = IGNORED_DIRS[dir_path]
  return ignored_status ~= nil and ignored_status == DIR_IS_IGNORED
end

local function get_file_is_ignored(path)
  local ignored_status = IGNORED_FILES[path]
  return ignored_status ~= nil and ignored_status == true
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

  -- Set color for ignore line
  vim.api.nvim_set_hl(0, "IgnoreLineColor", { fg = "#ff0000", bg = "#000000" })

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

  vim.api.nvim_buf_set_lines(win_buf, 0, -1, false, { PREV_DIR })

  -- Set Dirs
  local last_line_idx = 1
  for i = 1, #dirs
  do
    local dir_is_ignored = get_dir_is_ignored(dirs[i])
    local dir_is_partially_ignored = get_dir_is_partially_ignored(dirs[i])
    local dir_display = dirs[i]
    vim.api.nvim_buf_set_lines(win_buf, last_line_idx, last_line_idx, true, { dir_display })
    if dir_is_ignored then
      vim.api.nvim_buf_add_highlight(0, -1, "IgnoreLineColor", last_line_idx, 0, -1)
    end
    last_line_idx = last_line_idx + 1
  end

  -- Set Files
  vim.api.nvim_buf_set_lines(win_buf, last_line_idx, last_line_idx, true, { "FILES" })
  last_line_idx = last_line_idx + 1
  for i = 1, #files
  do
    local file_is_ignored = get_file_is_ignored(files[i])
    local path_str = files[i]
    vim.api.nvim_buf_set_lines(win_buf, last_line_idx, last_line_idx, true, { path_str })
    if file_is_ignored then
      vim.api.nvim_buf_add_highlight(0, -1, "IgnoreLineColor", last_line_idx, 0, -1)
    end
    last_line_idx = last_line_idx + 1
  end
end

-- Update IGNORED_FILE / IGNORED_DIRS
-- Update Styling of line
function M.add_to_ignores(win_buf)
  local path = vim.api.nvim_get_current_line()
  local line_idx = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_add_highlight(0, -1, "IgnoreLineColor", line_idx - 1, 0, -1)
  if path_is_dir(path) then
    set_dir_ignored(path, true)
  else
    set_file_ignored(path, true)
  end
end

function M.remove_from_ignores(win_buf)
  local path = vim.api.nvim_get_current_line()
  local line_idx = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_clear_namespace(0, -1, line_idx - 1, line_idx)
  if path_is_dir(path) then
    set_dir_ignored(path, false)
  else
    set_file_ignored(path, false)
  end
end

-- User has just tried to enter a path.
-- If dir -> update CURR_DIR
-- If file -> do nothing?
function M.enter_path(win_buf)
  local path = vim.api.nvim_get_current_line()
  if path_is_dir(path) then
    -- Do not move if we are currently in root_dir
    if CURR_DIR == ROOT_DIR and path == PREV_DIR then return end
    if path == PREV_DIR then
      path = remove_last_dir_from_path(CURR_DIR)
    end
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

vim.keymap.set('n', '<leader>\'', '<Cmd>lua require("dig").toggle_window()<CR>')
return M
