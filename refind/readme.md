# Оформление rEFInd

Тема **Nocturne**, скопированная из активной конфигурации
`/boot/EFI/refind/themes/nocturne` 19 октября 2026 года.
Фон, иконки, изображения выделения и `theme.conf` сохранены без изменений.

Тема использует фон на весь экран, иконки ОС размером 128 px и иконки
инструментов 48 px. Подсказки, стрелки и значки устройств скрыты.

## Подключение

rEFInd должен быть уже установлен. Команды выполняются из корня этого
репозитория; для другого расположения EFI-раздела скорректируй путь.

1. Создай резервную копию текущего конфига и, если она уже есть, темы:

   ```bash
   backup_dir="/boot/EFI/refind/backup-$(date +%Y%m%d-%H%M%S)"
   sudo mkdir -p "$backup_dir"
   sudo cp /boot/EFI/refind/refind.conf "$backup_dir/"
   if sudo test -d /boot/EFI/refind/themes/nocturne; then
       sudo cp -r /boot/EFI/refind/themes/nocturne "$backup_dir/"
   fi
   ```

2. Скопируй тему:

   ```bash
   sudo mkdir -p /boot/EFI/refind/themes/nocturne
   sudo cp -r refind/themes/nocturne/. /boot/EFI/refind/themes/nocturne/
   ```

3. Открой конфиг:

   ```bash
   sudoedit /boot/EFI/refind/refind.conf
   ```

   Добавь в конец файла следующую строку, если её ещё нет:

   ```text
   include themes/nocturne/theme.conf
   ```

   Если подключена другая тема, закомментируй её строку `include`.
   Проверь, что активная опция `textonly` не включает текстовый режим.
   Пути внутри `theme.conf` отсчитываются от каталога rEFInd, поэтому
   сохраняй расположение `themes/nocturne/`.

4. Оформление появится при следующем запуске rEFInd.

## Отключение и восстановление

Закомментируй `include themes/nocturne/theme.conf`, чтобы отключить тему.
Для полного возврата восстанови `refind.conf` и папку `nocturne` из
созданного резервного каталога.

В репозитории хранится только оформление. Настройки загрузки ОС,
тайм-аут, параметры ядра, EFI-программа, ключи и переменные rEFInd
остаются в локальной установке. Стандартный каталог `icons/` установленного
rEFInd нужен как запасной источник иконок, отсутствующих в теме.
