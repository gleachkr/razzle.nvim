local M = {}

local zen = require("zen-mode.view")

function M.set_layout(w, h)
    if zen.is_open() then
        local width = w or vim.api.nvim_win_get_width(zen.win)
        local height = h or vim.api.nvim_win_get_height(zen.win)
        local col = zen.round((vim.o.columns - width) / 2)
        local row = zen.round((zen.height() - height) / 2)
        local cfg = vim.api.nvim_win_get_config(zen.win)
        local wcol = type(cfg.col) == "number" and cfg.col or cfg.col[false]
        local wrow = type(cfg.row) == "number" and cfg.row or cfg.row[false]
        if wrow ~= row or wcol ~= col then
            vim.api.nvim_win_set_config(zen.win, { width = width, height = height, col = col, row = row, relative = "editor" })
        end
    end
end

return M
