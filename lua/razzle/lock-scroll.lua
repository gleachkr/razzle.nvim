---Module for locking the cursor to a certain range
---@class RazzleLock
local M = {}

---Restrict cursor movement within the bounds set in the buffer.
---@return nil
function M.restrict_cursor_movement()
    if not vim.b.razzle_scroll_bounds then return nil end
    local current_line = vim.fn.line(".")
    local lower_bound = vim.b.razzle_scroll_bounds[1]
    local upper_bound = vim.b.razzle_scroll_bounds[2]

    -- Ensure that the lower bound is the top visible line
    vim.fn.winrestview({ topline = lower_bound })

    if current_line < lower_bound then
        vim.fn.setpos(".", {0, lower_bound, 1, 0})
    elseif current_line > upper_bound then
        vim.fn.setpos(".", {0, upper_bound, 1, 0})
    end
end

---Lock the scroll by setting the bounds based on the current window.
---@return nil
function M.lock_scroll()
    -- Set scroll bounds
    vim.b.razzle_scroll_bounds = { vim.fn.line("w0"), vim.fn.line("w$") }
end

---Unlock the scroll by unsetting the bounds.
---@return nil
function M.unlock_scroll()
    -- Unset scroll bounds
    vim.b.razzle_scroll_bounds = nil
end

-- Create an autocommand to restrict cursor movement on CursorMoved and CursorMovedI events
vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    callback = M.restrict_cursor_movement,
    buffer = 0,
    group = vim.api.nvim_create_augroup("RazzleLock", { clear = true }),
})

return M
