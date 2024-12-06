---Module for concealing slide markers 
---@class RazzleConceal
local M = {}

---Conceals slide markers in the current buffer.
---@return nil
function M.conceal_slide_markers()

    vim.cmd('highlight ConcealLine guifg=bg guibg=bg')

    --for regular syntax
    vim.cmd([[
        syntax match SlideMarker /^.*\(SLIDE\|FIN\).*$/ containedin=ALL
    ]])
    vim.cmd('highlight link SlideMarker ConcealLine')

    --for treesitter
    vim.fn.matchadd('ConcealLine',"^.*(SLIDE|FIN).*$")
end

---Reveals slide markers in the current buffer.
---@return nil
function M.reveal_slide_markers()
    vim.cmd('syntax clear SlideMarker')
    vim.cmd('highlight clear ConcealLine')
end

return M
