extends Node
## Открытые источники: Википедия (ru/en) и Wikimedia Commons. Без ключей.
const UA := "IIMuzej/1.0 (Godot; personal museum app)"
const BAN := ["политик", "политич", "партия", "партии", "президент", "выбор", "депутат", "пропаганд", "революц",
	"диктат", "фашиз", "нацизм", "коммунизм", "митинг", "санкци", "парламент", "премьер-министр", "генсек",
	"ленин", "сталин", "гитлер", "муссолини", "путин", "трамп", "байден", "зеленск", "навальн", "мао цзэдун",
	"politic", "propaganda", "election", "president", "dictator", "nazi", "communis", "fascis", "parliament"]

## Разрешены только свободные лицензии, для которых достаточно атрибуции (см. legal-audit.md)
static func license_ok(m: Dictionary) -> bool:
	var lic := String(m.get("lic", "")).to_lower()
	if String(m.get("nonfree", "")) not in ["", "false"]: return false
	if lic.find("fair use") >= 0 or lic.find("non-free") >= 0: return false
	if RegEx.create_from_string("\\b(nc|nd)\\b").search(lic): return false
	if String(m.get("restr", "")).to_lower().find("insignia") >= 0: return false
	return RegEx.create_from_string("^(public domain|pd\\b|pd-|cc0|cc[- ]by(-sa)?|gfdl|gnu free|fal\\b|free art|attribution|no restrictions|copyrighted free use)").search(lic) != null

static func strip_html(s: String) -> String:
	return RegEx.create_from_string("<[^>]+>").sub(s, "", true).replace("&amp;", "&").replace("&quot;", "\"").strip_edges()

## Метаданные файлов Commons (лицензия, автор) по именам файлов
func commons_meta(files: Array) -> Dictionary:
	var out := {}
	if files.is_empty(): return out
	var t := "|".join(files.map(func(f): return "File:" + String(f)))
	var j = await get_json("https://commons.wikimedia.org/w/api.php?action=query&format=json&origin=*&prop=imageinfo&iiprop=extmetadata|url&iiurlwidth=500&titles=" + t.uri_encode())
	if j == null or not j.has("query"): return out
	var norm := {}
	for n in j["query"].get("normalized", []): norm[n["to"]] = n["from"]
	for p in j["query"]["pages"].values():
		if p.has("missing") or not p.has("imageinfo"): continue
		var ii: Dictionary = p["imageinfo"][0]; var md: Dictionary = ii.get("extmetadata", {})
		var g := func(k): return strip_html(String(md.get(k, {}).get("value", "")))
		var m := {"lic": g.call("LicenseShortName"), "lic_url": g.call("LicenseUrl"), "artist": g.call("Artist").left(120), "nonfree": g.call("NonFree"),
			"restr": g.call("Restrictions"), "page": ii.get("descriptionurl", ""), "thumb": ii.get("thumburl", ""), "file": String(p["title"]).trim_prefix("File:")}
		out[String(norm.get(p["title"], p["title"])).trim_prefix("File:")] = m
		out[m["file"]] = m
	return out

static func attribution(m: Dictionary) -> Dictionary:
	return {"img_author": m.get("artist", ""), "img_lic": m.get("lic", ""), "img_lic_url": m.get("lic_url", ""), "img_page": m.get("page", ""), "img_file": m.get("file", "")}

static func is_political(s: String) -> bool:
	var l := s.to_lower()
	for w in BAN:
		if l.find(w) >= 0: return true
	return false

func get_json(url: String) -> Variant:
	var h := HTTPRequest.new()
	h.timeout = 30
	add_child(h)
	var hd := PackedStringArray(["User-Agent: " + UA]) if OS.get_name() != "Web" else PackedStringArray()
	if h.request(url, hd) != OK:
		h.queue_free(); return null
	var r: Array = await h.request_completed
	h.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return null
	return JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())

## Поиск статей с картинкой — готовые экспонаты
func search_exhibits(query: String, n := 6, lang := "ru") -> Array:
	var u := "https://%s.wikipedia.org/w/api.php?action=query&format=json&origin=*&generator=search&gsrsearch=%s&gsrlimit=%d&prop=pageimages|extracts|info&inprop=url&piprop=thumbnail|name&pithumbsize=500&exintro=1&explaintext=1&exsentences=4&exlimit=max&redirects=1" % [lang, query.uri_encode(), n * 3]
	var j = await get_json(u)
	var out := []
	if j == null or not j.has("query"): return out
	var pages: Array = j["query"]["pages"].values()
	pages.sort_custom(func(a, b): return a.get("index", 0) < b.get("index", 0))
	var meta: Dictionary = await commons_meta(pages.filter(func(p): return p.has("pageimage")).map(func(p): return p["pageimage"]).slice(0, 45))
	for p in pages:
		if not p.has("thumbnail"): continue
		var t: String = p.get("title", ""); var d: String = p.get("extract", "")
		if is_political(t + " " + d): continue
		var img: String = p["thumbnail"]["source"]
		if img.ends_with(".svg.png"): continue
		var m: Dictionary = meta.get(String(p.get("pageimage", "")).replace("_", " "), meta.get(p.get("pageimage", ""), {}))
		if m.is_empty() or not license_ok(m): continue   # локальные (fair use) файлы Википедии и несвободные — отбрасываем
		var ex := {"title": t, "desc": d, "img": m["thumb"] if m["thumb"] != "" else img, "src": p.get("fullurl", ""), "text_lic": "wikipedia-%s" % lang}
		ex.merge(attribution(m))
		out.append(ex)
		if out.size() >= n: break
	if out.is_empty() and lang == "ru":
		return await search_exhibits(query, n, "en")
	return out

## Краткая справка по названию
func summary(title: String) -> Dictionary:
	var r := await search_exhibits(title, 1)
	if not r.is_empty(): return r[0]
	var u := "https://ru.wikipedia.org/w/api.php?action=query&format=json&origin=*&generator=search&gsrsearch=%s&gsrlimit=1&prop=extracts|info&inprop=url&exintro=1&explaintext=1&exsentences=6" % title.uri_encode()
	var j = await get_json(u)
	if j and j.has("query"):
		var p: Dictionary = j["query"]["pages"].values()[0]
		return {"title": p.get("title", ""), "desc": p.get("extract", ""), "src": p.get("fullurl", ""), "img": "", "text_lic": "wikipedia-ru"}
	return {}

## Картинки из Wikimedia Commons
func images(query: String, n := 6) -> Array:
	var u := "https://commons.wikimedia.org/w/api.php?action=query&format=json&origin=*&generator=search&gsrnamespace=6&gsrsearch=%s&gsrlimit=%d&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=500" % [(query + " filetype:bitmap").uri_encode(), n * 2]
	var j = await get_json(u)
	var out := []
	if j == null or not j.has("query"): return out
	for p in j["query"]["pages"].values():
		if not p.has("imageinfo"): continue
		var ii: Dictionary = p["imageinfo"][0]
		var t: String = String(p.get("title", "")).trim_prefix("File:").get_basename()
		if is_political(t): continue
		var md: Dictionary = ii.get("extmetadata", {})
		var g := func(k): return strip_html(String(md.get(k, {}).get("value", "")))
		var m := {"lic": g.call("LicenseShortName"), "lic_url": g.call("LicenseUrl"), "artist": g.call("Artist").left(80), "nonfree": g.call("NonFree"), "restr": g.call("Restrictions")}
		if not license_ok(m): continue
		out.append({"url": ii.get("thumburl", ii.get("url", "")), "page": ii.get("descriptionurl", ""), "caption": t, "lic": "%s, %s" % [m["artist"], m["lic"]], "lic_url": m["lic_url"]})
		if out.size() >= n: break
	return out
