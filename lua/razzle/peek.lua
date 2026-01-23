-- Inline "peek" view for Razzle.
--
-- If the current slide has a `peek=FRAG` marker param, this module renders the
-- interior lines of the target slide (by fragment id) as virtual lines below
-- the last line of the current slide.
--
-- This is meant as a lightweight alternative to zen-mode's `split=...` and is
-- useful even when not using zen-mode.

---@class RazzlePeek
local M = {}

local slide = require('razzle.slide')

M.config = {
  -- Param name on SLIDE markers: SLIDE?peek=frag
  param = 'peek',
  -- Highlight group for peeked virtual lines.
  hl = 'RazzlePeek',
  -- Insert a blank virtual line before the peeked content.
  blank_line = true,
  -- Optional header. When true, show a small label line.
  header = false,
  -- Prefix added to each rendered peek line (and header).
  prefix = '',
  -- When set, limit the number of rendered lines.
  max_lines = nil,
}

local ns = vim.api.nvim_create_namespace('RazzlePeek')

local enabled = false
local active_buf = nil
local extmark_id = nil

local function merge_cfg(dst, src)
  for k, v in pairs(src or {}) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      merge_cfg(dst[k], v)
    else
      dst[k] = v
    end
  end
end

local function ensure_hl()
  -- Default link: Comment. Users may override the group.
  pcall(vim.api.nvim_set_hl, 0, M.config.hl, {
    link = 'Comment',
    default = true,
  })
end

local function param_value(s)
  if not (s and s.params) then return nil end
  local v = s.params[M.config.param]
  if not v then return nil end
  if type(v) == 'table' then v = v[1] end
  if v == '' then return nil end
  return v
end

local function clear_active()
  if active_buf and vim.api.nvim_buf_is_valid(active_buf) then
    pcall(vim.api.nvim_buf_clear_namespace, active_buf, ns, 0, -1)
  end
  active_buf = nil
  extmark_id = nil
end

local function slide_interior_lines(s)
  if not (s and vim.api.nvim_buf_is_valid(s.bufNu)) then return {} end
  if not vim.api.nvim_buf_is_loaded(s.bufNu) then
    pcall(vim.fn.bufload, s.bufNu)
  end
  local start_0 = s.startLn
  local end_excl = s.endLn - 1
  if end_excl <= start_0 then return {} end
  return vim.api.nvim_buf_get_lines(s.bufNu, start_0, end_excl, false)
end

local function virt_line(text, hl)
  return { { text, hl } }
end

local function build_virt_lines(target, frag)
  local hl = M.config.hl
  local pref = M.config.prefix or ''

  local out = {}

  if M.config.blank_line then
    out[#out + 1] = virt_line('', hl)
  end

  if M.config.header then
    out[#out + 1] = virt_line(pref .. '[peek: ' .. frag .. ']', hl)
  end

  local lines = slide_interior_lines(target)

  local max_lines = M.config.max_lines
  if type(max_lines) == 'number' and max_lines > 0 then
    if #lines > max_lines then
      for i = 1, max_lines do
        out[#out + 1] = virt_line(pref .. lines[i], hl)
      end
      out[#out + 1] = virt_line(pref .. '…', hl)
      return out
    end
  end

  for _, l in ipairs(lines) do
    out[#out + 1] = virt_line(pref .. l, hl)
  end

  return out
end

local function anchor_row_for_slide(cur)
  -- Prefer the last interior line; fall back to the marker line.
  local anchor_line = cur.endLn - 1
  if anchor_line <= cur.startLn then anchor_line = cur.startLn end
  return anchor_line - 1
end

local function update()
  if not enabled then return end

  local cur = slide.cur_slide()
  if not cur then
    clear_active()
    return
  end

  -- Keep slide data reasonably fresh for the current buffer.
  pcall(slide.refresh_slides, cur.bufNu)
  cur = slide.cur_slide() or cur

  local frag = param_value(cur)
  if not frag then
    clear_active()
    return
  end

  local target = slide.fragment_slide(frag)
  if not target then
    clear_active()
    return
  end

  -- Avoid degenerate self-peeks.
  if target.bufNu == cur.bufNu and target.startLn == cur.startLn then
    clear_active()
    return
  end

  if active_buf and active_buf ~= cur.bufNu then
    clear_active()
  end

  local row = anchor_row_for_slide(cur)
  local virt_lines = build_virt_lines(target, frag)

  active_buf = cur.bufNu
  extmark_id = vim.api.nvim_buf_set_extmark(active_buf, ns, row, 0, {
    id = extmark_id,
    virt_lines = virt_lines,
    virt_lines_above = false,
    virt_lines_leftcol = true,
    hl_mode = 'combine',
    priority = 90,
  })
end

function M.setup(opts)
  merge_cfg(M.config, opts or {})
  ensure_hl()
end

-- Autocommands ------------------------------------------------------------

local group = vim.api.nvim_create_augroup('RazzlePeek', { clear = true })

vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'RazzleStart',
  callback = function()
    enabled = true
    ensure_hl()
    vim.schedule(update)
  end,
})

vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'RazzleSlideEnter',
  callback = function()
    if not enabled then return end
    vim.schedule(update)
  end,
})

vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
  group = group,
  callback = function()
    if not enabled then return end
    -- Only resync when editing the active slide buffer. Avoid clearing peek
    -- content when editing unrelated buffers during a presentation.
    if active_buf
       and vim.api.nvim_get_current_buf() ~= active_buf then
      return
    end
    vim.schedule(update)
  end,
})

vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'RazzleEnd',
  callback = function()
    enabled = false
    clear_active()
  end,
})

return M
