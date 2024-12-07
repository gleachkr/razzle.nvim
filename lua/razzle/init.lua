local M = {}

local slide = require("razzle.slide")

---Fires a slide changed event if the slide has changed
---@return nil
local function fire_slide_event()
    local active = vim.w.razzle_active_slide
    local bnum = vim.api.nvim_get_current_buf()
    local cur = slide.cur_slide_ln()
    local cur_end = slide.cur_slide_end_ln()
    local pos = vim.fn.getpos('.')  -- Store the current cursor position
    if active
    and (active.lnum ~= cur or active.bnum ~= bnum) -- Check if current slide is not the active one
    and pos[2] > cur --ensure we're in the current slide interior
    and pos[2] < cur_end
    then
        vim.w.razzle_active_slide = { lnum = cur, bnum = bnum }
        vim.cmd.doautocmd("User RazzleSlideChanged") -- Trigger the User RazzleSlideChanged
    end
end

---Starts the presentation by setting up autocmds and triggering the start event.
---@return nil
function M.start_presentation()
    local razzle_slide_group = vim.api.nvim_create_augroup("Razzle", { clear = true })
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        callback = fire_slide_event, -- Set the callback function for the autocmd
        group = razzle_slide_group, -- Assign the autocmd to the created group
    })
    local pos = slide.cur_slide_ln()
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
    local all_autocmds = vim.api.nvim_get_autocmds({ group = "Razzle"})
    for _, cmd in ipairs(all_autocmds) do
        -- if there's more than one command in the group, we accidentally try to delete it twice.
        -- this is a workaround, we should deduplicate the list instead.
        pcall(vim.api.nvim_del_augroup_by_name,cmd.group_name) -- Safely delete the autocommand group
    end
    vim.w.razzle_active_slide = nil -- Clear the active slide
end

return M
