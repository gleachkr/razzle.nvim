---Module for slide properties
---@class RazzleSlide
local M = {}

--[[-- 

This module is intended to provide basic functions that implicitly define what
counts as a slide. Slides intuitively begin with slide marker ("SLIDE" by
default), and end with an end marker ("FIN" by default). However, illegal
states should be unrepresentable. So, more precisely, a slide is:

    A sequence of one or more contiguous lines, 

    a. preceded by a line containing a slide-marker, 
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

M.startMark = vim.regex([[\(SLIDE\(#\w*\)\?\)]])

M.endMark = vim.regex([[\(SLIDE\(#\w*\)\?\)\|\(FIN\)]])

M.slidesByBuf = {}

M.slidesByFrag = {}

---@class Slide
---@field startLn number
---@field endLn number
---@field bufNu number
---@field fragment string | nil
---@field params table<string, string|table<string,string>> | nil

---@param queryString string
---@return table<string, string|table<string,string>>
local function parseQueryString(queryString)
    local params = {}

    for pair in queryString:gmatch("([^&]+)") do
        local key, value = pair:match("([^=]+)=?(.*)")
        if key then
            if params[key] then
                if type(params[key]) ~= "table" then
                    params[key] = {params[key]}
                end
                table.insert(params[key], value)
            else
                params[key] = value
            end
        end
    end

    return params
end

---Refreshes the slide data in M.slides for the given buffer
---@param buf number
---@return nil
function M.refresh_slides(buf)
    local lines = vim.api.nvim_buf_get_lines(buf,0,-1,false)
    local inSlide = false
    local curSlide = { bufNu = buf }
    local allSlides = {}
    for i, _ in ipairs(lines) do
        if inSlide and M.endMark:match_line(buf, i - 1) then
            inSlide = false
            if curSlide.startLn and i - curSlide.startLn > 1 then
                curSlide.endLn = i
            end
            curSlide = { bufNu = buf }
        end
        if (not inSlide) and M.startMark:match_line(buf, i - 1) then
            curSlide.startLn = i
            local params, fragment = vim.fn.getline(i):match("SLIDE%??([^#%s]*)#?(%S*)")
            if params then
                curSlide.params = parseQueryString(params)
            end
            if fragment then
                curSlide.fragment = fragment
                M.slidesByFrag[curSlide.fragment] = curSlide
            end
            allSlides[#allSlides + 1] = curSlide
            inSlide = true
        end
    end
    if not curSlide.endLn then curSlide.endLn = #lines + 1 end
    M.slidesByBuf[buf] = allSlides
end

---returns a list of all the slides in the current buffer
---@return Slide[] slides
function M.find_slides()
    return M.slidesByBuf[vim.api.nvim_get_current_buf()]
end

---Finds the the first slide beginning after the cursor line
---@return Slide | nil next_slide The next slide found, or nil if none found
function M.next_slide()
    local slides = M.find_slides()
    if not slides then return nil end
    local ln = vim.fn.line('.')
    local cur, next
    for _, slide in ipairs(slides) do
        if slide.startLn > ln and not next then
            next = slide
        end
        if slide.endLn > ln and slide.startLn < ln then
            cur = slide
        end
    end
    if cur and cur.params and cur.params["next"] then
        next = M.slidesByFrag[cur.params["next"]]
    end
    return next
end

---Finds the last slide ending before the cursor line
---@return Slide | nil prev_start The last slide ending before the cursor line, or nil if none found
function M.prev_slide()
    local slides = M.find_slides()
    if not slides then return nil end
    local ln = vim.fn.line('.')
    local cur, prev, slide
    for i=1, #slides do
        slide = slides[#slides + 1 - i]
        if slide.endLn < ln and not prev then
            prev = slide
        end
        if slide.endLn > ln and slide.startLn < ln then
            cur = slide
        end
    end
    if cur and cur.params and cur.params["prev"] then
        prev = M.slidesByFrag[cur.params["prev"]]
    end
    return prev
end

---Finds the slide containing the cursor line
---@return Slide | nil prev_start The slide containing the cursor line, or nil if none found
function M.cur_slide()
    local slides = M.find_slides()
    if not slides then return nil end
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

---Finds the slide with a certain fragment
---@param fragment string
---@return Slide | nil prev_start The slide with the fragment line, or nil if none found
function M.fragment_slide(fragment)
    return M.slidesByFrag[fragment]
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
    local cur = M.cur_slide()
    -- Count the number of virtual lines between the top and bottom of the slide
    if cur then
        local virt = count_virtual_lines(0, cur.startLn, cur.endLn)
        -- Return the total height of the slide, including virtual lines
        return (cur.endLn - cur.startLn) + virt - 1
    end
end

return M
