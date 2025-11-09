---Standalone "zen" view for Razzle that avoids external deps
---@class RazzleZen
local M = {}

local motion = require("razzle.motion")
local slide = require("razzle.slide")

-- Config with sensible defaults
M.config = {
    backdrop = {
        -- Percentage (0..100) of blend towards target color. 0 means keep the
        -- Normal bg as-is. 30 means 30% towards black (or target color).
        blend = 0,
        -- Target color to blend towards. Hex string like "#000000".
        color = "#000000",
    },
    -- Optional visual padding around the slide content. When non-zero, a
    -- secondary float is drawn behind the slide with the Normal background,
    -- sized larger by the given padding to create a "frame" effect.
    padding = {
        horizontal = 0,
        vertical = 0,
    },
    -- Minimum total width for the layout. For a single slide, this is the
    -- minimum slide width. For a split, each pane has a minimum of half of
    -- this value. If the longest line in a slide exceeds its minimum, that
    -- pane expands to fit the content.
    min_width = 80,
}

-- Constants to keep zindex and sizing in one place
local Z = { backdrop = 1, pad = 40, content = 50 }

-- State for our floating windows
M.win = nil           -- slide window id
M.backdrop = nil      -- backdrop window id
M.backdrop_buf = nil  -- backdrop buffer id
M.backdrop_au = nil   -- autocmd group id for backdrop focus guard
M.pad = nil           -- padding/frame window id
M.pad_buf = nil       -- padding/frame buffer id
-- Split state
M.split = nil         -- split window id (non-focusable)
M.split_frag = nil    -- current fragment id of split content
M.safe_au = nil       -- autocmd id for scoped SafeState handler

-- Basic helpers compatible with previous usage
function M.round(x) return math.floor(x + 0.5) end

-- Height in editor cells available to floating windows (relative = "editor")
function M.height()
    -- In practice, row/col for relative="editor" treat top-left of the
    -- editable area as origin, excluding the cmdline. The UI height reported
    -- by nvim_list_uis().height matches that.
    local ui = vim.api.nvim_list_uis()[1]
    return ui and ui.height or (vim.o.lines - vim.o.cmdheight)
end

local function is_valid_win(win)
    return win and vim.api.nvim_win_is_valid(win)
end

-- Shallow merge for config tables
local function merge_cfg(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" and type(dst[k]) == "table" then
            merge_cfg(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

---Setup user configuration
---@param opts table|nil
function M.setup(opts)
    if opts then merge_cfg(M.config, opts) end
    -- Reapply backdrop highlight if already open
    if is_valid_win(M.backdrop) then
        -- Recompute highlight and force winhighlight to use it
        local _ = M._apply_backdrop_highlight and M._apply_backdrop_highlight()
        vim.api.nvim_set_option_value(
            "winhighlight",
            "Normal:RazzleZenBackdrop,NormalNC:RazzleZenBackdrop",
            { win = M.backdrop }
        )
    end
end

-- Color helpers
local function clamp(n, min, max)
    if n < min then return min end
    if n > max then return max end
    return n
end

local function to_rgb_from_number(n)
    local r = math.floor(n / 65536) % 256
    local g = math.floor(n / 256) % 256
    local b = n % 256
    return r, g, b
end

local function to_rgb_from_hex(hex)
    local r, g, b = hex:match("#?(%x%x)(%x%x)(%x%x)")
    if not r then return 0, 0, 0 end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function to_hex(r, g, b)
    return string.format(
        "#%02x%02x%02x", clamp(r,0,255), clamp(g,0,255), clamp(b,0,255)
    )
end

local function blend_rgb(r1, g1, b1, r2, g2, b2, pct)
    local a = clamp(pct, 0, 100) / 100.0
    local r = math.floor(r1 + (r2 - r1) * a + 0.5)
    local g = math.floor(g1 + (g2 - g1) * a + 0.5)
    local b = math.floor(b1 + (b2 - b1) * a + 0.5)
    return r, g, b
end

-- Apply (and create) the RazzleZenBackdrop highlight according to config
function M._apply_backdrop_highlight()
    local ok, normal = pcall(
        vim.api.nvim_get_hl, 0, { name = "Normal", link = false }
    )
    local base_bg = (ok and normal and normal.bg) or nil
    local bg_hex
    if type(base_bg) == "number" then
        local r, g, b = to_rgb_from_number(base_bg)
        local tr, tg, tb = to_rgb_from_hex(
            M.config.backdrop.color or "#000000"
        )
        local br, bg, bb = blend_rgb(
            r, g, b, tr, tg, tb, M.config.backdrop.blend or 0
        )
        bg_hex = to_hex(br, bg, bb)
    else
        -- Fallback: just use the target color with small alpha towards it
        bg_hex = M.config.backdrop.color or "#000000"
    end
    vim.api.nvim_set_hl(0, "RazzleZenBackdrop", { bg = bg_hex, fg = bg_hex })
end

-- Small, focused helpers -------------------------------------------------

local function ensure_scratch_buf(buf)
    if buf and vim.api.nvim_buf_is_valid(buf) then return buf end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = b })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = b })
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "" })
    return b
end

--- This configures a minimal UI for padding and backdrop windows. It should
--- not be applied to slide windows, including splits
local function set_minimal_ui(win)
    local wo = function(opt, val)
        vim.api.nvim_set_option_value(opt, val, { win = win })
    end
    wo("number", false)
    wo("relativenumber", false)
    wo("signcolumn", "no")
    wo("foldcolumn", "0")
    wo("cursorline", false)
    wo("scrolloff", 0)
    wo("statusline", "")
end

local function center(total_w, total_h)
    local col = M.round((vim.o.columns - total_w) / 2)
    local row = M.round((M.height() - total_h) / 2)
    return col, row
end

local function refresh_backdrop_highlight()
    if not is_valid_win(M.backdrop) then return end
    M._apply_backdrop_highlight()
    vim.api.nvim_set_option_value(
        "winhighlight",
        "Normal:RazzleZenBackdrop,NormalNC:RazzleZenBackdrop",
        { win = M.backdrop }
    )
    -- Schedule one more pass after other autocmds (e.g., options)
    vim.schedule(function()
        if is_valid_win(M.backdrop) then
            M._apply_backdrop_highlight()
            pcall(vim.api.nvim_set_option_value,
                "winhighlight",
                "Normal:RazzleZenBackdrop,NormalNC:RazzleZenBackdrop",
                { win = M.backdrop }
            )
        end
    end)
end

-- Backdrop ---------------------------------------------------------------

local function install_backdrop_autocmds()
    if not (M.backdrop_buf and vim.api.nvim_buf_is_valid(M.backdrop_buf)) then
        return
    end

    -- Clean up any previous group for a prior backdrop buf
    if M.backdrop_au then
        pcall(vim.api.nvim_del_augroup_by_id, M.backdrop_au)
        M.backdrop_au = nil
    end

    -- Use a dedicated augroup per backdrop buffer
    M.backdrop_au = vim.api.nvim_create_augroup(
        "RazzleZenBackdrop_" .. M.backdrop_buf, { clear = true }
    )

    -- If focus enters the backdrop buffer for any reason, immediately
    -- return focus to the slide window. This swallows clicks/scrolls.
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
        group = M.backdrop_au,
        buffer = M.backdrop_buf,
        callback = function()
            if is_valid_win(M.win) then
                vim.schedule(function()
                    pcall(vim.api.nvim_set_current_win, M.win)
                end)
            end
        end,
        desc = "Razzle: prevent focusing backdrop"
    })

    -- Some UIs fire WinScrolled on wheel before CursorMoved changes; use it
    -- as a secondary guard. We can't buffer-filter WinScrolled, so check win.
    vim.api.nvim_create_autocmd("WinScrolled", {
        group = M.backdrop_au,
        callback = function()
            if is_valid_win(M.backdrop)
               and vim.api.nvim_get_current_win() == M.backdrop
               and is_valid_win(M.win) then
                vim.schedule(function()
                    pcall(vim.api.nvim_set_current_win, M.win)
                end)
            end
        end,
        desc = "Razzle: keep focus off backdrop on scroll"
    })
end

local function ensure_backdrop()
    if is_valid_win(M.backdrop) then return end

    -- Create (or reuse) a scratch buffer for the backdrop
    M.backdrop_buf = ensure_scratch_buf(M.backdrop_buf)

    -- Backdrop highlight derived from Normal and user blend settings
    M._apply_backdrop_highlight()

    M.backdrop = vim.api.nvim_open_win(M.backdrop_buf, false, {
        relative = "editor",
        width = vim.o.columns,
        height = M.height(),
        row = 0,
        col = 0,
        focusable = true,
        style = "minimal",
        zindex = Z.backdrop,
    })
    refresh_backdrop_highlight()
    vim.api.nvim_set_option_value("winblend", 0, { win = M.backdrop })
    set_minimal_ui(M.backdrop)

    install_backdrop_autocmds()
end

-- Pad/frame --------------------------------------------------------------

-- Ensure/create the padding "frame" window behind the slide, or close it
-- when padding is zero. The pad uses Normal background to simulate slide
-- padding against the dimmed backdrop.
local function ensure_pad(width, height, col, row)
    local pad = M.config.padding or {}
    local ph = math.max(0, tonumber(pad.horizontal or 0) or 0)
    local pv = math.max(0, tonumber(pad.vertical or 0) or 0)

    if ph == 0 and pv == 0 then
        if is_valid_win(M.pad) then
            pcall(vim.api.nvim_win_close, M.pad, true)
        end
        M.pad = nil
        M.pad_buf = nil
        return
    end

    local pwidth = width + ph * 2
    local pheight = height + pv * 2
    local pcol = col - ph
    local prow = row - pv

    M.pad_buf = ensure_scratch_buf(M.pad_buf)

    if is_valid_win(M.pad) then
        vim.api.nvim_win_set_config(M.pad, {
            relative = "editor",
            width = pwidth,
            height = pheight,
            col = pcol,
            row = prow,
            zindex = Z.pad,
        })
    else
        M.pad = vim.api.nvim_open_win(M.pad_buf, false, {
            relative = "editor",
            width = pwidth,
            height = pheight,
            col = pcol,
            row = prow,
            style = "minimal",
            zindex = Z.pad,
            focusable = false,
        })
        -- Match the slide window background (Normal)
        vim.api.nvim_set_option_value(
            "winhighlight", "Normal:Normal,NormalNC:Normal", { win = M.pad }
        )
        set_minimal_ui(M.pad)
    end
end

-- Sizing helpers ----------------------------------------------------------

-- Compute height of a given slide using the window-local fold/virt context
local function height_for_slide_in_win(win, s)
    if not (win and s) then return nil end
    local h
    vim.api.nvim_win_call(win, function()
        -- Move cursor inside the slide for cur_slide() detection
        pcall(vim.fn.setpos, '.', { 0, s.startLn + 1, 0, 0 })
        h = slide.slide_height()
    end)
    return h
end

-- Split management --------------------------------------------------------

-- Ensure or update the split window for a given target slide
local function ensure_split_for(target)
    if not target then
        if is_valid_win(M.split) then pcall(vim.api.nvim_win_close, M.split, true) end
        M.split = nil
        M.split_frag = nil
        return
    end

    if is_valid_win(M.split) then
        vim.api.nvim_win_set_buf(M.split, target.bufNu)
    else
        -- Create a non-focusable float for the split content. We'll size it
        -- correctly in the layout pass.
        M.split = vim.api.nvim_open_win(target.bufNu, false, {
            relative = "editor",
            width = 1,
            height = 1, -- temp; set below
            col = 0,
            row = 0,
            style = "minimal",
            zindex = Z.content,
            focusable = false,
        })
        -- Match slide window highlight
        vim.api.nvim_set_option_value(
            "winhighlight", "Normal:Normal,NormalNC:Normal", { win = M.split }
        )
    end

    -- Ensure view starts at the interior
    vim.api.nvim_win_call(M.split, function()
        pcall(vim.fn.winrestview, { topline = target.startLn + 1 })
    end)

    M.split_frag = target.fragment -- may be nil if not set on target
end

-- Layout -----------------------------------------------------------------

local function split_param_from(s)
    if not (s and s.params and s.params["split"]) then return nil end
    local val = s.params["split"]
    if type(val) == "table" then val = val[1] end
    return val
end

---Compute a sane minimum total width from config
---@return number
local function min_total_width()
    local mt = tonumber(M.config.min_width or 80) or 80
    if mt < 1 then mt = 1 end
    return mt
end

---Ensure the primary content window exists and is placed/sized
---@param w number
---@param h number
---@param col number
---@param row number
local function place_primary_window(w, h, col, row)
    if is_valid_win(M.win) then
        vim.api.nvim_win_set_config(M.win, {
            relative = "editor",
            width = w,
            height = h,
            col = col,
            row = row,
            zindex = Z.content,
        })
    else
        M.win = vim.api.nvim_open_win(0, true, {
            relative = "editor",
            width = w,
            height = h,
            col = col,
            row = row,
            style = "minimal",
            zindex = Z.content,
            border = nil,
        })
        vim.api.nvim_set_option_value(
            "winhighlight", "Normal:Normal,NormalNC:Normal", { win = M.win }
        )
    end
end

---Compute pane width with a per-pane minimum
---@param win number|nil
---@param s table
---@param min_pane number
---@return number
local function pane_width(win, s, min_pane)
    local intrinsic = slide.slide_content_width(win, s)
    return math.max(min_pane, intrinsic)
end

---Layout for single (no split) view
local function layout_single(cur, cur_h)
    ensure_split_for(nil)
    local min_total = min_total_width()
    local content_w = slide.slide_content_width(is_valid_win(M.win) and M.win or 0, cur)
    local w = math.max(min_total, content_w)
    local col, row = center(w, cur_h)
    ensure_pad(w, cur_h, col, row)
    place_primary_window(w, cur_h, col, row)
    refresh_backdrop_highlight()
end

---Layout for split view
local function layout_split(cur, cur_h, target)
    ensure_split_for(target)

    local split_h = height_for_slide_in_win(M.split, target) or 1
    -- Align view to interior in split again (in case folds opened)
    vim.api.nvim_win_call(M.split, function()
        pcall(vim.fn.winrestview, { topline = target.startLn + 1 })
    end)

    local min_total = min_total_width()
    local min_pane = math.max(1, math.floor(min_total / 2))

    local w_left = pane_width(is_valid_win(M.win) and M.win or 0, cur, min_pane)
    local w_right = pane_width(is_valid_win(M.split) and M.split or 0, target, min_pane)

    local total_w = w_left + w_right
    local total_h = math.max(cur_h, split_h)

    local col, row = center(total_w, total_h)

    ensure_pad(total_w, total_h, col, row)

    place_primary_window(w_left, cur_h, col, row)

    vim.api.nvim_win_set_config(M.split, {
        relative = "editor",
        width = w_right,
        height = split_h,
        col = col + w_left,
        row = row,
        zindex = Z.content,
    })

    refresh_backdrop_highlight()
end

---Main layout entry: open or update according to current slide/split state
local function open_or_update_layout()
    ensure_backdrop()

    local cur = slide.cur_slide()
    local cur_h = slide.slide_height() or 20

    -- Determine split target from params: split=FRAG
    local frag = split_param_from(cur)
    local target = frag and slide.fragment_slide(frag) or nil

    if not target then
        return layout_single(cur, cur_h)
    else
        return layout_split(cur, cur_h, target)
    end
end


function M.close()
    if is_valid_win(M.win) then vim.api.nvim_win_close(M.win, true) end
    M.win = nil
    if is_valid_win(M.split) then vim.api.nvim_win_close(M.split, true) end
    M.split = nil
    M.split_frag = nil
    if is_valid_win(M.pad) then vim.api.nvim_win_close(M.pad, true) end
    M.pad = nil
    if is_valid_win(M.backdrop) then vim.api.nvim_win_close(M.backdrop, true) end
    M.backdrop = nil
    -- Remove backdrop autocmds, if any
    if M.backdrop_au then
        pcall(vim.api.nvim_del_augroup_by_id, M.backdrop_au)
        M.backdrop_au = nil
    end
    -- The scratch buffers will be wiped by bufhidden=wipe when windows close
    M.backdrop_buf = nil
    M.pad_buf = nil
end

function M.set_layout()
    if not is_valid_win(M.win) then return end
    open_or_update_layout()

    -- Also ensure the backdrop matches the editor size (e.g., after resize)
    if not is_valid_win(M.backdrop) then ensure_backdrop() end
    if is_valid_win(M.backdrop) then
        vim.api.nvim_win_set_config(M.backdrop, {
            relative = "editor",
            width = vim.o.columns,
            height = M.height(),
            row = 0,
            col = 0,
            zindex = Z.backdrop,
        })
        -- Reapply highlight each layout in case options changed
        refresh_backdrop_highlight()
    end
end

-- Event wiring mirrors the previous implementation's contract
vim.api.nvim_create_autocmd("User", {
    callback = function()
        open_or_update_layout()
        motion.align_view()
    end,
    pattern = "RazzleSlideEnter",
})

local razzle_zen_group = vim.api.nvim_create_augroup(
    "RazzleZen", { clear = true }
)

vim.api.nvim_create_autocmd({"VimResized"}, {
    callback = function()
        if is_valid_win(M.win) then
            M.set_layout()
        end
    end,
    group = razzle_zen_group,
})

-- End the presentation instead of just closing the slide float when the
-- user executes :q in the zen window. Using QuitPre ensures we react before
-- Neovim actually closes the window, so backdrop/pad are cleaned up.
vim.api.nvim_create_autocmd("QuitPre", {
    callback = function()
        if is_valid_win(M.win)
           and vim.api.nvim_get_current_win() == M.win then
                require("razzle").end_presentation()
        end
    end,
    group = razzle_zen_group,
})

-- If colorscheme changes globally, update backdrop highlight when open
vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
        if is_valid_win(M.backdrop) then
            refresh_backdrop_highlight()
        end
    end,
    group = razzle_zen_group,
})

vim.api.nvim_create_autocmd("User", {
    callback = function()
        open_or_update_layout()
        vim.opt_local.scrolloff = 0
        motion.align_view()
        -- Scope SafeState updates to the content window to avoid firing
        -- while focus briefly lands in the backdrop.
        if M.safe_au then pcall(vim.api.nvim_del_autocmd, M.safe_au) end
        M.safe_au = vim.api.nvim_create_autocmd({"SafeState"}, {
            callback = function()
                if not (is_valid_win(M.win)
                        and vim.api.nvim_get_current_win() == M.win) then
                    return
                end
                vim.opt_local.scrolloff = 0
                open_or_update_layout()
                motion.align_view()
            end,
            group = razzle_zen_group,
            desc = "Razzle: sync layout (SafeState, slide window only)",
        })
    end,
    pattern = "RazzleStart"
})

vim.api.nvim_create_autocmd("User", {
    callback = M.close,
    pattern = "RazzleEnd"
})

return M
