# dmgbuild settings for the TimeTug installer (see scripts/release/make-dmg.sh).
#
# Defines (passed with `dmgbuild -D name=value`):
#   app          required, path to the built TimeTug.app
#   background   required, path to the combined hi-dpi background TIFF
#   volume_name  optional, default "TimeTug" (informational; the volume name is the dmgbuild argument)
#
# The window is 660x400 and the icon positions match the arrow drawn by generate-background.swift:
# app icon centre (170, 200), Applications shortcut centre (490, 200). verify-dmg.sh asserts them.
import os.path

application = defines.get("app")  # noqa: F821 (`defines` is injected by dmgbuild)
background_tiff = defines.get("background")  # noqa: F821
if not application or not background_tiff:
    raise SystemExit("settings.py needs -D app=<TimeTug.app> and -D background=<background.tiff>")

app_name = os.path.basename(application.rstrip("/"))

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

# Volume icon: the app's own icon.
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")
background = background_tiff

window_rect = ((200, 200), (660, 400))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
arrange_by = None
icon_size = 128
text_size = 13

icon_locations = {
    app_name: (170, 200),
    "Applications": (490, 200),
}
