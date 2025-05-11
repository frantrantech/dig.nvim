local M = {}
local finders = require "telescope.finders"
local make_entry = require "telescope.make_entry"
local pickers = require "telescope.pickers"
local utils = require "telescope.utils"
local conf = require("telescope.config").values
local log = require "telescope.log"
local popup = require("plenary.popup")

local flatten = utils.flatten

window = nil
window_id = nil

local function create_window()
  local window_buffer = vim.api.nvim_create_buf(false, false)
  local width = 60
  local height = 10
  local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }
  window_id, window = popup.create(window_buffer, {
    title = "Dig",
    highlight = "DigWindow",
    line = math.floor(((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    minwidth = width,
    minheight = height,
    borderchars = borderchars,
  })
  vim.api.nvim_win_set_option(
    window.border.win_id,
    "winhl",     -- Highlights
    "Normal:DigBorder"
  )
end

local function close_window()
  vim.api.nvim_win_close(window_id, true)
end

function M.toggle_window()
  local window_is_open = window_id ~= nil and vim.api.nvim_win_is_valid(window_id)
  if window_is_open then
    close_window()
  else
    create_window()
  end
end




-- local files = {}
--
-- function M.find_files(opts)
-- -- files.find_files = function(opts)
--   local find_command = (function()
--     if opts.find_command then
--       if type(opts.find_command) == "function" then
--         return opts.find_command(opts)
--       end
--       return opts.find_command
--     elseif 1 == vim.fn.executable "rg" then
--       return { "rg", "--files", "--color", "never" }
--     elseif 1 == vim.fn.executable "fd" then
--       return { "fd", "--type", "f", "--color", "never" }
--     elseif 1 == vim.fn.executable "fdfind" then
--       return { "fdfind", "--type", "f", "--color", "never" }
--     elseif 1 == vim.fn.executable "find" and vim.fn.has "win32" == 0 then
--       return { "find", ".", "-type", "f" }
--     elseif 1 == vim.fn.executable "where" then
--       return { "where", "/r", ".", "*" }
--     end
--   end)()
--
--   if not find_command then
--     utils.notify("builtin.find_files", {
--       msg = "You need to install either find, fd, or rg",
--       level = "ERROR",
--     })
--     return
--   end
--
--   local command = find_command[1]
--   local hidden = opts.hidden
--   local no_ignore = opts.no_ignore
--   local no_ignore_parent = opts.no_ignore_parent
--   local follow = opts.follow
--   local search_dirs = opts.search_dirs
--   local search_file = opts.search_file
--
--   if search_dirs then
--     for k, v in pairs(search_dirs) do
--       search_dirs[k] = utils.path_expand(v)
--     end
--   end
--
--   if command == "fd" or command == "fdfind" or command == "rg" then
--     if hidden then
--       find_command[#find_command + 1] = "--hidden"
--     end
--     if no_ignore then
--       find_command[#find_command + 1] = "--no-ignore"
--     end
--     if no_ignore_parent then
--       find_command[#find_command + 1] = "--no-ignore-parent"
--     end
--     if follow then
--       find_command[#find_command + 1] = "-L"
--     end
--     if search_file then
--       if command == "rg" then
--         find_command[#find_command + 1] = "-g"
--         find_command[#find_command + 1] = "*" .. search_file .. "*"
--       else
--         find_command[#find_command + 1] = search_file
--       end
--     end
--     if search_dirs then
--       if command ~= "rg" and not search_file then
--         find_command[#find_command + 1] = "."
--       end
--       vim.list_extend(find_command, search_dirs)
--     end
--   elseif command == "find" then
--     if not hidden then
--       table.insert(find_command, { "-not", "-path", "*/.*" })
--       find_command = flatten(find_command)
--     end
--     if no_ignore ~= nil then
--       log.warn "The `no_ignore` key is not available for the `find` command in `find_files`."
--     end
--     if no_ignore_parent ~= nil then
--       log.warn "The `no_ignore_parent` key is not available for the `find` command in `find_files`."
--     end
--     if follow then
--       table.insert(find_command, 2, "-L")
--     end
--     if search_file then
--       table.insert(find_command, "-name")
--       table.insert(find_command, "*" .. search_file .. "*")
--     end
--     if search_dirs then
--       table.remove(find_command, 2)
--       for _, v in pairs(search_dirs) do
--         table.insert(find_command, 2, v)
--       end
--     end
--   elseif command == "where" then
--     if hidden ~= nil then
--       log.warn "The `hidden` key is not available for the Windows `where` command in `find_files`."
--     end
--     if no_ignore ~= nil then
--       log.warn "The `no_ignore` key is not available for the Windows `where` command in `find_files`."
--     end
--     if no_ignore_parent ~= nil then
--       log.warn "The `no_ignore_parent` key is not available for the Windows `where` command in `find_files`."
--     end
--     if follow ~= nil then
--       log.warn "The `follow` key is not available for the Windows `where` command in `find_files`."
--     end
--     if search_dirs ~= nil then
--       log.warn "The `search_dirs` key is not available for the Windows `where` command in `find_files`."
--     end
--     if search_file ~= nil then
--       log.warn "The `search_file` key is not available for the Windows `where` command in `find_files`."
--     end
--   end
--
--   if opts.cwd then
--     opts.cwd = utils.path_expand(opts.cwd)
--   end
--
--   opts.entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)
--
--   pickers
--     .new(opts, {
--       prompt_title = "Find Files",
--       __locations_input = true,
--       finder = finders.new_oneshot_job(find_command, opts),
--       previewer = conf.grep_previewer(opts),
--       sorter = conf.file_sorter(opts),
--     })
--     :find()
-- end
--
--
--
-- local function apply_checks(mod)
--   for k, v in pairs(mod) do
--     mod[k] = function(opts)
--       opts = opts or {}
--
--       v(opts)
--     end
--   end
--
--   return mod
-- end
--
-- apply_checks(files)

vim.keymap.set('n', '<leader>-', '<Cmd>lua require("dig").toggle_window()<CR>')
-- vim.keymap.set('n', '<leader>=', '<Cmd>lua require("dig").find_files()<CR>',{hidden=true, layout_config={prompt_position="top"}})



return M
