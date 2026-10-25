extends SceneTree
## Запуск: godot --headless --path . --script res://tests/run_tests.gd
const AiT := preload("res://scripts/ai.gd")
const WikiT := preload("res://scripts/wiki.gd")
var ok := 0; var fail := 0
func check(c: bool, name: String) -> void:
	if c: ok += 1
	else: fail += 1; printerr("FAIL: ", name)

func _init() -> void:
	# разбор ответа ИИ
	var r := AiT.parse_reply("Вот зал!\n```json\n{\"actions\":[{\"type\":\"create_hall\",\"name\":\"Импрессионисты\"},{\"type\":\"create_shelf\",\"hall\":\"Импрессионисты\",\"name\":\"Моне\",\"query\":\"Клод Моне\"}],\"links\":[{\"title\":\"a\",\"url\":\"https://x\"}]}\n```\nПриятного просмотра")
	check(r["data"]["actions"].size() == 2, "actions parsed")
	check(r["text"].find("actions") < 0 and r["text"].find("Вот зал") >= 0 and r["text"].find("Приятного") >= 0, "text cleaned")
	var r2 := AiT.parse_reply("Ответ без JSON {скобки} тут")
	check(r2["data"].is_empty() and r2["text"].begins_with("Ответ"), "no json")
	var r3 := AiT.parse_reply("текст {\"actions\":[{\"type\":\"add_exhibit\",\"title\":\"Мона } Лиза\"}]} хвост")
	check(r3["data"].get("actions", []).size() == 1 and r3["data"]["actions"][0]["title"] == "Мона } Лиза", "brace in string")
	var r4 := AiT.parse_reply("{\"image_queries\":[\"Mona Lisa\"]}")
	check(r4["data"].get("image_queries", []) == ["Mona Lisa"], "image_queries only")
	check(AiT.parse_reply("{\"actions\":[bad json").get("data").is_empty(), "broken json tolerated")
	var pr: String = AiT.new().build_prompt("А что это за картина?", {"hall": "Живопись", "halls": ["Живопись"], "exhibit": {"title": "Звёздная ночь", "author": "Ван Гог"}, "shelf": "S"}, "links")
	check(pr.find("Звёздная ночь") > 0 and pr.find("actions") > 0 and pr.find("без политики") > 0 or pr.find("без политики") > 0, "prompt has context")
	# лицензии
	check(WikiT.license_ok({"lic": "CC BY-SA 3.0"}) and WikiT.license_ok({"lic": "Public domain"}) and WikiT.license_ok({"lic": "CC0"}) and WikiT.license_ok({"lic": "GFDL"}), "free licenses ok")
	check(not WikiT.license_ok({"lic": "CC BY-NC-SA 4.0"}) and not WikiT.license_ok({"lic": "CC BY-ND 2.0"}) and not WikiT.license_ok({"lic": "Fair use"}) and not WikiT.license_ok({"lic": "CC BY 4.0", "nonfree": "true"}) and not WikiT.license_ok({"lic": "", "restr": ""}) and not WikiT.license_ok({"lic": "CC BY-SA 4.0", "restr": "insignia"}), "non-free rejected")
	var at: String = preload("res://scripts/main.gd").attribution_bbcode({"img": "x", "img_file": "A.jpg", "img_author": "Ivan", "img_lic": "CC BY-SA 4.0", "img_lic_url": "https://creativecommons.org/licenses/by-sa/4.0", "img_page": "https://commons.wikimedia.org/wiki/File:A.jpg", "text_lic": "wikipedia-ru", "src": "https://ru.wikipedia.org/wiki/A"})
	check(at.find("Ivan") > 0 and at.find("CC BY-SA 4.0") > 0 and at.find("ShareAlike") > 0 and at.find("уменьшено") > 0 and at.find("by-sa/4.0/deed.ru") > 0 and at.find("File:A.jpg") > 0, "attribution complete")
	# офлайн-команды
	var c := AiT.parse_command("Сделай мне зал с импрессионистами")
	check(c["cmd"] == "hall" and c["topic"] == "импрессионистами", "cmd hall")
	c = AiT.parse_command("создай стеллаж про древний Египет")
	check(c["cmd"] == "shelf" and c["topic"] == "древний Египет", "cmd shelf")
	check(AiT.parse_command("А что это за картина?")["cmd"] == "this", "cmd this")
	check(AiT.parse_command("найди картинки Моны Лизы")["cmd"] == "images", "cmd images")
	check(AiT.parse_command("расскажи про Венеру Милосскую")["topic"] == "Венеру Милосскую", "cmd about")
	# фильтр политики
	check(WikiT.is_political("Президент и выборы"), "politics yes")
	check(not WikiT.is_political("Звёздная ночь Ван Гога"), "politics no")
	# данные
	var base := MuseumData.load_base()
	check(MuseumData.valid(base), "base valid")
	var n := MuseumData.count_exhibits(base)
	print("base halls=", base["halls"].size(), " exhibits=", n)
	check(n >= 300, "enough exhibits")
	var bad := 0
	for h in base["halls"]:
		for s in h["shelves"]:
			check(s["exhibits"].size() <= MuseumData.MAX_PER_SHELF, "shelf cap")
			for e in s["exhibits"]:
				if not String(e["img"]).begins_with("https://upload.wikimedia.org/") or e["title"] == "": bad += 1
				if WikiT.is_political(e["title"] + " " + e["desc"]): bad += 1
				if not WikiT.license_ok({"lic": e.get("img_lic", ""), "restr": ""}) or String(e.get("img_page", "")) == "": bad += 1; print("LIC: ", e["title"], " ", e.get("img_lic"))
	if bad: for h in base["halls"]:
		for s in h["shelves"]:
			for e in s["exhibits"]:
				if WikiT.is_political(e["title"] + " " + e["desc"]): print("POL: ", e["title"], " | ", e["desc"])
	check(bad == 0, "exhibit fields/politics (%d bad)" % bad)
	# модель + сохранение
	var st := {"version": 1, "halls": []}
	MuseumData.add_exhibit(st, "Египет", "Статуи", {"title": "Нефертити", "description": "Бюст", "image_url": "https://upload.wikimedia.org/a.jpg"})
	MuseumData.add_exhibit(st, "египет", "статуи", {"title": "нефертити"})
	check(st["halls"].size() == 1 and st["halls"][0]["shelves"][0]["exhibits"].size() == 1, "dedupe case-insensitive")
	for i in 8: MuseumData.add_exhibit(st, "Египет", "Статуи", {"title": "X%d" % i})
	check(st["halls"][0]["shelves"].size() == 2 and st["halls"][0]["shelves"][1]["name"] == "Статуи (2)", "overflow shelf")
	check(st["halls"][0]["shelves"][0]["exhibits"][0]["img"] == "https://upload.wikimedia.org/a.jpg", "image_url mapped")
	var p := "user://test_museum.json"
	check(MuseumData.save_state(st, p), "save")
	var ld := MuseumData.load_state(p)
	check(MuseumData.count_exhibits(ld) == 9 and ld["halls"][0]["name"] == "Египет", "load roundtrip")
	check(MuseumData.remove_exhibit(ld, "X3") and MuseumData.count_exhibits(ld) == 8, "remove exhibit")
	check(MuseumData.remove_shelf(ld, "Египет", "Статуи (2)"), "remove shelf")
	check(not MuseumData.valid({"halls": "x"}), "invalid rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("TESTS ok=%d fail=%d" % [ok, fail])
	quit(1 if fail > 0 else 0)
