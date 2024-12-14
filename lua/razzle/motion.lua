---Module for slide motions
---@class RazzleMotion
local M = {}

local slide = require("razzle.slide")

---Moves to the top of the next slide's interior
---@return nil
function M.next_slide()
    -- Get the line number of the next slide
    local pos = slide.next_slide_ln()
    -- Set the cursor position to the next slide
    if pos then
        vim.fn.setpos('.', { 0, pos + 1, 0, 0 })
    else
        print("Can't move to next slide, no next slide found")
    end
end

---Moves to the top of the previous slide's interior
---@return nil
function M.prev_slide()
    -- Get the line number of the previous slide
    local pos = slide.prev_slide_ln()
    -- Set the cursor position to the previous slide's line
    if pos then
        vim.fn.setpos('.', { 0, pos + 1, 0, 0 })
    else
        print("Can't move to previous slide, no next slide found")
    end
end

---Moves to top of the current slide's interior
---@return nil
function M.cur_slide()
    -- Get the line number of the current slide
    local pos = slide.cur_slide_ln() -- pos: number
    -- Set the cursor position to the current slide's line
    if pos then
        vim.fn.setpos('.', { 0, pos + 1, 0, 0 }) -- Set cursor position in the current buffer
    else
        print("Can't move to current slide, no current slide found")
    end
end

---Aligns the view to the current slide's interior.
---@return nil
function M.align_view()
    local top = slide.cur_slide_ln() -- the line number of the current slide
    local bot = slide.cur_slide_end_ln() -- end number, the line number of the end of the current slide
    local pos = vim.fn.getpos('.')
    if pos then
        if pos[2] <= top then pos[2] = top + 1 end -- Adjust pos to make sure we're in the slide interior
        if pos[2] >= bot then pos[2] = bot - 1 end
        vim.fn.setpos('.', pos)
        vim.fn.winrestview({ topline = top + 1 }) -- Adjusts the window view to the specified line
    else
        print("Can't align view to current slide, no current slide found")
    end
end

return M
