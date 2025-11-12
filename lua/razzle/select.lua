local slide = require("razzle.slide")
local motion = require("razzle.motion")

---@class RazzleSelect
local M = {}

function M.select_slide()
    local keys = {}
    for key, _ in pairs(slide.slidesByFrag) do
        table.insert(keys, key)
    end
    vim.ui.select(keys, {
        prompt = "Jump to slide:",
    }, motion.find_slide)
end

return M
