local M = {}

---Calculates the start of the next slide
---@return number next_start The line number of the next slide found, or end of buffer if not found.
function M.next_slide_ln()
    return vim.fn.search("SLIDE", "n") or vim.api.nvim_buf_line_count(0)
end

---Calculates the start of the previous slide
---@return number prev_start The line number of the previous slide found, or 1 if not found.
function M.prev_slide_ln()
    local pos = vim.fn.getpos('.')  -- Store the current cursor position
    local line = vim.api.nvim_get_current_line()
    if not line:find("SLIDE") then
        -- This search finds the current slide marker, if we're not already
        -- on it
        vim.fn.search("SLIDE", "bcW")
    end
    -- and this finds the one before that
    local slide_line_number = vim.fn.search("SLIDE", "bnW")
    vim.fn.setpos('.', pos)  -- Restore the cursor position
    return slide_line_number or 1  -- Return the line number of the previous slide
end

---Calculates the end of the previous slide
---@return number prev_end The line number of the end of the previous slide, or 1 if not found
function M.prev_slide_end_ln()
    return vim.fn.search("FIN", "bnW") or 1  -- Search for the previous end marker
end

---Calculates the start of the current slide
---@return number cur_start  The line number of the current slide, or 1 if not found.
function M.cur_slide_ln()
    local pos = vim.fn.getpos('.')  -- Store the current cursor position
    local line = vim.api.nvim_get_current_line()
    -- This search finds the current slide marker
    if line:find("SLIDE") then
        return pos[2]
    else
        return vim.fn.search("SLIDE", "bcnW") or 1
    end
end

---Calculates the end of the current slide
---@return number cur_end  The line number of the end of the current slide, or of the buffer if not found
function M.cur_slide_end_ln()
    -- Search for the end of the current slide
    return vim.fn.search("FIN", "cnW") or vim.api.nvim_buf_line_count(0)
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


---Moves to the top of the next slide's interior
---@return nil
function M.next_slide()
    -- Get the line number of the next slide
    local pos = M.next_slide_ln()
    -- Set the cursor position to the next slide
    vim.fn.setpos('.', { 0, pos + 1, 0, 0 })
end

---Moves to the top of the previous slide's interior
---@return nil
function M.prev_slide()
    -- Get the line number of the previous slide
    local pos = M.prev_slide_ln()
    -- Set the cursor position to the previous slide's line
    vim.fn.setpos('.', { 0, pos + 1, 0, 0 })
end


---Moves to top of the current slide's interior
---@return nil
function M.cur_slide()
    -- Get the line number of the current slide
    local pos = M.cur_slide_ln() -- pos: number
    -- Set the cursor position to the current slide's line
    vim.fn.setpos('.', { 0, pos + 1, 0, 0 }) -- Set cursor position in the current buffer
end

---Aligns the view to the current slide's interior.
---@return nil
function M.align_view()
    local top = M.cur_slide_ln() -- the line number of the current slide
    local bot = M.cur_slide_end_ln() -- end number, the line number of the end of the current slide
    local pos = vim.fn.getpos('.')
    if pos[2] <= top then pos[2] = top + 1 end -- Adjust pos to make sure we're in the slide interior
    if pos[2] >= bot then pos[2] = bot - 1 end
    vim.fn.setpos('.', pos)
    vim.fn.winrestview({ topline = top + 1 }) -- Adjusts the window view to the specified line
end

---Fires a slide changed event if the slide has changed
---@return nil
local function fire_slide_event()
    local active = vim.w.razzle_active_slide
    local bnum = vim.api.nvim_get_current_buf()
    local cur = M.cur_slide_ln()
    local prev_end = M.prev_slide_end_ln()
    if active
    and (active.lnum ~= cur or active.bnum ~= bnum) -- Check if current slide is not the active one
    and prev_end <= cur -- Ensure previous slide ends before what we think is the current slide begins
    then
        vim.w.razzle_active_slide = { lnum = cur, bnum = bnum }
        vim.cmd.doautocmd("User RazzleSlideChanged") -- Trigger the User RazzleSlideChanged
    end
end

---Starts the presentation by setting up autocmds and triggering the start event.
---@return nil
function M.start_presentation()
    local razzle_slide_group = vim.api.nvim_create_augroup("RazzleSlide", { clear = true }) -- Create a new autocommand group
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        callback = fire_slide_event, -- Set the callback function for the autocmd
        group = razzle_slide_group, -- Assign the autocmd to the created group
    })
    local pos = M.cur_slide_ln()
    vim.fn.setpos('.', { 0, pos, 0, 0 }) -- Set cursor position in the current buffer
    vim.cmd.doautocmd("User RazzleStart") -- Trigger the User RazzleStart event
    -- Set the current slide as the active slide
    vim.w.razzle_active_slide = {
        lnum = pos,
        bnum = vim.api.nvim_get_current_buf()
    }
end

---Ends the presentation by cleaning up autocmds and triggering the end event.
---@return nil
function M.end_presentation()
    vim.cmd.doautocmd("User RazzleEnd") -- Trigger the User RazzleEnd event
    local all_autocmds = vim.api.nvim_get_autocmds()
    for _, cmd in ipairs(all_autocmds) do
        if cmd.group_name then
            -- if there's more than one command in the group, we accidentally try to delete it twice.
            -- this is a workaround, we should deduplicate the list instead.
            pcall(vim.api.nvim_del_augroup_by_name,cmd.group_name) -- Safely delete the autocommand group
        end
    end
    vim.w.razzle_active_slide = nil -- Clear the active slide
end

return M
