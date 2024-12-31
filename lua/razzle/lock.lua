local slide = require("razzle.slide")

---Module for locking the cursor to a certain range within a certain window
---@class RazzleLock
local M = {}

---Restrict cursor movement within the bounds set in the window.
---@return nil
local function restrict_cursor_movement()
    if not vim.w.razzle_scroll_bounds then return nil end
    local current_line = vim.fn.line(".")
    local lower_bound = vim.w.razzle_scroll_bounds[1]
    local upper_bound = vim.w.razzle_scroll_bounds[2]

    -- Ensure that the lower bound is the top visible line
    vim.fn.winrestview({ topline = lower_bound })

    if current_line < lower_bound then
        vim.fn.setpos(".", {0, lower_bound, 1, 0})
    elseif current_line > upper_bound then
        vim.fn.setpos(".", {0, upper_bound, 1, 0})
    end
end

---Restrict cursor movement to the window, returning if its not a popup or
---a window with scroll bounds
---@return nil
local function restrict_cursor_window()
    local is_float = vim.fn.win_gettype() == "popup"
    if not vim.w.razzle_scroll_bounds and not is_float then
        vim.cmd.wincmd("p")
    end
end

---Lock the scroll by setting the bounds based on the current window.
---@return nil
function M.lock_scroll()
    -- Set scroll bounds
    local top = slide.cur_slide_ln()
    local bot = slide.cur_slide_end_ln()
    if not top then
        vim.notify("Can't lock scroll, cursor must be in a slide", vim.log.levels.ERROR)
    elseif bot <= top then
        vim.notify("slide lacks interior, cannot lock cursor to interior", vim.log.levels.ERROR)
    else
        vim.w.razzle_scroll_bounds = {  top + 1 , bot - 1 }
        -- Create an autocommand to restrict cursor movement on CursorMoved and CursorMovedI events
        vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
            callback = restrict_cursor_movement,
            group = vim.api.nvim_create_augroup("Razzle", { clear = false}),
        })
        vim.api.nvim_create_autocmd({"WinEnter"}, {
            callback = restrict_cursor_window,
            group = vim.api.nvim_create_augroup("Razzle", { clear = false}),
        })
    end
end

---Unlock the scroll by unsetting the bounds.
---@return nil
function M.unlock_scroll()
    -- Unset scroll bounds
    vim.w.razzle_scroll_bounds = nil
end

vim.api.nvim_create_autocmd("User", {
    callback = M.lock_scroll,
    pattern = "RazzleSlideEnter",
})

vim.api.nvim_create_autocmd("User", {
    callback = M.unlock_scroll,
    pattern = "RazzleEnd"
})

vim.api.nvim_create_autocmd("User", {
    callback = function()
        vim.opt.scrolloff = 0
        M.lock_scroll()
        vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
            callback = M.lock_scroll,
            group = vim.api.nvim_create_augroup("Razzle", { clear = false})
        })
    end,
    pattern = "RazzleStart"
})

return M