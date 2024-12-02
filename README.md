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
changing slides fires a `RazzleSlideChanged` event. That's the basic idea, it's
very simple.

You can handle these events by updating the view so that your slide is properly
centered, or focused, or however you want to make it look good. Razzle provides
some utilities to help with that. There's a lot of room for creativity here.

Look inside for function-level documentation. Eventually I'll write some some
proper `:help` docs, I hope.

## Example

Here's an example of some event handling for a razzle presentation:

```lua
vim.api.nvim_create_autocmd("User", {
    callback = function()
        local height = require("razzle").slide_height()
        require("razzle.zen-mode").set_layout(nil, height)
        require("razzle").align_view()
        require("razzle.lock-scroll").lock_scroll()
    end,
    pattern = "RazzleSlideChanged",
})


vim.api.nvim_create_autocmd("User", {
    callback = function()
        vim.opt.scrolloff = 0
        require("razzle.conceal").conceal_slide_markers()
        local height = require("razzle").slide_height()
        require("zen-mode").open({window = { height=height, width=80 }})
        require("razzle").align_view()
        require("razzle.lock-scroll").lock_scroll()
        vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
            callback = function()
                local height = require("razzle").slide_height()
                require("razzle.zen-mode").set_layout(nil, height)
                require("razzle").align_view()
                require("razzle.lock-scroll").lock_scroll()
            end,
            buffer = 0,
        })
    end,
    pattern = "RazzleStart"
})

vim.api.nvim_create_autocmd("User", {
    callback = function()
        require("razzle.conceal").reveal_slide_markers()
        require("razzle.lock-scroll").unlock_scroll()
        require("zen-mode").close()
    end,
    pattern = "RazzleEnd"
})


vim.keymap.set("n", "]S", require("razzle").next_slide)
vim.keymap.set("n", "[S", require("razzle").prev_slide)
```

