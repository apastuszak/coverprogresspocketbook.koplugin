--[[--
@module koplugin.coverprogresspocketbook

v1.21

v1.21: PocketBook: the power-off screen can mirror the sleep screen (cover,
       progress bar and message) instead of showing the cover alone.
v1.20: PocketBook: the power-off screen now works. The cover is also written,
       in the firmware's 4-bit format, into the logo customiser's cache
       (offlogo/pb_offlogo.bmp), which is what the power-off screen shows.
v1.19: PocketBook: optional power-off and startup screens showing just the
       book cover, written when a book is opened, off by default.
v1.18: fewer flash writes on PocketBook: locking no longer forces a rewrite of
       an unchanged image, and rotating the screen no longer rewrites both.
v1.17: a book without a cover gets its title in bold, centred on the plain
       background, instead of the lock screen keeping the previous book.
v1.16: fixes from a full review. A taskmgr.app reload skipped while going to
       sleep is now sent at the next safe moment instead of being lost. A book
       without a cover no longer re-extracts it after every page turn (in
       v1.17 it gets a title image instead). The theme's original image is
       never overwritten if backing it up fails.
v1.15: PocketBook: the taskmgr.app reload is no longer sent for writes made
       while going to sleep (the front light stayed off after waking), and
       can be switched off with "Refresh sleep-cover image".
v1.14: PocketBook: after each write, sends taskmgr.app EVT_CONFIGCHANGED via
       iv2sh, which makes the sleep-cover and double-click lock screen show the
       new image instead of the copy cached at boot.
v1.13: reverts v1.12's in-place overwrite. It did not change what the
       double-click lock shows, which comes from a copy held in memory.
v1.11: PocketBook: the default update delay is 1 s instead of 5 s, because the
       write at lock time is too late for the firmware to show. Every write
       and skipped write is logged with its trigger.
v1.10: PocketBook: creates system/resources/Line if it is missing, as it is
       on a device where no custom lock screen was ever installed.
v1.09: PocketBook: a legacy saved path of <data dir>/cover.jpg is replaced
       by the Line default, and BMPs are written 24-bit like the theme's own.
       "Update now" reports what was written or why not.
v1.08: PocketBook: writes the Line theme lock screen, portrait and landscape,
       as BMP. Adds a sleep screen message with KOReader's placeholders, in a
       box or banner at a chosen height. It replaces the header text and the
       Kobo-style box; a saved "kobo" mode becomes "No progress bar".
v1.07: the Kobo-style info box now slides vertically to avoid the title and
       author on the cover, using the same flat-strip search as the overlay
       bar. It keeps the Kobo left placement and stays near its usual height,
       moving only when a cleaner strip is nearby. Toggle KOBO_FIND_QUIET.
v1.06: the display-mode and background menu entries render as radio buttons
       (mutually exclusive) rather than checkmarks.
v1.05: fixes an instant crash on opening the reader top menu on setups that
       lack the "screen" menu section (stripped builds, or plugins such as
       Simple UI / Menu Customizer, whose persistent menu-order override
       removes it). KOReader's MenuSorter does not guard a sorting_hint whose
       target section is missing and crashes in core during menu assembly. The
       hint is now validated against the effective menu order and falls back to
       "setting", then to a safe orphan, if "screen" is unavailable. Menu build
       is also wrapped with self-logging crash capture (coverprogress_crash.log).

Writes the current book cover, overlaid with reading progress, to an image the
device shows when locked. On PocketBook that is the Line theme's lock screen,
portrait and landscape. Elsewhere it is a fixed path that an external
screensaver app points at.


Derived from KOReader's built-in coverimage.koplugin.
Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0), as KOReader is.
]]

local Device = require("device")

-- The stock coverimage plugin restricts itself to devices with a known
-- external screensaver. This one runs anywhere, which makes a Kobo or the
-- desktop emulator usable as a stand-in for testing other screen shapes.

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local RenderImage = require("ui/renderimage")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen

------------------------------------------------------------------------------
-- Crash capture (added v1.04)
--
-- Android KOReader writes no crash.log, and on mt6765 the logcat buffer the
-- crash screen tails is flooded by the MediaTek GED GPU driver, so the real
-- Lua traceback rotates out before it can be read. This captures it ourselves,
-- via xpcall (whose handler runs BEFORE the stack unwinds, so the traceback is
-- the actual crash stack), and writes it to a file any file manager can find:
--   <koreader data dir>/coverprogress_crash.log   (e.g. /sdcard/koreader/)
-- It also stops a bad menu entry from ever taking KOReader down.
------------------------------------------------------------------------------

local CP_CRASH_LOG = DataStorage:getDataDir() .. "/coverprogress_crash.log"
local cp_unpack = table.unpack or unpack

-- KOReader version string, best-effort. Included in crash logs so a report
-- identifies the build without a separate round-trip.
local CP_KOVER = "?"
do
    local ok, Version = pcall(require, "version")
    if ok and Version then
        local ok2, rev = pcall(function()
            if Version.getCurrentRevision then return Version:getCurrentRevision() end
            if Version.getNormalizedCurrentVersion then return Version:getNormalizedCurrentVersion() end
        end)
        if ok2 and rev then CP_KOVER = tostring(rev) end
    end
end

-- Appends a caught error, with a full traceback, to CP_CRASH_LOG. Only ever
-- called from the crash guards below, so the file exists only if something
-- actually went wrong.
local function cpLogError(where, err)
    logger.err("coverprogress [" .. tostring(where) .. "]: " .. tostring(err))
    local ok, f = pcall(io.open, CP_CRASH_LOG, "a")
    if ok and f then
        f:write(os.date("!%Y-%m-%dT%H:%M:%SZ"),
                "  device=", tostring(Device.model),
                "  koreader=", CP_KOVER,
                "\n  where=", tostring(where), "\n",
                tostring(err), "\n\n")
        f:close()
    end
end

-- Wraps fn so a throw is logged with a full traceback and swallowed, returning
-- `fallback` instead. Extra args and return values are passed through, so it is
-- safe to wrap menu callbacks that receive touchmenu_instance.
local function cpGuard(where, fn, fallback)
    return function(...)
        local n = select("#", ...)
        local args = { ... }
        local res
        local ok, err = xpcall(function()
            res = fn(cp_unpack(args, 1, n))
        end, function(e)
            return tostring(e) .. "\n" .. debug.traceback("", 2)
        end)
        if not ok then
            cpLogError(where, err)
            return fallback
        end
        return res
    end
end

-- Menu fields KOReader may evaluate at build or interaction time. The key-set
-- says which function fields to wrap; the fallback map says what a caught error
-- should return so the entry degrades instead of the whole app dying. A field
-- whose fallback is nil (callbacks) simply becomes a no-op on error.
local CP_MENU_FUNC_KEYS = {
    text_func = true, help_text_func = true,
    checked_func = true, enabled_func = true,
    callback = true, hold_callback = true,
}
local CP_MENU_FUNC_FALLBACK = {
    text_func = "\226\154\160",  -- warning glyph if a label throws
    help_text_func = "",
    checked_func = false,
    enabled_func = false,
}

-- Recursively wrap every menu-func field in a built menu subtree.
local function cpWrapMenuTree(node, path)
    if type(node) ~= "table" then return node end
    for k, v in pairs(node) do
        if type(v) == "function" and CP_MENU_FUNC_KEYS[k] then
            node[k] = cpGuard(tostring(path) .. "." .. tostring(k), v,
                              CP_MENU_FUNC_FALLBACK[k])
        elseif type(v) == "table" then
            cpWrapMenuTree(v, tostring(path) .. "/" .. tostring(k))
        end
    end
    return node
end

-- Some builds, and UI-stripping plugins such as Simple UI, remove reader menu
-- sections. KOReader's MenuSorter does NOT guard a sorting_hint whose target is
-- missing: findById() returns nil and the next line indexes nil.sub_item_table,
-- crashing during menu assembly -- in core, after addToMainMenu has returned, so
-- it cannot be caught by this plugin. Returns the hint only if that section is
-- still present in the effective reader menu order (base order merged with the
-- user override, exactly as MenuSorter:mergeAndSort does); otherwise nil, so the
-- entry orphans into the first menu instead of taking KOReader down.
local function cpSafeSortingHint(candidates)
    -- Merge base order with the user override exactly as MenuSorter:mergeAndSort
    -- does (per-key replace). A persistent override written by Menu Customizer /
    -- Simple UI lives at this same path, so disabling those plugins does not undo
    -- it -- which is why the section stays missing. We read the same effective
    -- order and return the FIRST candidate whose section is both reachable from
    -- the top-level menu buttons AND defined (the two conditions under which
    -- MenuSorter:findById returns a real node instead of nil). If none resolve,
    -- return nil so the entry orphans safely instead of crashing core.
    local merged = {}
    local ok, base = pcall(require, "ui/elements/reader_menu_order")
    if ok and type(base) == "table" then
        for k, v in pairs(base) do merged[k] = v end
    end
    local ok2, user = pcall(dofile,
        DataStorage:getSettingsDir() .. "/reader_menu_order.lua")
    if ok2 and type(user) == "table" then
        for k, v in pairs(user) do merged[k] = v end
    end

    local roots = merged["KOMenu:menu_buttons"]

    local function resolves(hint)
        if type(roots) ~= "table" then
            return merged[hint] ~= nil            -- unknown shape: definition only
        end
        local seen, queue = {}, {}
        for _, id in ipairs(roots) do queue[#queue + 1] = id end
        while #queue > 0 do
            local id = table.remove(queue)
            if id == hint then
                return merged[hint] ~= nil        -- reachable AND defined
            end
            if not seen[id] then
                seen[id] = true
                local children = merged[id]
                if type(children) == "table" then
                    for _, cid in ipairs(children) do queue[#queue + 1] = cid end
                end
            end
        end
        return false
    end

    for _, hint in ipairs(candidates) do
        if resolves(hint) then return hint end
    end
    return nil
end

------------------------------------------------------------------------------
-- Tunables
------------------------------------------------------------------------------

local function defaultPath()
    if Device:isAndroid() then
        return "/storage/emulated/0/cover.jpg"
    end
    if Device:isPocketBook() then
        -- Lock screen background of the firmware's "Line" theme.
        return "/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp"
    end
    -- Kobo: /mnt/onboard/.adds/koreader/cover.jpg
    return DataStorage:getDataDir() .. "/cover.jpg"
end

-- PocketBook themes also have a landscape lock screen, so write a second image
-- at panel-landscape size next to the first, named with a _landscape suffix:
--   taskmgr_lock_background.bmp -> taskmgr_lock_background_landscape.bmp
local WRITE_LANDSCAPE = Device:isPocketBook()

-- PocketBook's taskmgr.app draws the sleep-cover and double-click lock screen
-- from a copy of taskmgr_lock_background.bmp that it loads once and keeps
-- until the device restarts. Sending it EVT_CONFIGCHANGED (154) through iv2sh
-- makes it pick up the new file (found by experiment on an Era Lite, firmware
-- 6.11). The timeout lock reads the file itself and needs nothing.
-- Can be switched off in the menu (coverprogress_notify_taskmgr).
local NOTIFY_TASKMGR = Device:isPocketBook()

-- Optional extra PocketBook screens, both just the cover (no bar, no message)
-- and both off by default. Written when a book is opened, and only when the
-- image would differ from the last one written (another book, background or
-- size). Never on close: KOReader's auto power-off closes the book on its way
-- down, and a startup-logo write could then be cut off part-way.
-- Power-off screen: when a custom power-off image is chosen in the PocketBook
-- settings (offlogo=@user_defined in global.cfg), the firmware's logo
-- customiser converts that source file once into OFFLOGO_CACHE_PATH, a 4-bit
-- greyscale BMP, and shows the cache at power-off. It never rereads the
-- source (Era Lite, firmware 6.11; see system/config/logos_customizer/
-- logos.json). So the plugin writes both: the 24-bit cover at OFFLOGO_PATH,
-- which the user picks as the custom image, and the same cover in the
-- firmware's own 4-bit format straight into the cache. If the customiser ever
-- rebuilds the cache from the source, it gets the same cover.
local OFFLOGO_PATH = "/mnt/ext1/system/logo/offlogo/cover.bmp"
local OFFLOGO_CACHE_PATH = "/mnt/ext1/system/logo/offlogo/pb_offlogo.bmp"
-- The power-off screen can instead mirror the sleep screen (cover, bar and
-- message): coverprogress_offlogo_mode "sleep". Then only the cache is
-- written, each time the portrait lock image is, and the user picks the Line
-- lock image as the custom source. "cover" is the cover alone, as above.
local LINE_LOCK_PATH = "/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp"
-- Startup screen: `iv2sh WriteStartupLogo` copies a BMP into the boot logo
-- area of flash, as the stock coverimage plugin does. This is the working
-- file it is copied from, in KOReader's data folder.
local STARTUP_LOGO_FILE = "coverprogress_startup.bmp"

-- Writes made while the device is going to sleep must not send that event.
-- Sending it at that moment left the front light off after waking, and could
-- stop the device waking from a double-click lock (Era Lite, v1.14; fixed by
-- this in v1.15). These writes are too late to show on that lock anyway.
local NO_NOTIFY_REASONS = { ["suspend"] = true, ["settings flush"] = true }


local function landscapePath(path)
    local base, ext = path:match("^(.*)(%.[^./]*)$")
    if not base then return path .. "_landscape" end
    return base .. "_landscape" .. ext
end

-- Set both to 0 to use KOReader's screen size. On Android this can be the app
-- window rather than the panel, in which case the screensaver app upscales.
-- Also handy for previewing another device's geometry: a Bigme B7 is
-- 1264 x 1680, a HiBreak Pro BW is 824 x 1648.
local TARGET_W = 0
local TARGET_H = 0

-- Wait after the last page turn before rewriting. On PocketBook the firmware
-- draws the lock screen from the file as the device locks, and the write that
-- KOReader's Suspend event triggers lands too late to be shown (confirmed on an
-- Era Lite: a timeout lock showed the new image, an immediate double-click
-- lock did not). So write soon after a page turn, before the reader can lock.
local DEBOUNCE_SECONDS   = Device:isPocketBook() and 1 or 5
local JPEG_QUALITY       = 95
-- Greyscale affects BMP output only. PocketBook's own lock-screen BMPs are
-- 24-bit, so match that there rather than risk an 8-bit file the firmware
-- may not accept.
local GRAYSCALE          = not Device:isPocketBook()

local DEFAULT_MODE       = "margin"  -- "margin" | "below" | "overlay" | "none"
local DEFAULT_BACKGROUND = "auto"    -- "white" | "black" | "auto"

-- Sleep screen message, as in KOReader's own sleep screen on Kobo/Kindle.
-- The text goes through KOReader's placeholder expansion (%T title, %p percent,
-- %b battery, ...). It is drawn in a "box" or a full-width "banner" at a
-- vertical position from 0 (bottom) to 100 (top).
local MESSAGE_FONT       = "infofont"
local MESSAGE_MAX_W_PCT  = 80      -- box width limit, % of output width
local MESSAGE_PAD        = 10      -- unscaled px inside the box or banner
local MESSAGE_BORDER     = 2       -- unscaled px box border

-- A book without a cover gets its title in bold, centred, wrapping onto more
-- lines if needed, on the plain background instead of the cover art.
local TITLE_FONT         = "cfont"
local TITLE_SIZE         = 36
local TITLE_MAX_W_PCT    = 80      -- % of output width before the title wraps

-- Page number is shown in "margin" mode only, where the band has room for it.
local PAGE_FONT        = "infont"
local PAGE_SIZE        = 18
local PAGE_ROW_EXTRA   = 8          -- px padding added to the page row height

-- below / overlay
local FIT_TO_COVER     = true   -- align the bar/box to the cover, not the screen
local BAND_HEIGHT_PCT  = 8      -- % of output height
local BAND_RULE        = false  -- hairline above the band ("below" mode only)
local BAR_THICKNESS    = 10     -- unscaled px
local PCT_FONT_SIZE    = 20
local PAD              = 16     -- unscaled px

-- overlay: compact block anchored to the cover's bottom-right
local OVERLAY_BAR_W_PCT   = 42   -- % of cover width for bar + percentage
local OVERLAY_INSET       = 14   -- unscaled px in from the cover's edges
local OVERLAY_FIND_QUIET  = true -- search upward for a strip free of lettering
local OVERLAY_SEARCH_PCT  = 22   -- how far up to look, % of cover height
local OVERLAY_CANDIDATES  = 10
local OVERLAY_SAMPLE_STEP = 4
local OVERLAY_LOW_BIAS    = 0.03 -- preference for staying near the bottom

-- Pixels below this 8-bit grey count as dark, for both the overlay
-- polarity check and the auto background decision.
local LUMA_THRESHOLD   = 128

-- Auto background: if more than this fraction of the cover is dark, go
-- black. Counting dark pixels beats averaging them, because covers are
-- often bimodal (pale stock plus heavy black artwork) and the mean lands
-- misleadingly mid-grey.
-- Separate, lower threshold for the auto decision. Measured: the periwinkle
-- on the Karamazov cover is luma 116, so a 128 cut-off counts every purple
-- block as dark and flips a plainly light cover to black. 110 keeps mid
-- colours on the light side. Do not raise this past ~130: pale cover stock
-- often sits around 140 and would suddenly all count as dark.
local AUTO_BG_LUMA       = 110
local AUTO_BG_DARK_RATIO = 50   -- percent dark before going black; menu-adjustable
local AUTO_BG_STEP       = 8

------------------------------------------------------------------------------

local CoverProgress = WidgetContainer:extend{
    name = "coverprogresspocketbook",
    is_doc_only = true,
}

local function getExtension(filename)
    local _dir, name = util.splitFilePathName(filename)
    return util.getFileNameSuffix(name):lower()
end

-- Mean 8-bit grey of a region. Subsampled; returns nil if it can't read.
local function sampleLuma(bb, x, y, w, h, step)
    step = step or 8
    local ok, mean = pcall(function()
        local max_x, max_y = bb:getWidth() - 1, bb:getHeight() - 1
        local sum, n = 0, 0
        for py = math.max(y, 0), math.min(y + h - 1, max_y), step do
            for px = math.max(x, 0), math.min(x + w - 1, max_x), step do
                sum = sum + bb:getPixel(px, py):getColor8().a
                n = n + 1
            end
        end
        if n == 0 then return nil end
        return sum / n
    end)
    if ok then return mean end
    return nil
end

-- A JPEG that lost its end-of-image marker still decodes, but the missing
-- rows come out as a grey band. Cheap to check, so check.
local function fileLooksComplete(path, fmt)
    local f = io.open(path, "rb")
    if not f then return false end
    local size = f:seek("end")
    if size < 1024 then
        f:close()
        return false
    end
    if fmt ~= "jpg" and fmt ~= "jpeg" then
        f:close()
        return true
    end
    f:seek("set", size - 2)
    local tail = f:read(2)
    f:close()
    return tail == string.char(0xFF, 0xD9)
end

-- Fixed text, with no paths or user input in it. Runs in the background so a
-- slow or missing iv2sh can never stall the reader.
local TASKMGR_NOTIFY_CMD =
    [[(p=$(ps | grep '[t]askmgr\.app' | grep -v visualizer | awk '{print $1}' | head -n 1); ]] ..
    [[[ -n "$p" ] && /ebrmain/bin/iv2sh SendEventTo "$p" 154 0) >/dev/null 2>&1 &]]

-- Asks taskmgr.app to reload the lock-screen image; see NOTIFY_TASKMGR.
local function notifyTaskManager()
    os.execute(TASKMGR_NOTIFY_CMD)
    logger.info("CoverProgress: asked taskmgr.app to reload the lock image")
end

-- The output path may hold a file the firmware theme shipped with. Before the
-- first overwrite, keep a copy as <path>.orig so it can be restored by hand.
-- Each path is checked only once (remembered in settings), so a file this
-- plugin wrote itself is never mistaken for the original. The path is only
-- marked checked once that is settled, and false is returned if an existing
-- file could not be copied, so the caller does not overwrite it.
-- Writes bb as a 4-bit greyscale BMP in the layout the PocketBook logo
-- customiser produces: 40-byte header, 16-entry palette from black (index 0)
-- to white (index 15) in steps of 17, bottom-up rows padded to 4 bytes, and
-- the image-size, resolution and colour-count fields left at 0. KOReader's
-- own BMP writer only does 8 and 24 bits. Returns true on success.
local function writeBMP4(bb, path)
    local ffi = require("ffi")
    local w, h = bb:getWidth(), bb:getHeight()
    local row_bytes = math.ceil(w / 2)
    row_bytes = row_bytes + (4 - row_bytes % 4) % 4
    local data_size = row_bytes * h
    local pixel_offset = 14 + 40 + 16 * 4

    local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
    local function le32(n)
        return string.char(n % 256, math.floor(n / 256) % 256,
                           math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    end
    local parts = {
        "BM", le32(pixel_offset + data_size), le16(0), le16(0), le32(pixel_offset),
        le32(40), le32(w), le32(h), le16(1), le16(4), le32(0),
        le32(0), le32(0), le32(0), le32(0), le32(0),
    }
    for i = 0, 15 do
        local v = i * 17
        parts[#parts + 1] = string.char(v, v, v, 0)
    end

    -- Grey 0..255 to palette index 0..15, rounding to the nearest shade.
    local function nibble(x, y)
        if x >= w then return 15 end  -- row padding: white
        return math.floor(bb:getPixel(x, y):getColor8().a / 17 + 0.5)
    end
    local buf = ffi.new("uint8_t[?]", data_size)  -- zero-filled
    for y = 0, h - 1 do
        local row = (h - 1 - y) * row_bytes  -- bottom-up
        for x = 0, w - 1, 2 do
            buf[row + x / 2] = nibble(x, y) * 16 + nibble(x + 1, y)
        end
    end

    local f = io.open(path, "wb")
    if not f then return false end
    local ok = f:write(table.concat(parts)) and f:write(ffi.string(buf, data_size))
    f:close()
    return ok and true or false
end

local function backupOriginal(path)
    local checked = G_reader_settings:readSetting("coverprogress_backup_checked", {})
    if checked[path] then return true end
    local function settled()
        checked[path] = true
        G_reader_settings:saveSetting("coverprogress_backup_checked", checked)
        return true
    end

    local f = io.open(path .. ".orig", "rb")
    if f then
        f:close()
        return settled()
    end
    local src = io.open(path, "rb")
    if not src then return settled() end  -- nothing there to back up
    local data = src:read("*a")
    src:close()
    local tmp = path .. ".orig.tmp"
    local dst = io.open(tmp, "wb")
    local written = dst and data and dst:write(data)
    if dst then dst:close() end
    if written and os.rename(tmp, path .. ".orig") then
        logger.info("CoverProgress: backed up original", path)
        return settled()
    end
    os.remove(tmp)
    logger.warn("CoverProgress: could not back up", path)
    return false
end

-- Mean and standard deviation of a region's luminance. The deviation is the
-- useful part: it distinguishes flat areas (paper, solid ink) from lettering
-- and detail, regardless of how light or dark they are.
local function sampleStats(bb, x, y, w, h, step)
    step = step or 4
    local ok, mean, sd = pcall(function()
        local max_x, max_y = bb:getWidth() - 1, bb:getHeight() - 1
        local sum, sumsq, n = 0, 0, 0
        for py = math.max(y, 0), math.min(y + h - 1, max_y), step do
            for px = math.max(x, 0), math.min(x + w - 1, max_x), step do
                local v = bb:getPixel(px, py):getColor8().a
                sum = sum + v
                sumsq = sumsq + v * v
                n = n + 1
            end
        end
        if n == 0 then return nil end
        local m = sum / n
        return m, math.sqrt(math.max(0, sumsq / n - m * m))
    end)
    if ok and mean then return mean, sd end
    return nil, nil
end

-- Font files vary between builds and platforms, so try the preferred face and
-- quietly fall back to the interface default rather than erroring.
local function pickFace(preferred, size)
    if preferred then
        local ok, face = pcall(Font.getFace, Font, preferred, size)
        if ok and face then return face end
    end
    return Font:getFace("cfont", size)
end

local function paintOutline(bb, x, y, w, h, thickness, color)
    bb:paintRect(x, y, w, thickness, color)
    bb:paintRect(x, y + h - thickness, w, thickness, color)
    bb:paintRect(x, y, thickness, h, color)
    bb:paintRect(x + w - thickness, y, thickness, h, color)
end

function CoverProgress:init()
    self.output_path = G_reader_settings:readSetting("coverprogress_path", defaultPath())
    -- Earlier versions saved cover.jpg in the data directory as the path. On
    -- PocketBook that saved value overrides the Line lock-screen default, so
    -- drop it and use the default.
    if Device:isPocketBook() and self.output_path == DataStorage:getDataDir() .. "/cover.jpg" then
        logger.info("CoverProgress: replacing legacy output path", self.output_path)
        self.output_path = defaultPath()
        G_reader_settings:delSetting("coverprogress_path")
    end
    self.enabled = G_reader_settings:isTrue("coverprogress_enabled")
    self.debounce = G_reader_settings:readSetting("coverprogress_debounce", DEBOUNCE_SECONDS)
    self.background = G_reader_settings:readSetting("coverprogress_background", DEFAULT_BACKGROUND)
    self.mode = G_reader_settings:readSetting("coverprogress_mode", DEFAULT_MODE)
    self.auto_ratio = G_reader_settings:readSetting("coverprogress_auto_ratio", AUTO_BG_DARK_RATIO)
    self.message = G_reader_settings:readSetting("coverprogress_message", "")
    self.message_container = G_reader_settings:readSetting("coverprogress_message_container", "box")
    self.message_position = G_reader_settings:readSetting("coverprogress_message_position", 50)
    -- The Kobo-style box was replaced by the message; keep the full cover.
    if self.mode == "kobo" then self.mode = "none" end
    self.show_page = G_reader_settings:isTrue("coverprogress_show_page")
    self.notify_taskmgr = NOTIFY_TASKMGR and G_reader_settings:nilOrTrue("coverprogress_notify_taskmgr")
    self.offlogo = Device:isPocketBook() and G_reader_settings:isTrue("coverprogress_offlogo")
    self.offlogo_mode = G_reader_settings:readSetting("coverprogress_offlogo_mode", "cover")
    self.startup_logo = Device:isPocketBook() and G_reader_settings:isTrue("coverprogress_startup_logo")

    self.bases = nil

    self.render_callback = function()
        self:safeRender(false, "page turn")
    end

    self.ui.menu:registerToMainMenu(self)
end

------------------------------------------------------------------------------
-- Geometry and colour
------------------------------------------------------------------------------

-- Resolves "auto" to whatever the last cover analysis decided.
function CoverProgress:resolvedBackground()
    if self.background == "auto" then
        return self.auto_choice or "white"
    end
    return self.background
end

function CoverProgress:getColors()
    if self:resolvedBackground() == "black" then
        return Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    end
    return Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK
end

-- Counts dark pixels rather than averaging them: covers are frequently
-- bimodal, and a mean sits mid-grey for artwork that is plainly light or
-- plainly dark to the eye.
function CoverProgress:decideAutoBackground(bb, w, h)
    local ok, ratio = pcall(function()
        local dark, n = 0, 0
        for y = 0, h - 1, AUTO_BG_STEP do
            for x = 0, w - 1, AUTO_BG_STEP do
                if bb:getPixel(x, y):getColor8().a < AUTO_BG_LUMA then
                    dark = dark + 1
                end
                n = n + 1
            end
        end
        if n == 0 then return nil end
        return dark / n
    end)
    if ok and ratio then
        self.last_dark_ratio = ratio
        logger.info("CoverProgress: cover is",
            string.format("%.0f%%", ratio * 100), "dark (threshold",
            tostring(self.auto_ratio) .. "%)")
        return (ratio * 100) > self.auto_ratio and "black" or "white"
    end
    self.last_dark_ratio = nil
    return "white"
end

function CoverProgress:getTargetSize(landscape)
    local w, h
    if TARGET_W > 0 and TARGET_H > 0 then
        w, h = TARGET_W, TARGET_H
    elseif Device:isPocketBook() then
        -- The panel size, independent of KOReader's rotation. getWidth() and
        -- getHeight() give sizes the PocketBook firmware rejects.
        w, h = Screen:getScreenWidth(), Screen:getScreenHeight()
    else
        w, h = Screen:getWidth(), Screen:getHeight()
    end
    if WRITE_LANDSCAPE then
        local short, long = math.min(w, h), math.max(w, h)
        if landscape then return long, short end
        return short, long
    end
    return w, h
end

-- One entry per image written: the main path, plus the landscape variant.
function CoverProgress:outputTargets()
    local targets = { { path = self.output_path, landscape = false } }
    if WRITE_LANDSCAPE then
        table.insert(targets, { path = landscapePath(self.output_path), landscape = true })
    end
    return targets
end

-- Horizontal extent that overlays should occupy: the cover itself when it is
-- narrower than the screen, otherwise the full width.
function CoverProgress:getContentSpan(t_w)
    local r = self.cover_rect
    if FIT_TO_COVER and r and r.w > 0 and r.w <= t_w then
        return r.x, r.w
    end
    return 0, t_w
end

function CoverProgress:getBandHeight(t_h)
    local h = math.floor(t_h * BAND_HEIGHT_PCT / 100)
    -- The page number sits on its own row above the bar, so the band grows to
    -- fit it. Margin mode only; see pageRowActive().
    if self:pageRowActive() then
        h = h + Screen:scaleBySize(PAGE_SIZE + PAGE_ROW_EXTRA)
    end
    return h
end

function CoverProgress:pageRowActive()
    return self.mode == "margin" and self.show_page
end

------------------------------------------------------------------------------
-- Base image
------------------------------------------------------------------------------

function CoverProgress:buildBase()
    self:freeBase()

    -- Without a cover, the title is drawn instead (placeTitle), so the lock
    -- screen never keeps showing the previous book.
    local cover_bb = FileManagerBookInfo:getCoverImage(self.ui.document)
    if not cover_bb then
        logger.info("CoverProgress: no cover image, using the title")
    end

    -- Portrait first: it makes the auto background decision the landscape
    -- variant reuses.
    local bases = {}
    local ok, err = pcall(function()
        for _, target in ipairs(self:outputTargets()) do
            if cover_bb then
                target.bb, target.rect = self:placeCover(cover_bb:copy(), target.landscape)
            else
                target.bb, target.rect = self:placeTitle(target.landscape)
            end
            table.insert(bases, target)
        end
    end)
    if cover_bb then cover_bb:free() end
    if not ok then
        for _, base in ipairs(bases) do base.bb:free() end
        error(err, 0)
    end

    self.bases = bases
    return true
end

-- Scales the cover onto a background of the target size. Takes ownership of
-- cover_bb. Returns the base buffer and the rectangle the cover occupies.
-- With plain set, the cover is fitted to the whole screen (no room reserved for
-- a bar) and the auto background is not re-decided: used for the power-off and
-- startup images, which are the cover alone.
function CoverProgress:placeCover(cover_bb, landscape, plain)
    local t_w, t_h = self:getTargetSize(landscape)

    -- "below" reserves the band before scaling, so the cover can never
    -- extend under it regardless of screen aspect ratio.
    -- "below" reserves the band before scaling, which raises the cover so the
    -- band never sits on artwork -- necessary on screens wide enough that the
    -- cover would otherwise reach the bottom edge.
    -- "margin" scales to the full height and leaves the cover centred, letting
    -- the band fall into the letterbox a tall screen already produces.
    local avail_h = t_h
    if self.mode == "below" and not plain then
        avail_h = t_h - self:getBandHeight(t_h)
    end

    local i_w, i_h = cover_bb:getWidth(), cover_bb:getHeight()
    local scale = math.min(t_w / i_w, avail_h / i_h)
    local s_w, s_h = math.floor(i_w * scale), math.floor(i_h * scale)

    -- NOTE: scaleBlitBuffer frees the source. Do not free cover_bb after this.
    cover_bb = RenderImage:scaleBlitBuffer(cover_bb, s_w, s_h)

    if self.background == "auto" and not landscape and not plain then
        self.auto_choice = self:decideAutoBackground(cover_bb, s_w, s_h)
    end

    local bg = self:getColors()
    local base = Blitbuffer.new(t_w, t_h, cover_bb:getType())
    base:fill(bg)
    local off_x = math.floor((t_w - s_w) / 2)
    local off_y = math.floor((avail_h - s_h) / 2)
    base:blitFrom(cover_bb, off_x, off_y, 0, 0, s_w, s_h)
    cover_bb:free()

    logger.dbg("CoverProgress: base built", t_w .. "x" .. t_h, self.mode)
    -- Remember the placed rectangle. On a screen wider than the cover the
    -- artwork is pillarboxed, and a full-width bar would run out over the
    -- empty margins.
    return base, { x = off_x, y = off_y, w = s_w, h = s_h }
end

-- The book's title, as KOReader shows it, or the file name without extension.
function CoverProgress:bookTitle()
    local props = self.ui.doc_props
    local title = props and (props.display_title or props.title)
    if type(title) == "string" and title ~= "" then return title end
    local file = self.ui.document and self.ui.document.file or ""
    local name = file:match("([^/]+)$") or file
    return (name:gsub("%.[^.]*$", ""))
end

-- Base image for a book without a cover: the plain background with the title
-- in bold, centred in the space the cover would use. Same return values as
-- placeCover. Built as 24-bit colour, because the BMP writer keeps the
-- buffer's depth and the PocketBook lock screen expects 24-bit.
function CoverProgress:placeTitle(landscape, plain)
    local t_w, t_h = self:getTargetSize(landscape)
    local avail_h = t_h
    if self.mode == "below" and not plain then
        avail_h = t_h - self:getBandHeight(t_h)
    end

    local bg, fg = self:getColors()
    local base = Blitbuffer.new(t_w, t_h, Blitbuffer.TYPE_BBRGB24)
    base:fill(bg)

    local title = TextBoxWidget:new{
        text = self:bookTitle(),
        face = Font:getFace(TITLE_FONT, TITLE_SIZE),
        bold = true,
        width = math.floor(t_w * TITLE_MAX_W_PCT / 100),
        alignment = "center",
        fgcolor = fg,
        bgcolor = bg,
    }
    local size = title:getSize()
    title:paintTo(base, math.floor((t_w - size.w) / 2),
        math.max(0, math.floor((avail_h - size.h) / 2)))
    title:free()

    logger.dbg("CoverProgress: title base built", t_w .. "x" .. t_h, self.mode)
    -- The "cover" is the whole area, so overlays align to the screen.
    return base, { x = 0, y = 0, w = t_w, h = avail_h }
end

function CoverProgress:freeBase()
    if self.bases then
        for _, base in ipairs(self.bases) do base.bb:free() end
        self.bases = nil
    end
    self.cover_rect = nil
    -- The look changed, so the next render must write even at the same percent.
    self.last_sig = nil
end

------------------------------------------------------------------------------
-- Progress and stats
------------------------------------------------------------------------------

-- doc_settings exists but its backing table is nil during teardown and parts
-- of setup, so check before touching it. This is what FlushSettings tripped on.
function CoverProgress:docSettings()
    local ds = self.ui and self.ui.doc_settings
    if ds and ds.data then return ds end
    return nil
end

-- Current page and total for the open document, or nil,nil.
function CoverProgress:getPageInfo()
    local ok, cur, total = pcall(function()
        local doc = self.ui.document
        local total = doc:getPageCount()
        local cur
        if self.ui.view and self.ui.view.state and self.ui.view.state.page then
            cur = self.ui.view.state.page
        end
        if not cur and doc.getCurrentPage then
            cur = doc:getCurrentPage()
        end
        return cur, total
    end)
    if ok and type(cur) == "number" and type(total) == "number" and total > 0 then
        return cur, total
    end
    return nil, nil
end

function CoverProgress:getPercent()
    local function clamp(p)
        if type(p) == "number" and p == p then
            return math.min(math.max(p, 0), 1)
        end
        return nil
    end

    -- 1. The footer's live value. This is the figure KOReader itself persists
    --    as percent_finished, kept current for both paged and scrolled
    --    documents. Earlier versions computed position by hand and read the
    --    wrong field for paged epubs, so the percentage never moved between
    --    page turns -- this is the fix for that.
    local footer = self.ui.view and self.ui.view.footer
    if footer then
        local p = clamp(footer.percent_finished)
        if p then return p end
    end

    -- 2. getLastPercent(), which ReaderRolling and ReaderPaging each implement
    --    correctly for their own mode.
    -- Note: a plain array would hit an ipairs nil-hole when rolling is absent,
    -- so check each module explicitly.
    for _, mod in ipairs({ self.ui.rolling or false, self.ui.paging or false }) do
        if mod and type(mod.getLastPercent) == "function" then
            local ok, p = pcall(mod.getLastPercent, mod)
            if ok then
                p = clamp(p)
                if p then return p end
            end
        end
    end

    -- 3. Last persisted value, if the reader modules are somehow unavailable.
    local ds = self:docSettings()
    if ds then
        local ok, stored = pcall(ds.readSetting, ds, "percent_finished")
        if ok then
            local p = clamp(stored)
            if p then return p end
        end
    end

    return 0
end

function CoverProgress:drawBand(bb, pct)
    local t_w, t_h = bb:getWidth(), bb:getHeight()
    local bg, fg = self:getColors()

    local band_h = self:getBandHeight(t_h)
    local band_y = t_h - band_h
    local pad = Screen:scaleBySize(PAD)

    -- Band spans the full width; its contents align to the cover.
    bb:paintRect(0, band_y, t_w, band_h, bg)
    if BAND_RULE then
        bb:paintRect(0, band_y, t_w, Screen:scaleBySize(1), fg)
    end

    local span_x, span_w = self:getContentSpan(t_w)

    -- Page row occupies the top of the band; the bar and percentage take the
    -- rest. When the page row is inactive, page_row_h is 0 and the layout is
    -- exactly as before.
    local page_row_h = 0
    if self:pageRowActive() then
        page_row_h = Screen:scaleBySize(PAGE_SIZE + PAGE_ROW_EXTRA)
        local cur, total = self:getPageInfo()
        if cur and total then
            local ptext = TextWidget:new{
                text = T(_("page %1 of %2"), cur, total),
                face = pickFace(PAGE_FONT, PAGE_SIZE),
                fgcolor = fg,
            }
            local psz = ptext:getSize()
            ptext:paintTo(bb, span_x + pad,
                band_y + math.floor((page_row_h - psz.h) / 2))
            ptext:free()
        end
    end

    local row_y = band_y + page_row_h
    local row_h = band_h - page_row_h

    local label = TextWidget:new{
        text = string.format("%d%%", math.floor(pct * 100 + 0.5)),
        face = Font:getFace("cfont", PCT_FONT_SIZE),
        bold = true,
        fgcolor = fg,
    }
    local label_size = label:getSize()
    local label_x = span_x + span_w - pad - label_size.w
    label:paintTo(bb, label_x, row_y + math.floor((row_h - label_size.h) / 2))
    label:free()

    local bar_h = Screen:scaleBySize(BAR_THICKNESS)
    local bar_x = span_x + pad
    local bar_w = label_x - pad - bar_x
    local bar_y = row_y + math.floor((row_h - bar_h) / 2)
    if bar_w > 0 then
        local t = Screen:scaleBySize(1)
        paintOutline(bb, bar_x, bar_y, bar_w, bar_h, t, fg)
        local fill_w = math.floor((bar_w - 2 * t) * pct)
        if fill_w > 0 then
            bb:paintRect(bar_x + t, bar_y + t, fill_w, bar_h - 2 * t, fg)
        end
    end
end

------------------------------------------------------------------------------
-- Mode: overlay
------------------------------------------------------------------------------

function CoverProgress:drawOverlay(bb, pct)
    local t_w, t_h = bb:getWidth(), bb:getHeight()
    local _bg, theme_fg = self:getColors()

    local span_x, span_w = self:getContentSpan(t_w)
    local inset = Screen:scaleBySize(OVERLAY_INSET)
    local gap = Screen:scaleBySize(8)
    local bar_h = Screen:scaleBySize(BAR_THICKNESS)

    local text = string.format("%d%%", math.floor(pct * 100 + 0.5))
    local face = Font:getFace("cfont", PCT_FONT_SIZE)

    -- Measure first; the colour is chosen once the position is known.
    local probe = TextWidget:new{ text = text, face = face, bold = true }
    local label_w = probe:getSize().w
    local label_h = probe:getSize().h
    probe:free()

    local block_w = math.floor(span_w * OVERLAY_BAR_W_PCT / 100)
    local min_w = label_w + gap + Screen:scaleBySize(40)
    if block_w < min_w then block_w = math.min(min_w, span_w - 2 * inset) end
    local block_h = math.max(bar_h, label_h)
    local block_x = span_x + span_w - inset - block_w

    -- Bottom of the artwork, not of the screen.
    local r = self.cover_rect
    local cover_bottom = (r and math.min(r.y + r.h, t_h)) or t_h
    local cover_top = (r and r.y) or 0

    local y = cover_bottom - inset - block_h
    local mean

    if OVERLAY_FIND_QUIET then
        -- Cover art usually has the title and author set in the lower third,
        -- and a bar laid across them reads as a strikethrough. Walk upward a
        -- little and settle on the flattest strip: low standard deviation
        -- means no lettering or detail, whichever shade it happens to be.
        local limit = math.max(cover_top, y - math.floor((cover_bottom - cover_top) * OVERLAY_SEARCH_PCT / 100))
        local step = math.max(1, math.floor((y - limit) / OVERLAY_CANDIDATES))
        local best_score
        for cy = y, limit, -step do
            local m, sd = sampleStats(bb, block_x, cy, block_w, block_h, OVERLAY_SAMPLE_STEP)
            if m then
                -- Nudge towards the bottom so a marginally flatter strip
                -- higher up does not drag the bar into the middle of the art.
                local score = sd + (y - cy) * OVERLAY_LOW_BIAS
                if not best_score or score < best_score then
                    best_score, y, mean = score, cy, m
                end
            end
        end
    end

    if not mean then
        mean = sampleStats(bb, block_x, y, block_w, block_h, OVERLAY_SAMPLE_STEP)
    end

    -- One colour for the bar and the percentage. Sampling them separately
    -- gives a black number beside a white bar, which just looks broken.
    local fg = theme_fg
    if mean then
        fg = (mean < LUMA_THRESHOLD) and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    end

    local label = TextWidget:new{ text = text, face = face, bold = true, fgcolor = fg }
    label:paintTo(bb, block_x + block_w - label_w, y + math.floor((block_h - label_h) / 2))
    label:free()

    local bar_w = block_w - label_w - gap
    local bar_y = y + math.floor((block_h - bar_h) / 2)
    if bar_w > 0 then
        local t = Screen:scaleBySize(2)
        paintOutline(bb, block_x, bar_y, bar_w, bar_h, t, fg)
        local fill_w = math.floor((bar_w - 2 * t) * pct)
        if fill_w > 0 then
            bb:paintRect(block_x + t, bar_y + t, fill_w, bar_h - 2 * t, fg)
        end
    end
end
------------------------------------------------------------------------------
-- Sleep screen message
------------------------------------------------------------------------------

-- The message with KOReader's placeholders filled in, or nil if there is none.
-- Uses the same expansion as KOReader's sleep screen, so every code it knows
-- works here. Builds without expandString get the text unexpanded.
function CoverProgress:expandedMessage()
    local msg = self.message
    if type(msg) ~= "string" or msg == "" then return nil end
    local bookinfo = self.ui.bookinfo
    if bookinfo and type(bookinfo.expandString) == "function" then
        local ok, expanded = pcall(bookinfo.expandString, bookinfo, msg)
        if ok and type(expanded) == "string" then
            msg = expanded
        end
    end
    if msg == "" then return nil end
    return msg
end

function CoverProgress:drawMessage(bb, text)
    local t_w, t_h = bb:getWidth(), bb:getHeight()
    local bg, fg = self:getColors()
    local face = Font:getFace(MESSAGE_FONT)
    local pad = Screen:scaleBySize(MESSAGE_PAD)
    local banner = self.message_container == "banner"

    -- A box is as wide as its longest line, up to MESSAGE_MAX_W_PCT; longer
    -- lines wrap. A banner spans the full width.
    local text_w
    if banner then
        text_w = t_w - 2 * pad
    else
        local border = Screen:scaleBySize(MESSAGE_BORDER)
        local max_w = math.floor(t_w * MESSAGE_MAX_W_PCT / 100) - 2 * (pad + border)
        text_w = 1
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local probe = TextWidget:new{ text = line, face = face }
            text_w = math.max(text_w, probe:getSize().w)
            probe:free()
        end
        text_w = math.min(text_w, max_w)
    end

    local textbox = TextBoxWidget:new{
        text = text,
        face = face,
        width = text_w,
        alignment = "center",
        fgcolor = fg,
        bgcolor = bg,
    }
    local text_h = textbox:getSize().h

    local box_w, box_h, box_x, border
    if banner then
        border = 0
        box_w, box_h, box_x = t_w, text_h + 2 * pad, 0
    else
        border = Screen:scaleBySize(MESSAGE_BORDER)
        box_w = text_w + 2 * (pad + border)
        box_h = text_h + 2 * (pad + border)
        box_x = math.floor((t_w - box_w) / 2)
    end

    -- 0 is the bottom and 100 the top, as in KOReader's setting. With a bar
    -- band at the bottom, keep the message above it.
    local bottom = t_h
    if self.mode == "margin" or self.mode == "below" then
        bottom = t_h - self:getBandHeight(t_h)
    end
    local pos = math.min(math.max(tonumber(self.message_position) or 50, 0), 100)
    local box_y = math.floor((bottom - box_h) * (1 - pos / 100))
    box_y = math.max(0, math.min(box_y, bottom - box_h))

    bb:paintRect(box_x, box_y, box_w, box_h, bg)
    if border > 0 then
        paintOutline(bb, box_x, box_y, box_w, box_h, border, fg)
    end
    textbox:paintTo(bb, box_x + border + pad, box_y + border + pad)
    textbox:free()
end

------------------------------------------------------------------------------
-- Render + write
------------------------------------------------------------------------------

-- reason is a short label for the log ("page turn", "suspend", ...), so the
-- KOReader log shows which events actually led to a write on the device.
function CoverProgress:render(force, reason)
    if not self.enabled then return end
    if not self.bases then
        if not self:buildBase() then return end
    end
    local ds = self:docSettings()
    if ds then
        local got, excluded = pcall(ds.isTrue, ds, "exclude_cover_image")
        if got and excluded then return end
    end

    local pct = self:getPercent()

    -- Skip the encode when nothing visible has changed since the last write.
    -- On this device roughly 20 page flips make one whole percent, so without
    -- this the same image is re-encoded and rewritten twenty times over.
    -- The signature is the displayed percent plus the expanded message, which
    -- changes whenever one of its placeholders does. A forced call (open,
    -- suspend, close, background/mode change) always writes.
    local message = self:expandedMessage()
    local sig = tostring(math.floor(pct * 100 + 0.5)) .. "|" .. tostring(message or "")
    -- With the page number shown, the display changes several times per whole
    -- percent, so the page must be in the signature or it would lag. This is
    -- the source of the extra writes noted in the menu help.
    if self:pageRowActive() then
        local cur = select(1, self:getPageInfo())
        sig = sig .. "|p" .. tostring(cur or "")
    end
    -- A write made while going to sleep cannot ask taskmgr.app to reload (see
    -- NO_NOTIFY_REASONS), so it leaves notify_pending set. The next safe
    -- trigger sends it, even when nothing new needs writing; otherwise the
    -- sleep cover would keep an old image until the percentage changed again.
    local can_notify = self.notify_taskmgr and not NO_NOTIFY_REASONS[reason]
    if not force and sig == self.last_sig then
        if can_notify and self.notify_pending then
            self.notify_pending = false
            notifyTaskManager()
        end
        logger.info("CoverProgress: unchanged, not written (" .. tostring(reason) .. ")")
        return
    end

    -- Draw and write every variant; record the signature only if all of
    -- them landed, so a failed write is retried on the next render.
    -- Each result is kept in self.write_report for "Update now" to show.
    local all_ok = true
    self.write_report = {}
    for _, base in ipairs(self.bases) do
        self.cover_rect = base.rect
        local ok, detail = self:writeImage(base.bb, base.path, pct, message, base.landscape)
        table.insert(self.write_report, { path = base.path, ok = ok, reason = detail })
        if not ok then
            all_ok = false
        end
    end
    self.cover_rect = nil

    if all_ok then
        self.last_sig = sig
        if can_notify then
            self.notify_pending = false
            notifyTaskManager()
        elseif self.notify_taskmgr then
            self.notify_pending = true
        end
    end
    logger.info("CoverProgress:", all_ok and "wrote" or "write FAILED",
        "(" .. tostring(reason) .. ")", string.format("%d%%", math.floor(pct * 100 + 0.5)))
end

-- Draws the progress onto a copy of base_bb and publishes it at path.
-- Returns true and the image size, or false and the reason it failed.
function CoverProgress:writeImage(base_bb, path, pct, message, landscape)
    local t_w, t_h = base_bb:getWidth(), base_bb:getHeight()

    -- Fresh copy each time; drawing onto the base would stack overlays.
    local out = Blitbuffer.new(t_w, t_h, base_bb:getType())
    out:blitFrom(base_bb, 0, 0, 0, 0, t_w, t_h)

    if self.mode == "overlay" then
        self:drawOverlay(out, pct)
    elseif self.mode ~= "none" then
        -- "margin" and "below" share a renderer; they differ only in whether
        -- buildBase reserved room for the band beforehand.
        self:drawBand(out, pct)
    end
    if message then
        self:drawMessage(out, message)
    end

    -- Power-off screen mirroring the sleep screen: the same portrait image,
    -- in the firmware's 4-bit format, into the power-off cache. A plain file
    -- write, so it is safe on every trigger, including going to sleep.
    if self.offlogo and self.offlogo_mode == "sleep" and not landscape then
        local copy = Blitbuffer.new(out:getWidth(), out:getHeight(), out:getType())
        copy:blitFrom(out, 0, 0, 0, 0, out:getWidth(), out:getHeight())
        if not self:publishImage(copy, OFFLOGO_CACHE_PATH, writeBMP4) then
            logger.warn("CoverProgress: could not update the power-off screen")
        end
    end

    return self:publishImage(out, path)
end

-- Saves out at path safely: written to <path>.tmp, checked, the existing file
-- backed up once (see backupOriginal), then renamed into place. Frees out.
-- write_fn, if given, writes the file instead of KOReader's writer (used for
-- the 4-bit power-off cache). Returns true and the image size, or false and
-- the reason it failed.
function CoverProgress:publishImage(out, path, write_fn)
    local t_w, t_h = out:getWidth(), out:getHeight()
    local fmt = getExtension(path)
    if fmt ~= "jpg" and fmt ~= "jpeg" and fmt ~= "png" and fmt ~= "bmp" then
        fmt = "jpg"
    end

    -- The PocketBook firmware shows these files only if they exist, and the
    -- system/resources/Line folder is not there on a fresh device (it is
    -- created by hand in the usual guides), so create it rather than fail.
    if Device:isPocketBook() then
        local dir = util.splitFilePathName(path)
        if dir ~= "" and not util.directoryExists(dir) then
            local made, err = util.makePath(dir)
            if not made then
                logger.warn("CoverProgress: could not create", dir, err)
                return false, T(_("could not create the folder %1: %2"), dir, tostring(err))
            end
            logger.info("CoverProgress: created", dir)
        end
    end

    local tmp = path .. ".tmp"
    local ok
    if write_fn then
        ok = write_fn(out, tmp)
    else
        ok = out:writeToFile(tmp, fmt, JPEG_QUALITY, GRAYSCALE)
    end
    out:free()

    if not ok then
        logger.warn("CoverProgress: write failed", tmp)
        os.remove(tmp)
        return false, _("could not write the file (does the folder exist?)")
    end

    if not fileLooksComplete(tmp, fmt) then
        logger.warn("CoverProgress: incomplete write, discarding", tmp)
        os.remove(tmp)
        return false, _("the written file was incomplete")
    end

    if not backupOriginal(path) then
        os.remove(tmp)
        return false, _("could not back up the existing file, so it was left as it is")
    end

    local renamed, err = os.rename(tmp, path)
    if not renamed then
        logger.warn("CoverProgress: rename failed", err)
        os.remove(tmp)
        return false, T(_("could not replace the file: %1"), tostring(err))
    end

    logger.info("CoverProgress: wrote", path, t_w .. "x" .. t_h)
    return true, t_w .. "x" .. t_h
end

function CoverProgress:scheduleRender()
    if not self.enabled then return end
    UIManager:unschedule(self.render_callback)
    UIManager:scheduleIn(self.debounce, self.render_callback)
end

-- A screensaver plugin must never be able to break the reader, so errors are
-- contained here rather than propagating out of an event handler.
function CoverProgress:safeRender(force, reason)
    local ok, err = pcall(self.render, self, force, reason)
    if not ok then
        logger.warn("CoverProgress: render failed:", err)
    end
    return ok, err
end

-- force = true bypasses the change guard, for writes that must happen even at
-- an unchanged percentage (book open/close, suspend, background or mode change).
function CoverProgress:renderNow(force, reason)
    UIManager:unschedule(self.render_callback)
    self:safeRender(force, reason)
end

-- Rebuilds and writes now, and returns a message saying what happened to
-- each file, for the "Update now" menu entry.
function CoverProgress:updateNow()
    if not self.enabled then
        return _("Nothing written: the plugin is not enabled.")
    end
    local ok, err = pcall(self.buildBase, self)
    if not ok then
        return T(_("Nothing written: preparing the cover failed:\n%1"), tostring(err))
    end
    self.write_report = nil
    UIManager:unschedule(self.render_callback)
    local rendered, render_err = self:safeRender(true, "update now")
    if not rendered then
        return T(_("Nothing written: drawing the image failed:\n%1"), tostring(render_err))
    end
    if not self.write_report then
        return _("Nothing written: this book is excluded from cover images.")
    end
    local lines = {}
    for _i, r in ipairs(self.write_report) do
        if r.ok then
            table.insert(lines, T(_("Written (%1):\n%2"), r.reason, r.path))
        else
            table.insert(lines, T(_("Failed: %1\n%2"), r.reason, r.path))
        end
    end
    -- Say what message, if any, went into the image, so a missing message
    -- can be told apart from one that was drawn but not shown.
    local message = self:expandedMessage()
    if message then
        table.insert(lines, T(_("Message drawn:\n%1"), message))
    else
        table.insert(lines, _("No sleep screen message is set. Add one under Sleep screen message > Message."))
    end
    return table.concat(lines, "\n\n")
end

function CoverProgress:rebuild()
    if not self.enabled then return end
    local ok, err = pcall(self.buildBase, self)
    if not ok then
        logger.warn("CoverProgress: buildBase failed:", err)
        return
    end
    self:renderNow(false, "rebuild")
end

------------------------------------------------------------------------------
-- Power-off and startup screens (PocketBook, optional)
------------------------------------------------------------------------------

-- What the cover-only image depends on. Unchanged means nothing to rewrite.
function CoverProgress:logoKey()
    local w, h = self:getTargetSize(false)
    local file = self.ui.document and self.ui.document.file or ""
    return table.concat({ file, self:resolvedBackground(), w .. "x" .. h }, "|")
end

-- The cover alone, fitted to the portrait screen, or the title if there is no
-- cover. The caller frees it.
function CoverProgress:buildPlainImage()
    local cover_bb = FileManagerBookInfo:getCoverImage(self.ui.document)
    if cover_bb then
        return (self:placeCover(cover_bb, false, true))
    end
    return (self:placeTitle(false, true))
end

-- Writes the power-off and/or startup image if switched on and out of date.
-- Called after a book opens and when either switch is turned on; never from
-- the sleep or close paths (see OFFLOGO_PATH).
function CoverProgress:writeLogos()
    if not (self.enabled and (self.offlogo or self.startup_logo)) then return end
    local key = self:logoKey()
    local want_off = self.offlogo and self.offlogo_mode == "cover"
        and G_reader_settings:readSetting("coverprogress_offlogo_key") ~= key
    local want_start = self.startup_logo
        and G_reader_settings:readSetting("coverprogress_startup_key") ~= key
    if not (want_off or want_start) then return end

    local plain = self:buildPlainImage()
    local ok, err = pcall(function()
        if want_off then
            local copy = Blitbuffer.new(plain:getWidth(), plain:getHeight(), plain:getType())
            copy:blitFrom(plain, 0, 0, 0, 0, plain:getWidth(), plain:getHeight())
            local cache = Blitbuffer.new(plain:getWidth(), plain:getHeight(), plain:getType())
            cache:blitFrom(plain, 0, 0, 0, 0, plain:getWidth(), plain:getHeight())
            local source_ok = self:publishImage(copy, OFFLOGO_PATH)
            local cache_ok = self:publishImage(cache, OFFLOGO_CACHE_PATH, writeBMP4)
            if source_ok and cache_ok then
                G_reader_settings:saveSetting("coverprogress_offlogo_key", key)
                logger.info("CoverProgress: power-off screen updated")
            end
        end
        if want_start then
            local path = DataStorage:getFullDataDir() .. "/" .. STARTUP_LOGO_FILE
            local copy = Blitbuffer.new(plain:getWidth(), plain:getHeight(), plain:getType())
            copy:blitFrom(plain, 0, 0, 0, 0, plain:getWidth(), plain:getHeight())
            if self:publishImage(copy, path) then
                -- iv2sh is slow, so it runs in the background, as in the stock
                -- coverimage plugin. The path is quoted with util.shell_escape.
                os.execute("sync")
                os.execute("/ebrmain/bin/iv2sh WriteStartupLogo "
                    .. util.shell_escape({ path }) .. " >/dev/null 2>&1 &")
                G_reader_settings:saveSetting("coverprogress_startup_key", key)
                logger.info("CoverProgress: startup screen update started")
            end
        end
    end)
    plain:free()
    if not ok then
        logger.warn("CoverProgress: power-off/startup screen failed:", err)
    end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

function CoverProgress:onReaderReady()
    self.closing = false
    self:rebuild()
    local ok, err = pcall(self.writeLogos, self)
    if not ok then
        logger.warn("CoverProgress: writeLogos failed:", err)
    end
end

function CoverProgress:onPageUpdate()
    self:scheduleRender()
end

function CoverProgress:onPosUpdate()
    self:scheduleRender()
end

function CoverProgress:onFlushSettings()
    -- FlushSettings also fires while the document is being torn down, when
    -- there is nothing meaningful left to read. onCloseDocument covers that
    -- case, so skip rather than racing it.
    if self.closing or not self:docSettings() then return end
    -- Not forced: settings are flushed periodically and on suspend, and a
    -- forced write here rewrote an identical image each time. This still
    -- flushes a pending debounced render if the progress has changed.
    self:renderNow(false, "settings flush")
end

function CoverProgress:onSuspend()
    -- Not forced: a write at this point is too late to be shown on the lock
    -- that triggers it (PocketBook draws it as the device locks), and the
    -- page-turn writes have normally made the file current already. Forcing
    -- it rewrote the same image on every lock. This still writes a change
    -- that was waiting on the update delay, ready for the next lock.
    self:renderNow(false, "suspend")
end

function CoverProgress:onCloseDocument()
    self:renderNow(true, "close")
    self.closing = true
    UIManager:unschedule(self.render_callback)
    self:freeBase()
end

function CoverProgress:onSetRotationMode()
    -- With WRITE_LANDSCAPE (PocketBook) both images are panel-sized whatever
    -- KOReader's rotation, so rotating would only rewrite identical files.
    if WRITE_LANDSCAPE then return end
    self:rebuild()
end

------------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------------

function CoverProgress:menuEntryMode(mode, label, help, separator)
    return {
        text = label,
        help_text = help,
        separator = separator,
        radio = true,  -- mutually exclusive: show a radio dot, not a checkmark
        checked_func = function()
            return self.mode == mode
        end,
        callback = function()
            if self.mode == mode then return end
            self.mode = mode
            G_reader_settings:saveSetting("coverprogress_mode", mode)
            -- "below" changes the cover scale, so a full rebuild is needed.
            self:rebuild()
        end,
    }
end

-- Edits the message text. Multi-line; empty hides the message.
function CoverProgress:menuEntryMessageText()
    return {
        text_func = function()
            local val = self.message or ""
            if val == "" then return _("Message: (none)") end
            return T(_("Message: %1"), (val:gsub("\n", " / ")))
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local InputDialog = require("ui/widget/inputdialog")
            local dialog
            local buttons = {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        self.message = dialog:getInputText() or ""
                        G_reader_settings:saveSetting("coverprogress_message", self.message)
                        UIManager:close(dialog)
                        self:renderNow(true, "menu")
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
            }
            -- Called without an instance, expandString shows the list of
            -- placeholders, as the button in KOReader's own sleep screen menu does.
            if type(FileManagerBookInfo.expandString) == "function" then
                table.insert(buttons, 1, {
                    text = _("Info"),
                    callback = FileManagerBookInfo.expandString,
                })
            end
            dialog = InputDialog:new{
                title = _("Sleep screen message"),
                description = _("Leave empty for no message. Placeholders such as %T (title), %p (percent read) and %b (battery) are filled in; tap Info for the full list."),
                input = self.message or "",
                allow_newline = true,
                buttons = { buttons },
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    }
end

function CoverProgress:menuEntryContainer(container, label)
    return {
        text = label,
        radio = true,
        checked_func = function()
            return self.message_container == container
        end,
        callback = function()
            if self.message_container == container then return end
            self.message_container = container
            G_reader_settings:saveSetting("coverprogress_message_container", container)
            self:renderNow(true, "menu")
        end,
    }
end

function CoverProgress:menuEntryBackground(color, label, separator)
    return {
        text_func = function()
            if color == "auto" and self.background == "auto" then
                if self.last_dark_ratio then
                    return T(_("%1 (now: %2, cover %3% dark)"), label,
                        self:resolvedBackground(),
                        string.format("%.0f", self.last_dark_ratio * 100))
                end
                return T(_("%1 (now: %2)"), label, self:resolvedBackground())
            end
            return label
        end,
        separator = separator,
        radio = true,  -- mutually exclusive: show a radio dot, not a checkmark
        help_text = color == "auto"
            and _("Picks white or black per book by counting how much of the cover is dark.")
            or nil,
        checked_func = function()
            return self.background == color
        end,
        callback = function()
            if self.background == color then return end
            self.background = color
            G_reader_settings:saveSetting("coverprogress_background", color)
            self:rebuild()
        end,
    }
end

function CoverProgress:addToMainMenu(menu_items)
    -- Resolve placement safely. On setups missing the reader "screen" section, a
    -- "screen" hint crashes core MenuSorter (see cpSafeSortingHint); we validate
    -- a short chain and fall back to a safe orphan if none of them exist.
    local hint = cpSafeSortingHint({ "screen", "setting" })
    if hint ~= "screen" then
        logger.info("coverprogress: reader 'screen' section unavailable; placing entry under '"
                    .. tostring(hint or "first menu (orphaned)") .. "'")
    end

    -- Build under xpcall: a throw here (or in any menuEntry* helper it calls)
    -- is captured with a real traceback instead of crashing KOReader.
    local build_ok, build_err = xpcall(function()
    menu_items.coverprogress = {
        sorting_hint = hint,
        text = _("Cover Image PocketBook"),
        checked_func = function()
            return self.enabled
        end,
        sub_item_table = {
            {
                text = _("Enabled"),
                checked_func = function()
                    return self.enabled
                end,
                callback = function()
                    self.enabled = not self.enabled
                    G_reader_settings:saveSetting("coverprogress_enabled", self.enabled)
                    if self.enabled then
                        self:rebuild()
                    else
                        UIManager:unschedule(self.render_callback)
                    end
                end,
                separator = true,
            },
            self:menuEntryMode("margin", _("Progress bar in the margin"),
                _("Leaves the cover centred at full size and puts the bar in the empty band below it. Best on tall screens such as phones, where a portrait cover cannot reach the bottom edge.")),
            self:menuEntryMode("below", _("Progress bar below cover"),
                _("Shrinks and raises the cover to make room for the bar underneath. Use on wider screens such as tablets, where the cover would otherwise run to the bottom edge.")),
            self:menuEntryMode("overlay", _("Progress bar overlays cover"),
                _("Full-bleed cover with a compact bar drawn on top, placed to avoid lettering and coloured black or white to suit whatever sits beneath it.")),
            self:menuEntryMode("none", _("No progress bar"),
                _("The cover at full size with no bar. Use with a sleep screen message to show progress as text instead."), true),
            {
                text = _("Sleep screen message"),
                help_text = _("Text drawn on the image, as KOReader's sleep screen message does on Kobo and Kindle. The image is written ahead of time, so time, date and battery placeholders show their value at the last write, not the moment the device sleeps, and each change to them rewrites the image."),
                checked_func = function()
                    return (self.message or "") ~= ""
                end,
                sub_item_table = {
                    self:menuEntryMessageText(),
                    self:menuEntryContainer("box", _("Box")),
                    self:menuEntryContainer("banner", _("Banner")),
                    {
                        text_func = function()
                            return T(_("Vertical position: %1%"), self.message_position)
                        end,
                        help_text = _("0 is the bottom of the screen, 100 the top. In the bar layouts the message stays above the bar."),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new{
                                value = self.message_position,
                                value_min = 0,
                                value_max = 100,
                                value_step = 5,
                                default_value = 50,
                                unit = "%",
                                title_text = _("Message position"),
                                info_text = _("0 is the bottom, 100 the top."),
                                ok_text = _("Set"),
                                callback = function(spin)
                                    self.message_position = spin.value
                                    G_reader_settings:saveSetting("coverprogress_message_position", spin.value)
                                    self:renderNow(true, "menu")
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                    },
                },
                separator = true,
            },
            {
                text = _("Show page number"),
                enabled_func = function()
                    return self.mode == "margin"
                end,
                checked_func = function()
                    return self.show_page
                end,
                help_text = _("Shows 'page X of Y' above the bar, in the margin layout. Note: with this on, the image is rewritten on every page turn. With it off, the image is rewritten only when the whole percentage changes, which is far less often."),
                callback = function()
                    self.show_page = not self.show_page
                    G_reader_settings:saveSetting("coverprogress_show_page", self.show_page)
                    self:rebuild()
                end,
                separator = true,
            },
            self:menuEntryBackground("white", _("White background, black text")),
            self:menuEntryBackground("black", _("Black background, white text")),
            self:menuEntryBackground("auto", _("Auto background")),
            {
                text_func = function()
                    return T(_("Auto: go black above %1% dark"), self.auto_ratio)
                end,
                enabled_func = function()
                    return self.background == "auto"
                end,
                help_text = _("Raise this to favour white backgrounds, lower it to favour black. The current cover's measurement is shown on the Auto background entry above."),
                keep_menu_open = true,
                separator = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        value = self.auto_ratio,
                        value_min = 10,
                        value_max = 90,
                        value_step = 5,
                        default_value = AUTO_BG_DARK_RATIO,
                        title_text = _("Darkness threshold"),
                        info_text = _("Percentage of the cover that must be dark before a black background is used."),
                        ok_text = _("Set"),
                        callback = function(spin)
                            self.auto_ratio = spin.value
                            G_reader_settings:saveSetting("coverprogress_auto_ratio", spin.value)
                            self:rebuild()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
            {
                text_func = function()
                    return T(_("Output: %1"), self.output_path)
                end,
                keep_menu_open = true,
                callback = function()
                    local paths = self.output_path
                    if WRITE_LANDSCAPE then
                        paths = paths .. "\n" .. landscapePath(self.output_path)
                    end
                    UIManager:show(InfoMessage:new{
                        text = T(_("Writing to:\n%1\n\nEdit coverprogress_path in settings.reader.lua to change."),
                            paths),
                    })
                end,
            },
            {
                text_func = function()
                    return T(_("Update delay: %1 s"), self.debounce)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        value = self.debounce,
                        value_min = 0,
                        value_max = 60,
                        default_value = DEBOUNCE_SECONDS,
                        title_text = _("Seconds after last page turn"),
                        ok_text = _("Set"),
                        callback = function(spin)
                            self.debounce = spin.value
                            G_reader_settings:saveSetting("coverprogress_debounce", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
            {
                text = _("Update now"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = self:updateNow(),
                    })
                end,
            },
        },
    }
    if Device:isPocketBook() then
        -- PocketBook only; placed before "Update now", the last entry.
        local items = menu_items.coverprogress.sub_item_table
        local function logoSwitch(field, key, label, help)
            return {
                text = label,
                help_text = help,
                checked_func = function()
                    return self[field]
                end,
                callback = function()
                    self[field] = not self[field]
                    G_reader_settings:saveSetting(key, self[field])
                    if self[field] then
                        self:writeLogos()
                    end
                end,
            }
        end
        -- Power-off screen: Off / Book cover only / Same as sleep screen.
        local function offChoice(on, mode, label, help)
            return {
                text = label,
                help_text = help,
                radio = true,
                checked_func = function()
                    if not on then return not self.offlogo end
                    return self.offlogo and self.offlogo_mode == mode
                end,
                callback = function()
                    self.offlogo = on
                    G_reader_settings:saveSetting("coverprogress_offlogo", on)
                    if not on then return end
                    self.offlogo_mode = mode
                    G_reader_settings:saveSetting("coverprogress_offlogo_mode", mode)
                    if mode == "cover" then
                        -- Write the cover now, even for the book already shown.
                        G_reader_settings:delSetting("coverprogress_offlogo_key")
                        self:writeLogos()
                    else
                        self:renderNow(true, "menu")
                    end
                end,
            }
        end
        table.insert(items, #items, {
            text_func = function()
                if not self.offlogo then return _("Power-off screen: unchanged") end
                if self.offlogo_mode == "sleep" then return _("Power-off screen: same as sleep screen") end
                return _("Power-off screen: book cover")
            end,
            sub_item_table = {
                offChoice(false, nil, _("Off"),
                    _("The plugin leaves the power-off screen alone.")),
                offChoice(true, "cover", _("Book cover only"),
                    T(_("The cover alone, with no bar or text, updated when a different book is opened. In the PocketBook settings, set the power-off logo to Custom image and choose %1. Turn off the built-in Cover image plugin, which writes the same file."), OFFLOGO_PATH)),
                offChoice(true, "sleep", _("Same as sleep screen"),
                    T(_("The same image as the sleep screen, with the progress bar and message, updated whenever the sleep screen is. In the PocketBook settings, set the power-off logo to Custom image and choose %1."), LINE_LOCK_PATH)),
            },
        })
        table.insert(items, #items, logoSwitch("startup_logo", "coverprogress_startup_logo",
            _("Startup screen: book cover"),
            _("Sets the cover alone, with no bar or text, as the screen shown while the device starts. Written when a different book is opened, not on every page, because it is stored in the device's flash memory. Turn off the built-in Cover image plugin, which also sets it.")))
    end
    if NOTIFY_TASKMGR then
        -- PocketBook only; placed before "Update now", the last entry.
        local items = menu_items.coverprogress.sub_item_table
        table.insert(items, #items, {
            text = _("Refresh sleep-cover image"),
            help_text = _("After each update, tells the PocketBook firmware to reload the lock-screen image, so closing the cover or double-clicking the menu button shows the current one. Without this, those locks show the image from the last restart."),
            checked_func = function()
                return self.notify_taskmgr
            end,
            callback = function()
                self.notify_taskmgr = not self.notify_taskmgr
                G_reader_settings:saveSetting("coverprogress_notify_taskmgr", self.notify_taskmgr)
            end,
        })
    end
    end, function(e)
        return tostring(e) .. "\n" .. debug.traceback("", 2)
    end)

    -- Build failed: log the traceback and install a harmless placeholder entry
    -- so the menu still opens and the user knows where to look.
    if not build_ok then
        cpLogError("addToMainMenu", build_err)
        menu_items.coverprogress = {
            sorting_hint = hint,
            text = _("Cover Image PocketBook (menu build error)"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = T(_("coverprogress could not build its menu.\nA traceback was saved to:\n%1"),
                        CP_CRASH_LOG),
                })
            end,
        }
        return
    end

    -- Build succeeded: wrap every text/checked/enabled/callback in the tree so
    -- an error at interaction time is logged and swallowed, not fatal.
    cpWrapMenuTree(menu_items.coverprogress, "coverprogress")
end

return CoverProgress
