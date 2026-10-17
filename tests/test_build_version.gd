extends TestCase
## BuildVersion.resolve: the menu's build stamp (see scripts/ui/build_version.gd).


func setup() -> void:
	eq(BuildVersion.resolve(true, "2026-10-17.143005\n", false), "2026-10-17.143005", "export: trailing newline stripped")
	eq(BuildVersion.resolve(true, String.chr(0xFEFF) + "2026-10-17.143005\r\n", false), "2026-10-17.143005", "BOM stripped")
	eq(BuildVersion.resolve(false, "", false), BuildVersion.UNKNOWN, "missing file")
	eq(BuildVersion.resolve(true, "  \n", false), BuildVersion.UNKNOWN, "blank file")
	eq(BuildVersion.resolve(true, "2026-10-17.143005", true), "dev (2026-10-17.143005)", "a source run never passes as a build")
	eq(BuildVersion.resolve(false, "", true), "dev (unversioned)", "source run, no file")
	check(BuildVersion.text().begins_with("dev ("), "tests run from source: " + BuildVersion.text())
	var label := BuildVersion.make_label()
	check(label.text.contains(BuildVersion.text()), "label shows the stamp")
	eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE, "label never eats clicks")
	label.free()
	finish()
