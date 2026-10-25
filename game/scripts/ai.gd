extends Node
## ИИ музея. Режимы: офлайн (команды + Википедия), веб-чат как в «Наставнике» (Android, скрытый WebView со входом),
## OpenAI-совместимый API (ключ). Ответ ИИ может содержать JSON {"actions":[...], "images":[...], "links":[...]}.
signal reply(text: String, data: Dictionary)
signal status(text: String)

const PROVIDERS := ["offline", "web:grok", "web:deepseek", "web:gigachat", "web:qwen", "api"]
const PROVIDER_NAMES := ["Без ИИ (команды + Википедия)", "Grok (веб-чат, вход)", "DeepSeek (веб-чат, вход)", "GigaChat (веб-чат, вход)", "Qwen (веб-чат, вход)", "API-ключ (OpenAI-совместимый)"]

var wiki: Node
var plugin: Object = null
var pending := {}   # id -> true
var seq := 0

const SYSTEM := """Ты — гид-экскурсовод интерактивного 3D-музея. Отвечай по-русски, увлекательно и точно, 3–8 предложений.
Строго без политики: не обсуждай политиков, партии, выборы, пропаганду, современные конфликты — вежливо откажись и предложи искусство, науку, природу, историю культуры.
Ты можешь менять музей. Если пользователь просит создать зал/стеллаж, добавить экспонаты, найти картинки — В КОНЦЕ ответа добавь ОДИН блок ```json с объектом:
{"actions":[
 {"type":"create_hall","name":"Импрессионисты"},
 {"type":"create_shelf","hall":"Импрессионисты","name":"Клод Моне","query":"Клод Моне картины"},
 {"type":"add_exhibit","hall":"Импрессионисты","shelf":"Клод Моне","title":"Впечатление. Восходящее солнце","author":"Клод Моне","date":"1872","description":"…","wiki":"Впечатление. Восходящее солнце","image_url":""},
 {"type":"remove_exhibit","title":"…"}, {"type":"remove_shelf","hall":"…","name":"…"}, {"type":"rename_hall","name":"…","new_name":"…"}, {"type":"goto_hall","name":"…"}],
 "image_queries":["Claude Monet Impression Sunrise"],
 "images":[{"url":"https://upload.wikimedia.org/…","caption":"…"}],
 "links":[{"title":"…","url":"https://…"}]}
Правила: create_shelf с полем query приложение само наполнит экспонатами из Википедии (5–6 шт.). Для add_exhibit давай точное название статьи Википедии в "wiki" — картинку приложение найдёт само; image_url указывай только если уверен в прямой ссылке на upload.wikimedia.org. На один стеллаж — до 6 экспонатов. Если менять музей не нужно, но полезны картинки — дай только image_queries/links. JSON должен быть валидным."""

func _ready() -> void:
	if Engine.has_singleton("MuzejAI"):
		plugin = Engine.get_singleton("MuzejAI")
		plugin.connect("ai_result", _on_plugin_result)
		plugin.connect("ai_error", _on_plugin_error)

func web_supported() -> bool:
	return plugin != null

func login(provider: String) -> void:
	if plugin: plugin.call("login", provider.trim_prefix("web:"))

func build_prompt(user: String, ctx: Dictionary, image_mode: String) -> String:
	var s := SYSTEM + "\n\nРежим картинок: " + ("давай прямые ссылки на изображения в images и image_queries" if image_mode != "links" else "давай ссылки (links) на страницы с изображениями и image_queries") + "."
	s += "\nСостояние музея: залы — " + ", ".join(ctx.get("halls", [])) + ". Пользователь сейчас в зале «%s»." % ctx.get("hall", "")
	if ctx.has("exhibit"):
		var e: Dictionary = ctx["exhibit"]
		s += "\nПеред пользователем экспонат: «%s» %s %s. %s (стеллаж «%s»). Вопросы вроде «что это?» относятся к нему." % [e.get("title", ""), e.get("author", ""), e.get("date", ""), String(e.get("desc", "")).left(300), ctx.get("shelf", "")]
	s += "\n\nСообщение пользователя: " + user
	return s

func ask(provider: String, user: String, ctx: Dictionary, settings: Dictionary) -> void:
	if provider == "offline" or (provider.begins_with("web:") and plugin == null):
		if provider != "offline": status.emit("Веб-чат доступен только в Android-версии — отвечаю офлайн.")
		await offline(user, ctx); return
	var prompt := build_prompt(user, ctx, settings.get("image_mode", "embed"))
	status.emit("ИИ думает…")
	if provider == "api":
		await _api(prompt, settings); return
	seq += 1
	pending[str(seq)] = true
	plugin.call("ask", str(seq), provider.trim_prefix("web:"), prompt)

func _on_plugin_result(id: String, text: String) -> void:
	pending.erase(id); _emit_parsed(text)

func _on_plugin_error(id: String, msg: String) -> void:
	pending.erase(id); reply.emit("(!) " + msg, {})

func _api(prompt: String, st: Dictionary) -> void:
	var base: String = String(st.get("api_url", "https://api.x.ai/v1")).trim_suffix("/")
	var key: String = st.get("api_key", "")
	if key == "":
		reply.emit("(!) Укажите API-ключ в настройках или выберите веб-чат / офлайн-режим.", {}); return
	var h := HTTPRequest.new(); h.timeout = 120; add_child(h)
	var body := JSON.stringify({"model": st.get("api_model", "grok-3-mini"), "messages": [{"role": "user", "content": prompt}], "temperature": 0.6})
	h.request(base + "/chat/completions", PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + key]), HTTPClient.METHOD_POST, body)
	var r: Array = await h.request_completed
	h.queue_free()
	var j = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8()) if r[0] == 0 else null
	if r[1] != 200 or j == null or not j.has("choices"):
		reply.emit("(!) Ошибка API (%s): %s" % [r[1], (r[3] as PackedByteArray).get_string_from_utf8().left(300)], {}); return
	_emit_parsed(String(j["choices"][0]["message"]["content"]))

func _emit_parsed(text: String) -> void:
	var p := parse_reply(text)
	reply.emit(p["text"], p["data"])

## Разбор ответа: текст + JSON-блок с действиями. Терпим к markdown и мусору вокруг.
static func parse_reply(text: String) -> Dictionary:
	var data := {}
	var clean := text
	var k := text.find("\"actions\"")
	if k < 0: k = text.find("\"image_queries\"")
	if k < 0: k = text.find("\"images\"")
	if k >= 0:
		var st := text.rfind("{", k)
		while st >= 0:
			var en := _match_brace(text, st)
			if en > 0:
				var j = JSON.parse_string(text.substr(st, en - st + 1))
				if j is Dictionary:
					data = j
					clean = text.left(st) + text.substr(en + 1)
					break
			st = text.rfind("{", st - 1) if st > 0 else -1
	clean = clean.replace("```json", "").replace("```", "").strip_edges()
	if data.has("actions") and not (data["actions"] is Array): data["actions"] = []
	return {"text": clean, "data": data}

static func _match_brace(s: String, st: int) -> int:
	var d := 0; var q := false; var esc := false
	for i in range(st, s.length()):
		var c := s[i]
		if q:
			if esc: esc = false
			elif c == "\\": esc = true
			elif c == "\"": q = false
			continue
		if c == "\"": q = true
		elif c == "{": d += 1
		elif c == "}":
			d -= 1
			if d == 0: return i
	return -1

## Офлайн: распознавание команд на русском без ИИ.
static func parse_command(t: String) -> Dictionary:
	var s := t.strip_edges()
	var lo := s.to_lower()
	var re := RegEx.new()
	re.compile("(?i)(созда|сдела|добав|построй|открой)\\S*\\s+(мне\\s+)?(нов\\S*\\s+)?(зал|стеллаж|полк\\S*|витрин\\S*)\\s*(с|со|про|о|об|по|на тему|:)?\\s+(.+)")
	var m := re.search(lo)
	if m:
		var kind := "hall" if m.get_string(4) == "зал" else "shelf"
		var topic := s.substr(m.get_start(6), m.get_end(6) - m.get_start(6)).strip_edges().trim_suffix(".").trim_suffix("!")
		return {"cmd": kind, "topic": topic}
	re.compile("(?i)(найди|покажи|ищи)\\s+(мне\\s+)?(картинк\\S*|изображени\\S*|фото\\S*)\\s*(с|про|о|об)?\\s*(.*)")
	m = re.search(lo)
	if m: return {"cmd": "images", "topic": s.substr(m.get_start(5), m.get_end(5) - m.get_start(5)).strip_edges()}
	re.compile("(?i)^(а |и |так,? )?(что это|что за|кто это|расскажи (об этом|про это|подробнее))")
	if re.search(lo): return {"cmd": "this"}
	re.compile("(?i)(расскажи|что такое|кто такой|кто такая)\\s+(про|о|об)?\\s*(.+)")
	m = re.search(lo)
	if m: return {"cmd": "about", "topic": s.substr(m.get_start(3), m.get_end(3) - m.get_start(3)).strip_edges().trim_suffix("?")}
	return {"cmd": "about", "topic": s.trim_suffix("?")}

func offline(user: String, ctx: Dictionary) -> void:
	var c := parse_command(user)
	if wiki.is_political(user):
		reply.emit("Я гид без политики Давайте лучше об искусстве, науке, природе или истории культуры.", {}); return
	match c["cmd"]:
		"hall":
			var topic: String = c["topic"]
			var words := []
			for w in topic.split(" "):
				if w.ends_with("ами") and w.length() > 5: w = w.left(w.length() - 3) + "ы"
				elif w.ends_with("ями") and w.length() > 5: w = w.left(w.length() - 3) + "и"
				words.append(w)
			var name := " ".join(words).left(40)
			name = name.left(1).to_upper() + name.substr(1)
			reply.emit("Создаю зал «%s» и наполняю его экспонатами из Википедии…" % name, {"actions": [
				{"type": "create_hall", "name": name},
				{"type": "create_shelf", "hall": name, "name": name, "query": topic},
				{"type": "create_shelf", "hall": name, "name": name + ": ещё", "query": topic + " произведение", "skip": 6},
				{"type": "goto_hall", "name": name}]})
		"shelf":
			reply.emit("Добавляю стеллаж «%s» в зал «%s»…" % [c["topic"], ctx.get("hall", "")], {"actions": [
				{"type": "create_shelf", "hall": ctx.get("hall", ""), "name": c["topic"], "query": c["topic"]}]})
		"images":
			var topic2: String = c["topic"]
			if topic2 == "" and ctx.has("exhibit"): topic2 = ctx["exhibit"]["title"]
			reply.emit("Ищу изображения: %s" % topic2, {"image_queries": [topic2]})
		_:
			var topic3: String = c.get("topic", "")
			if c["cmd"] == "this" or (topic3.length() < 4 and ctx.has("exhibit")):
				if not ctx.has("exhibit"):
					reply.emit("Подойдите к экспонату и посмотрите на него — тогда я пойму, о чём вы спрашиваете.", {}); return
				topic3 = ctx["exhibit"]["title"]
			status.emit("Ищу в Википедии…")
			var d: Dictionary = await wiki.summary(topic3)
			if d.is_empty():
				reply.emit("Не нашёл «%s» в Википедии. Подключите ИИ в настройках для свободных вопросов." % topic3, {}); return
			reply.emit("[b]%s[/b]\n%s" % [d["title"], d["desc"]], {"links": [{"title": "Статья в Википедии", "url": d.get("src", "")}], "image_queries": [d["title"]]})
