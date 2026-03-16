local M = {}

local next_id = 0

function M.new(source_bufnr)
  next_id = next_id + 1
  return {
    id = next_id,
    status = "idle",
    process = nil,
    bufnr = nil,
    winnr = nil,
    source_bufnr = source_bufnr,
    source_path = source_bufnr and vim.api.nvim_buf_get_name(source_bufnr) or nil,
    started_at = vim.loop.hrtime(),
    ended_at = nil,
    active_tool = nil,
    last_error = nil,
    closing = false,
    cancelled = false,
    history = {},
  }
end

function M.push(session, message)
  session.history[#session.history + 1] = message
end

return M
