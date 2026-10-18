class_name Credits
extends RefCounted
## The Credits screen: who made what, and every license the shipped game must carry.

const SOURCE_URL := "https://github.com/BRAITG/zero-gx"
## Packed into the APK by the export preset's include filter.
const LICENSE_FILES := [
	["GNU Affero General Public License, version 3 (Zero-GX)", "res://LICENSE"],
	["Additional permission under section 7 (Zero-GX)", "res://LICENSE-EXCEPTION"],
	["SIL Open Font License 1.1 (Orbitron)", "res://assets/fonts/Orbitron-OFL.txt"],
	["SIL Open Font License 1.1 (Exo 2)", "res://assets/fonts/Exo2-OFL.txt"],
	["CC0 1.0 (Kenney Sci-fi Sounds)", "res://assets/sounds/Kenney-SciFi-License.txt"],
	["CC0 1.0 (Kenney Interface Sounds)", "res://assets/sounds/Kenney-Interface-License.txt"],
]


static func open(parent: Node) -> Overlay:
	var o := Overlay.open(parent, "Credits")
	o.heading("Zero-GX")
	o.paragraph("Copyright © 2026 the Zero-GX contributors. Zero-GX is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License, version 3 or (at your option) any later version. It comes with no warranty. An additional permission allows linking it with Google Play's client libraries. Source code: %s" % SOURCE_URL)
	o.heading("Fonts")
	o.paragraph("Orbitron. Copyright 2018 The Orbitron Project Authors (https://github.com/theleagueof/orbitron), with Reserved Font Name \"Orbitron\". Licensed under the SIL Open Font License 1.1.")
	o.paragraph("Exo 2. Copyright 2013 The Exo 2 Project Authors (https://github.com/googlefonts/Exo-2.0). Licensed under the SIL Open Font License 1.1.")
	o.heading("Sound effects")
	o.paragraph("Sci-fi Sounds and Interface Sounds by Kenney (https://kenney.nl), dedicated to the public domain under CC0 1.0. The ambient drone is synthesized by the game.")
	o.heading("Engine")
	o.paragraph("Made with Godot Engine (https://godotengine.org).")
	o.paragraph(Engine.get_license_text(), 16, Style.INK_DIM)
	o.heading("Godot's third-party components")
	var parts := PackedStringArray()
	for component in Engine.get_copyright_info():
		for part in component.parts:
			parts.append("%s: %s (%s)" % [component.name, ", ".join(part.copyright), part.license])
	o.paragraph("\n".join(parts), 16, Style.INK_DIM)
	o.heading("License texts")
	for entry in LICENSE_FILES:
		o.paragraph(entry[0], 22)
		o.paragraph(FileAccess.get_file_as_string(entry[1]), 14, Style.INK_DIM)
	var licenses: Dictionary = Engine.get_license_info()
	for name: String in licenses:
		o.paragraph("%s (Godot component)" % name, 22)
		o.paragraph(licenses[name], 14, Style.INK_DIM)
	return o
