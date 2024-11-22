local M = {}

function M.next_slide_pos()
    return vim.fn.search("SLIDE","n")
end

function M.prev_slide_pos()
    local pos = vim.fn.getpos('.')
    --This search jumps to the current slide marker
    vim.fn.search("SLIDE", "bc")
    --and this finds the one before that
    local slide_line_number = vim.fn.search("SLIDE", "bn")
    vim.fn.setpos('.', pos)
    return slide_line_number
end

function M.cur_slide_pos()
    return vim.fn.search("SLIDE", "bcn")
end

function M.next_slide()
    local pos = M.next_slide_pos()
    vim.fn.winrestview({
        topline = pos,
        lnum = pos,
        col = 0,
    })
end

function M.prev_slide()
    local pos = M.prev_slide_pos()
    vim.fn.winrestview({
        topline = pos,
        lnum = pos,
        col = 0,
    })
end

local function fire_slide_event()
    if vim.fn.expand("<cword>") == "SLIDE" then
        vim.cmd.doautocmd("User RazzleSlide")
    end
end

function M.start_presentation()
    vim.cmd.doautocmd("User RazzleStart")
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        callback = fire_slide_event,
        group = vim.api.nvim_create_augroup("RazzleSlide", { clear = true }),
        buffer = 0,
    })
end

function M.end_presentation()
    vim.cmd.doautocmd("User RazzleEnd")
    -- CLEAN UP AUCMDS
end

return M
