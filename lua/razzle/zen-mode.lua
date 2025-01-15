---Module for dynamically updating zen_mode layouts
---@class RazzleZen
local M = {}

local zen = require("zen-mode.view")
local motion = require("razzle.motion")
local slide = require("razzle.slide")

function M.set_layout(w, h)
    if zen.is_open() then
        local width = w or vim.api.nvim_win_get_width(zen.win)
        local height = h or vim.api.nvim_win_get_height(zen.win)
        local col = zen.round((vim.o.columns - width) / 2)
        local row = zen.round((zen.height() - height) / 2)
        local cfg = vim.api.nvim_win_get_config(zen.win)
        local wcol = type(cfg.col) == "number" and cfg.col or cfg.col[false]
        local wrow = type(cfg.row) == "number" and cfg.row or cfg.row[false]
        if wrow ~= row or wcol ~= col or w or h then
            vim.api.nvim_win_set_config(zen.win, {
                width = width,
                height = height,
                col = col,
                row = row,
                relative = "editor"
            })
        end
    end
end

vim.api.nvim_create_autocmd("User", {
    callback = function()
        local height = slide.slide_height()
        M.set_layout(nil, height)
        motion.align_view()
    end,
    pattern = "RazzleSlideEnter",
})

vim.api.nvim_create_autocmd("User", {
    callback = function()
        vim.opt.scrolloff = 0
        zen.open({window = { height=slide.slide_height(), width=80 }})
        motion.align_view()
        vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI", "SafeState"}, {
            callback = function()
                local height = slide.slide_height()
                if height then
                    M.set_layout(nil, slide.slide_height())
                    motion.align_view()
                end
            end,
            group = vim.api.nvim_create_augroup("Razzle", { clear = false})
        })
    end,
    pattern = "RazzleStart"
})

vim.api.nvim_create_autocmd("User", {
    callback = zen.close,
    pattern = "RazzleEnd"
})

return M
