Idea

A slide presentation framework using neovim. 

1. You move between slides by just searching for a keyword SLIDE#TYPE,
   probably with ]] or similar. The keywords are concealed during a presentation. There's function to retrieve the TYPE of a given slide. There should be a data type for slides, roughly { line: number, tag: Maybe tag, etc }

2. There are events that fire when certain events occur, like SlideChange, or
   PresentationStart.

    a. RazzleStart is allowed to change the window before variables local to
       the presentation window are initialized. It is called *after* the
       callback firing RazzleSlideChanged is established, so any CursorChanged
       event handlers registered during the RazzleStart callback will fire
       after the event handlers for RazzleSlideChanged

3. There are some useful callbacks, shipping with the plugin, that can be
   attached to these events. The callbacks might include for example locking
   the view to prevent accidental scrolling, or changing a ZenMode view. 

4. There's an ordering of slides, which is mostly linear within documents,
   but with customizable edges from one slide to another. There's a function
   for getting the start of the next, current, or previous slide.

5. One could have a telescope integration for navigating slides
