# Voice Assistance для Quickshell

Исходники core включены в конфигурацию end-4. Служба запускает
`~/.config/quickshell/ii/scripts/voice-assistant/src/index.ts` через Bun.
Отдельный checkout voice-assistant и node_modules для запуска не нужны:
core использует встроенные модули Bun и Node.

Интерфейс — вкладка Voice Assistance в левой панели Quickshell. Она подключается к
`ws://127.0.0.1:8765`. HTTP на этом порту возвращает состояние сервиса.

Нижний блок содержит отдельный выбор модели. Выбор сохраняется в
`Persistent.states.voiceAssistant.model` и не меняет модель Intelligence.
Список моделей общий с Quickshell; поддерживаются OpenAI-совместимый формат,
Mistral и Gemini. Backend читает ключ провайдера из системного keyring
(`secret-tool lookup application illogical-impulse`) перед каждым запросом.
Ключ не передаётся через WebSocket и не дублируется в настройках Voice Assistance.
Для этого требуется установленный `secret-tool` и разблокированный keyring.

Кнопка «История» переключает область сообщений на отдельный экран чатов
с кнопками «Назад» и «Новый чат». Заголовки ограничены одной строкой,
текущий чат отмечен. История не накладывается на разговор или поле ввода.
При подключении восстанавливается выбранный чат. Его идентификатор хранится
рядом с SQLite в `current-session.json`. Во время генерации ответа переключение
чатов блокируется, чтобы ответ сохранился в исходном разговоре.

## Локальные данные

Пути учитывают XDG_CONFIG_HOME, XDG_DATA_HOME и XDG_STATE_HOME. По умолчанию:

- `~/.config/voice-assistant/config.json` — настройки API и ключи;
- `~/.local/share/voice-assistant/libvosk.so` — библиотека Vosk;
- `~/.local/share/voice-assistant/models/vosk/` — модель распознавания;
- `~/.local/share/voice-assistant/whisper/` — whisper-server и его библиотеки;
- `~/.local/share/voice-assistant/models/ggml-large-v3-turbo-q5_0.bin` — модель Whisper;
- `~/.local/state/voice-assistant/history.sqlite` — история чата.

Ключи, история, аудио и веса моделей не входят в snapshot. Для первого
переноса с существующего приложения выполните:

```sh
python3 ~/.config/quickshell/ii/scripts/voice-assistant/import-local.py \
  --from /путь/к/исходному-проекту
systemctl --user daemon-reload
systemctl --user start voice-assistant.service
```

Импорт копирует нужные ресурсы; рабочая служба больше не обращается к исходному
каталогу. Уже существующие локальные настройки, модель и история сохраняются.
История переносится через SQLite backup, включая данные из WAL.

Если STT настроен на локальный HTTP-адрес с путём `/inference`, core запускает
Whisper из локальных ресурсов и ждёт готовности перед захватом звука.
Выключение службы останавливает и Whisper. При использовании внешнего STT
локальный сервер не запускается. Импорт переносит Whisper и модель, если они
есть в исходном проекте.

На другой машине установите Bun в `~/.bun/bin/bun`, команды `pactl` и
`parec`, совместимую libvosk.so и модель Vosk. Локальную конфигурацию можно
создать из config.example.json. Секреты задаются на целевой машине.
Служба запускается переключателем вкладки; автоматический запуск при входе
не настраивается.

Код адаптирован из локального проекта interview-hypr-assistant (MIT).
Лицензия исходного проекта сохранена в LICENSE. Изменения этой копии:
XDG-пути настроек, ресурсов и истории; режим WebSocket для Quickshell;
HTTP-проверка состояния вместо зависимости от собранного web-client.
