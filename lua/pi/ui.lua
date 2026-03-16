local M = {}

local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local active_statuses = {
  collecting_context = true,
  starting = true,
  thinking = true,
  running_tool = true,
  applying = true,
}

local function is_session_window_valid(session)
  return session and session.winnr and vim.api.nvim_win_is_valid(session.winnr)
end

local function is_session_buffer_valid(session)
  return session and session.bufnr and vim.api.nvim_buf_is_valid(session.bufnr)
end

local function title_for(session)
  if session.status == "error" then
    return " pi error "
  end
  return " pi "
end

local function status_line(session)
  local prefix = ""
  if session.status == "thinking" or session.status == "collecting_context" or session.status == "starting" or session.status == "running_tool" or session.status == "applying" then
    session.spinner_idx = ((session.spinner_idx or 0) % #spinner) + 1
    prefix = spinner[session.spinner_idx] .. " "
  end

  if session.status == "running_tool" and session.active_tool then
    return prefix .. "Running tool: " .. session.active_tool
  end

  local labels = {
    idle = "Idle",
    collecting_context = "Collecting context...",
    starting = "Starting pi...",
    thinking = "Thinking...",
    applying = "Applying edits...",
    done = "Done",
    error = session.last_error or "pi failed",
    cancelled = "Cancelled",
  }

  return prefix .. (labels[session.status] or session.status)
end

local function render(session)
  if not is_session_buffer_valid(session) then
    return
  end

  local lines = { status_line(session) }
  local start_idx = math.max(1, #session.history - 3)
  for i = start_idx, #session.history do
    lines[#lines + 1] = session.history[i]
  end

  vim.bo[session.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(session.bufnr, 0, -1, false, lines)
  vim.bo[session.bufnr].modifiable = false

  if is_session_window_valid(session) then
    pcall(vim.api.nvim_win_set_config, session.winnr, vim.tbl_extend("force", vim.api.nvim_win_get_config(session.winnr), {
      title = title_for(session),
      height = math.min(math.max(#lines, 1), math.max(3, math.floor(vim.o.lines * 0.25))),
    }))
  end
end

local function stop_timer(session)
  if session.ui_timer then
    session.ui_timer:stop()
    session.ui_timer:close()
    session.ui_timer = nil
  end
end

local function ensure_timer(session)
  if session.ui_timer or not active_statuses[session.status] then
    return
  end

  session.ui_timer = vim.loop.new_timer()
  session.ui_timer:start(100, 100, vim.schedule_wrap(function()
    if not is_session_buffer_valid(session) or not active_statuses[session.status] then
      stop_timer(session)
      return
    end
    render(session)
  end))
end

function M.open(session, focus)
  local width = math.min(60, math.max(40, math.floor(vim.o.columns * 0.45)))
  local height = 4
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  session.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[session.bufnr].buftype = "nofile"
  vim.bo[session.bufnr].bufhidden = "wipe"
  vim.bo[session.bufnr].swapfile = false
  vim.bo[session.bufnr].modifiable = false
  vim.api.nvim_buf_set_name(session.bufnr, "pi-session://" .. session.id)

  session.winnr = vim.api.nvim_open_win(session.bufnr, focus, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title_for(session),
    title_pos = "center",
    noautocmd = true,
  })

  vim.wo[session.winnr].wrap = true
  vim.wo[session.winnr].linebreak = true
  vim.wo[session.winnr].winfixbuf = true

  render(session)
  ensure_timer(session)
end

function M.update(session)
  if active_statuses[session.status] then
    ensure_timer(session)
  else
    stop_timer(session)
  end
  render(session)
end

function M.close(session)
  stop_timer(session)
  if is_session_window_valid(session) then
    pcall(vim.api.nvim_win_close, session.winnr, true)
  end
  if is_session_buffer_valid(session) then
    pcall(vim.api.nvim_buf_delete, session.bufnr, { force = true })
  end
  session.winnr = nil
  session.bufnr = nil
end

return M
