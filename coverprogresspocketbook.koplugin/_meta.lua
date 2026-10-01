local _ = require("gettext")
return {
    fullname = _("Cover Image PocketBook"),
    description = _([[Writes the current book's cover, with a reading-progress bar and an optional sleep screen message, to an image file. On PocketBook this is the Line theme's lock screen (portrait and landscape); elsewhere a file an external screensaver app can display.

The message supports KOReader's sleep screen placeholders (title, author, percent read, time left, battery, ...) in a box or banner. Updates as you read.

Derived from KOReader's built-in coverimage plugin.]]),
}
