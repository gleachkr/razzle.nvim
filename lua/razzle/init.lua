local M = {}

function M.next_slide_ln()
    return vim.fn.search("SLIDE","n")
end

function M.prev_slide_ln()
    local pos = vim.fn.getpos('.')
    --This search jumps to the current slide marker
    vim.fn.search("SLIDE", "bc")
    --and this finds the one before that
    local slide_line_number = vim.fn.search("SLIDE", "bn")
    vim.fn.setpos('.', pos)
    return slide_line_number
end

function M.cur_slide_ln()
    return vim.fn.search("SLIDE", "bcn")
end

function M.end_slide_ln()
    return vim.fn.search("FIN", "cn")
end

function M.slide_height()
    return M.end_slide_ln() - M.cur_slide_ln()
end

function M.next_slide()
    local pos = M.next_slide_ln()
    vim.fn.setpos('.', { 0, pos, 0, 0 })
end

function M.prev_slide()
    local pos = M.prev_slide_ln()
    vim.fn.setpos('.', { 0, pos, 0, 0 })
end

function M.cur_slide()
    local pos = M.cur_slide_ln()
    vim.fn.setpos('.', { 0, pos, 0, 0 })
end

function M.align_view()
    local pos = vim.fn.getpos('.')
    vim.fn.winrestview({ topline = pos[2] })
end

local function fire_slide_event()
    if vim.fn.expand("<cword>") == "SLIDE" then
        vim.cmd.doautocmd("User RazzleSlide")
    end
end


function M.start_presentation()

    vim.cmd.doautocmd("User RazzleStart")
    local razzle_slide_group = vim.api.nvim_create_augroup("RazzleSlide", { clear = true })
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        callback = fire_slide_event,
        group = razzle_slide_group,
        buffer = 0,
    })

    M.cur_slide()
end

function M.end_presentation()
    vim.cmd.doautocmd("User RazzleEnd")
    local all_autocmds = vim.api.nvim_get_autocmds({
        buffer=0, ---note, this requires that all razzle groups have buffer=0 set
    })
    for _, cmd in ipairs(all_autocmds) do
        if cmd.group_name then
            -- if there's more than one command in the group, we accidentally try to delete it twice.
            -- this is a workaround, we should deduplicate the list instead.
            pcall(vim.api.nvim_del_augroup_by_name,cmd.group_name)
        end
    end
end

return M
