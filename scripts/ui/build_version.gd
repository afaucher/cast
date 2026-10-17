class_name BuildVersion
extends RefCounted
## The build stamp shown on the menus, so a playtest report or screenshot says which build it came
## from. Ported from bridge-to-friendship (scripts/ui/build_version.gd).
##
## build.ps1 writes `version.txt` (yyyy-MM-dd.HHmmss) into the project root right before the export,
## so it is packed into Cast.pck (export_presets.cfg include_filter) and travels with the .exe. It is
## gitignored: an output, not source.
##
## A source or editor run always says "dev (...)": version.txt is never cleaned up after a build, so
## an editor run would otherwise present the last export's stamp as its own.

const UNKNOWN := "unversioned"
const PATH := "res://version.txt"


## Pure, so the awkward cases (missing file, blank file, a BOM) are testable without fixtures.
## `in_editor` is OS.has_feature("editor"): true from the editor or a source run, false in an export.
static func resolve(exists: bool, raw: String, in_editor: bool) -> String:
	var stamp := UNKNOWN
	if exists:
		# strip_edges() doesn't remove a byte-order mark (Set-Content may write one), so trim it
		# explicitly. Written as a codepoint: a literal BOM is invisible and easy to delete by accident.
		var t := raw.strip_edges().trim_prefix(String.chr(0xFEFF)).strip_edges()
		if t != "":
			stamp = t
	if in_editor:
		return "dev (%s)" % stamp
	return stamp


static func text() -> String:
	var exists := FileAccess.file_exists(PATH)
	var raw := ""
	if exists:
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			exists = false
		else:
			raw = f.get_as_text()
	return resolve(exists, raw, OS.has_feature("editor"))


## A dim corner label that never takes clicks. Callers place it (default: bottom-left).
static func make_label() -> Label:
	var label := Label.new()
	label.name = "BuildVersion"
	label.text = "build " + text()
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_left = 10.0
	label.offset_top = -26.0
	label.offset_bottom = -6.0
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.66, 0.75))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
