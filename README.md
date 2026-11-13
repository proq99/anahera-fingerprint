# Сканер отпечатков на Chromebook Anahera (Ubuntu + DMS)

Как заставить работать встроенный сканер отпечатков на Google **Anahera**
(плата Brya, HP Elite c640 G3) под обычным Linux. Проверено на Ubuntu 26.04
с Dux Modular Shell (DMS): экран блокировки разблокируется пальцем.

## Почему не работает из коробки

Сенсор подключён не по USB, а через отдельный микроконтроллер ChromeOS
(FPMCU, чип `bloonchipper`), он виден как `/dev/cros_fp`. В обычном libfprint
драйвера для него нет: `fprintd-list` пишет «No devices available».

Драйвер `crfpmoc` есть только в форке, который ещё не принят в основной
проект ([libfprint MR !512](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/512)).
Здесь используется ветка `feature/crfpmoc` форка
[Xelef2000/libfprint](https://gitlab.freedesktop.org/Xelef2000/libfprint),
закреплённая на коммите `5644259`, с двумя патчами.

## Патчи

- `patches/0001-…` — три исправления драйвера (они же описаны на
  [форуме chrultrabook](https://forum.chrultrabook.com/t/new-fix-for-the-fingerprint-reader-hp-elite-dragonfly-chromebook/9224)):
  1. Команды `FP_MODE` ждут ответ правильного размера. Без этого запись
     отпечатка падает с «Message too long».
  2. Исправлен обработчик событий сенсора. Без этого fprintd падает при
     первом касании.
  3. Ключ шифрования (seed) и context не случайные, а постоянные. Иначе
     отпечатки перестают работать в следующем сеансе и после перезагрузки.
- `patches/0002-…` — исправление `tests/meson.build`: без него сборка
  ломается при `-Dintrospection=false`.

## Установка

```bash
./install-fingerprint.sh
```

Скрипт ставит пакеты для сборки, скачивает форк, накладывает патчи, собирает
и ставит libfprint в `/usr/local`. Системные пакеты Ubuntu не трогаются, а
копия в `/usr/local` загружается первой.

Потом:

1. Перезагрузиться.
2. Записать отпечаток: `fprintd-enroll -f right-index-finger`.
   Сообщение `enroll-retry-scan` на каждом касании — это нормально.
3. Проверить: `fprintd-verify`.
4. Включить в DMS: Настройки → Lock Screen → Fingerprint, или командой
   `dms ipc call settings set enableFprint true`.

Ещё пальцы: `fprintd-enroll -f left-index-finger` и т.д. Сенсор хранит не
больше 5 отпечатков. Удалить все: `fprintd-delete $USER`.

## Отпечаток для sudo

```bash
sudo pam-auth-update --enable fprintd
```

Проверка: `sudo -k && sudo true`, должно попросить приложить палец. Пароль
спросит после неудачной попытки, через 10 секунд или по Ctrl+C. Включается
для всего, что использует `common-auth`: `sudo`, `su`, вход в TTY, polkit.
Выключить: `sudo pam-auth-update --disable fprintd`.

## Если экран блокировки перестал принимать палец

Сканер может занять только одна программа за раз. Если при блокировке
запускаются два экрана блокировки, второй не получит сенсор. В журнале это
видно так:

```
fprintd: ... call method 'Claim' ... Device was already claimed
```

Пример: после включения отпечатка для sudo hyprlock тоже начинает брать
сканер (его PAM подключает `common-auth`). Если hypridle запускает hyprlock
одновременно с экраном DMS, палец на экране DMS не срабатывает. Решение:
пусть hypridle блокирует через DMS. В `~/.config/hypr/hypridle.conf`:

```
general {
    lock_cmd = dms ipc call lock lock
    ...
}
```

Потом `systemctl --user restart hypridle`.

Смотреть журнал после неудачной попытки:

```bash
journalctl -b --since "-5min" | grep -iE 'fprint|pam'
```

## Удаление

```bash
./install-fingerprint.sh --uninstall
```

Или вручную:

```bash
sudo rm /usr/local/lib/x86_64-linux-gnu/libfprint-2.so* && sudo ldconfig && sudo systemctl restart fprintd
```

Когда драйвер попадёт в libfprint из Ubuntu, эту сборку можно удалить.

## Железо, на котором проверено

- Google Anahera, Ubuntu 26.04, fprintd 1.94.5
- FPMCU: RO `bloonchipper_v2.0.5938-197506c1`, RW `bloonchipper-v2.0.29318-6543bef`
