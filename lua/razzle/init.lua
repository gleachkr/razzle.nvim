local M = {}

local slide = require("razzle.slide")

---Fires a slide enter event on entering a new slide
---@return nil
local function fire_slide_event()
    local active = vim.w.razzle_active_slide
    local cur = slide.cur_slide()
    local pos = vim.fn.getpos('.')  -- Store the current cursor position
    if cur
    and active
    and (active.startLn ~= cur.startLn or active.bufNu ~= cur.bufNu) -- Check if current slide is not the active one
    and pos[2] > cur.startLn --ensure we're in the current slide interior
    and pos[2] < cur.endLn
    then
        vim.w.razzle_active_slide = cur
        vim.cmd.doautocmd("User RazzleSlideEnter") -- Trigger the User RazzleSlideChanged
    end
end

---Starts the presentation by setting up autocmds and triggering the start event.
---@return nil
function M.start_presentation()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            slide.refresh_slides(buf)
        end
    end
    local cur = slide.cur_slide() --get start marker for current slide
    if not cur then
        vim.notify("Can't start presentation: cursor must be in a slide", vim.log.levels.ERROR)
    else
        local razzle_slide_group = vim.api.nvim_create_augroup("Razzle", { clear = true })
        -- fire slide events on move to a new window
        vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
            callback = fire_slide_event,
            group = razzle_slide_group,
        })
        -- update slide data when text changes
        vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
            callback = function () slide.refresh_slides(vim.api.nvim_get_current_buf()) end,
            group = razzle_slide_group
        })
        vim.fn.setpos('.', { 0, cur.startLn + 1, 0, 0 }) -- Set cursor position in the current buffer
        vim.cmd.doautocmd("User RazzleStart") -- Trigger the User RazzleStart event
        -- Set the current slide as the active slide
        vim.w.razzle_active_slide = cur
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
