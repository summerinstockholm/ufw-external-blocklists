# UFW external blocklists for Ubuntu 24.04

Этот репозиторий защищает Ubuntu 24.04 сервер от IP-адресов и подсетей из внешних blocklist-источников:

- [CyberOK_Skipa_ips](https://github.com/tread-lightly/CyberOK_Skipa_ips/tree/main)
- [AS_Network_List](https://github.com/C24Be/AS_Network_List)

## Структура репозитория

```text
.
├── README.md
├── scripts
│   ├── install-ufw-blocklists.sh
│   └── update-ufw-blocklists.sh
└── systemd
    ├── ufw-blocklists.service
    └── ufw-blocklists.timer
```

## Смысл решения

Решение работает через **UFW** и **не трогает** `/etc/nftables.conf`.

Скрипты делают следующее:

- скачивают IPv4 CIDR-список из `CyberOK_Skipa_ips`;
- скачивают IPv4 blacklist из `AS_Network_List`;
- скачивают IPv6 blacklist из `AS_Network_List`;
- валидируют IPv4 и IPv6 отдельно;
- объединяют и дедуплицируют IPv4-источники;
- ведут IPv4-блоклист как управляемый блок внутри `/etc/ufw/before.rules`;
- ведут IPv6-блоклист как управляемый блок внутри `/etc/ufw/before6.rules`;
- вставляют managed-блоки в начало `*filter`-секции, то есть раньше стандартных UFW-правил, включая стандартные ICMP/ICMPv6 accept;
- не трогают существующие правила, добавленные через `ufw allow/deny/...`;
- обновляют блоклисты по `systemd timer`.

В результате:

- входящий IPv4/IPv6 трафик **от** IP/подсетей из списков дропается;
- исходящий IPv4/IPv6 трафик **к** IP/подсетям из списков дропается;
- транзитный `forward`-трафик **от** и **к** IP/подсетям из списков дропается;
- ICMP/ICMPv6 от заблокированных адресов тоже дропается, потому что managed-блоки стоят раньше стандартных UFW accept для ICMP/ICMPv6.

## Источники списков

По умолчанию updater использует три источника:

```bash
SOURCE_URL_SKIPA_V4="https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/main/lists/skipa_cidr.txt"

SOURCE_URL_AS_NETWORK_V4="https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist-v4.txt"

SOURCE_URL_AS_NETWORK_V6="https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist-v6.txt"
```

IPv4-источники объединяются в один IPv4 managed-блок.

IPv6-источник применяется отдельно в `/etc/ufw/before6.rules`.

## Что важно заранее понимать

- это решение рассчитано на хосты, где **UFW является единственным активным firewall-менеджером**;
- если на сервере `nftables.service` **включён** (`enabled`) или **активен** (`active`), `install-ufw-blocklists.sh` и `update-ufw-blocklists.sh` **завершатся с ошибкой** и не будут вносить изменения;
- существующие правила UFW не удаляются и не переписываются;
- IPv4 managed-блок добавляется в `/etc/ufw/before.rules`;
- IPv6 managed-блок добавляется в `/etc/ufw/before6.rules`;
- проверять результат нужно через `ufw show raw` и просмотр самих файлов, а не только через `ufw status`;
- текущая версия рассчитана на включённую IPv6-поддержку UFW, потому что применяет и IPv4, и IPv6 blocklists.

## Trust model

Updater тянет списки из upstream-репозиториев по raw URL на ветку `main`.

Это означает:

- любое изменение upstream `main` будет использовано на следующем обновлении;
- если upstream-списки вырастут или изменятся, это отразится на firewall после очередного запуска updater-а;
- если один из upstream-источников временно недоступен, обновление завершится ошибкой, а уже применённые ранее managed-блоки останутся как есть.

Практический режим использования:

- сначала установить и проверить решение на одном хосте вручную;
- посмотреть `ufw show raw`;
- проверить managed-блоки в `/etc/ufw/before.rules` и `/etc/ufw/before6.rules`;
- после этого оставить timer включённым на остальных хостах.

## Требования

- Ubuntu 24.04;
- root или `sudo`;
- установленный `ufw`;
- включённый `ufw`;
- включённая IPv6-поддержка UFW: `IPV6=yes` в `/etc/default/ufw`;
- доступ к `https://raw.githubusercontent.com/`.

## Проверки перед установкой

### Проверить, что UFW включён

```bash
sudo ufw status verbose
```

Ожидается:

```text
Status: active
```

Если UFW выключен, включи его сам:

```bash
sudo ufw enable
```

### Проверить, что IPv6 включён в UFW

```bash
grep '^IPV6=' /etc/default/ufw
```

Ожидается:

```text
IPV6=yes
```

Если там `IPV6=no`, включи IPv6 в `/etc/default/ufw`, затем перезагрузи UFW:

```bash
sudo sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
sudo ufw reload
```

### Проверить конфликт с standalone nftables

```bash
sudo systemctl is-enabled nftables.service
sudo systemctl is-active nftables.service
sudo sed -n '1,200p' /etc/nftables.conf 2>/dev/null
```

Этот репозиторий рассчитан только на **UFW-only** сценарий.

Если `nftables.service` включён (`enabled`) или активен (`active`), `install-ufw-blocklists.sh` и `update-ufw-blocklists.sh` **завершатся с ошибкой** и не будут вносить изменения.

Причина простая: репозиторий не рассчитан на параллельную работу с отдельным standalone `nftables.service`.

## Установка

### Шаг 1. Клонировать репозиторий

```bash
git clone git@github.com:summerinstockholm/ufw-external-blocklists.git
cd ufw-external-blocklists
```

### Шаг 2. Запустить installer

```bash
sudo bash scripts/install-ufw-blocklists.sh
```

Installer сам сделает следующее:

- проверит root;
- проверит наличие файлов репозитория;
- установит `ufw`, `curl`, `python3`, если нужно;
- проверит, что `ufw` активен;
- проверит, что `IPV6=yes` в `/etc/default/ufw`;
- проверит конфликт с `nftables.service`;
- сделает backup `/etc/ufw/before.rules`;
- сделает backup `/etc/ufw/before6.rules`;
- установит updater-скрипт и systemd unit-файлы;
- удалит старые `skipa-banlist` unit-файлы, если они остались после предыдущей версии;
- выполнит первую загрузку блоклистов;
- включит timer.

## Что создаётся на сервере

### Установленные файлы

```text
/usr/local/sbin/update-ufw-blocklists.sh
/etc/systemd/system/ufw-blocklists.service
/etc/systemd/system/ufw-blocklists.timer
```

### Изменяемые файлы

```text
/etc/ufw/before.rules
/etc/ufw/before6.rules
```

В `/etc/ufw/before.rules` добавляется IPv4 managed-блок:

```text
# BEGIN UFW EXTERNAL BLOCKLIST V4 - managed by update-ufw-blocklists.sh
...
# END UFW EXTERNAL BLOCKLIST V4 - managed by update-ufw-blocklists.sh
```

В `/etc/ufw/before6.rules` добавляется IPv6 managed-блок:

```text
# BEGIN UFW EXTERNAL BLOCKLIST V6 - managed by update-ufw-blocklists.sh
...
# END UFW EXTERNAL BLOCKLIST V6 - managed by update-ufw-blocklists.sh
```

Updater пересобирает эти блоки целиком при каждом обновлении.

## Проверка после установки

### Проверить timer

```bash
systemctl status ufw-blocklists.timer --no-pager
systemctl list-timers --all | grep ufw-blocklists
```

### Проверить service

```bash
systemctl status ufw-blocklists.service --no-pager
journalctl -u ufw-blocklists.service -n 100 --no-pager
```

### Проверить IPv4 managed-блок

```bash
sudo sed -n '/BEGIN UFW EXTERNAL BLOCKLIST V4/,/END UFW EXTERNAL BLOCKLIST V4/p' /etc/ufw/before.rules
```

### Проверить IPv6 managed-блок

```bash
sudo sed -n '/BEGIN UFW EXTERNAL BLOCKLIST V6/,/END UFW EXTERNAL BLOCKLIST V6/p' /etc/ufw/before6.rules
```

### Проверить полный firewall state

```bash
sudo ufw show raw
```

## Обновление вручную

Если нужно немедленно подтянуть свежие списки:

```bash
sudo /usr/local/sbin/update-ufw-blocklists.sh
```

## Как именно блокируется IPv4

Updater добавляет в `/etc/ufw/before.rules` такие типы правил:

```text
-A ufw-before-input -s <CIDR> -j DROP
-A ufw-before-output -d <CIDR> -j DROP
-A ufw-before-forward -s <CIDR> -j DROP
-A ufw-before-forward -d <CIDR> -j DROP
```

Это означает:

- с этих IPv4-адресов нельзя достучаться до хоста;
- хост сам не сможет ходить на эти IPv4-адреса;
- если хост форвардит трафик, то IPv4-трафик через него от/к этим адресам тоже режется.

## Как именно блокируется IPv6

Updater добавляет в `/etc/ufw/before6.rules` такие типы правил:

```text
-A ufw6-before-input -s <CIDR> -j DROP
-A ufw6-before-output -d <CIDR> -j DROP
-A ufw6-before-forward -s <CIDR> -j DROP
-A ufw6-before-forward -d <CIDR> -j DROP
```

Это означает:

- с этих IPv6-адресов нельзя достучаться до хоста;
- хост сам не сможет ходить на эти IPv6-адреса;
- если хост форвардит трафик, то IPv6-трафик через него от/к этим адресам тоже режется.

## Почему ICMP и ICMPv6 тоже блокируются

Managed-блоки вставляются в начало `*filter`-секции `before.rules` и `before6.rules`, то есть **раньше** стандартных UFW-правил для ICMP/ICMPv6.

Поэтому ping, IPv6 ping и другой трафик от заблокированных адресов попадают под DROP раньше стандартных accept-правил.

## Повторный запуск installer

Повторный запуск допустим:

```bash
sudo bash scripts/install-ufw-blocklists.sh
```

Он не должен ломать существующие правила UFW и просто переустановит свои файлы и заново пересоберёт managed-блоки.

## Миграция со старой версии `ufw-skipa-blocklist`

Если на сервере раньше уже была установлена старая версия с именами `skipa-banlist`, новый installer должен удалить старые unit-файлы и старый updater-скрипт:

```text
/usr/local/sbin/update-skipa-banlist.sh
/etc/systemd/system/skipa-banlist.service
/etc/systemd/system/skipa-banlist.timer
```

Также updater удаляет старые managed-блоки со старыми маркерами, чтобы не было дублей в UFW rules files.

## Удаление

### Остановить timer

```bash
sudo systemctl disable --now ufw-blocklists.timer
```

### Удалить unit-файлы

```bash
sudo rm -f /etc/systemd/system/ufw-blocklists.service
sudo rm -f /etc/systemd/system/ufw-blocklists.timer
sudo systemctl daemon-reload
```

### Удалить managed-блоки из UFW rules files

Самый простой путь — восстановить backup, который делал installer или updater.

Если backup не нужен и хочется убрать только managed-блоки:

```bash
sudo python3 - <<'PY'
from pathlib import Path

targets = [
    (
        Path('/etc/ufw/before.rules'),
        '# BEGIN UFW EXTERNAL BLOCKLIST V4 - managed by update-ufw-blocklists.sh',
        '# END UFW EXTERNAL BLOCKLIST V4 - managed by update-ufw-blocklists.sh',
    ),
    (
        Path('/etc/ufw/before6.rules'),
        '# BEGIN UFW EXTERNAL BLOCKLIST V6 - managed by update-ufw-blocklists.sh',
        '# END UFW EXTERNAL BLOCKLIST V6 - managed by update-ufw-blocklists.sh',
    ),
]

for path, start, end in targets:
    text = path.read_text(encoding='utf-8')
    start_index = text.find(start)
    if start_index == -1:
        continue
    end_index = text.find(end, start_index)
    if end_index == -1:
        continue
    end_index += len(end)
    if end_index < len(text) and text[end_index:end_index + 1] == '\n':
        end_index += 1
    path.write_text(text[:start_index] + text[end_index:], encoding='utf-8')
PY

sudo ufw reload
```

### Удалить updater-скрипт

```bash
sudo rm -f /usr/local/sbin/update-ufw-blocklists.sh
```
