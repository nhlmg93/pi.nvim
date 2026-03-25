local M = {}

local function format_time()
  return os.date("%Y-%m-%d %H:%M:%S")
end

function M.append_session(log_path, session, message, status, source_path)
  if not log_path or log_path == "" then
    return
  end

  local lines = {
    "",
    "=" .. string.rep("=", 78),
    string.format("[%s] %s", format_time(), status:upper()),
    "=" .. string.rep("=", 78),
    "Prompt: " .. (message or "(empty)"),
    "File: " .. (source_path or "(no file)"),
    "Status: " .. status,
  }

  if session.last_error then
    table.insert(lines, "Error: " .. session.last_error)
  end

  if #session.history > 0 then
    table.insert(lines, "")
    table.insert(lines, "--- Session History ---")
    for _, entry in ipairs(session.history) do
      table.insert(lines, entry)
    end
  end

  local ok, err = pcall(function()
    local file = io.open(log_path, "a")
    if file then
      for _, line in ipairs(lines) do
        file:write(line .. "\n")
      end
      file:close()
    end
  end)

  if not ok then
    vim.notify("Failed to write pi log: " .. tostring(err), vim.log.levels.WARN)
  end
end

return M
