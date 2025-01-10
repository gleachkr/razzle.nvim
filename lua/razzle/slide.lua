---Module for slide properties
---@class RazzleSlide
local M = {}

--[[-- 

This module is intended to provide basic functions that implicitly define what
counts as a slide. Slides intuitively begin with slide marker ("SLIDE" by
default), and end with an end marker ("FIN" by default). However, illegal
states should be unrepresentable. So, more precisely, a slide is:

    A sequence of one or more contiguous lines, 

    a. preceded by a line contianing a slide-marker, 
    b. not containing any lines that contain end-markers or slide-markers, and 
    c. not containing any slides as parts.

This definition entails that every line belongs to at most one slide, with no
assumptions about how we insert slide and end markers For: if a line belonged
to two slides, A and B, then A and B need to begin on different lines (since
otherwise whichever one ended first would be a part of the other). Assuming
A starts later than B, then B must end after A starts (otherwise they couldn't
share a line). But that means B contains a slide marker, which is forbidden.

Here's an example that illustrates most of the tricky cases:

```

SLIDE
        ┐
        │ Slide 1
        ┘
SLIDE
        ┐
        │ Slide 2
        ┘
FIN

FIN

FIN SLIDE FIN
       ┐
       │
       │ Slide 3
       │
       ┘
SLIDE
FIN
SLIDE
       ┐
       │
       │ Slide 4
       │
       ┘
```

]]

M.startMark = vim.regex([[\(^.*SLIDE.*$\)]])

M.endMark = vim.regex([[\(^.*SLIDE\|FIN.*$\)]])

---@class Slide
---@field startLn number
---@field endLn number
---@field bufNu number

---Generates a list of all the slides in the current buffer
---@return Slide[] slides
function M.find_slides()
    local lines = vim.api.nvim_buf_get_lines(0,0,-1,false)
    local inSlide = false
    local curSlide = { bufNu = vim.api.nvim_get_current_buf() }
    local allSlides = {}
    for i, _ in ipairs(lines) do
        if inSlide and M.endMark:match_line(0,i - 1) then
            inSlide = false
            if curSlide.startLn and i - curSlide.startLn > 1 then
                curSlide.endLn = i
                allSlides[#allSlides + 1] = curSlide
            end
            curSlide = { bufNu = vim.api.nvim_get_current_buf() }
        end
        if (not inSlide) and M.startMark:match_line(0,i - 1) then
            curSlide.startLn = i
            inSlide = true
        end
    end
    return allSlides
end

---Finds the the first slide beginning after the cursor line
---@return Slide | nil next_slide The next slide found, or nil if none found
function M.next_slide()
    local slides = M.find_slides()
    local ln = vim.fn.line('.')
    for _, slide in ipairs(slides) do
        if slide.startLn > ln then
            return slide
        end
    end
end

---Finds the last slide ending before the cursor line
---@return Slide | nil prev_start The last slide ending before the cursor line, or nil if none found
function M.prev_slide()
    local slides = M.find_slides()
    local ln = vim.fn.line('.')
    for i=1, #slides do
        if slides[#slides + 1 - i].endLn < ln then
            return slides[#slides + 1 - i]
        end
    end
end

---Finds the slide containing the cursor line
---@return Slide | nil prev_start The slide containing the cursor line, or nil if none found
function M.cur_slide()
    local slides = M.find_slides()
    local ln = vim.fn.line('.')
    for _, slide in ipairs(slides) do
        if slide.endLn > ln then
            if slide.startLn < ln then
                return slide
            else
                return nil
            end
        end
    end
end

---Calculates the start of the first slide beginning after the cursor line
---@return number | nil next_start The line number of the next slide found, or nil if not found.
function M.next_slide_ln()
    local next = M.next_slide()
    if next then
        return next.startLn
    end
end

---Calculates the start of the last slide ending before the cursor line
---@return number | nil prev_start The line number of the previous slide found, or nil if not found.
function M.prev_slide_ln()
    local prev = M.prev_slide()
    if prev then
        return prev.startLn
    end
end

---Calculates the end of the last slide ending before the cursor line
---@return number | nil prev_end The line number of the end of the previous slide, or nil if not found
function M.prev_slide_end_ln()
    local prev = M.prev_slide()
    if prev then
        return prev.endLn
    end
end

---Calculates the start of the slide contianing the cursor
---@return number | nil cur_start  The line number of the start of the current slide, or nil if not found.
function M.cur_slide_ln()
    local cur = M.cur_slide()
    if cur then
        return cur.startLn
    end
end

---Calculates the end of the slide contianing the cursor
---@return number | nil cur_end  The line number of the end of the current slide, or nil if not found
function M.cur_slide_end_ln()
    local cur = M.cur_slide()
    if cur then
        return cur.endLn
    end
end

---Counts the number of virtual lines in a specified range of a buffer.
---@param bufnr number  The buffer number to count virtual lines in.
---@param start_line number  The starting line number (1-based).
---@param end_line number  The ending line number (1-based).
---@return number total_virt_lines  The total number of virtual lines in the specified range.
local function count_virtual_lines(bufnr, start_line, end_line)
    -- Convert to 0-based indices
    local start_pos = {start_line - 1, 0}
    local end_pos = {end_line - 1, -1}
    local total_virt_lines = 0

    -- Get all extmarks in range
    local marks = vim.api.nvim_buf_get_extmarks(
        bufnr,
        -1,  -- Use any namespace
        start_pos,
        end_pos,
        {details = true}
    )

    -- Loop through marks and count virtual lines
    for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.virt_lines then
            total_virt_lines = total_virt_lines + #details.virt_lines
        end
    end
    return total_virt_lines
end

---Calculates the height of the current slide's interior
---@return number | nil height The height of the current slide's interior, including virtual lines.
function M.slide_height()
    -- Get the line number of the top of the current slide
    local top = M.cur_slide_ln()
    -- Get the line number of the end of the current slide
    local bot = M.cur_slide_end_ln()
    -- Count the number of virtual lines between the top and bottom of the slide
    if top and bot then
        local virt = count_virtual_lines(0, top, bot)
        -- Return the total height of the slide, including virtual lines
        return (bot - top) + virt - 1
    end
end

return M
