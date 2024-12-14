local M = {}

local slide = require("razzle.slide")

---Fires a slide enter event on entering a new slide
---@return nil
local function fire_slide_event()
    local active = vim.w.razzle_active_slide
    local bnum = vim.api.nvim_get_current_buf()
    local cur = slide.cur_slide_ln()
    local cur_end = slide.cur_slide_end_ln()
    local pos = vim.fn.getpos('.')  -- Store the current cursor position
    if cur
    and active
    and (active.lnum ~= cur or active.bnum ~= bnum) -- Check if current slide is not the active one
    and pos[2] > cur --ensure we're in the current slide interior
    and pos[2] < cur_end
    then
        vim.w.razzle_active_slide = { lnum = cur, bnum = bnum }
        vim.cmd.doautocmd("User RazzleSlideEnter") -- Trigger the User RazzleSlideChanged
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
    local pos = slide.cur_slide_ln() --get start marker for current slide
    if not pos then
        print("Can't start presentation: cursor must be in a slide")
    else
        vim.fn.setpos('.', { 0, pos + 1, 0, 0 }) -- Set cursor position in the current buffer
        vim.cmd.doautocmd("User RazzleStart") -- Trigger the User RazzleStart event
        -- Set the current slide as the active slide
        vim.w.razzle_active_slide = {
            lnum = pos,
            bnum = vim.api.nvim_get_current_buf()
        }
    end
end

---Ends the presentation by cleaning up autocmds and triggering the end event.
---@return nil
function M.end_presentation()
    vim.cmd.doautocmd("User RazzleEnd") -- Trigger the User RazzleEnd event
    vim.api.nvim_del_augroup_by_name("Razzle")
    vim.w.razzle_active_slide = nil -- Clear the active slide
end

vim.api.nvim_create_user_command("RazzleStart", M.start_presentation, {
    desc = "Starts the presentation by setting up autocmds and triggering the start event."
})

vim.api.nvim_create_user_command("RazzleEnd", M.end_presentation, {
    desc = "Ends the presentation by cleaning up autocmds and triggering the end event."
})

return M
