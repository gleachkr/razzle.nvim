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

M.startMark = vim.regex([[SLIDE]])

M.endMark = vim.regex([[\(SLIDE\)\|\(FIN\)]])

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
    -- Clear any fragment mappings that pointed into this buffer
    for frag, s in pairs(M.slidesByFrag) do
        if s.bufNu == buf then M.slidesByFrag[frag] = nil end
    end

    local lines = vim.api.nvim_buf_get_lines(buf,0,-1,false)
    local inSlide = false
    local allSlides = {}
    local curSlide
    for i, _ in ipairs(lines) do
        if inSlide and M.endMark:match_line(buf, i - 1) then
            inSlide = false
            if curSlide.startLn and i - curSlide.startLn > 1 then
                curSlide.endLn = i
                allSlides[#allSlides + 1] = curSlide
            end
        end
        if (not inSlide) and M.startMark:match_line(buf, i - 1) then
            curSlide = { bufNu = buf, startLn = i }
            local params, fragment = lines[i]:match("SLIDE%??([^#%s]*)#?(%S*)")
            if params and params ~= "" then
                curSlide.params = parseQueryString(params)
            end
            if fragment and fragment ~= "" then
                curSlide.fragment = fragment
                M.slidesByFrag[curSlide.fragment] = curSlide
            end
            inSlide = true
        end
    end
    if curSlide and not curSlide.endLn then
        curSlide.endLn = #lines + 1
        allSlides[#allSlides + 1] = curSlide
    end
    M.slidesByBuf[buf] = allSlides
end

---returns a list of all the slides in the current buffer
---@return Slide[] | nil slides
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

---Count virtual lines on visible lines in a given range (current window)
---@param bufnr number
---@param start_line number 1-based inclusive
---@param end_line number   1-based inclusive
---@return number
local function count_visible_virtual_lines(bufnr, start_line, end_line)
    local total = 0
    local ns_map = vim.api.nvim_get_namespaces()
    for _, ns_id in pairs(ns_map) do
        local marks = vim.api.nvim_buf_get_extmarks(
            bufnr,
            ns_id,
            {start_line - 1, 0},
            {end_line - 1, -1},
            { details = true }
        )
        for _, mark in ipairs(marks) do
            local row = mark[2] -- 0-based
            if vim.fn.foldclosed(row + 1) == -1 then
                local details = mark[4]
                if details and details.virt_lines then
                    total = total + #details.virt_lines
                end
            end
        end
    end
    return total
end

---Count visible screen lines between two buffer lines, respecting folds.
---Closed folds are counted as a single screen line.
---@param start_line number 1-based inclusive
---@param end_line number   1-based inclusive
---@return number
local function count_visible_lines(start_line, end_line)
    local visible = 0
    local l = start_line
    while l <= end_line do
        local fc = vim.fn.foldclosed(l)
        visible = visible + 1
        if fc ~= -1 then
            l = vim.fn.foldclosedend(l) + 1
        else
            l = l + 1
        end
    end
    return visible
end

---Open folds that include the start and end markers of the slide.
---@param start_mark number 1-based start marker line (cur.startLn)
---@param end_mark number 1-based end marker line (cur.endLn)
local function ensure_marker_folds_visible(start_mark, end_mark)
    local win = 0
    local save = vim.api.nvim_win_get_cursor(win)
    local line_count = vim.api.nvim_buf_line_count(0)

    local function open_at(lnum)
        if lnum >= 1 and lnum <= line_count and vim.fn.foldclosed(lnum) ~= -1 then
            vim.api.nvim_win_set_cursor(win, {lnum, 0})
            vim.cmd('silent! normal! zv')
        end
    end

    open_at(start_mark)
    open_at(end_mark)

    vim.api.nvim_win_set_cursor(win, save)
end

---Calculates the height of the current slide's interior.
---Accounts for virtual lines and closed folds. Folds that include the
---marker endpoints are opened to avoid degenerate displays.
---@return number | nil height
function M.slide_height()
    local cur = M.cur_slide()
    if not cur then return nil end

    -- Open folds that include the slide's marker lines
    ensure_marker_folds_visible(cur.startLn, cur.endLn)

    local top = cur.startLn + 1
    local bot = cur.endLn - 1
    if top > bot then return 0 end

    -- Visible buffer lines between interior endpoints
    local visible = count_visible_lines(top, bot)

    -- Virtual lines on visible (non-folded) lines only
    local virt = count_visible_virtual_lines(0, top, bot)

    return visible + virt
end

return M
