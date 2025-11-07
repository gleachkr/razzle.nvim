--- Presentation-wide and per-slide option management for Razzle
---@class RazzleOptions
local M = {}

local slide = require("razzle.slide")

-- Public config. Users can set baseline presentation defaults here.
-- Example:
-- require('razzle.options').setup({
--   o  = { number = false },             -- global/window-inheritable opts
--   wo = { relativenumber = false },     -- window-local opts
--   bo = {},                             -- buffer-local opts
--   colorscheme = nil,                   -- e.g. 'gruvbox'
-- })
M.config = { o = {}, wo = {}, bo = {}, colorscheme = nil }

-- Saved original values to restore on :RazzleEnd
local saved = {
  colorscheme = nil,  -- original colorscheme name (vim.g.colors_name)
  o = {},             -- option name -> value (global)
  wo = {},            -- winid -> { opt -> value }
  bo = {},            -- bufnr -> { opt -> value }
}

-- Track which overrides we applied per window/buffer so we can revert them
local applied = { o = {}, wo = {}, bo = {}, colorscheme = false }

-- Utilities ---------------------------------------------------------------

local function tcopy(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    if type(v) == 'table' then out[k] = tcopy(v) else out[k] = v end
  end
  return out
end

local function coerce(v)
  if v == nil then return nil end
  if type(v) ~= 'string' then return v end
  if v == '' then return true end
  local lower = v:lower()
  if lower == 'true' or lower == 'on' then return true end
  if lower == 'false' or lower == 'off' then return false end
  local n = tonumber(v)
  if n ~= nil then return n end
  return v
end

local function ensure_saved_global(name)
  if saved.o[name] == nil then
    saved.o[name] = vim.api.nvim_get_option_value(name, {})
  end
end

local function ensure_saved_win(win, name)
  saved.wo[win] = saved.wo[win] or {}
  if saved.wo[win][name] == nil then
    saved.wo[win][name] = vim.api.nvim_get_option_value(name, { win = win })
  end
end

local function ensure_saved_buf(buf, name)
  saved.bo[buf] = saved.bo[buf] or {}
  if saved.bo[buf][name] == nil then
    saved.bo[buf][name] = vim.api.nvim_get_option_value(name, { buf = buf })
  end
end

local function set_global(name, val)
  vim.api.nvim_set_option_value(name, val, {})
end

local function set_win(win, name, val)
  vim.api.nvim_set_option_value(name, val, { win = win })
end

local function set_buf(buf, name, val)
  vim.api.nvim_set_option_value(name, val, { buf = buf })
end

local function set_colorscheme(name)
  if not name or name == '' then return end
  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then
    vim.notify("Razzle options: colorscheme '" .. name ..
      "' failed: " .. tostring(err), vim.log.levels.WARN)
  end
end

-- Apply the presentation baseline for a specific window/buffer
local function apply_baseline(win, buf)
  -- Save original colorscheme once
  if saved.colorscheme == nil then
    saved.colorscheme = vim.g.colors_name
  end
  -- Global options
  for name, val in pairs(M.config.o or {}) do
    ensure_saved_global(name)
    set_global(name, val)
  end
  -- Window options
  for name, val in pairs(M.config.wo or {}) do
    ensure_saved_win(win, name)
    set_win(win, name, val)
    -- mark as managed to reapply on next slide
    applied.wo[win] = applied.wo[win] or {}
    applied.wo[win][name] = false -- baseline, not an override
  end
  -- Buffer options
  for name, val in pairs(M.config.bo or {}) do
    ensure_saved_buf(buf, name)
    set_buf(buf, name, val)
    applied.bo[buf] = applied.bo[buf] or {}
    applied.bo[buf][name] = false -- baseline
  end
  -- Colorscheme baseline
  if M.config.colorscheme and M.config.colorscheme ~= '' then
    set_colorscheme(M.config.colorscheme)
  end
end

-- Reset any slide-specific overrides for this win/buf back to the baseline
local function reset_overrides_to_baseline(win, buf)
  -- Global overrides
  for name, was_override in pairs(applied.o or {}) do
    if was_override then
      if M.config.o and M.config.o[name] ~= nil then
        set_global(name, M.config.o[name])
      else
        if saved.o[name] ~= nil then
          set_global(name, saved.o[name])
        end
      end
      applied.o[name] = false
    end
  end
  -- Window overrides: restore either baseline from config or original value
  if applied.wo[win] then
    for name, was_override in pairs(applied.wo[win]) do
      if was_override then
        if M.config.wo and M.config.wo[name] ~= nil then
          set_win(win, name, M.config.wo[name])
        else
          -- restore original recorded value
          if saved.wo[win] and saved.wo[win][name] ~= nil then
            set_win(win, name, saved.wo[win][name])
          end
        end
        applied.wo[win][name] = false
      end
    end
  end
  -- Buffer overrides
  if applied.bo[buf] then
    for name, was_override in pairs(applied.bo[buf]) do
      if was_override then
        if M.config.bo and M.config.bo[name] ~= nil then
          set_buf(buf, name, M.config.bo[name])
        else
          if saved.bo[buf] and saved.bo[buf][name] ~= nil then
            set_buf(buf, name, saved.bo[buf][name])
          end
        end
        applied.bo[buf][name] = false
      end
    end
  end
  -- Colorscheme override
  if applied.colorscheme then
    if M.config.colorscheme and M.config.colorscheme ~= '' then
      set_colorscheme(M.config.colorscheme)
    else
      set_colorscheme(saved.colorscheme)
    end
    applied.colorscheme = false
  end
end

-- Apply per-slide overrides from the slide.params table
local function apply_slide_overrides(s, win)
  if not s or not s.params then return end
  local params = s.params

  -- colorscheme=name
  if params.colorscheme then
    applied.colorscheme = true
    local cs = params.colorscheme
    if type(cs) == 'table' then cs = cs[#cs] end
    set_colorscheme(cs)
  end

  -- Handle global o.xxx=
  for key, v in pairs(params) do
    local prefix = 'o.'
    if type(key) == 'string' and key:sub(1, #prefix) == prefix then
      local name = key:sub(#prefix + 1)
      local val = v
      if type(val) == 'table' then val = val[#val] end
      val = coerce(val)
      ensure_saved_global(name)
      set_global(name, val)
      applied.o[name] = true
    end
  end

  -- Handle wo.xxx= and bo.xxx=
  local function apply_scope(scope_name, setter, saver, marks, ctx)
    for key, v in pairs(params) do
      local prefix = scope_name .. '.'
      if type(key) == 'string' and key:sub(1, #prefix) == prefix then
        local name = key:sub(#prefix + 1)
        local val = v
        if type(val) == 'table' then val = val[#val] end
        val = coerce(val)
        saver(ctx, name)
        setter(ctx, name, val)
        marks[ctx] = marks[ctx] or {}
        marks[ctx][name] = true
      end
    end
  end

  apply_scope('wo', function(winid, name, val)
    set_win(winid, name, val)
  end, function(winid, name)
    ensure_saved_win(winid, name)
  end, applied.wo, win)

  apply_scope('bo', function(bufnr, name, val)
    set_buf(bufnr, name, val)
  end, function(bufnr, name)
    ensure_saved_buf(bufnr, name)
  end, applied.bo, s.bufNu)
end

-- Public API --------------------------------------------------------------

function M.setup(opts)
  if opts then
    -- shallow merge, keep existing tables if not provided
    for k, v in pairs(opts) do
      if type(v) == 'table' and type(M.config[k]) == 'table' then
        for kk, vv in pairs(v) do M.config[k][kk] = vv end
      else
        M.config[k] = v
      end
    end
  end

  local group = vim.api.nvim_create_augroup('RazzleOptions', { clear = true })

  -- On start: compute baseline and apply to current slide/win, then overrides
  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleStart',
    group = group,
    callback = function(ev)
      local s = (ev and ev.data and ev.data.entered) or slide.cur_slide()
      if not s then return end
      local win = vim.api.nvim_get_current_win()
      apply_baseline(win, s.bufNu)
      apply_slide_overrides(s, win)
    end,
  })

  -- On slide enter: reset overrides back to baseline, then apply new ones
  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleSlideEnter',
    group = group,
    callback = function(ev)
      local s = ev and ev.data and ev.data.entered
      if not s then return end
      local win = vim.api.nvim_get_current_win()
      apply_baseline(win, s.bufNu)
      reset_overrides_to_baseline(win, s.bufNu)
      apply_slide_overrides(s, win)
    end,
  })

  -- On end: restore originals everywhere we touched, and clear state
  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleEnd',
    group = group,
    callback = function()
      -- Restore global options
      for name, val in pairs(saved.o) do
        pcall(set_global, name, val)
      end
      -- Restore per-window options
      for win, tbl in pairs(saved.wo) do
        if vim.api.nvim_win_is_valid(win) then
          for name, val in pairs(tbl) do
            pcall(set_win, win, name, val)
          end
        end
      end
      -- Restore per-buffer options
      for buf, tbl in pairs(saved.bo) do
        if vim.api.nvim_buf_is_valid(buf) then
          for name, val in pairs(tbl) do
            pcall(set_buf, buf, name, val)
          end
        end
      end
      -- Restore colorscheme
      if saved.colorscheme ~= nil then
        set_colorscheme(saved.colorscheme)
      end
      -- Clear state for next run
      saved = { colorscheme = nil, o = {}, wo = {}, bo = {} }
      applied = { wo = {}, bo = {}, colorscheme = false }
    end,
  })
end

return M
