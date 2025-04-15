---Module for converting slides to HTML
---@class RazzleHTML
local M = {}

local slide = require("razzle.slide")
local html = require("tohtml")

function M.slidesToHTML()
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

GLOBAL = M

return M
