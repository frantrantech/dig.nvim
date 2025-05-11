local finders = require "telescope.finders"
local make_entry = require "telescope.make_entry"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values
local log = require "telescope.log"
local utils = require "telescope.utils"
local flatten = utils.flatten

local M = {}
local files = {}

local function find(opts)
  local find_command = (function()
    if opts.find_command then
      if type(opts.find_command) == "function" then
        vim.notify("Function")
        return opts.find_command(opts)
      end
      vim.notify("Else function")
      return opts.find_command
    elseif 1 == vim.fn.executable "rg" then
      vim.notify("rg")
      return { "rg", "--files", "--color", "never" }
    elseif 1 == vim.fn.executable "fd" then
      vim.notify(fd)
      return { "fd", "--type", "f", "--color", "never" }
    elseif 1 == vim.fn.executable "fdfind" then
      vim.notify("fdfind")
      return { "fdfind", "--type", "f", "--color", "never" }
    elseif 1 == vim.fn.executable "find" and vim.fn.has "win32" == 0 then
      vim.notify("findwin32")
      return { "find", ".", "-type", "f" }
    elseif 1 == vim.fn.executable "where" then
      vim.notify("where")
      return { "where", "/r", ".", "*" }
    end
  end)()

  if not find_command then
    utils.notify("builtin.find_files", {
      msg = "You need to install either find, fd, or rg",
      level = "ERROR",
    })
    return
  end

  local command = find_command[1]
  local hidden = opts.hidden
  local no_ignore = opts.no_ignore
  local no_ignore_parent = opts.no_ignore_parent
  local follow = opts.follow
  local search_dirs = opts.search_dirs
  local search_file = opts.search_file

  if search_dirs then
    for k, v in pairs(search_dirs) do
      search_dirs[k] = utils.path_expand(v)
    end
  end
  vim.notify(vim.inspect(search_dirs))
  if command == "fd" or command == "fdfind" or command == "rg" then
    if hidden then
      find_command[#find_command + 1] = "--hidden"
    end
    if no_ignore then
      find_command[#find_command + 1] = "--no-ignore"
    end
    if no_ignore_parent then
      find_command[#find_command + 1] = "--no-ignore-parent"
    end
    if follow then
      find_command[#find_command + 1] = "-L"
    end
    if search_file then
      if command == "rg" then
        find_command[#find_command + 1] = "-g"
        find_command[#find_command + 1] = "*" .. search_file .. "*"
      else
        find_command[#find_command + 1] = search_file
      end
    end
    if search_dirs then
      if command ~= "rg" and not search_file then
        find_command[#find_command + 1] = "."
      end
      vim.list_extend(find_command, search_dirs)
    end
  elseif command == "find" then
    if not hidden then
      table.insert(find_command, { "-not", "-path", "*/.*" })
      find_command = flatten(find_command)
    end
    if no_ignore ~= nil then
      log.warn "The `no_ignore` key is not available for the `find` command in `find_files`."
    end
    if no_ignore_parent ~= nil then
      log.warn "The `no_ignore_parent` key is not available for the `find` command in `find_files`."
    end
    if follow then
      table.insert(find_command, 2, "-L")
    end
    if search_file then
      table.insert(find_command, "-name")
      table.insert(find_command, "*" .. search_file .. "*")
    end
    if search_dirs then
      table.remove(find_command, 2)
      for _, v in pairs(search_dirs) do
        table.insert(find_command, 2, v)
      end
    end
  elseif command == "where" then
    if hidden ~= nil then
      log.warn "The `hidden` key is not available for the Windows `where` command in `find_files`."
    end
    if no_ignore ~= nil then
      log.warn "The `no_ignore` key is not available for the Windows `where` command in `find_files`."
    end
    if no_ignore_parent ~= nil then
      log.warn "The `no_ignore_parent` key is not available for the Windows `where` command in `find_files`."
    end
    if follow ~= nil then
      log.warn "The `follow` key is not available for the Windows `where` command in `find_files`."
    end
    if search_dirs ~= nil then
      log.warn "The `search_dirs` key is not available for the Windows `where` command in `find_files`."
    end
    if search_file ~= nil then
      log.warn "The `search_file` key is not available for the Windows `where` command in `find_files`."
    end
  end

  if opts.cwd then
    opts.cwd = utils.path_expand(opts.cwd)
  end

  opts.entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)

  pickers
      .new(opts, {
        prompt_title = "Ignore Find Files",
        __locations_input = true,
        finder = finders.new_oneshot_job(find_command, opts),
        previewer = conf.grep_previewer(opts),
        sorter = conf.file_sorter(opts),
      })
      :find()
end

function M.find_files()
  local opts = {
    -- cwd = "",
    grep_open_files = false,
    search = "*",
    search_dirs = {"~/Desktop/testing/", "~/Desktop/dig.nvim"}
  }
  find(opts)
end

vim.keymap.set('n', '<leader>=', '<Cmd>lua require("picker").find_files()<CR>')

return M
