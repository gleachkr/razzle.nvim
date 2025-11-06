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
}

-- State for our floating windows
M.win = nil           -- slide window id
M.backdrop = nil      -- backdrop window id
M.backdrop_buf = nil  -- backdrop buffer id
M.backdrop_au = nil   -- autocmd group id for backdrop focus guard
M.pad = nil           -- padding/frame window id
M.pad_buf = nil       -- padding/frame buffer id

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

function M.is_open()
    return is_valid_win(M.win)
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
    if not (M.backdrop_buf and vim.api.nvim_buf_is_valid(M.backdrop_buf)) then
        M.backdrop_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value(
            "buftype", "nofile", { buf = M.backdrop_buf }
        )
        vim.api.nvim_set_option_value(
            "bufhidden", "wipe", { buf = M.backdrop_buf }
        )
        vim.api.nvim_buf_set_lines(M.backdrop_buf, 0, -1, false, {""})
    end

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
        zindex = 1,
    })
    vim.api.nvim_set_option_value(
        "winhighlight",
        "Normal:RazzleZenBackdrop,NormalNC:RazzleZenBackdrop",
        { win = M.backdrop }
    )
    vim.api.nvim_set_option_value("winblend", 0, { win = M.backdrop })
    -- No UI clutter on backdrop
    vim.api.nvim_set_option_value("number", false, { win = M.backdrop })
    vim.api.nvim_set_option_value(
        "relativenumber", false, { win = M.backdrop }
    )
    vim.api.nvim_set_option_value("signcolumn", "no", { win = M.backdrop })
    vim.api.nvim_set_option_value("foldcolumn", "0", { win = M.backdrop })

    install_backdrop_autocmds()
end

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

    if not (M.pad_buf and vim.api.nvim_buf_is_valid(M.pad_buf)) then
        M.pad_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value(
            "buftype", "nofile", { buf = M.pad_buf }
        )
        vim.api.nvim_set_option_value(
            "bufhidden", "wipe", { buf = M.pad_buf }
        )
        vim.api.nvim_buf_set_lines(M.pad_buf, 0, -1, false, {""})
    end

    if is_valid_win(M.pad) then
        vim.api.nvim_win_set_config(M.pad, {
            relative = "editor",
            width = pwidth,
            height = pheight,
            col = pcol,
            row = prow,
            zindex = 40,
        })
    else
        M.pad = vim.api.nvim_open_win(M.pad_buf, false, {
            relative = "editor",
            width = pwidth,
            height = pheight,
            col = pcol,
            row = prow,
            style = "minimal",
            zindex = 40,
            focusable = false,
        })
        -- Match the slide window background (Normal)
        vim.api.nvim_set_option_value(
            "winhighlight", "Normal:Normal,NormalNC:Normal", { win = M.pad }
        )
        -- Tidy the pad window UI
        local wo = function(opt, val)
            vim.api.nvim_set_option_value(opt, val, { win = M.pad })
        end
        wo("number", false)
        wo("relativenumber", false)
        wo("signcolumn", "no")
        wo("foldcolumn", "0")
        wo("cursorline", false)
        wo("statusline", "")
        wo("scrolloff", 0)
    end
end

local function open_slide_window(width, height)
    ensure_backdrop()

    local col = M.round((vim.o.columns - width) / 2)
    local row = M.round((M.height() - height) / 2)

    -- Always ensure the padding frame according to current layout
    ensure_pad(width, height, col, row)

    -- If the slide window already exists, just reconfigure it
    if is_valid_win(M.win) then
        vim.api.nvim_win_set_config(M.win, {
            relative = "editor",
            width = width,
            height = height,
            col = col,
            row = row,
            zindex = 50,
        })
        return
    end

    -- Open a floating window on the current buffer (so edits apply directly)
    M.win = vim.api.nvim_open_win(0, true, {
        relative = "editor",
        width = width,
        height = height,
        col = col,
        row = row,
        style = "minimal",
        zindex = 50,
        border = nil,
    })

    -- Tidy the slide window UI
    local wo = function(opt, val)
        vim.api.nvim_set_option_value(opt, val, { win = M.win })
    end
    wo("number", false)
    wo("relativenumber", false)
    wo("signcolumn", "no")
    wo("foldcolumn", "0")
    wo("cursorline", false)
    wo("statusline", "")
    wo("scrolloff", 0)
    -- Inherit highlights; users can override NormalFloat if they want a box
    wo("winhighlight", "Normal:Normal,NormalNC:Normal")
end

function M.open(opts)
    opts = opts or {}
    local w = 80
    local h = slide.slide_height() or 20
    if opts.window then
        w = opts.window.width or w
        h = opts.window.height or h
    end
    open_slide_window(w, h)
end

function M.close()
    if is_valid_win(M.win) then vim.api.nvim_win_close(M.win, true) end
    M.win = nil
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

function M.set_layout(w, h)
    if not is_valid_win(M.win) then return end
    local width = w or vim.api.nvim_win_get_width(M.win)
    local height = h or vim.api.nvim_win_get_height(M.win)
    local col = M.round((vim.o.columns - width) / 2)
    local row = M.round((M.height() - height) / 2)
    local cfg = vim.api.nvim_win_get_config(M.win)
    local wcol = type(cfg.col) == "number" and cfg.col or cfg.col[false]
    local wrow = type(cfg.row) == "number" and cfg.row or cfg.row[false]
    if wrow ~= row or wcol ~= col or w or h then
        vim.api.nvim_win_set_config(M.win, {
            width = width,
            height = height,
            col = col,
            row = row,
            relative = "editor",
            zindex = 50,
        })
    end

    -- Ensure/update the padding frame according to current layout
    ensure_pad(width, height, col, row)

    -- Also ensure the backdrop matches the editor size (e.g., after resize)
    if not is_valid_win(M.backdrop) then ensure_backdrop() end
    if is_valid_win(M.backdrop) then
        vim.api.nvim_win_set_config(M.backdrop, {
            relative = "editor",
            width = vim.o.columns,
            height = M.height(),
            row = 0,
            col = 0,
            zindex = 1,
        })
        -- Reapply highlight each layout in case options changed
        M._apply_backdrop_highlight()
        vim.api.nvim_set_option_value(
            "winhighlight",
            "Normal:RazzleZenBackdrop,NormalNC:RazzleZenBackdrop",
            { win = M.backdrop }
        )
    end
end

-- Event wiring mirrors the previous implementation's contract
vim.api.nvim_create_autocmd("User", {
    callback = function()
        local height = slide.slide_height()
        if not M.is_open() then
            M.open({ window = { width = 80, height = height or 20 } })
        else
            M.set_layout(nil, height)
        end
        motion.align_view()
    end,
    pattern = "RazzleSlideEnter",
})

local razzle_zen_group = vim.api.nvim_create_augroup(
    "RazzleZen", { clear = true }
)

vim.api.nvim_create_autocmd({"VimResized"}, {
    callback = function()
        if M.is_open() then
            local height = slide.slide_height()
                or vim.api.nvim_win_get_height(M.win)
            M.set_layout(nil, height)
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
            M._apply_backdrop_highlight()
            vim.api.nvim_set_option_value(
                "winhighlight",
                "Normal:RazzleZenBackdrop,NormalNC:RazzleZenBackdrop",
                { win = M.backdrop }
            )
        end
    end,
    group = razzle_zen_group,
})

vim.api.nvim_create_autocmd("User", {
    callback = function()
        M.open({ window = { height = slide.slide_height() or 20, width = 80 } })
        vim.opt_local.scrolloff = 0
        motion.align_view()
        vim.api.nvim_create_autocmd({"SafeState"}, {
            callback = function()
                vim.opt_local.scrolloff = 0
                local height = slide.slide_height()
                if height then
                    M.set_layout(nil, height)
                    motion.align_view()
                end
            end,
            group = vim.api.nvim_create_augroup("Razzle", { clear = false})
        })
    end,
    pattern = "RazzleStart"
})

vim.api.nvim_create_autocmd("User", {
    callback = M.close,
    pattern = "RazzleEnd"
})

return M
