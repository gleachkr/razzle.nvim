-- Current-slide visuals for Razzle
-- - Per-window highlights via a decoration provider (ephemeral extmarks)
-- - Optional sign indicators via extmark sign_* (continuous bar)
--
-- Config example:
-- require('razzle.mark').setup({
--   colors = {
--     dim   = { blend = 30, color = '#000000' }, -- enables outside dim
--     slide = { link = 'CursorLine' },           -- enables interior bg
--   },
--   sign = {                     -- indicator in sign column; presence enables
--     text  = '▎',
--     texthl= 'RazzleMarkSign',
--     -- draws on every interior line of the slide
--   },
-- })
--
-- During a presentation, visuals update on slide changes and redraws.

local M = {}

local slide = require('razzle.slide')

-- State --------------------------------------------------------------------

M.config = {
  colors = {
    dim   = { blend = 30, color = '#000000' },
    slide = nil, -- set to { link = 'CursorLine' } to enable interior bg
  },
  -- signs disabled by default; set to a table to enable
  sign = nil, -- { text = '▎', texthl = 'RazzleMarkSign' }
}

local ns = vim.api.nvim_create_namespace('RazzleMark')
local enabled = false
local sign_extmark_id

-- Color helpers ------------------------------------------------------------

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function rgb_from_number(n)
  local r = math.floor(n / 65536) % 256
  local g = math.floor(n / 256) % 256
  local b = n % 256
  return r, g, b
end

local function rgb_from_hex(hex)
  local r, g, b = hex:match('#?(%x%x)(%x%x)(%x%x)')
  if not r then return 0, 0, 0 end
  return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function to_hex(r, g, b)
  return string.format('#%02x%02x%02x', clamp(r,0,255),
                                      clamp(g,0,255),
                                      clamp(b,0,255))
end

local function blend_rgb(r1,g1,b1, r2,g2,b2, pct)
  local a = clamp(pct or 0, 0, 100) / 100.0
  local r = math.floor(r1 + (r2 - r1) * a + 0.5)
  local g = math.floor(g1 + (g2 - g1) * a + 0.5)
  local b = math.floor(b1 + (b2 - b1) * a + 0.5)
  return r, g, b
end

local function ensure_dim_hl()
  -- Recompute a dimming highlight that preserves background and dims text.
  -- Strategy: blend Normal.fg toward target (default: Normal.bg) by pct,
  -- and set only fg so background remains untouched.
  local ok, normal = pcall(vim.api.nvim_get_hl, 0, { name = 'Normal',
                                                     link = false })
  local base_fg = (ok and normal and normal.fg) or nil
  local base_bg = (ok and normal and normal.bg) or nil
  local dim = M.config.colors and M.config.colors.dim or {}
  local tgt_hex = dim.color -- if nil, we use base_bg
  local blend = dim.blend or 0

  local fr, fg, fb = 255, 255, 255
  if type(base_fg) == 'number' then
    fr, fg, fb = rgb_from_number(base_fg)
  end

  local tr, tg, tb
  if tgt_hex and type(tgt_hex) == 'string' then
    tr, tg, tb = rgb_from_hex(tgt_hex)
  elseif type(base_bg) == 'number' then
    tr, tg, tb = rgb_from_number(base_bg)
  else
    -- Fallback to blending toward black if we have nothing better.
    tr, tg, tb = 0, 0, 0
  end

  local rr, rg, rb = blend_rgb(fr, fg, fb, tr, tg, tb, blend)
  local fg_hex = to_hex(rr, rg, rb)

  -- Only set fg so we do not alter background.
  vim.api.nvim_set_hl(0, 'RazzleMarkDim', { fg = fg_hex })
end

local function ensure_slide_hl()
  local s = M.config.colors and M.config.colors.slide or {}
  if s and s.link then
    vim.api.nvim_set_hl(0, 'RazzleMarkSlide',
                        { link = s.link, default = false })
    return
  end
  if s and (s.bg or s.fg) then
    vim.api.nvim_set_hl(0, 'RazzleMarkSlide',
                        { bg = s.bg, fg = s.fg })
    return
  end
  -- Default: link to CursorLine
  vim.api.nvim_set_hl(0, 'RazzleMarkSlide', { link = 'CursorLine' })
end

local function ensure_sign_hl()
  if type(M.config.sign) ~= 'table' or not M.config.sign.texthl then return end
  local name = M.config.sign.texthl
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  local exists = ok and hl and (next(hl) ~= nil)
  if not exists then
    vim.api.nvim_set_hl(0, name, { link = 'DiagnosticInfo' })
  end
end

local function apply_highlights()
  ensure_dim_hl()
  ensure_slide_hl()
  ensure_sign_hl()
end

-- Decoration provider (per-window visuals) --------------------------------

local function hl_range(buf, row0, end_row, group, mode, prio)
  if row0 >= end_row then return end
  vim.api.nvim_buf_set_extmark(buf, ns, row0, 0, {
    end_row = end_row,
    end_col = 0,
    hl_group = group,
    hl_mode = mode or 'replace',
    hl_eol = true,
    priority = prio or 80,
    ephemeral = true,
  })
end

local function signs_enabled()
  return type(M.config.sign) == 'table'
end

local function dim_enabled()
  return M.config.colors and (M.config.colors.dim ~= nil)
end

local function slidehl_enabled()
  return M.config.colors and (M.config.colors.slide ~= nil)
end

vim.api.nvim_set_decoration_provider(ns, {
  on_start = function()
    return enabled
  end,
  on_win = function(_, win, buf)
    if not enabled then return false end

    local cur
    pcall(vim.api.nvim_win_call, win, function()
      cur = slide.cur_slide()
    end)

    if not cur then
      return false
    end

    local s = cur
    local nlines = vim.api.nvim_buf_line_count(buf)

    -- Unified draw path: clear our namespace and redraw everything.
    -- Ephemeral highlights are recreated below; signs must be persistent.
    if signs_enabled() then
      local text   = M.config.sign.text   or '▎'
      local texthl = M.config.sign.texthl or 'RazzleMarkSign'
      sign_extmark_id = vim.api.nvim_buf_set_extmark(buf, ns, s.startLn, 0, {
        sign_text = text,
        sign_hl_group = texthl,
        end_row = s.endLn - 2,
        priority = 100,
        id = sign_extmark_id,
      })
    end

    -- Dim top outside including the SLIDE marker line
    if dim_enabled() then
      hl_range(buf, 0, s.startLn, 'RazzleMarkDim', 'combine', 40)
      -- Dim bottom outside including the end marker line
      hl_range(buf, s.endLn - 1, nlines, 'RazzleMarkDim', 'combine', 40)
    end

    -- Interior background across the whole interior (no viewport clipping)
    if slidehl_enabled() then
      hl_range(buf, s.startLn, s.endLn - 1, 'RazzleMarkSlide', 'replace', 80)
    end

    -- We’ve handled all drawing; skip per-line callbacks
    return false
  end,
  on_line = function() end,
})

-- Event wiring -------------------------------------------------------------

local function on_start(ev)
  enabled = true
  apply_highlights()
  vim.schedule(apply_highlights)
  -- No sign placement here; unified draw happens in on_win
end

local function on_enter(ev)
  vim.schedule(apply_highlights)
  -- No sign placement here; unified draw happens in on_win
end

local function on_end()
  enabled = false
  -- Clear signs everywhere we can reasonably reach
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
    end
  end
end

local function on_colorscheme()
  if not enabled then return end
  vim.schedule(apply_highlights)
end

-- Public API ---------------------------------------------------------------

function M.setup(cfg)
  -- Shallow-merge config
  if cfg then
    for k, v in pairs(cfg) do
      if type(v) == 'table' and type(M.config[k]) == 'table' then
        for kk, vv in pairs(v) do M.config[k][kk] = vv end
      else
        M.config[k] = v
      end
    end
  end

  apply_highlights()

  local grp = vim.api.nvim_create_augroup('RazzleMark', { clear = true })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleStart',
    group = grp,
    callback = on_start,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleSlideEnter',
    group = grp,
    callback = on_enter,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleEnd',
    group = grp,
    callback = on_end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = grp,
    callback = on_colorscheme,
  })
end

return M
