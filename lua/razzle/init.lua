local M = {}

---Calculates the start of the next slide
---@return number next_start The line number of the next slide found, or 0 if not found.
function M.next_slide_ln()
    return vim.fn.search("SLIDE", "n")
end

---Calculates the start of the previous slide
---@return number prev_start The line number of the previous slide found, or 0 if not found.
function M.prev_slide_ln()
    local pos = vim.fn.getpos('.')  -- Store the current cursor position
    -- This search jumps to the current slide marker
    vim.fn.search("SLIDE", "bc")
    -- and this finds the one before that
    local slide_line_number = vim.fn.search("SLIDE", "bn")
    vim.fn.setpos('.', pos)  -- Restore the cursor position
    return slide_line_number  -- Return the line number of the previous slide
end

---Calculates the start of the current slide
---@return number cur_start  The line number of the current slide found, or 0 if not found.
function M.cur_slide_ln()
    return vim.fn.search("SLIDE", "bcn")  -- Search for the current slide marker
end

---Calculates the end of the current slide
---@return number cur_end  The line number of the end marker of the current slide found, or 0 if not found.
function M.end_slide_ln()
    return vim.fn.search("FIN", "cn")  -- Search for the end marker of the current slide
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

---Calculates the height of the current slide.
---@return number height The height of the current slide, including virtual lines.
function M.slide_height()
    -- Get the line number of the top of the current slide
    local top = M.cur_slide_ln()
    -- Get the line number of the end of the current slide
    local bot = M.end_slide_ln()
    -- Count the number of virtual lines between the top and bottom of the slide
    local virt = count_virtual_lines(0, top, bot)
    -- Return the total height of the slide, including virtual lines
    return (bot - top) + virt
end


---Moves to the top of the next slide in the presentation.
---@return nil
function M.next_slide()
    -- Get the line number of the next slide
    local pos = M.next_slide_ln()
    -- Set the cursor position to the next slide
    vim.fn.setpos('.', { 0, pos, 0, 0 })
end

---Moves to the top of the previous slide in the presentation.
---@return nil
function M.prev_slide()
    -- Get the line number of the previous slide
    local pos = M.prev_slide_ln()
    -- Set the cursor position to the previous slide's line
    vim.fn.setpos('.', { 0, pos, 0, 0 })
end


---Moves to top of the current slide in the presentation.
---@return nil
function M.cur_slide()
    -- Get the line number of the current slide
    local pos = M.cur_slide_ln() -- pos: number
    -- Set the cursor position to the current slide's line
    vim.fn.setpos('.', { 0, pos, 0, 0 }) -- Set cursor position in the current buffer
end

---Aligns the view to the current slide.
---@return nil
function M.align_view()
    local pos = M.cur_slide_ln() -- pos: number, the line number of the current slide
    -- Restore the window view to the specified line number
    vim.fn.winrestview({ topline = pos }) -- Adjusts the window view to the specified line
end

---Fires a slide event if the current word is "SLIDE".
---@return nil
local function fire_slide_event()
    if vim.fn.expand("<cword>") == "SLIDE" then -- Check if the current word is "SLIDE"
        vim.cmd.doautocmd("User RazzleSlide") -- Trigger the User RazzleSlide event
    end
end

---Starts the presentation by setting up autocmds and triggering the start event.
---Moves to the start of the current slide, triggering a RazzleSlide event
---@return nil
function M.start_presentation()
    vim.cmd.doautocmd("User RazzleStart") -- Trigger the User RazzleStart event
    local razzle_slide_group = vim.api.nvim_create_augroup("RazzleSlide", { clear = true }) -- Create a new autocommand group
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        callback = fire_slide_event, -- Set the callback function for the autocmd
        group = razzle_slide_group, -- Assign the autocmd to the created group
        buffer = 0, -- Apply to the current buffer
    })

    M.cur_slide() -- Move to the start of the current slide, triggering a RazzleSlide event
end

---Ends the presentation by cleaning up autocmds and triggering the end event.
---@return nil
function M.end_presentation()
    vim.cmd.doautocmd("User RazzleEnd") -- Trigger the User RazzleEnd event
    local all_autocmds = vim.api.nvim_get_autocmds({
        buffer=0, -- NOTE: this requires that all razzle groups have buffer=0 set
    })
    for _, cmd in ipairs(all_autocmds) do
        if cmd.group_name then
            -- if there's more than one command in the group, we accidentally try to delete it twice.
            -- this is a workaround, we should deduplicate the list instead.
            pcall(vim.api.nvim_del_augroup_by_name,cmd.group_name) -- Safely delete the autocommand group
        end
    end
end

return M
