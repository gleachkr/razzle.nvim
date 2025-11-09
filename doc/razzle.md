# Razzle.nvim

Terminal slide presentations in Neovim.

## TL;DR {#razzle.tldr}

```lua
-- Start a presentation (cursor must be inside a slide)
require("razzle").start_presentation()

-- Optional helpers
require("razzle.lock")
require("razzle.conceal")
require("razzle.zen-mode")
-- Optional presentation-wide options and per-slide overrides
require("razzle.options").setup({
  o  = { number = false },              -- example: turn off line numbers
  wo = { signcolumn = "no" },           -- window-local example
  -- colorscheme = "habamax",           -- optionally pin a colorscheme
})
-- Optional temporary maps (saved/restored automatically)
local motion = require("razzle.motion")
require("razzle.maps").setup({
  n = { ["]S"] = motion.next_slide, ["[S"] = motion.prev_slide },
  i = { ["<Right>"] = motion.next_slide, ["<Left>"] = motion.prev_slide },
})
-- Optional: return to the deck after a terminal closes
-- require("razzle.term")

local motion = require("razzle.motion")
vim.keymap.set("n", "]S", motion.next_slide)
vim.keymap.set("n", "[S", motion.prev_slide)
```

Slides are delimited by lines that contain `SLIDE` and an ending marker.

## Concepts {#razzle.concepts}

A slide begins at a line containing `SLIDE` (may be in a comment) and ends at 
the next line that contains either `SLIDE` or `FIN`. The interior of a slide is 
the text strictly between those markers. Slides can be any text: markdown, 
code, plain text. During a presentation, entering a slide fires 
|RazzleSlideEnter|. Razzle ships small modules that help with view/layout and 
navigation. Put razzle setup in a Session file or `.nvim.lua` to style each 
presentation.

### Slide markers with params and fragments {#razzle.markers}

`SLIDE` lines can carry an optional query string and an optional fragment:

```
SLIDE?key=value&k2=v2#my-fragment
```

- Params become a table on the slide object, e.g. `slide.params.next`.
- Fragment becomes `slide.fragment` and is used by |razzle.motion.find|.
- If the current slide has `next` or `prev` params, they override linear
  navigation by naming the fragment of the target slide.
- When |razzle.options| is enabled, certain params are recognized as
  temporary option overrides for that slide and are restored when leaving:
  - `colorscheme=name`
  - `o.option=value`   for global options
  - `wo.option=value`  for window-local options
  - `bo.option=value`  for buffer-local options

Example:

```
SLIDE#intro
... intro content ...
FIN

SLIDE?next=section-2#section-1
... section 1 ...
SLIDE#section-2
... section 2 ...
FIN
```

## Events {#razzle.events}

Razzle emits User autocommands with payload in `event.data`:

- RazzleStart
  Fired when a presentation starts. `data.entered` is the starting slide.

- RazzleEnd
  Fired when a presentation ends.

- RazzleSlideEnter
  Fired when the cursor enters a different slide during a presentation,
  including the first slide at start.

Timing and ordering:

- On start, slide-change handlers are set up before firing RazzleStart, so
  CursorMoved handlers you register during RazzleStart run after slide-change
  handlers.

Payload shape (table fields are a stable contract):

```
{
  startLn: number,  -- 1-based line of SLIDE marker
  endLn:   number,  -- 1-based line of end marker (exclusive interior end)
  bufNu:   number,  -- buffer handle containing this slide
  fragment: string|nil,
  params:   table<string, string|string[]>|nil,
}
```

## Commands and API {#razzle.api}

### :RazzleStart {#razzle.cmd.start}

Begin a presentation in the current window. The cursor must be inside a slide,
otherwise you will see an error. Moves the cursor to the first line of the
slide interior. Triggers |RazzleStart| and then |RazzleSlideEnter| for the
starting slide.

### :RazzleEnd {#razzle.cmd.end}

End the current presentation. Triggers |RazzleEnd| and cleans up internal
state.

### require("razzle").start_presentation() {#razzle.start}

Programmatic equivalent of |:RazzleStart|.

### require("razzle").end_presentation() {#razzle.end}

Programmatic equivalent of |:RazzleEnd|.

## Modules {#razzle.modules}

Each module is optional. Require the ones you want.

### motion {#razzle.motion}

Navigation helpers.

```lua
local motion = require("razzle.motion")
motion.next_slide() -- go to next slide start (interior)
motion.prev_slide() -- go to previous slide start (interior)
motion.cur_slide()  -- jump to the current slide interior
motion.align_view() -- keep view aligned to the slide top
motion.find_slide("fragment") -- jump to slide by fragment id
```

Notes:

- `next` / `prev` consider `SLIDE?next=frag` or `?prev=frag` overrides on the
  current slide.
- Slides are indexed per-buffer. A presentation start preloads all normal
  buffers so fragment-based jumps can cross buffers.

### maps {#razzle.maps}

Temporary keymaps that are active only during a presentation. Any existing
mappings for those keys are saved and restored when the presentation ends.

- On |RazzleStart|: saves current mappings for your keys and installs the
  presentation mappings.
- On |RazzleEnd|: removes the presentation mappings and restores the saved
  mappings.

Setup example (shorthand by mode):

```lua
local motion = require("razzle.motion")
require("razzle.maps").setup({
  n = { ["]S"] = motion.next_slide, ["[S"] = motion.prev_slide },
  i = { ["<Right>"] = motion.next_slide, ["<Left>"] = motion.prev_slide },
})
```

### conceal {#razzle.conceal}

Conceals lines containing slide markers while a presentation is active.
Works with both regex syntax and Tree-sitter via a `matchadd`.

- On |RazzleStart|: installs highlight and conceal rules.
- On |RazzleEnd|: clears them.

### lock {#razzle.lock}

Restricts cursor movement to within the current slide’s interior while a
presentation is active. Also keeps the top of the slide at the top of the
window.

- On |RazzleStart|: sets `scrolloff=0`, computes bounds for the current slide,
  and installs handlers to maintain bounds and view.
- On |RazzleSlideEnter|: recomputes bounds for the entered slide.
- On |RazzleEnd|: removes bounds.

### zen-mode {#razzle.zen-mode}

Centers the current slide in a floating window with a solid backdrop. The
slide remains editable; clicking the backdrop does nothing and focus stays in
the slide window. Responds to VimResized and ColorScheme changes.

If the current slide marker has a `split=FRAG` parameter,
zen-mode will draw a second, non-focusable floating window to the right that
shows the slide with fragment id `FRAG`. The total minimum width defaults to
80 columns. Each split pane has a minimum of half that. If a slide's
longest interior line is wider than its minimum, that pane expands to fit its
content. The padding frame expands to encompass both windows. Each pane uses
the intrinsic height of its content; the overall layout height is the max of
the two.

Note: zen-mode focuses on layout. It does not toggle typical UI options like
`number`, `relativenumber`, `signcolumn`, or `scrolloff`. Use
|razzle.options| to set presentation defaults and per-slide overrides for
those.

#### Setup {#razzle.zen-mode.setup}

```lua
require("razzle.zen-mode").setup({
  backdrop = {
    blend = 30,        -- 0..100: how much to blend toward target color
    color = "#000000", -- target color to blend toward
  },
  padding = {
    horizontal = 4,    -- cells added left and right
    vertical   = 2,    -- cells added top and bottom
  },
  min_width = 80,      -- minimum total width; split panes get half each
})
```

### term (optional) {#razzle.term}

Restores focus to the current slide when a terminal job closes.

- On |RazzleStart|: remembers the starting slide and updates on
  |RazzleSlideEnter|.
- On `TermClose`: jumps back to the last seen slide interior.

### options {#razzle.options}

Manage presentation-wide defaults and per-slide overrides for options.

- On |RazzleStart|: saves original values, applies your presentation
  defaults, and applies overrides for the starting slide (if any).
- On |RazzleSlideEnter|: resets any previous slide overrides to the
  presentation defaults (or to the original value if you did not specify a
  default), then applies the new slide’s overrides.
- On |RazzleEnd|: restores the original values.

Setup example:

```lua
require("razzle.options").setup({
  o  = { number = false, cursorline = false },
  wo = { signcolumn = "no" },
  bo = {},
  -- colorscheme = "habamax",
})
```

Per-slide example:

```
SLIDE?colorscheme=elflord&wo.signcolumn=yes&o.cursorline=false#intro
```

### html (experimental) {#razzle.html}

Exports slides to HTML using the `:TOhtml` runtime (requires `tohtml`).

```lua
require("razzle.html").slidesToSimpleHTML()  -- SlideN.html per slide
require("razzle.html").slidesToSingleHTML()  -- Slides.html with <section>s
```

## Slide detection details {#razzle.slides}

A slide begins at a line that contains `SLIDE` and ends at the next line
that contains either `SLIDE` or `FIN`, or at end-of-file. The slide interior 
excludes the marker lines. Folds that cover marker lines are opened 
automatically when computing the slide height to avoid degenerate displays.

## FAQ {#razzle.faq}

- Q: Can I mix code and markdown?
  A: Yes. Any text between `SLIDE` and the next marker is slide content.

- Q: Do I need to use Lua only?
  A: You can also use |:RazzleStart| and |:RazzleEnd| commands.

- Q: Is there a “slide leave” event?
  A: Not currently. Only |RazzleSlideEnter| is emitted. A leave event may be
     added later.
