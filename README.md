# ИИ-Музей (Godot 4.7.2)

Интерактивный 3D-музей со встроенным ИИ-гидом. ПК (Windows), Android, браузер (Web/PWA).

- **Движок:** Godot 4.7.2 (MIT, полностью бесплатный), рендер Compatibility (OpenGL ES 3 / WebGL2): работает на телефонах, ПК и в браузере.
- **Данные:** 557 экспонатов в 13 залах. Источники: Wikidata (CC0), изображения Wikimedia Commons (лицензия указана на странице каждого файла), справки из Википедии (CC BY-SA 4.0). Политические темы отфильтрованы.
- **Управление:** ПК: WASD или стрелки, мышь (клик захватывает курсор, Esc отпускает), E открывает карточку, T открывает чат, Shift ускоряет шаг. Телефон: джойстик слева, свайп справа поворачивает обзор, касание экспоната открывает карточку.
- **ИИ-гид** знает, на какой экспонат вы смотрите («А что это за картина?»). Он ищет картинки: в настройках выбирается, встраивать их или давать ссылки. По командам вроде «Сделай мне зал с импрессионистами» или «создай стеллаж про древний Египет» ИИ возвращает JSON-действия (`create_hall`, `create_shelf`, `add_exhibit`, `remove_*`, `rename_hall`, `goto_hall`), а приложение сразу применяет их и сохраняет в `user://museum.json`. Экспорт и импорт работают через буфер обмена или файл.
- **Режимы ИИ:** без ИИ: офлайн-разбор команд плюс Википедия и Commons. Веб-чат Grok, DeepSeek, GigaChat или Qwen: вход один раз, дальше скрытый WebView с `capture.js`, как в «Наставнике» (только в Android-версии, плагин `android/build/src/main/java/com/godot/game/MuzejAIPlugin.java`). Ещё можно подключить любой OpenAI-совместимый API по ключу; ключ хранится в зашифрованном `user://settings.cfg`.

## Сборка
```
cd game
godot --headless --path . --script res://tests/run_tests.gd   # тесты
godot --headless --path . --export-release "Windows Desktop"
godot --headless --path . --export-release "Web"              # однопоточная сборка, подходит для GitHub Pages
godot --headless --path . --export-release "Android"          # gradle-сборка, arm64
```
Данные заново собираются так: `cd tools && node q.mjs && node p.mjs && node build.mjs`.

Android-шаблон: `game/android/build` хранит только плагин и манифест. Перед сборкой распакуйте `android_source.zip` из export templates 4.7.2 поверх него, не затирая `MuzejAIPlugin.java`, `AndroidManifest.xml` и `res/raw/capture.js`.

Сайт: https://ivanivorontsov-sudo.github.io/ii-muzej/
