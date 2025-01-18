---Module for slide motions
---@class RazzleMotion
local M = {}

local slide = require("razzle.slide")

---Moves to the top of the next slide's interior
---@return nil
function M.next_slide()
    -- Get the line number of the next slide
    local next = slide.next_slide()
    -- Set the cursor position to the next slide
    if next then
        vim.fn.setpos('.', { 0, next.startLn + 1, 0, 0 })
    else
        vim.notify("Can't move to next slide, no next slide found", vim.log.levels.ERROR)
    end
end

---Moves to the top of the previous slide's interior
---@return nil
function M.prev_slide()
    -- Get the line number of the previous slide
    local prev = slide.prev_slide()
    -- Set the cursor position to the previous slide's line
    if prev then
        vim.fn.setpos('.', { 0, prev.startLn + 1, 0, 0 })
    else
        vim.notify("Can't move to previous slide, no next slide found", vim.log.levels.ERROR)
    end
end

---Moves to top of the current slide's interior
---@return nil
function M.cur_slide()
    -- Get the line number of the current slide
    local cur = slide.cur_slide() -- pos: number
    -- Set the cursor position to the current slide's line
    if cur then
        vim.fn.setpos('.', { 0, cur.startLn + 1, 0, 0 }) -- Set cursor position in the current buffer
    else
        vim.notify("Can't move to current slide, no current slide found", vim.log.levels.ERROR)
    end
end

---Aligns the view to the current slide's interior.
---@return nil
function M.align_view()
    local cur = slide.cur_slide() -- the line number of the current slide
    if cur then
        local pos = vim.fn.getpos('.')
        if pos[2] <= cur.startLn then pos[2] = cur.startLn + 1 end -- Adjust pos to make sure we're in the slide interior
        if pos[2] >= cur.endLn then pos[2] = cur.endLn - 1 end
        vim.fn.setpos('.', pos)
        vim.fn.winrestview({ topline = cur.startLn + 1 }) -- Adjusts the window view to the specified line
    else
        vim.notify("Can't align view to current slide, no current slide found", vim.log.levels.ERROR)
    end
end

---Jumps to given slide by fragment
---@param fragment string
---@return nil
function M.find_slide(fragment)
    local frag_slide = slide.fragment_slide(fragment)
    if frag_slide then
        vim.fn.setpos('.', { 0, frag_slide.startLn + 1, 0, 0 })
    end
end

return M
