---Module for returning window focus to presentation when a terminal closes
---@class RazzleTerm
local M = {}

M.return_target = nil
M._saved_terminal_autocmds = nil

---return to buffer of current slide
---@return nil
function M.return_to_deck()
    if M.return_target then
        vim.api.nvim_set_current_buf(M.return_target.bufNu)
        vim.fn.setpos('.', { 0, M.return_target.startLn + 1, 0, 0 })
    end
end

vim.api.nvim_create_autocmd("User", {
    callback = function(start_args)
        -- Capture existing nvim.terminal autocommands so we can restore them.
        local ok, acs = pcall(vim.api.nvim_get_autocmds, {
            group = "nvim.terminal",
        })
        if ok and type(acs) == "table" and #acs > 0 then
            M._saved_terminal_autocmds = acs
        else
            M._saved_terminal_autocmds = nil
        end
        -- Clear the default terminal handlers that close the window on TermClose
        pcall(vim.api.nvim_del_augroup_by_name, "nvim.terminal")

        M.return_target = start_args.data.entered

        local razzle_group = vim.api.nvim_create_augroup("Razzle", {
            clear = false,
        })

        vim.api.nvim_create_autocmd("User", {
            callback = function(ent_args)
                M.return_target = ent_args.data.entered
            end,
            pattern = "RazzleSlideEnter",
            group = razzle_group,
        })

        vim.api.nvim_create_autocmd("TermClose", {
            callback = M.return_to_deck,
            group = razzle_group,
        })

        -- On presentation end, restore the original nvim.terminal handlers.
        vim.api.nvim_create_autocmd("User", {
            pattern = "RazzleEnd",
            group = razzle_group,
            callback = function()
                if M._saved_terminal_autocmds and #M._saved_terminal_autocmds > 0 then
                    local term_group = vim.api.nvim_create_augroup("nvim.terminal", {
                        clear = true,
                    })
                    for _, ac in ipairs(M._saved_terminal_autocmds) do
                        local opts = {
                            group = term_group,
                            desc = ac.desc,
                            pattern = ac.pattern,
                            buffer = ac.buffer,
                            callback = ac.callback,
                            command = ac.command,
                            once = ac.once,
                            nested = ac.nested,
                        }
                        -- ac.event is a string or list; nvim accepts both.
                        pcall(vim.api.nvim_create_autocmd, ac.event, opts)
                    end
                end
                -- Clear state so future presentations recapture fresh handlers.
                M._saved_terminal_autocmds = nil
                M.return_target = nil
            end,
        })
    end,
    pattern = "RazzleStart"
})

return M
