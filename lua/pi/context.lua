local M = {}

local SYSTEM_PROMPT = [[You are running inside the pi.nvim Neovim plugin. The user has sent a request and will not be able to reply back. You must complete the task immediately without asking any questions or requesting clarification. Take action now and do what was asked.]]

local QUESTION_PROMPT_APPENDIX = [[IMPORTANT: The user is asking a question using the @question directive. Your task is to ADD A COMMENT at the very top of the file (before line 1) that answers their question.

INSTRUCTIONS:
1. Use the edit_file tool to insert a comment block at line 1 (the very beginning of the file)
2. Do NOT modify any existing code - only insert the new comment at the top
3. Use the correct comment syntax for this filetype (e.g., // for JavaScript, # for Python, -- for Lua, etc.)
4. The comment should be brief (2-4 lines max), straightforward, and use simple language
5. After adding the comment, you are DONE - no further actions needed

EXAMPLE for Lua file:
-- This function calculates the factorial of a number.
-- It uses recursion and returns 1 for the base case.

Now answer the user's question by adding an appropriate comment at the top of their file.]]

local EMPTY_FILE_NOTE = [[NOTE: This file is currently empty. Please create or populate it directly by applying the necessary edits so pi.nvim can write the file.]]

local function buffer_is_empty(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return true
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      return false
    end
  end
  return true
end

function M.buffer_is_file_backed(bufnr)
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end
  local filename = vim.api.nvim_buf_get_name(bufnr)
  return filename ~= nil and filename ~= ""
end

function M.get_visual_selection_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  if not start_pos or not end_pos then
    return nil
  end
  local start_line = start_pos[2]
  local end_line = end_pos[2]
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return { start = start_line, ["end"] = end_line }
end

function M.format_prompt_label(bufnr, selection_range)
  local components = {}
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename ~= "" then
    table.insert(components, vim.fn.fnamemodify(filename, ":t"))
  end
  if selection_range and selection_range.start and selection_range["end"] then
    table.insert(components, string.format("%d:%d", selection_range.start, selection_range["end"]))
  end
  if #components == 0 then
    return "ask pi: "
  end
  return string.format("ask pi (%s): ", table.concat(components, ":"))
end

local function filetype_for(bufnr)
  return vim.bo[bufnr].filetype ~= "" and vim.bo[bufnr].filetype or "text"
end

local function limit_lines(lines, max_lines)
  if #lines <= max_lines then
    return vim.deepcopy(lines), false
  end
  return vim.list_slice(lines, 1, max_lines), true
end

local function truncate_to_bytes(text, max_bytes)
  if #text <= max_bytes then
    return text, false
  end
  return text:sub(1, max_bytes), true
end

local function content_block(label, text)
  return string.format("%s:\n```\n%s\n```", label, text)
end

function M.detect_directives(message)
  local is_question = false
  local cleaned_message = message

  -- Check for @question directive
  if cleaned_message:find("@question") then
    is_question = true
    cleaned_message = cleaned_message:gsub("@question", "")
    cleaned_message = cleaned_message:gsub("%s+", " ")
    cleaned_message = cleaned_message:gsub("^%s*", "")
    cleaned_message = cleaned_message:gsub("%s*$", "")
  end

  return {
    is_question = is_question,
    cleaned_message = cleaned_message,
  }
end

function M.get_question_appendix(filetype)
  return string.format("%s\n\nFiletype: %s", QUESTION_PROMPT_APPENDIX, filetype)
end

function M.get_buffer_context(bufnr, config, is_question)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local limited_lines, did_trim_lines = limit_lines(lines, config.max_context_lines)
  local content, did_trim_bytes = truncate_to_bytes(table.concat(limited_lines, "\n"), config.max_context_bytes)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local ft = filetype_for(bufnr)

  local parts = {
    SYSTEM_PROMPT,
    string.format("File: %s", filename),
    string.format("Cwd: %s", vim.fn.getcwd()),
    string.format("Filetype: %s", ft),
    content_block("File content", content),
  }

  if is_question then
    parts[#parts + 1] = M.get_question_appendix(ft)
  end

  if did_trim_lines or did_trim_bytes then
    parts[#parts + 1] = string.format(
      "NOTE: Context was trimmed for speed (max_lines=%d, max_bytes=%d).",
      config.max_context_lines,
      config.max_context_bytes
    )
  end

  if buffer_is_empty(bufnr) then
    parts[#parts + 1] = EMPTY_FILE_NOTE
  end

  return table.concat(parts, "\n\n")
end

function M.get_visual_context(bufnr, config, is_question)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local selection_range = M.get_visual_selection_range() or { start = 1, ["end"] = #all_lines }
  local before = math.max(1, selection_range.start - config.selection_context_lines)
  local after = math.min(#all_lines, selection_range["end"] + config.selection_context_lines)

  local nearby_lines = vim.api.nvim_buf_get_lines(bufnr, before - 1, after, false)
  local selected_lines = vim.api.nvim_buf_get_lines(bufnr, selection_range.start - 1, selection_range["end"], false)
  local nearby_text, nearby_trimmed = truncate_to_bytes(table.concat(nearby_lines, "\n"), config.max_context_bytes)
  local selected_text, selected_trimmed = truncate_to_bytes(table.concat(selected_lines, "\n"), config.max_context_bytes)
  local ft = filetype_for(bufnr)

  local parts = {
    SYSTEM_PROMPT,
    string.format("File: %s", filename),
    string.format("Cwd: %s", vim.fn.getcwd()),
    string.format("Filetype: %s", ft),
    string.format("Selected lines: %d-%d", selection_range.start, selection_range["end"]),
    content_block("Selected content", selected_text),
    content_block(string.format("Nearby context (%d-%d)", before, after), nearby_text),
  }

  if is_question then
    parts[#parts + 1] = M.get_question_appendix(ft)
  end

  if nearby_trimmed or selected_trimmed then
    parts[#parts + 1] = string.format(
      "NOTE: Selection context was trimmed for speed (max_bytes=%d).",
      config.max_context_bytes
    )
  end

  if buffer_is_empty(bufnr) then
    parts[#parts + 1] = EMPTY_FILE_NOTE
  end

  return table.concat(parts, "\n\n")
end

return M
