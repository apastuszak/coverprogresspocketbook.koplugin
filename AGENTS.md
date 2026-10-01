# AGENTS.md

## What this is

`coverprogresspocketbook.koplugin` is a KOReader plugin, shown in KOReader as "Cover Image PocketBook".
It is derived from KOReader's stock Cover Image plugin (`plugins/coverimage.koplugin` in
github.com/koreader/koreader). It writes the current book's cover to an image file that the device
shows when locked, and adds:

- a progress bar, in one of four layouts (`margin`, `below`, `overlay`, `none`)
- page numbers (`margin` layout only)
- a sleep screen message with KOReader's placeholders, in a box or a banner

The owner's device is a PocketBook Era Lite (PB710). On PocketBook it writes the Line theme's
lock screen, in portrait and landscape. It still runs on Android, Kobo and the desktop emulator,
where it writes a single `cover.jpg` as before.

The image is written ahead of time, while reading. Whatever it shows is only as fresh as the last write.

## Layout

```
coverprogresspocketbook.koplugin/
  _meta.lua   fullname and description shown in Plugin management
  main.lua    the whole plugin
README.md     user documentation (install, device setup, menu, settings keys, tunables)
LICENSE       AGPL-3.0, as KOReader; required because main.lua is derived from coverimage.koplugin
tools/        shell scripts run on the device to investigate firmware behaviour (not shipped)
```

There are no tests in the repo (see Testing).

## Names: do not change casually

- Plugin name `coverprogresspocketbook` must match in two places: the folder name and `name` in
  `main.lua`. Do not add `name` to `_meta.lua`: KOReader v2026.07 warns that it is deprecated
  and ignores it.
- Settings keys stay `coverprogress_*`, along with the menu key `menu_items.coverprogress` and the
  crash log `coverprogress_crash.log`. They predate the rename; changing them loses the user's saved settings.

## How `main.lua` works

- **Targets.** `outputTargets()` returns one entry per image: the main path, plus a `_landscape`
  copy when `WRITE_LANDSCAPE` is set (PocketBook only). `getTargetSize(landscape)` gives the size
  of each.
- **Base images.** `buildBase()` gets the cover once and calls `placeCover()` for each target, or
  `placeTitle()` when the book has no cover (bold title on the plain background, built as
  `TYPE_BBRGB24` because the BMP writer keeps the buffer's bit depth). It
  stores `self.bases = { {path, landscape, bb, rect}, ... }`. Portrait is built first; it makes the
  auto background decision (`decideAutoBackground`), which landscape reuses. `freeBase()` frees all
  bases and clears `last_sig`.
- **Rendering.** `render(force)` builds a change signature: the displayed percent, the expanded
  message, and the page if shown. It returns early if the signature is unchanged and `force` is not
  set. Otherwise it calls `writeImage()` for each base:
  - copy the base
  - draw the bar with `drawBand` (`margin`/`below`) or `drawOverlay` (`overlay`)
  - draw the message with `drawMessage`
  - write `<path>.tmp`, check it with `fileLooksComplete`, call `backupOriginal`, then rename into place

  `self.cover_rect` is set per target during drawing; the draw functions read it.
- **Message.** `expandedMessage()` passes `self.message` through `self.ui.bookinfo:expandString()`.
  This is the same function as KOReader's own sleep screen, so all its placeholders work. If that
  function is missing, the text is used unexpanded. `drawMessage()` lays out the box or banner.
  Position runs from 0 (bottom) to 100 (top); in the bar layouts the message stays above the band.
- **Triggers:**
  - `onReaderReady`: rebuild.
  - `onPageUpdate` / `onPosUpdate`: render after the update delay (`coverprogress_debounce` seconds)
    via `scheduleRender`.
  - `onSuspend`: unforced render. It writes only a change still waiting on the update delay; the
    write is too late for the lock that triggers it, so forcing it only rewrote identical files.
  - `onCloseDocument`: forced render.
  - `onFlushSettings`: unforced render, which writes a pending change at once and skips an
    unchanged image (settings are flushed periodically and on suspend).
  - `onSetRotationMode`: rebuild, except with `WRITE_LANDSCAPE` (PocketBook), where the output
    doesn't depend on rotation.
  - Menu changes: `rebuild()` if the base image changes (layout, background), `renderNow(true)` if
    only the overlay changes (message settings).
- **Error containment:**
  - Rendering runs under `pcall` in `safeRender`.
  - The menu is built under `xpcall`. Every menu function field is wrapped by `cpWrapMenuTree`,
    which logs errors to `coverprogress_crash.log` and swallows them.
  - `cpSafeSortingHint` keeps the menu from referencing a missing "screen" section, which crashes
    KOReader's core menu code.

  A screensaver plugin must never be able to crash the reader; keep new code inside these guards.
- **Legacy:** a saved `coverprogress_mode = "kobo"` is mapped to `"none"` in `init()`. The old
  header text and Kobo-style box were replaced by the message.

## PocketBook specifics (do not break)

- **Output path:** `/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp` and
  `taskmgr_lock_background_landscape.bmp`. The format comes from the file extension.
  `coverprogress_path` overrides the main path, and the landscape path is derived from it.
  These files override the stock lock screen when present, and deleting them restores it. The
  folder does not exist on a fresh device, so `writeImage()` creates it on PocketBook
  (`util.makePath`). Path, names and behaviour are the same on all models, per
  [Cyfranek's guide](http://cyfranek.booklikes.com/post/5815379/poradnik-wlasna-grafika-usypiania-dla-czytnikow-pocketbook)
  (2023, Polish; the live site times out, so use the Wayback Machine copy).
- **Size:** use `Screen:getScreenWidth()/getScreenHeight()` (the physical panel), not
  `getWidth()/getHeight()`. Sizes are normalised to short×long for portrait and long×short for
  landscape, so KOReader's current rotation doesn't matter. The guide's per-model table
  (600×800 up to 1404×1872, Era 1264×1680) is exactly each model's panel resolution, so there is
  no per-model table in the code. Don't add one.
- **Backups:** `backupOriginal()` copies the theme's original file to `<path>.orig` before the first
  overwrite. It records each path in `coverprogress_backup_checked`, so the plugin's own output is
  never backed up by mistake. Never overwrite an existing `.orig`. If an existing file can't be
  copied, `backupOriginal()` returns false, the path stays unchecked, and `writeImage()` does not
  overwrite the file.
- **No `iv2sh`:** this plugin does not call `iv2sh WriteStartupLogo`; that sets the startup logo,
  which is the stock plugin's job. Any shell call added later must quote paths with
  `util.shell_escape`.
- **Unverified:**
  - whether the firmware rereads the lock-screen file on every lock or caches it
  - which BMP format the firmware accepts. The theme's own files (and the stock plugin's output)
    are 24-bit 1264×1680, 6.4 MB, so `GRAYSCALE` is false on PocketBook to match. It only affects
    BMP output.
- **Legacy path:** `init()` drops a saved `coverprogress_path` equal to `<data dir>/cover.jpg` on
  PocketBook. Older versions saved that value, and it would override the Line default.
- **Stock plugin conflict:** if the stock Cover image plugin's path points at the Line file, both
  plugins write it (seen on the owner's device). The stock one should be disabled.
- **Lock timing (confirmed on the Era Lite):** the firmware reads the lock-screen file as it
  locks. KOReader's `Suspend` event does reach the plugin (PocketBook's `powerd:beforeSuspend()`
  calls `Device:_beforeSuspend()`, which broadcasts it), but the write it triggers lands too late
  to be shown. A timeout lock showed the new image, an immediate double-click lock did not. So the
  file must already be current before the lock: `DEBOUNCE_SECONDS` is 1 on PocketBook (5 elsewhere).
  Don't rely on `onSuspend` for freshness. Every write and skip is logged at INFO with its trigger
  ("page turn", "suspend", ...), which shows up in the device's `crash.log`.
- **Sleep cover and double-click lock show a cached image (Era Lite, firmware 6.11):** these locks
  are drawn by `/ebrmain/cramfs/bin/taskmgr.app` (the only firmware binary that names
  `taskmgr_lock_background`), which loads the image once and keeps it until reboot. The timeout lock
  reads the file itself. Overwriting the file in place (v1.12, reverted) and restarting KOReader do
  not refresh the copy. Sending taskmgr.app `EVT_CONFIGCHANGED` (154) does (confirmed by the owner
  over several cover and double-click locks with v1.14):
  `iv2sh SendEventTo <taskmgr.app pid> 154 0` (the "task ID" `FindTaskByAppName` returns is the
  process ID). `NOTIFY_TASKMGR` / `notifyTaskManager()` does this after every successful write, in
  the background, with a fixed command string. It is skipped for writes made while going to sleep
  (`NO_NOTIFY_REASONS`: "suspend", "settings flush"). Sending it at that moment (v1.14) left the
  front light off after waking, and sometimes the device would not wake from a double-click lock;
  skipping it for those writes (v1.15) fixed both (confirmed on the Era Lite). Never send it from
  the sleep path.
  Users can switch it off ("Refresh sleep-cover image", `coverprogress_notify_taskmgr`).
  A skipped reload sets `notify_pending`, and the next allowed trigger sends it even when the image
  is unchanged, so a write made while going to sleep can't leave the sleep cover out of date. Also reported in
  https://www.mobileread.com/forums/showthread.php?t=359223, where nobody had a fix. The diagnostic
  scripts used to find this are in `tools/` (`pbinfo.sh`, `pbprobe.sh`, `pbtest.sh`); run them from
  KOReader's file browser (long-press, Execute shell script).
- **Write volume:** writes land on internal flash. Keep them throttled, and skip them when the
  signature is unchanged. Placeholders that change often (`%m` clock) cause frequent rewrites by design.

## KOReader API notes

- **Freeing image buffers:** `RenderImage:scaleBlitBuffer(bb, w, h)` frees `bb` unless the fourth
  argument is `false`. It returns the same buffer when no scaling is needed. Free only the returned
  buffer. `buildBase` passes `cover_bb:copy()` into each `placeCover` and frees the original once.
- **Write results:** `Blitbuffer:writeToFile()` wraps the writer in `pcall` and returns its status.
  It does not throw.
- **Garbage collection:** Blitbuffers have an `ffi.gc` finalizer, but free them explicitly anyway;
  they are full-screen sized.
- **Placeholder help:** `FileManagerBookInfo.expandString` called with no instance shows the
  placeholder help. The message dialog's Info button relies on this, and the button is hidden when
  the function is missing.

## Testing

There is no KOReader runtime here and no test harness in the repo. Checks available:

```
luajit -e 'assert(loadfile("coverprogresspocketbook.koplugin/main.lua")); assert(loadfile("coverprogresspocketbook.koplugin/_meta.lua")); print("ok")'
```

For behaviour, run `main.lua` under LuaJIT with `require` stubbed for the KOReader modules it
uses. The stubs needed are:

- `device`, `ffi/blitbuffer`, `datastorage`, `apps/filemanager/filemanagerbookinfo`
- `ui/font`, `ui/renderimage`, `ui/widget/textwidget`, `ui/widget/textboxwidget`
- `ui/widget/infomessage`, `ui/uimanager`, `ui/widget/container/widgetcontainer`
- `logger`, `util`, `gettext`, `ffi/util`
- a `G_reader_settings` global

Then drive the event handlers and check:

- file paths and sizes
- the change signature skipping writes
- message placement
- that no buffers leak

Such a mock checks control flow only. Anything about layout, fonts, BMP format or the lock screen
must be verified on the device.

## Packaging

```
zip -r coverprogresspocketbook.koplugin.zip coverprogresspocketbook.koplugin
```

Install by copying the folder into `koreader/plugins/`, after deleting any older copy such as
`coverprogress.koplugin`. Two copies would write the same files. Disable the stock "Cover image"
plugin unless its startup-logo output is wanted and its path differs.

## Conventions

- Never add dependencies outside KOReader's own modules.
- Keep non-PocketBook behaviour unchanged unless asked; gate PocketBook-only behaviour on `Device:isPocketBook()`.
- Match the existing style: tunables as upper-case locals at the top of `main.lua`, comments that
  explain why, and settings read in `init()` into fields on `self`.
- When adding a menu item or setting, update the README's menu reference, settings keys table and,
  if relevant, tunables table.
- Add a short version note at the top of `main.lua` for user-visible changes.
