extends SceneTree
const ImagesT := preload("res://scripts/images.gd")
func _initialize() -> void:
	var f := FileAccess.open("res://data/museum.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	var urls := {}
	for h in d["halls"]:
		for s in h["shelves"]:
			for e in s["exhibits"]:
				if String(e.get("img", "")) != "": urls[e["img"]] = true
	var ok := 0
	for u in urls.keys():
		var b := FileAccess.get_file_as_bytes("res://pics/%s.bin" % String(u).md5_text())
		if ImagesT._tex(b) != null: ok += 1
	print("OFFLINE_TEXTURES %d/%d" % [ok, urls.size()])
	quit(0 if ok == urls.size() else 1)
