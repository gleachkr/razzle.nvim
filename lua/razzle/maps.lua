--- Temporary presentation keymaps for Razzle
---@class RazzleMaps
local M = {}

-- Public config via setup() uses shorthand by mode only, e.g.
-- require('razzle.maps').setup({
--   n = { [']S'] = next_fn, ['[S'] = prev_fn },
--   i = { ['<Right>'] = next_fn, ['<Left>'] = prev_fn },
-- })
M.config = { maps = {} }

-- Internal state saved on RazzleStart and restored on RazzleEnd
local state = {
  saved = {               -- previously defined mappings we override
    global = {},          -- global[mode][lhs] = { entry, ... }
  },
  applied = {},           -- list of { mode, lhs }
}

-- Utilities ---------------------------------------------------------------

local function is_empty(t)
  return not t or next(t) == nil
end

local function entry_to_opts(entry)
  local opts = {}
  if entry == nil then return opts end
  -- Fields commonly returned by nvim_get_keymap
  local copy = {
    'silent', 'nowait', 'noremap', 'expr', 'script', 'unique', 'desc',
  }
  for _, k in ipairs(copy) do
    if entry[k] ~= nil then opts[k] = entry[k] end
  end
  return opts
end

local function filter_by_lhs(entries, lhs)
  local out = {}
  for _, e in ipairs(entries or {}) do
    if e.lhs == lhs then table.insert(out, e) end
  end
  return out
end

local function save_existing(mode, lhs)
  state.saved.global[mode] = state.saved.global[mode] or {}
  local entries = vim.api.nvim_get_keymap(mode)
  state.saved.global[mode][lhs] = filter_by_lhs(entries, lhs)
end

local function apply_map(mode, lhs, rhs)
  local set_opts = { silent = true, noremap = true }
  vim.keymap.set(mode, lhs, rhs, set_opts)
end

local function del_map(mode, lhs)
  return pcall(vim.keymap.del, mode, lhs)
end

local function restore_entry(mode, entry)
  local rhs = entry.callback or entry.rhs
  if rhs == nil then return end
  local opts = entry_to_opts(entry)
  -- Prefer vim.keymap.set because it supports Lua callbacks
  pcall(vim.keymap.set, mode, entry.lhs, rhs, opts)
end

local function on_start()
  -- Clear state in case of re-entry
  state.saved = { global = {} }
  state.applied = {}

  for _, spec in ipairs(M.config.maps or {}) do
    local mode = spec.mode
    local lhs = spec.lhs
    local rhs = spec.rhs
    if mode and lhs and rhs then
      save_existing(mode, lhs)
      apply_map(mode, lhs, rhs)
      table.insert(state.applied, { mode = mode, lhs = lhs })
    else
      vim.notify('Razzle maps: invalid spec (mode/lhs/rhs missing)',
        vim.log.levels.WARN)
    end
  end
end

local function on_end()
  -- Remove the active presentation maps
  for _, a in ipairs(state.applied or {}) do
    del_map(a.mode, a.lhs)
  end

  -- Restore saved global maps
  for mode, by_lhs in pairs(state.saved.global or {}) do
    for lhs, entries in pairs(by_lhs) do
      if not is_empty(entries) then
        for _, e in ipairs(entries) do
          restore_entry(mode, e)
        end
      end
    end
  end

  -- Clear state
  state.saved = { global = {} }
  state.applied = {}
end

-- Public API --------------------------------------------------------------

---Register temporary keymaps to use during a presentation.
---Only supports shorthand-by-mode form:
---  setup({ n = { lhs = rhs, ... }, i = { ... }, v = { ... } })
---@param cfg table
function M.setup(cfg)
  local conf = cfg or {}
  M.config.maps = {}

  -- Expand shorthand mode tables into map specs
  local function push(mode, lhs, rhs)
    table.insert(M.config.maps, { mode = mode, lhs = lhs, rhs = rhs })
  end

  local known_modes = { n = true, i = true, v = true, x = true, o = true,
                        t = true, s = true, c = true }

  for k, v in pairs(conf) do
    if known_modes[k] and type(v) == 'table' then
      for lhs, rhs in pairs(v) do push(k, lhs, rhs) end
    end
  end

  local group = vim.api.nvim_create_augroup('RazzleMaps', { clear = true })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleStart',
    group = group,
    callback = on_start,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'RazzleEnd',
    group = group,
    callback = on_end,
  })
end

return M
