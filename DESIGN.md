Idea

A slide presentation framework using neovim. 

1. You move between slides by just searching for a keyword SLIDE#TYPE, probably
   with ]] or similar. The keywords are concealed.

2. There are callbacks for each slide-type, which might include for example
   locking the view to prevent accidental scrolling, or changing a ZenMode
   view. Some of these ship with the plugin.

3. There's an ordering of slides, which is mostly linear within documents, but
   with definable edges from one slide to another. There's a function for
   getting the start of the next, current, or previous slide.
