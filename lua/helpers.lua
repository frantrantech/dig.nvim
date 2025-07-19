function filter(arr, filter_fn)
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
