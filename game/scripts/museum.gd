class_name MuseumData
extends RefCounted
## Модель музея: {"version":1,"halls":[{"name","shelves":[{"name","exhibits":[{title,desc,author,date,collection,img,src,lic}]}]}]}
const SAVE := "user://museum.json"
const MAX_PER_SHELF := 6

static func load_base() -> Dictionary:
	var f := FileAccess.open("res://data/museum.json", FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text()) if f else null
	return j if j is Dictionary else {"version": 1, "halls": []}

static func load_state(path := SAVE) -> Dictionary:
	if FileAccess.file_exists(path):
		var j = JSON.parse_string(FileAccess.get_file_as_string(path))
		if valid(j): return j
	return load_base()

static func save_state(st: Dictionary, path := SAVE) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(st, "", false)); f.close(); return true

static func valid(j) -> bool:
	if not (j is Dictionary) or not j.has("halls") or not (j["halls"] is Array): return false
	for h in j["halls"]:
		if not (h is Dictionary) or not h.has("name") or not (h.get("shelves", []) is Array): return false
	return true

static func _eq(a: String, b: String) -> bool:
	return a.strip_edges().to_lower() == b.strip_edges().to_lower()

static func find_hall(st: Dictionary, name: String) -> Dictionary:
	for h in st["halls"]:
		if _eq(h["name"], name): return h
	return {}

static func hall_index(st: Dictionary, name: String) -> int:
	for i in st["halls"].size():
		if _eq(st["halls"][i]["name"], name): return i
	return -1

static func add_hall(st: Dictionary, name: String) -> Dictionary:
	var h := find_hall(st, name)
	if h.is_empty():
		h = {"name": name, "shelves": []}; st["halls"].append(h)
	return h

static func find_shelf(h: Dictionary, name: String) -> Dictionary:
	for s in h["shelves"]:
		if _eq(s["name"], name): return s
	return {}

static func add_shelf(st: Dictionary, hall: String, name: String) -> Dictionary:
	var h := add_hall(st, hall if hall != "" else "Мои стеллажи")
	var s := find_shelf(h, name)
	if s.is_empty():
		s = {"name": name, "exhibits": []}; h["shelves"].append(s)
	return s

static func add_exhibit(st: Dictionary, hall: String, shelf: String, ex: Dictionary) -> Dictionary:
	var s := add_shelf(st, hall, shelf if shelf != "" else "Новые экспонаты")
	if s["exhibits"].size() >= MAX_PER_SHELF:
		var n := 2
		while find_shelf(find_hall(st, hall if hall != "" else "Мои стеллажи"), "%s (%d)" % [s["name"], n]).get("exhibits", []).size() >= MAX_PER_SHELF: n += 1
		s = add_shelf(st, hall, "%s (%d)" % [s["name"], n])
	for s2 in find_hall(st, hall if hall != "" else "Мои стеллажи")["shelves"]:
		for e in s2["exhibits"]:
			if _eq(e.get("title", ""), ex.get("title", "")): return e
	var e2 := {"title": ex.get("title", "Экспонат"), "desc": ex.get("desc", ex.get("description", "")), "author": ex.get("author", ""),
		"date": str(ex.get("date", "")), "collection": ex.get("collection", ""), "img": ex.get("img", ex.get("image_url", "")),
		"src": ex.get("src", ""), "text_lic": ex.get("text_lic", "wikidata")}
	for k in ["img_author", "img_lic", "img_lic_url", "img_page", "img_file"]: e2[k] = ex.get(k, "")
	s["exhibits"].append(e2)
	return e2

static func remove_exhibit(st: Dictionary, title: String) -> bool:
	for h in st["halls"]:
		for s in h["shelves"]:
			for i in s["exhibits"].size():
				if _eq(s["exhibits"][i]["title"], title):
					s["exhibits"].remove_at(i); return true
	return false

static func remove_shelf(st: Dictionary, hall: String, name: String) -> bool:
	var h := find_hall(st, hall)
	if h.is_empty(): return false
	for i in h["shelves"].size():
		if _eq(h["shelves"][i]["name"], name):
			h["shelves"].remove_at(i); return true
	return false

static func count_exhibits(st: Dictionary) -> int:
	var n := 0
	for h in st["halls"]:
		for s in h["shelves"]: n += s["exhibits"].size()
	return n
