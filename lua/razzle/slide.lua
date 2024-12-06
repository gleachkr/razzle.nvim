---Module for slide properties
---@class RazzleSlide
local M = {}

--Vim Search, but falsy if nothing is found
function M.search(pattern, flags, stopline, timeout, skip)
    local rslt = vim.fn.search(pattern, flags, stopline, timeout, skip)
    if rslt > 0 then
        return rslt
    else
        return nil
    end
end

---Calculates the start of the next slide
---@return number next_start The line number of the next slide found, or end of buffer if not found.
function M.next_slide_ln()
    return M.search("SLIDE", "znW") or vim.api.nvim_buf_line_count(0)
end

---Calculates the start of the previous slide
---@return number prev_start The line number of the previous slide found, or 1 if not found.
function M.prev_slide_ln()
    local pos = vim.fn.getpos('.')  -- Store the current cursor position
    local line = vim.api.nvim_get_current_line()
    if not line:find("SLIDE") then
        -- This search finds the current slide marker, if we're not already
        -- on it
        M.search("SLIDE", "bcW")
    end
    -- and this finds the one before that
    local slide_line_number = M.search("SLIDE", "bnW")
    vim.fn.setpos('.', pos)  -- Restore the cursor position
    return slide_line_number or 1  -- Return the line number of the previous slide
end

---Calculates the end of the previous slide
---@return number prev_end The line number of the end of the previous slide, or 1 if not found
function M.prev_slide_end_ln()
    return M.search("FIN", "bnW") -- Search for the previous end marker
        or M.cur_slide_ln() -- or the start of the current slide
end

---Calculates the start of the current slide
---@return number cur_start  The line number of the current slide, or 1 if not found.
function M.cur_slide_ln()
    local line = vim.api.nvim_get_current_line()
    -- This search finds the current slide marker
    if line:find("SLIDE") then
        return vim.fn.getpos('.')[2]
    else
        return M.search("SLIDE", "bcnW") or 1
    end
end

---Calculates the end of the current slide
---@return number cur_end  The line number of the end of the current slide, or of the buffer if not found
function M.cur_slide_end_ln()
    local cur_start = M.cur_slide_ln()
    local pos = vim.fn.getpos('.')
    vim.fn.setpos('.', { 0, cur_start, 10000, 0 }) --setup search by moving to last col of first line
    local end_marker = M.search("FIN", "cnW") -- Search for the end marker of the current slide
    local next_start = M.next_slide_ln() -- or the start of the next slide / end of file
    vim.fn.setpos('.', pos) -- restore cursor position

    if end_marker and end_marker < next_start then
        return end_marker
    else
        return next_start
    end
end

---Counts the number of virtual lines in a specified range of a buffer.
---@param bufnr number  The buffer number to count virtual lines in.
---@param start_line number  The starting line number (1-based).
---@param end_line number  The ending line number (1-based).
---@return number total_virt_lines  The total number of virtual lines in the specified range.
local function count_virtual_lines(bufnr, start_line, end_line)
    -- Convert to 0-based indices
    local start_pos = {start_line - 1, 0}
    local end_pos = {end_line - 1, -1}
    local total_virt_lines = 0

    -- Get all extmarks in range
    local marks = vim.api.nvim_buf_get_extmarks(
        bufnr,
        -1,  -- Use any namespace
        start_pos,
        end_pos,
        {details = true}
    )

    -- Loop through marks and count virtual lines
    for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.virt_lines then
            total_virt_lines = total_virt_lines + #details.virt_lines
        end
    end
    return total_virt_lines
end

---Calculates the height of the current slide's interior
---@return number height The height of the current slide's interior, including virtual lines.
function M.slide_height()
    -- Get the line number of the top of the current slide
    local top = M.cur_slide_ln()
    -- Get the line number of the end of the current slide
    local bot = M.cur_slide_end_ln()
    -- Count the number of virtual lines between the top and bottom of the slide
    local virt = count_virtual_lines(0, top, bot)
    -- Return the total height of the slide, including virtual lines
    return (bot - top) + virt - 1
end

return M
