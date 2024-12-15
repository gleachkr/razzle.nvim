# Razzle.nvim

Terminal slide presentations, in neovim. Beware, WIP.

## Basic Idea

Text files are slides. Any kind of text file: markdown, code, plain text,
whatever you want.

A slide begins with an occurrence of the word SLIDE (maybe in a comment) and
ends with FIN.

You start a presentation with `require("razzle").start_presentation()` and end
it with `require("razzle").end_presentation()`. The first fires a `RazzleStart`
event, and the second fires a `RazzleEnd` event. During the presentation,
entering a new slide fires a `RazzleSlideEnter` event. That's the basic idea, it's
very simple.

You can handle these events by updating the view so that your slide is properly
centered, or focused, or however you want to make it look good. Razzle provides
some utilities to help with that. There's a lot of room for creativity here.

Look inside for function-level documentation. Eventually I'll write some some
proper `:help` docs, I hope.

## Example

Here's an example of some event handling for a razzle presentation:

```lua
razzle = require("razzle")
zen_mode = require("razzle.zen-mode")
lock = require("razzle.lock")
motion = require("razzle.motion")
conceal = require("razzle.conceal")


vim.api.nvim_create_autocmd("User", {
    callback = function()
        local height = require("razzle.slide").slide_height()
        zen_mode.set_layout(nil, height)
        motion.align_view()
        lock.lock_scroll()
    end,
    pattern = "RazzleSlideEnter",
})


vim.api.nvim_create_autocmd("User", {
    callback = function()
        vim.opt.scrolloff = 0
        local slide_group = vim.api.nvim_create_augroup("Razzle", { clear = false})
        conceal.conceal_slide_markers()
        local height = require("razzle.slide").slide_height()
        require("zen-mode").open({window = { height=height, width=80 }})
        motion.align_view()
        lock.lock_scroll()
        vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
            callback = function()
                local height = require("razzle.slide").slide_height()
                zen_mode.set_layout(nil, height)
                motion.align_view()
                lock.lock_scroll()
            end,
            group = slide_group
        })
    end,
    pattern = "RazzleStart"
})

vim.api.nvim_create_autocmd("User", {
    callback = function()
        conceal.reveal_slide_markers()
        lock.unlock_scroll()
        require("zen-mode").close()
    end,
    pattern = "RazzleEnd"
})


vim.keymap.set("n", "]S", motion.next_slide)
vim.keymap.set("n", "[S", motion.prev_slide)
```

