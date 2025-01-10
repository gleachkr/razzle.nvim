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
entering a new slide fires a `RazzleSlideEnter` event. That's the basic idea,
it's very simple!

Look inside for function-level documentation. Eventually I'll write some some
proper `:help` docs, I hope.

## Usage

You can handle `RazzleStart`, `RazzleEnd`, and `RazzleSlideEnter` by updating
the view so that your slide is properly centered, or focused, or however you
want to make it look good. There's a lot of room for creativity here. But
Razzle provides some utilities for out-of-the-box setups.

Utilities are currently provided as separate modules, so you'll want to
require them individually. It would probably make the most sense to do this in
a `Sessionx.vim`, or an `.nvim.lua`, so that you can configure your
presentation style per-presentation.

Available modules:

Name     Description 
-------- ---------------------------------------------------------------------
conceal  Conceals lines containing slide markers while presentation is active
lock     Restricts cursor movement to within slides
zen-mode Integrates with [folke/zen-mode](https://github.com/folke/zen-mode) to center and isolate the current slide
motion   Provides slide navigation functions

## Example

Here's an example of some event handling for a razzle presentation:

```lua
require("razzle")
require("razzle.lock")
require("razzle.conceal")
require("razzle.zen-mode")

motion = require("razzle.motion")
vim.keymap.set("n", "]S", motion.next_slide)
vim.keymap.set("n", "[S", motion.prev_slide)
```

