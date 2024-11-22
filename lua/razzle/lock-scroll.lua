local M = {}

-- Restrict cursor movement within the bounds
function M.restrict_cursor_movement()
    if not vim.b.razzle_scroll_bounds then return nil end
    local current_line = vim.fn.line(".")
    local lower_bound = vim.b.razzle_scroll_bounds[1]
    local upper_bound = vim.b.razzle_scroll_bounds[2]

    --ensure that the lower bound is the top visible line
    vim.fn.winrestview({ topline = lower_bound  })

    if current_line < lower_bound then
        vim.fn.setpos(".", {0, lower_bound, 1, 0})
    elseif current_line > upper_bound then
        vim.fn.setpos(".", {0, upper_bound, 1, 0})
    end
end

function M.lock_scroll()
    --set scroll bounds
    vim.b.razzle_scroll_bounds = { vim.fn.line("w0"), vim.fn.line("w$") }
end

function M.unlock_scroll()
    --unset scroll bounds
    vim.b.razzle_scroll_bounds = nil
end

vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    callback = M.restrict_cursor_movement,
    -- this makes it one presentation/buffer at a time. 
    -- Could be generalized to support several
    -- best approach would be storing scrollbounds in a buffer local var
    group = vim.api.nvim_create_augroup("RazzleLock", { clear = true }),
})

return M
