---Module for concealing slide markers
---@class RazzleConceal
local M = {}

-- Pattern that matches lines with slide markers (window-local match).
local MARKER_PATTERN = [[^.*\(SLIDE\C\|FIN\C\).*$]]

-- Ensure our highlight exists. Independent of conceallevel.
local function ensure_highlights()
  vim.cmd('highlight ConcealLine guifg=bg guibg=bg')
end

---Conceals slide markers in the current window.
---Idempotent; safe to call repeatedly.
---@return nil
function M.conceal_slide_markers()
  ensure_highlights()
  if not vim.w.razzle_conceal_match_id then
    local id = vim.fn.matchadd('ConcealLine', MARKER_PATTERN)
    vim.w.razzle_conceal_match_id = id
  end
end

---Reveals slide markers in the current window.
---@return nil
function M.reveal_slide_markers()
  local id = vim.w.razzle_conceal_match_id
  if id then
    pcall(vim.fn.matchdelete, id)
    vim.w.razzle_conceal_match_id = nil
  end
end

-- Apply on presentation start/slide-enter/end.
vim.api.nvim_create_autocmd('User', {
  pattern = 'RazzleStart',
  callback = function()
    -- Defer so colorscheme changes from options run first.
    vim.schedule(M.conceal_slide_markers)
  end,
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'RazzleSlideEnter',
  callback = function()
    vim.schedule(M.conceal_slide_markers)
  end,
})

vim.api.nvim_create_autocmd('User', {
  callback = function()
    -- Clear matches in all windows to be safe when ending.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local ok, id = pcall(vim.api.nvim_win_get_var, win, 'razzle_conceal_match_id')
      if ok and type(id) == 'number' then
        pcall(vim.api.nvim_win_call, win, function()
          pcall(vim.fn.matchdelete, id)
        end)
        pcall(vim.api.nvim_win_del_var, win, 'razzle_conceal_match_id')
      end
    end
  end,
  pattern = 'RazzleEnd',
})

-- Re-apply highlight on colorscheme changes.
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = ensure_highlights,
})

return M
