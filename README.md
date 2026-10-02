# Cover Image PocketBook

A KOReader plugin (`coverprogresspocketbook.koplugin`) that puts the cover of the book you're reading on your device's lock screen. It can add a reading-progress bar and a sleep screen message, such as the title, percent read, time left or battery level.

Open a book, lock the device, and the lock screen shows that book's cover and how far through it you are. As you read, the image updates.

Works on **PocketBook** (written to the Line theme's lock screen), **Android e-readers** (Bigme, Onyx, Tolino and similar), **Kobo**, and the KOReader desktop emulator.

<img width="752" height="978" alt="Lock screen showing a book cover with a progress bar" src="https://github.com/user-attachments/assets/81502cd1-0bf7-46d8-afe3-c3f65f533037" />

---

## How it works

KOReader ships a built-in plugin, `coverimage`, that writes the current book's cover to an image file when you open a book. This plugin builds on it:

- draws a **reading-progress bar** onto the cover, in one of **four layouts** suited to different screen shapes
- draws an optional **sleep screen message** using KOReader's placeholders (title, percent, time left, battery, ...)
- **refreshes as you read**, not only when a book is opened
- on PocketBook, writes **portrait and landscape** lock screens as BMP, and **backs up** the theme's originals first
- picks a **light or dark background per book** by analysing the cover
- writes **atomically**: to a temporary file that is checked, then renamed into place

The image is written ahead of time, while you read. The lock screen shows whatever was last written.

Derived from KOReader's `coverimage` plugin.

---

## Installation

Download [this repository](https://github.com/apastuszak/coverprogresspocketbook.koplugin) (**Code → Download ZIP**) and extract it. Inside the extracted `coverprogresspocketbook.koplugin-main` folder is the plugin folder, `coverprogresspocketbook.koplugin`. Copy that inner folder, not the outer one, into KOReader's `plugins/` directory:

| Platform | Path |
| --- | --- |
| PocketBook | `/mnt/ext1/applications/koreader/plugins/` |
| Android | `/storage/emulated/0/koreader/plugins/` |
| Kobo | `/mnt/onboard/.adds/koreader/plugins/` |
| Kindle | `/mnt/us/koreader/plugins/` |
| Desktop emulator | `koreader/plugins/` in your build |

If you have an older copy named `coverprogress.koplugin`, **delete it first**. Otherwise KOReader loads both, and they write the same files.

Restart KOReader. Then **open a book** (the settings menu only exists inside a book, not in the file browser) and go to:

**Menu (gear icon) → Screen → Cover Image PocketBook → Enabled**

The image is written immediately. By default it goes to:

- PocketBook: `/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp` and `taskmgr_lock_background_landscape.bmp`
- Android: `/storage/emulated/0/cover.jpg`
- Everything else: `cover.jpg` in the KOReader data directory (on Kobo, `/mnt/onboard/.adds/koreader/cover.jpg`)

### The built-in `coverimage` plugin

- **Android, Kobo and others:** disable it under **Tools → More tools → Plugin management**. Both plugins write the same `cover.jpg` by default. With both enabled they can write at the same moment, which can produce a truncated image with a grey band across the bottom.
- **PocketBook:** this plugin writes the lock screen files, not `coverimage`'s output, so the two don't collide. Keep `coverimage` only if you also want the cover as the startup logo. Otherwise disable it, so each book open doesn't write a second image.

---

## Device setup

### PocketBook

Tested on an Era Lite (PB710). Other models should work the same way, but have not been tried.

The firmware shows `/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp` as the lock screen when that file exists, and `taskmgr_lock_background_landscape.bmp` in landscape. Deleting them brings back the stock image. That folder does not exist on a device where nobody has added a lock screen before, so the plugin creates it.

1. Open a book and enable the plugin. It writes a portrait and a landscape BMP at the screen's size, whatever KOReader's rotation
2. Choose **Progress bar below cover** or **No progress bar**. On most PocketBook screens the cover fills the full height, so the margin and overlay layouts draw the bar over the artwork
3. Lock the device to check. Open a different book and lock again; the cover should follow

The image size is taken from the device's screen, so no per-model setting is needed. For reference, the sizes per model (from [Cyfranek's guide](http://cyfranek.booklikes.com/post/5815379/poradnik-wlasna-grafika-usypiania-dla-czytnikow-pocketbook), 2023, in Polish):

| Models | Portrait image (w×h) |
| --- | --- |
| Aqua, Basic, Basic 2, Basic 3, Basic Touch, Basic Touch 2, Touch, Mini | 600×800 |
| Touch Lux, Touch Lux 2–5, Sense, Ultra, Basic Lux, Basic Lux 2–4, Aqua 2, Empik GoBook | 758×1024 |
| InkPad, InkPad 2 | 1200×1600 |
| Touch HD, Touch HD 2, Touch HD 3, Color | 1072×1448 |
| InkPad 3, InkPad 3 Pro, InkPad X, InkPad Color, InkPad Color 2, InkPad 4 | 1404×1872 |
| InkPad Lite | 825×1200 |
| Era, Era Lite | 1264×1680 |

The landscape file is the same size turned sideways. The same guide notes that a firmware update may remove these files. While this plugin is enabled, it writes them again the next time you read.

If either file already exists, it is copied to `<name>.bmp.orig` before the plugin first overwrites it. To go back to the stock lock screen, disable the plugin and delete both `.bmp` files. To get back a custom image you had before, rename its `.orig` file back instead.

#### Power-off and startup screens

Two optional settings, off by default, put the book on two more PocketBook screens. The startup screen shows the cover alone, with no progress bar or message (or the title for a book without a cover). The power-off screen can show the cover alone, or the same image as the sleep screen.

- **Power-off screen** offers **Off**, **Book cover only** or **Same as sleep screen**. In the PocketBook settings, set the power-off logo to **Custom image** and choose the matching file: `system/logo/offlogo/cover.bmp` for *Book cover only*, which the plugin writes when a different book is opened, or `system/resources/Line/taskmgr_lock_background.bmp` for *Same as sleep screen*, which follows the sleep screen, progress bar and message included. The firmware converts a custom image only once, when you pick it, into its own copy (`offlogo/pb_offlogo.bmp`, a 4-bit greyscale BMP) and shows that copy at power-off; so the plugin also writes the new image straight into that copy each time. With *Same as sleep screen* that copy (about 1 MB) is rewritten whenever the sleep screen is. The **Book Cover** option does not work with KOReader.
- **Startup screen: book cover** sets the screen shown while the device starts, using the firmware's `iv2sh WriteStartupLogo`, as KOReader's built-in Cover image plugin does. This is stored in the device's flash memory, so it is only written when a different book is opened.

Both are written when a book is opened, and only when the image would change. They are never written while the device is going to sleep or when a book closes; an automatic power-off closes the book, and a startup-screen write cut off by the power going out could leave it damaged. If you use either, keep the built-in Cover image plugin turned off, since it writes the same file and startup screen.

### Bigme (HiBreak, HiBreak Pro, B-series tablets)

Tested on a HiBreak Pro BW; the process is the same across Bigme's Android devices.

1. In KOReader, enable the plugin as above and confirm `/storage/emulated/0/cover.jpg` now exists
2. Open the **ScreenSaver** app
3. Select **Picture mode**
4. **Select image → Single Image mode**
5. **Add image → tap Camera Roll** at the top
6. Choose the album named **"unknown"**. That's `cover.jpg` in the root of internal storage; it shows as unnamed because it isn't inside a named folder like Pictures or Downloads
7. Select it

Lock the device to check. Open a different book and lock again; the cover should follow.

If you'd rather the file lived somewhere tidier, set `coverprogress_path` (see [Settings keys](#settings-keys)) to something like `/storage/emulated/0/Pictures/Wallpaper/cover.jpg`. The folder must already exist, and it will then show up as a properly named album in the ScreenSaver app.

**On Bigme tablets** (B6, B7 and similar) choose **Progress bar below cover**. Tablet screens are wide enough that a portrait cover reaches the bottom edge, so the default layout would put the bar on top of the artwork. See [Layouts](#layouts).

### Kobo

1. Copy the plugin to `/mnt/onboard/.adds/koreader/plugins/` and restart KOReader
2. Open a book and enable the plugin. The image is written to `/mnt/onboard/.adds/koreader/cover.jpg`
3. Go to **Menu → Sleep Screen → Wallpaper → Show custom image** and point it at that file
4. In the same **Sleep Screen** settings, turn off KOReader's own **sleep screen message**, or it prints its text over the image. Use this plugin's [sleep screen message](#sleep-screen-message) instead

Kobo screens are around 0.75 aspect ratio, so **Progress bar below cover** is usually the better choice here too.

### Other Android e-readers

Onyx, Tolino and others have a file-based screensaver setting somewhere in their system settings. Point it at the output path. Tolino devices conventionally read `/sdcard/suspend_others.jpg`, so setting `coverprogress_path` to that may work without touching any system setting.

---

## Layouts

Choose under **Screen → Cover Image PocketBook**. Which one suits you depends on your screen's aspect ratio compared with a typical 2:3 book cover.

### Progress bar in the margin *(default)*

The cover stays centred at full size and the bar sits in the empty band below it.

Best on **tall screens**, such as e-ink phones like the HiBreak Pro (0.50 aspect). There a portrait cover is limited by width and cannot reach the bottom edge, so nothing is drawn over the artwork. On wider screens, including most PocketBooks and Kobos, the cover fills the height and the bar covers its bottom edge.

This layout also supports a **page number** above the bar. See [Page number](#page-number).

### Progress bar below cover

The cover is shrunk slightly and raised to make room for the bar underneath.

Use on **wider screens**: PocketBooks, Kobos and tablets, around 0.75 aspect, where a cover is limited by height and runs to the bottom edge. Space for the bar is reserved *before* the cover is scaled, so the bar can never land on artwork whatever the screen shape. The trade-off is that the cover sits a few percent higher than dead centre.

### Progress bar overlays cover

Full-bleed cover with a compact bar and percentage drawn on top, near the bottom right.

Two things keep it readable:

- **It avoids lettering.** It searches upward for the flattest strip it can find, scoring each candidate by how much the brightness varies. Text and detail vary a lot whether they're light or dark; plain areas vary little.
- **It picks one colour.** Once the position is chosen, it samples it once and uses a single colour for both the bar and the percentage, so you never get a white bar beside a black number.

### No progress bar

The cover at full size with nothing drawn on it, apart from the sleep screen message if you set one. Pair it with a message such as `%p% read · %H left` to show progress as text, as Kobo's own sleep screen does. (This replaces the earlier "Kobo style box" layout; a saved `kobo` setting is treated as this one.)

---

## Sleep screen message

Text drawn on the image, like KOReader's sleep screen message on Kobo and Kindle. Set it under **Sleep screen message → Message**; leave it empty for none. It can span several lines.

The text goes through KOReader's own placeholder expansion, so every code KOReader's sleep screen supports works here. Tap **Info** in the edit dialog for the list:

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

For example, `%T\n%p% read · %H left` shows the title, with the percentage and time left on a second line.

Style and placement:

- **Box**: a bordered box, as wide as the longest line, up to 80% of the screen
- **Banner**: a full-width strip
- **Vertical position**: 0 is the bottom, 100 the top. In the bar layouts the message stays above the bar

The message uses the background colour, with text and border in the opposite colour. See [Background](#background).

**Placeholders are filled in when the image is written, not when the device sleeps.** Book and progress placeholders are always current, because they only change when you turn a page. Time, date and battery show their value at the last write. The image is rewritten whenever the filled-in text changes, so a clock (`%m`) means a rewrite every minute you read. See [Battery and write frequency](#battery-and-write-frequency).

### Time remaining

`%H` and `%h` come from KOReader's **statistics** plugin, as on KOReader's own sleep screen. They need that plugin enabled and some reading history for the book. Without them the placeholder shows "N/A".

---

## Books without a cover

If a book has no cover image, the plugin draws its title in bold, centred on the plain background, wrapping onto more lines if it is long. The progress bar and sleep screen message are added as usual. The title is the one KOReader shows for the book, or the file name if there is none.

## Page number

Toggle **Show page number** (margin layout only) to print "page X of Y" above the progress bar. The count is KOReader's page count for the open document, so on a reflowable EPUB it reflects your current font size rather than the print edition.

**This changes how often the image is written.** Normally the image is only rewritten when the whole displayed percentage changes, so turning several pages within the same percent writes nothing. The page number changes on every page turn, so with it shown the image is rewritten on every page turn too. The menu warns about this.

---

## Background

Sets the colour behind the cover, the progress bar and the message box. Bar, border and text always take the opposite colour.

- **White background, black text**
- **Black background, white text**
- **Auto** *(default)*: decided per book from the cover itself

### How Auto decides

It counts what fraction of the cover's pixels are darker than a threshold, and goes black if that fraction exceeds a percentage you can set.

Counting dark pixels works better than averaging them, because covers are often pale stock with heavy black artwork, which averages out to a misleading mid-grey. Measured across five real covers, the average called them all light; the dark-fraction test separated them correctly.

The menu shows the measurement for the open book, e.g. *"Auto background (now: white, cover 25% dark)"*, so you can read the actual figure before deciding where to put the threshold. **Auto: go black above N% dark** adjusts it between 10 and 90.

If a cover is being classified wrongly, read its percentage from the menu and set the threshold either side of it.

---

## Battery and write frequency

The plugin only runs while KOReader is open. While the device is asleep it uses no power; the firmware just shows the file that's already there.

While you read, each write draws the image and saves it. On PocketBook that's two BMPs at panel size. With default settings, writes happen:

- when you open a book
- after each whole-percent change, a few seconds after your last page turn
- when you close the book
- when the device locks, but only if a change was still waiting on the update delay

That is infrequent compared with screen refreshes and page rendering, which dominate battery use while reading. When KOReader saves its settings, an unchanged image is not rewritten.

These options increase writes:

| Option | Effect |
| --- | --- |
| **Show page number** | A write after every page turn |
| `%m` / `%M` in the message | A write every minute (every second for `%M`) while reading |
| `%h` / `%H` in the message | A write whenever the estimate changes, which can be every page or two near the end of a chapter |
| `%b` / `%B` in the message | A write whenever the battery percentage drops |

To keep writes, and wear on the device's storage, to a minimum, leave page numbers off and keep time placeholders out of the message.

---

## Menu reference

| Entry | Purpose |
| --- | --- |
| Enabled | Turns image writing on or off |
| Progress bar in the margin | Layout for tall screens *(default)* |
| Progress bar below cover | Layout for wider screens, including PocketBook and Kobo |
| Progress bar overlays cover | Compact bar on a full-bleed cover |
| No progress bar | Cover only; pair with a message |
| Sleep screen message | Message text, Box / Banner, Vertical position |
| Show page number | "page X of Y" above the bar; margin layout only. Writes on every page turn |
| White / Black / Auto background | Colour scheme; Auto shows its measurement |
| Auto: go black above N% dark | Auto sensitivity, 10–90% |
| Output: *path* | Shows where the image is written (both files on PocketBook) |
| Update delay: N s | Wait after the last page turn before rewriting, 0–60 s |
| Power-off screen | PocketBook only. *Off* (default), *Book cover only* (written when a different book is opened; pick `system/logo/offlogo/cover.bmp` as the Custom image) or *Same as sleep screen* (follows the sleep screen; pick the Line `taskmgr_lock_background.bmp`). Also written into the firmware's copy, `pb_offlogo.bmp` |
| Startup screen: book cover | PocketBook only, off by default. Sets the cover alone as the startup screen, via `iv2sh WriteStartupLogo`, when a different book is opened |
| Refresh sleep-cover image | PocketBook only, on by default. After each update, tells the firmware to reload the lock image, so the sleep cover and double-click locks show it |
| Update now | Rebuilds and writes immediately |

---

## Settings keys

Stored in `settings.reader.lua` in your KOReader settings directory. Fully exit KOReader before editing by hand, or your changes will be overwritten on the next autosave.

| Key | Default | Notes |
| --- | --- | --- |
| `coverprogress_enabled` | *(unset)* | Set by the menu toggle |
| `coverprogress_path` | platform-dependent | Output file; folder must already exist. On PocketBook a `_landscape` copy is written beside it |
| `coverprogress_mode` | `"margin"` | `margin`, `below`, `overlay`, `none` |
| `coverprogress_background` | `"auto"` | `white`, `black`, `auto` |
| `coverprogress_auto_ratio` | `50` | Auto threshold, percent |
| `coverprogress_debounce` | `1` on PocketBook, `5` elsewhere | Update delay, seconds |
| `coverprogress_message` | `""` | Sleep screen message; placeholders allowed |
| `coverprogress_message_container` | `"box"` | `box`, `banner` |
| `coverprogress_message_position` | `50` | 0 bottom – 100 top |
| `coverprogress_show_page` | *(unset)* | Show page number; writes on every page turn |
| `coverprogress_offlogo` / `coverprogress_startup_logo` | *(unset = off)* | PocketBook: write the power-off / startup screen |
| `coverprogress_offlogo_mode` | `"cover"` | Power-off screen: `cover` (cover alone) or `sleep` (same as the sleep screen) |
| `coverprogress_offlogo_key` / `coverprogress_startup_key` | *(set by plugin)* | What was last written, so the same book isn't written again |
| `coverprogress_notify_taskmgr` | *(unset = on)* | PocketBook: send the lock-image reload after each update |
| `coverprogress_backup_checked` | *(set by plugin)* | Paths already checked for a `.orig` backup. Remove an entry to back that path up again |

The keys keep the `coverprogress_` prefix from before the plugin was renamed, so existing settings carry over.

The output format is taken from the file extension: `.bmp`, `.png` or `.jpg`. PocketBook's lock screen uses BMP, which is the default there. PNG is worth trying elsewhere if your covers are hard-edged graphic art, which JPEG handles poorly.

---

## Tunables

Constants at the top of `main.lua`, for anything not exposed in the menu.

| Constant | Default | Purpose |
| --- | --- | --- |
| `TARGET_W` / `TARGET_H` | `0` | Output size; `0` uses the screen (the physical panel on PocketBook). Set explicitly if output looks upscaled, or to preview another device's geometry (Bigme B7 is 1264×1680) |
| `WRITE_LANDSCAPE` | PocketBook only | Also writes a `_landscape` image |
| `DEBOUNCE_SECONDS` | `1` on PocketBook, `5` elsewhere | Default update delay. PocketBook needs it short; see [Troubleshooting](#pocketbook-1) |
| `JPEG_QUALITY` | `95` | JPEG only |
| `GRAYSCALE` | `true`; `false` on PocketBook | Greyscale output; affects BMP only. PocketBook gets 24-bit BMPs to match the theme's own files |
| `FIT_TO_COVER` | `true` | Aligns the bar to the cover rather than the screen when the cover doesn't fill the width |
| `BAND_HEIGHT_PCT` | `8` | Height of the progress bar's band, % of output height |
| `BAND_RULE` | `false` | Thin line above the band |
| `BAR_THICKNESS` | `10` | Bar height |
| `PCT_FONT_SIZE` | `20` | Percentage text size |
| `OVERLAY_BAR_W_PCT` | `42` | Overlay block width, % of cover width |
| `OVERLAY_FIND_QUIET` | `true` | Search for a strip free of lettering |
| `OVERLAY_SEARCH_PCT` | `22` | How far up to search, % of cover height |
| `OVERLAY_LOW_BIAS` | `0.03` | Preference for staying near the bottom |
| `AUTO_BG_LUMA` | `110` | Darkness threshold for the Auto decision |
| `AUTO_BG_DARK_RATIO` | `50` | Default Auto percentage |
| `TITLE_FONT` / `TITLE_SIZE` | `"cfont"` / `36` | Title font and size for books without a cover |
| `TITLE_MAX_W_PCT` | `80` | Title width before it wraps, % of output width |
| `MESSAGE_FONT` | `"infofont"` | Message font, as KOReader's sleep screen uses |
| `MESSAGE_MAX_W_PCT` | `80` | Box width limit, % of output width |
| `MESSAGE_PAD` / `MESSAGE_BORDER` | `10` / `2` | Message padding and box border |

**Don't raise `AUTO_BG_LUMA` much past 130.** Pale cover stock commonly sits around luminance 140, so a threshold there flips plainly light covers to dark. Measured on two such covers, the dark fraction jumped from around 2% and 14% at a threshold of 110 to roughly 65% at 140. The 110–130 range is the safe band.

---

## Troubleshooting

### PocketBook

**Lock screen doesn't change.** Work through these in order:

1. Tap **Update now** in the plugin's menu. It lists each file as written or says why not.
2. Check that both `.bmp` files in `/mnt/ext1/system/resources/Line/` have a recent modified time. On a computer the time may look several hours off, most likely because the device stores file times in UTC.
3. Make sure the built-in **Cover image** plugin is disabled, or that its path is not one of these files, so it does not overwrite them.
4. If the files are current but the lock screen still shows an old image, the firmware may only reload them at certain times. Try restarting the device.

**Lock screen is blank or shows the default image.** The firmware may not accept the BMP variant KOReader writes. On PocketBook the plugin writes 24-bit BMPs, which the Era Lite accepts. The guide above describes 8-bit BMPs with a colour palette instead, so if a model rejects the 24-bit file, try `GRAYSCALE = true` in `main.lua`.

**Parts of the lock screen show the page underneath.** In 8-bit lock-screen BMPs, the palette colour #808040 marks transparent areas, which show whatever was on screen before sleep. It is not known whether the firmware does the same for 24-bit files. If it does, a cover pixel of exactly that colour would show through, which is rare and hard to notice on a black-and-white screen.

**Sleep cover or double-click lock shows an old image.** These locks are drawn by the firmware's `taskmgr.app`, which loads the image once and keeps that copy; other PocketBook users report the same ([MobileRead thread](https://www.mobileread.com/forums/showthread.php?t=359223)). After each write, the plugin sends `taskmgr.app` a "settings changed" event through `iv2sh`, which makes it load the new file. Tested on an Era Lite with firmware 6.11. If it doesn't work on your model or firmware, the image still updates when the device restarts, and timeout locks always show the current image. The KOReader log shows `asked taskmgr.app to reload the lock image` after each write.

**Lock screen is one step behind after locking straight after a page turn.** The firmware draws the lock screen from the file as the device locks. The plugin also writes when the device locks, but that write finishes too late to be shown; it is only there for the next lock. So the image has to be written before you lock: the plugin writes 1 second after your last page turn. If you lock within that second, you see the previous image. Set **Update delay** to 0 to shorten the gap further. Locking by timeout is never affected.

**Front light is off after waking, or the device won't wake from a double-click lock.** Both happened in v1.14, when the plugin asked the firmware to reload the lock image while the device was going to sleep. Since v1.15 it no longer does that during sleep, which fixed both on the Era Lite. If it still happens, switch off **Refresh sleep-cover image** and see whether the light stays on. If it does, the reload is the cause; tell me, or leave it off (the sleep cover then shows the image from the last restart).

**Lock screen shows the time or battery from earlier.** Expected: placeholders are filled in at the last write, not at sleep. See [Sleep screen message](#sleep-screen-message).

**Restore the stock lock screen.** Disable the plugin, then delete `taskmgr_lock_background.bmp` and `taskmgr_lock_background_landscape.bmp` from `/mnt/ext1/system/resources/Line/`. If you had your own images there before, rename the `.orig` files back instead.

### All devices

**No menu entry.** The settings only exist inside a book. Open a book first; the entry does not exist in the file browser. Also confirm the plugin is ticked in **Tools → More tools → Plugin management**. That checkbox controls whether the plugin *loads*, which is separate from the Enabled toggle in the Screen menu.

**The entry is under Settings, not Screen (or shows a "NEW:" prefix in the first menu).** Your menu is missing the reader **Screen** section. That happens on some stripped or older builds, and with menu-customising plugins such as **Simple UI** or **Menu Customizer**. They save a menu-order override that persists, so disabling them afterwards does not bring the section back. The plugin detects this and places its entry under **Settings** instead, falling back to the first menu if that is gone too. Everything works the same; only the location differs.

**KOReader crashes the instant you open the reader top menu.** This was a bug in KOReader itself: it crashed when a plugin asked to be placed in a menu section that didn't exist, such as a missing **Screen** section. It wrote no `crash.log`. Fixed from plugin **v1.05**, which checks your actual menu before choosing where to place its entry. If you are on an older build of this plugin and see this, update.

**Plugin ticked in Plugin management but no Screen menu entry.** The plugin was found but failed to load; Plugin management lists plugins from `_meta.lua` alone. Look for `coverprogress_crash.log` in the KOReader data directory (`/mnt/ext1/applications/koreader/` on PocketBook, `/sdcard/koreader/` on Android). If the plugin catches an error while building or using its menu, it writes a traceback there and keeps the reader running. On Kobo and desktop, KOReader's own `crash.log` may also have the reason.

On Android, logcat has the load error:

```
adb logcat -c
```

Restart KOReader, open a book, then:

```
adb shell "logcat -d | grep -i -e coverprogress -e plugin -e lua"
```

A load failure appears as a `.lua:NN:` line naming the file and line number. Android builds do not write `crash.log`, so its absence there means nothing.

**Windows note:** put quotes around the remote command so `grep` runs on the device rather than on Windows. In PowerShell, call `adb.exe` explicitly; a bare `adb` can resolve to an extensionless file in `system32` and fail with *"Cannot run a document in the middle of a pipeline"*.

**Nothing written after a re-push.** `adb push coverprogresspocketbook.koplugin /path/plugins/` copies *into* the destination if it already exists, giving you `plugins/coverprogresspocketbook.koplugin/coverprogresspocketbook.koplugin/`. Check with `ls`, and push as `adb push coverprogresspocketbook.koplugin/. /path/plugins/coverprogresspocketbook.koplugin/` instead.

**Grey band across the bottom of the image.** That's a truncated JPEG; image viewers fill the missing rows with grey. It's usually caused by two plugins writing the same path, so make sure the built-in `coverimage` is disabled. The plugin checks each JPEG is complete before using it and discards bad writes, so the previous good image survives.

**Bar sits on the cover artwork.** Your screen is too wide for the margin or overlay layout, which is the case on PocketBook and Kobo. Switch to **Progress bar below cover**.

**Wrong background colour.** Read the cover's dark percentage from the Auto background menu entry and move the threshold either side of it.

**Cover looks soft or upscaled.** Your screensaver app is rescaling because KOReader reported the app window's size rather than the screen's. Set `TARGET_W` and `TARGET_H` to the screen's true resolution.

---

## Notes

- The image is rewritten shortly after the last page turn (1 s by default on PocketBook, 5 s elsewhere), and immediately on book open and close. When the device locks, a change that was still waiting is written straight away, but an unchanged image is not rewritten. When KOReader saves its settings, any pending update is written straight away, but an unchanged image is not rewritten.
- Errors while drawing the image or using the menu are caught and logged, so a screensaver plugin can never take down the reader. Caught menu errors are written to `coverprogress_crash.log` in the KOReader data directory with a full traceback.
- Menu placement adapts to your actual menu: it prefers the **Screen** section, falls back to **Settings**, then to the first menu, so a menu missing sections can never cause a crash.
- There is no disk cache. The built-in `coverimage` caches by filename and settings, which would serve a stale percentage.
- Writes go to a temporary file and are renamed into place, so the lock screen can never read a half-written image.

## Licence

[AGPL-3.0](LICENSE), the same licence as KOReader. This plugin is derived from KOReader's `coverimage` plugin, which is AGPL-3.0, so modified copies must stay under it.
