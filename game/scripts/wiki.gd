extends Node
## Открытые источники: Википедия (ru/en) и Wikimedia Commons. Без ключей.
const UA := "IIMuzej/1.0 (Godot; personal museum app)"
const BAN := ["политик", "политич", "партия", "партии", "президент", "выбор", "депутат", "пропаганд", "революц",
	"диктат", "фашиз", "нацизм", "коммунизм", "митинг", "санкци", "парламент", "премьер-министр", "генсек",
	"ленин", "сталин", "гитлер", "муссолини", "путин", "трамп", "байден", "зеленск", "навальн", "мао цзэдун",
	"politic", "propaganda", "election", "president", "dictator", "nazi", "communis", "fascis", "parliament"]

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
	var u := "https://%s.wikipedia.org/w/api.php?action=query&format=json&origin=*&generator=search&gsrsearch=%s&gsrlimit=%d&prop=pageimages|extracts|info&inprop=url&piprop=thumbnail&pithumbsize=500&exintro=1&explaintext=1&exsentences=4&exlimit=max&redirects=1" % [lang, query.uri_encode(), n * 3]
	var j = await get_json(u)
	var out := []
	if j == null or not j.has("query"): return out
	var pages: Array = j["query"]["pages"].values()
	pages.sort_custom(func(a, b): return a.get("index", 0) < b.get("index", 0))
	for p in pages:
		if not p.has("thumbnail"): continue
		var t: String = p.get("title", ""); var d: String = p.get("extract", "")
		if is_political(t + " " + d): continue
		var img: String = p["thumbnail"]["source"]
		if img.ends_with(".svg.png"): continue
		out.append({"title": t, "desc": d, "img": img, "src": p.get("fullurl", ""), "lic": "Текст: Википедия (CC BY-SA 4.0); изображение: Wikimedia Commons"})
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
		return {"title": p.get("title", ""), "desc": p.get("extract", ""), "src": p.get("fullurl", ""), "img": ""}
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
		var lic := ""
		var md: Dictionary = ii.get("extmetadata", {})
		if md.has("LicenseShortName"): lic = String(md["LicenseShortName"]["value"])
		out.append({"url": ii.get("thumburl", ii.get("url", "")), "page": ii.get("descriptionurl", ""), "caption": t, "lic": lic})
		if out.size() >= n: break
	return out
