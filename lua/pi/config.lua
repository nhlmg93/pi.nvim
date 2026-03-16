local M = {}

M.defaults = {
  provider = nil,
  model = nil,
  max_context_lines = 300,
  max_context_bytes = 24000,
  selection_context_lines = 40,
  focus_ui = false,
}

local values = vim.deepcopy(M.defaults)

local function validate_number(name, value)
  if type(value) ~= "number" or value < 1 then
    error(string.format("pi.nvim: %s must be a positive number", name))
  end
end

function M.validate(opts)
  if opts.max_context_lines ~= nil then
    validate_number("max_context_lines", opts.max_context_lines)
  end
  if opts.max_context_bytes ~= nil then
    validate_number("max_context_bytes", opts.max_context_bytes)
  end
  if opts.selection_context_lines ~= nil then
    validate_number("selection_context_lines", opts.selection_context_lines)
  end
  if opts.focus_ui ~= nil and type(opts.focus_ui) ~= "boolean" then
    error("pi.nvim: focus_ui must be a boolean")
  end
end

function M.setup(opts)
  opts = opts or {}
  M.validate(opts)
  values = vim.tbl_extend("force", vim.deepcopy(M.defaults), opts)
  return values
end

function M.get()
  return values
end

return M
