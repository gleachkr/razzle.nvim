---Module for converting slides to HTML
---@class RazzleHTML
local M = {}

local slide = require("razzle.slide")
local html = require("tohtml")

function M.slidesToSimpleHTML()
    slide.refresh_slides(vim.api.nvim_get_current_buf())
    for idx, s in ipairs(slide.find_slides()) do
        local doc = html.tohtml(0, {
            range = { s.startLn + 1, s.endLn - 1 }
        })
        local name = "Slide" .. idx .. ".html"
        local file = io.open(name, "w")
        if file then
            for _, str in ipairs(doc) do
                file:write(str .. "\n")
            end
            file:close()
        else
            vim.notify("couldn't write " .. name, vim.log.levels.WARN)
        end
    end
end

function M.slidesToSingleHTML()
    slide.refresh_slides(vim.api.nvim_get_current_buf())
    local full_doc = table.concat(html.tohtml(0), '\n')
    local head = full_doc:match('<head[^>]*>.*</head>')
    local body = "<body>\n"
    for idx, s in ipairs(slide.find_slides()) do
        local doc = table.concat(html.tohtml(0, {
            range = { s.startLn + 1, s.endLn - 1 }
        }), '\n')
        local body_inner = doc:match('<body[^>]*>(.*)</body>')
        body = body
            .. "<section " .. "id=\"slide_" .. idx .. "\"><div>\n"
            .. body_inner
            .. "</div></section>\n"
    end
    body = body .. "</body>"
    local rslt = "<!DOCTYPE html><html>" .. head .. body .. "</html>"
    local file = io.open("Slides.html", "w")
    if file then
        file:write(rslt)
        file:close()
    else
        vim.notify("couldn't write Slides.html", vim.log.levels.WARN)
    end
end

return M
