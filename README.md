# Cover Image PocketBook

A KOReader plugin for **PocketBook** e-readers that puts the cover of the book you're reading on the lock screen, with a reading-progress bar and an optional message such as the title, percent read or time left.

Open a book, close the cover, and the lock screen shows that book and how far through it you are. As you read, it keeps up.

**PocketBook only.** Tested on a **PocketBook Era Lite (PB710)** with firmware 6.11 and KOReader v2026.07. Other PocketBook models should work the same way (see [Other PocketBook models](#other-pocketbook-models)), but have not been tried.

Derived from KOReader's built-in Cover image plugin.

---

## What it does

- **Sleep screen.** Writes the book cover, with a progress bar and your message, as the lock screen of PocketBook's **Line** theme, in portrait and landscape. It updates as you read.
- **Works with the sleep cover.** Closing the cover or double-clicking the menu button normally shows whatever image the firmware loaded at startup. After each update the plugin tells the firmware to reload it, so these show the current book too.
- **Four layouts** for the progress bar, or none.
- **Sleep screen message** with KOReader's placeholders: title, author, percent read, time left, battery, and more.
- **Books without a cover** show their title in bold instead.
- **Startup screen** *(optional)*: the book cover while the device starts.
- **Power-off screen** *(optional)*: the book cover, or the same image as the sleep screen, while the device is switched off.

---

## Installation

1. Download `coverprogresspocketbook.koplugin.zip` from the [latest release](https://github.com/apastuszak/coverprogresspocketbook.koplugin/releases/latest) and extract it. You get a folder named `coverprogresspocketbook.koplugin`.

   If you download the repository instead (**Code → Download ZIP**), the plugin folder is inside an outer `coverprogresspocketbook.koplugin-main` folder. Use the inner one.
2. Connect the PocketBook by USB and copy the `coverprogresspocketbook.koplugin` folder into:
   ```
   /mnt/ext1/applications/koreader/plugins/
   ```
   On a computer that's `applications/koreader/plugins/` on the device's storage. If an older `coverprogress.koplugin` folder is there, delete it first, so the two don't write the same files.
3. Eject the device and start KOReader.
4. Turn off KOReader's built-in **Cover image** plugin: **Tools → More tools → Plugin management**, untick **Cover image**. It writes some of the same files.
5. Open a book, then go to **Menu (gear icon) → Screen → Cover Image PocketBook → Enabled**. The settings menu only exists inside a book, not in the file browser.

The lock screen image is written immediately.

> **macOS:** copying files to the PocketBook from a Mac leaves hidden `._` files next to them. They can stop some KOReader plugins loading. Run `dot_clean -m /Volumes/<device name>` before ejecting.

---

## Setting it up

1. **Choose a layout.** On a PocketBook screen a book cover fills the full height, so pick **Progress bar below cover** (the cover is shrunk slightly to make room for the bar) or **No progress bar**. The other two layouts draw the bar over the bottom of the cover. See [Layouts](#layouts).
2. **Optionally add a message** under **Sleep screen message**. See [Sleep screen message](#sleep-screen-message).
3. **Lock the device** to check: close the cover, double-click the menu button or let it time out. Open a different book and lock again; the image should follow.

The plugin writes these two files, which the firmware shows as the lock screen whenever they exist:

```
/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp
/mnt/ext1/system/resources/Line/taskmgr_lock_background_landscape.bmp
```

The folder is created if it doesn't exist. If either file already exists, it is copied to `<name>.bmp.orig` before the plugin first overwrites it.

---

## Layouts

Choose under **Screen → Cover Image PocketBook**.

| Layout | What it looks like | On PocketBook |
| --- | --- | --- |
| **Progress bar below cover** | The cover is shrunk slightly and raised; the bar sits in the space below it, so it never covers artwork | **Recommended** |
| **No progress bar** | The cover at full size, plus your message if you set one, e.g. `%p% read · %H left` | Recommended |
| **Progress bar in the margin** *(default)* | The cover at full size, with the bar in the band below it | The bar covers the bottom of the cover |
| **Progress bar overlays cover** | A compact bar and percentage drawn on the cover, near the bottom right, placed in the plainest strip it can find and coloured black or white to stand out | Covers part of the artwork by design |

The margin layout can also show a **page number** above the bar. See [Page number](#page-number).

---

## Sleep screen message

Text drawn on the image, like KOReader's own sleep screen message. Set it under **Sleep screen message → Message**; leave it empty for none. It can span several lines.

It uses KOReader's placeholders. Tap **Info** in the edit dialog for the full list:

| Code | Meaning | Code | Meaning |
| --- | --- | --- | --- |
| `%T` | Title | `%p` | Percent read |
| `%A` | Author | `%P` | Chapter percent read |
| `%S` | Series | `%c` / `%t` | Current / total pages |
| `%C` | Chapter title | `%l` | Pages left in chapter |
| `%H` | Time left in book | `%h` | Time left in chapter |
| `%b` | Battery level | `%B` | Battery symbol |
| `%D` / `%d` | Date (yyyy-mm-dd / mm-dd) | `%m` / `%M` | Time (hh:mm / hh-mm-ss) |
| `%f` / `%F` | File name / path | `%r` | Separator |

For example, `%T` on one line and `%p% read · %H left` on the next shows the title, then the percentage and time left.

- **Box:** a bordered box, as wide as the longest line, up to 80% of the screen.
- **Banner:** a full-width strip.
- **Vertical position:** 0 is the bottom, 100 the top. With a progress bar, the message stays above it.

The message uses the background colour, with text and border in the opposite colour.

**Placeholders are filled in when the image is written, not when the device sleeps.** Book and progress placeholders are always current, because they only change when you turn a page. Time, date and battery show their value at the last update. A clock (`%m`) rewrites the image every minute you read; see [When the image is written](#when-the-image-is-written).

`%H` and `%h` come from KOReader's **statistics** plugin. They need it enabled and some reading history for the book; otherwise they show "N/A".

---

## Books without a cover

If a book has no cover image, the plugin draws its title in bold, centred on the plain background, wrapping onto more lines if needed. The progress bar and message are added as usual. The title is the one KOReader shows, or the file name if there is none.

## Page number

**Show page number** (margin layout only) prints "page X of Y" above the bar. The count is KOReader's, so on an EPUB it depends on your font size.

With it on, the image is rewritten on every page turn instead of only when the percentage changes.

## Background

Sets the colour behind the cover, bar and message. Bar, border and text take the opposite colour.

- **White background, black text**
- **Black background, white text**
- **Auto** *(default):* decided per book, by how much of the cover is dark.

The Auto entry shows the measurement for the open book, e.g. *"Auto background (now: white, cover 25% dark)"*. If a cover is classified wrongly, set **Auto: go black above N% dark** either side of that figure (10–90%).

---

## Power-off and startup screens

Two optional settings, both off by default, put the book on two more screens.

### Startup screen

**Startup screen: book cover** shows the cover alone, with no bar or message, while the device starts. It is written into the device's flash memory with the firmware's `iv2sh WriteStartupLogo`, as KOReader's built-in Cover image plugin does, so it is only written when you open a different book.

### Power-off screen

**Power-off screen** offers three choices:

| Choice | Shows | Set in the PocketBook settings |
| --- | --- | --- |
| **Off** *(default)* | Whatever the PocketBook settings choose | — |
| **Book cover only** | The cover alone, updated when you open a different book | Power-off logo → **Custom image** → `system/logo/offlogo/cover.bmp` |
| **Same as sleep screen** | The sleep screen image, bar and message included, updated whenever the sleep screen is | Power-off logo → **Custom image** → `system/resources/Line/taskmgr_lock_background.bmp` |

Why both steps are needed: when you choose a custom power-off image, the firmware converts it once into its own copy, `system/logo/offlogo/pb_offlogo.bmp`, and shows that copy from then on. The plugin writes the new image straight into that copy each time. Choosing the matching file as the custom image means that if the firmware ever rebuilds its copy, it gets the same picture.

The firmware's **Book Cover** power-off option does not work with KOReader; it shows the default image.

### When these are written

Both are written when you open a book, and only if the image would change: a different book, background or screen size. They are never written while the device is going to sleep or when a book closes. An automatic power-off closes the book, and a startup-screen write cut off by the power going out could damage it.

---

## When the image is written

The plugin only runs while KOReader is open. A locked or switched-off device uses no power for it; the firmware just shows the files already there.

While you read, the lock screen images (two BMPs at screen size) are written:

- when you open a book
- 1 second after your last page turn, if the percentage or the message has changed
- when you close the book
- when the device locks, only if a change was still waiting

These options mean more writes, and more wear on the device's storage:

| Option | Effect |
| --- | --- |
| **Show page number** | A write after every page turn |
| `%m` / `%M` in the message | A write every minute (every second for `%M`) while reading |
| `%h` / `%H` in the message | A write whenever the estimate changes, which can be every page or two near the end of a chapter |
| `%b` / `%B` in the message | A write whenever the battery percentage drops |
| Power-off screen: **Same as sleep screen** | One more 1 MB file with each sleep screen write |

---

## Menu reference

| Entry | Purpose |
| --- | --- |
| Enabled | Turns the plugin on or off |
| Progress bar in the margin / below cover / overlays cover, No progress bar | Layout; see [Layouts](#layouts) |
| Sleep screen message | Message text, Box or Banner, Vertical position |
| Show page number | "page X of Y" above the bar; margin layout only |
| White / Black / Auto background | Background colour; Auto shows its measurement |
| Auto: go black above N% dark | Auto sensitivity, 10–90% |
| Output: *path* | Shows where the lock screen images are written |
| Update delay: N s | Wait after the last page turn before writing, 0–60 s (default 1) |
| Power-off screen | Off, Book cover only, or Same as sleep screen |
| Startup screen: book cover | The cover as the startup screen |
| Refresh sleep-cover image | On by default. Tells the firmware to reload the lock image after each update, so the sleep cover and double-click show it |
| Update now | Writes immediately and reports what was written, or why not |

---

## Troubleshooting

**No menu entry.** The settings only exist inside a book; open one first. Also check the plugin is ticked in **Tools → More tools → Plugin management**.

**The entry is under Settings, not Screen.** Your menu is missing the **Screen** section, which happens with menu-customising plugins such as Simple UI or Menu Customizer. The plugin places itself under **Settings** instead; everything works the same.

**Lock screen doesn't change.**
1. Tap **Update now**. It lists each file as written or says why not.
2. Make sure the built-in **Cover image** plugin is turned off. If its output path is one of the Line files, it overwrites them.
3. If the files are current but the screen isn't, restart the device.

**Sleep cover or double-click shows an old image.** Check that **Refresh sleep-cover image** is on. These locks are drawn by the firmware's `taskmgr.app`, which keeps a copy of the image; other PocketBook users report the same ([MobileRead thread](https://www.mobileread.com/forums/showthread.php?t=359223)). The plugin asks it to reload after each update. Locking by timeout always reads the current file.

**Lock screen is one step behind right after a page turn.** The image is written 1 second after your last page turn; lock within that second and you see the previous one. Set **Update delay** to 0 to narrow the gap.

**Front light is off after waking, or the device won't wake from a double-click.** Both were caused by version 1.14 asking the firmware to reload the image while the device was going to sleep; fixed since 1.15. If either happens, turn off **Refresh sleep-cover image** and report it.

**Time or battery on the lock screen is out of date.** Expected: placeholders are filled in at the last update, not at sleep.

**Lock screen is blank or shows the default image.** On another model, the firmware may not accept the 24-bit BMPs the plugin writes. Try `GRAYSCALE = true` at the top of `main.lua`, which writes 8-bit.

**Something else went wrong.** If the plugin catches an error in its menu, it writes the details to `/mnt/ext1/applications/koreader/coverprogress_crash.log` and keeps KOReader running. KOReader's own `crash.log` in the same folder lists every image write with its reason, for example `CoverProgress: wrote (page turn) 52%`.

### Restoring the stock screens

- **Lock screen:** turn off **Enabled**, then delete `taskmgr_lock_background.bmp` and `taskmgr_lock_background_landscape.bmp` from `system/resources/Line/`. If you had your own images there before, rename the `.orig` files back instead.
- **Power-off screen:** set **Power-off screen** to **Off**, and choose another power-off logo in the PocketBook settings.
- **Startup screen:** turn off **Startup screen: book cover**, and choose another startup logo in the PocketBook settings.

---

## Other PocketBook models

Only the Era Lite has been tested. Other models should work, because the image size comes from the device's screen and the lock screen files have the same names on every model. For reference, the sizes per model, from [Cyfranek's guide](http://cyfranek.booklikes.com/post/5815379/poradnik-wlasna-grafika-usypiania-dla-czytnikow-pocketbook) (2023, in Polish):

| Models | Portrait image (w×h) |
| --- | --- |
| Aqua, Basic, Basic 2, Basic 3, Basic Touch, Basic Touch 2, Touch, Mini | 600×800 |
| Touch Lux, Touch Lux 2–5, Sense, Ultra, Basic Lux, Basic Lux 2–4, Aqua 2, Empik GoBook | 758×1024 |
| InkPad, InkPad 2 | 1200×1600 |
| Touch HD, Touch HD 2, Touch HD 3, Color | 1072×1448 |
| InkPad 3, InkPad 3 Pro, InkPad X, InkPad Color, InkPad Color 2, InkPad 4 | 1404×1872 |
| InkPad Lite | 825×1200 |
| Era, Era Lite | 1264×1680 |

What may differ on other models or firmware: whether the sleep-cover refresh works (it depends on the firmware's `taskmgr.app`), the power-off copy's format, and which BMP bit depth the lock screen accepts. If you try another model, please report what works.

A firmware update may remove the lock screen files; the plugin writes them again the next time you read.

---

## For advanced users

### Settings keys

Stored in `settings.reader.lua` in KOReader's settings folder. Fully exit KOReader before editing by hand, or your changes are overwritten.

| Key | Default | Notes |
| --- | --- | --- |
| `coverprogress_enabled` | *(unset)* | Set by **Enabled** |
| `coverprogress_path` | `/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp` | Lock screen image; a `_landscape` copy is written beside it |
| `coverprogress_mode` | `"margin"` | `margin`, `below`, `overlay`, `none` |
| `coverprogress_background` | `"auto"` | `white`, `black`, `auto` |
| `coverprogress_auto_ratio` | `50` | Auto threshold, percent |
| `coverprogress_debounce` | `1` | Update delay, seconds |
| `coverprogress_message` | `""` | Sleep screen message; placeholders allowed |
| `coverprogress_message_container` | `"box"` | `box`, `banner` |
| `coverprogress_message_position` | `50` | 0 bottom – 100 top |
| `coverprogress_show_page` | *(unset)* | Page number above the bar |
| `coverprogress_notify_taskmgr` | *(unset = on)* | Refresh sleep-cover image |
| `coverprogress_offlogo` | *(unset = off)* | Power-off screen on |
| `coverprogress_offlogo_mode` | `"cover"` | `cover` or `sleep` (same as sleep screen) |
| `coverprogress_startup_logo` | *(unset = off)* | Startup screen on |
| `coverprogress_offlogo_key` / `coverprogress_startup_key` | *(set by plugin)* | What was last written, so the same book isn't written again |
| `coverprogress_backup_checked` | *(set by plugin)* | Files already checked for a `.orig` backup |

### Tunables

Constants at the top of `main.lua`:

| Constant | Default | Purpose |
| --- | --- | --- |
| `GRAYSCALE` | `false` on PocketBook | `true` writes 8-bit BMPs instead of 24-bit |
| `BAND_HEIGHT_PCT` | `8` | Height of the progress bar's band, % of screen height |
| `BAR_THICKNESS` | `10` | Bar height |
| `PCT_FONT_SIZE` | `20` | Percentage text size |
| `BAND_RULE` | `false` | Thin line above the band |
| `FIT_TO_COVER` | `true` | Aligns the bar to the cover rather than the screen |
| `OVERLAY_BAR_W_PCT` | `42` | Overlay layout: block width, % of cover width |
| `OVERLAY_FIND_QUIET` | `true` | Overlay layout: search for a strip free of lettering |
| `AUTO_BG_LUMA` | `110` | Darkness threshold for Auto background. Don't raise it much past 130: pale covers sit around 140 and would all count as dark |
| `TITLE_FONT` / `TITLE_SIZE` | `"cfont"` / `36` | Title for books without a cover |
| `TITLE_MAX_W_PCT` | `80` | Title width before it wraps, % of screen width |
| `MESSAGE_FONT` | `"infofont"` | Message font |
| `MESSAGE_MAX_W_PCT` | `80` | Message box width limit, % of screen width |

### Developer notes

[AGENTS.md](AGENTS.md) describes how the plugin works and what was found about the PocketBook firmware. The shell scripts in [tools/](tools/) were run on the device during that investigation and are not part of the plugin. All but one only read and report; `pbtest.sh` sends the firmware the same reload event the plugin does.

---

## Licence

[AGPL-3.0](LICENSE), the same licence as KOReader. This plugin is derived from KOReader's Cover image plugin, which is AGPL-3.0, so modified copies must stay under it.
