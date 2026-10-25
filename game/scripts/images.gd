extends Node
## Загрузка картинок экспонатов по HTTP с кэшем в user://img/
signal loaded(url: String, tex: Texture2D)
const MAX_PAR := 6
var queue: Array[String] = []
var busy := 0
var mem := {}          # url -> Texture2D
var waiting := {}      # url -> true
const UA := "IIMuzej/1.0 (Godot; personal museum app)"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://img")

func request(url: String, urgent := false) -> void:
	if url == "" : return
	if mem.has(url):
		loaded.emit.call_deferred(url, mem[url]); return
	if waiting.has(url):
		if urgent and queue.has(url): queue.erase(url); queue.push_front(url)
		return
	var p := "user://img/%s" % url.md5_text()
	if FileAccess.file_exists(p):
		var t := _tex(FileAccess.get_file_as_bytes(p))
		if t:
			mem[url] = t; loaded.emit.call_deferred(url, t); return
	waiting[url] = true
	if urgent: queue.push_front(url)
	else: queue.append(url)
	_pump()

func _pump() -> void:
	while busy < MAX_PAR and not queue.is_empty():
		var url: String = queue.pop_front()
		busy += 1
		var h := HTTPRequest.new()
		h.timeout = 40
		h.max_redirects = 6
		add_child(h)
		h.request_completed.connect(func(res, code, _hd, body):
			busy -= 1; h.queue_free(); waiting.erase(url)
			if res == HTTPRequest.RESULT_SUCCESS and code == 200:
				var t := _tex(body)
				if t:
					mem[url] = t
					var f := FileAccess.open("user://img/%s" % url.md5_text(), FileAccess.WRITE)
					if f: f.store_buffer(body); f.close()
					loaded.emit(url, t)
			_pump())
		var hd := PackedStringArray(["User-Agent: " + UA]) if OS.get_name() != "Web" else PackedStringArray()
		if h.request(url, hd) != OK:
			busy -= 1; h.queue_free(); waiting.erase(url)

static func _tex(b: PackedByteArray) -> Texture2D:
	if b.size() < 12: return null
	var img := Image.new()
	var e := ERR_FILE_UNRECOGNIZED
	if b[0] == 0xFF and b[1] == 0xD8: e = img.load_jpg_from_buffer(b)
	elif b[0] == 0x89 and b[1] == 0x50: e = img.load_png_from_buffer(b)
	elif b[0] == 0x52 and b[8] == 0x57: e = img.load_webp_from_buffer(b)
	elif b[0] == 0x47: return null
	if e != OK: return null
	var m: int = max(img.get_width(), img.get_height())
	if m > 1024:
		var k := 1024.0 / m
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
