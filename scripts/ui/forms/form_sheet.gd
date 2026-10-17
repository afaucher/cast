class_name FormSheet
extends PaperPanel
## A whole form: PaperPanel + FormHeader + a body column for FormSections / FormRows. The carbon colour
## names the screen family ("white", "canary", "pink", "gold", "green", "blue").

var header: FormHeader
var body: VBoxContainer


func _init(form_no: String = "", title: String = "", company: String = "", copy_caption: String = "", copy_text: String = "", carbon_name: String = "white", title_size: int = 40) -> void:
	super(FormTheme.carbon(carbon_name))
	set_padding(0, 0, 0, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)
	header = FormHeader.new(form_no, title, company, copy_caption, copy_text, title_size)
	root.add_child(header)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(body)
