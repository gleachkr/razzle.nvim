---Module for returning window focus to presentation when a terminal closes
---@class RazzleTerm
local M = {}

M.return_target = nil

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
        -- TODO should probably restore previous TermClose on RazzleEnd
        vim.api.nvim_del_augroup_by_name("nvim.terminal")

        M.return_target = start_args.data.entered

        vim.api.nvim_create_autocmd("User", {
            callback = function(ent_args) M.return_target = ent_args.data.entered end,
            pattern = "RazzleSlideEnter",
            group = vim.api.nvim_create_augroup("Razzle", { clear = false}),
        })

        vim.api.nvim_create_autocmd("TermClose", {
            callback = M.return_to_deck,
            group = vim.api.nvim_create_augroup("Razzle", { clear = false}),
        })
    end,
    pattern = "RazzleStart"
})

return M
