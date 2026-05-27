#!/usr/bin/env bash

# Включаем строгий режим bash:
# -e завершает скрипт при ошибке команды.
# -u запрещает использовать несуществующие переменные.
# -o pipefail делает ошибкой падение любой команды в pipeline.
set -euo pipefail

# Определяем URL IPv4 CIDR-списка CyberOK_Skipa_ips.
SOURCE_URL_SKIPA_V4="${SOURCE_URL_SKIPA_V4:-https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/main/lists/skipa_cidr.txt}"

# Определяем URL IPv4 blacklist из AS_Network_List.
SOURCE_URL_AS_NETWORK_V4="${SOURCE_URL_AS_NETWORK_V4:-https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist-v4.txt}"

# Определяем URL IPv6 blacklist из AS_Network_List.
SOURCE_URL_AS_NETWORK_V6="${SOURCE_URL_AS_NETWORK_V6:-https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist-v6.txt}"

# Определяем путь к UFW IPv4 before.rules файлу.
UFW_BEFORE_RULES="${UFW_BEFORE_RULES:-/etc/ufw/before.rules}"

# Определяем путь к UFW IPv6 before6.rules файлу.
UFW_BEFORE6_RULES="${UFW_BEFORE6_RULES:-/etc/ufw/before6.rules}"

# Определяем путь к UFW defaults-файлу.
UFW_DEFAULT="${UFW_DEFAULT:-/etc/default/ufw}"

# Определяем путь к native nftables-конфигу только для проверки конфликта.
NFTABLES_CONF="${NFTABLES_CONF:-/etc/nftables.conf}"

# Определяем имя standalone nftables unit-файла для проверки конфликта.
NFTABLES_SERVICE="${NFTABLES_SERVICE:-nftables.service}"

# Определяем новый маркер начала IPv4 managed-блока.
BEGIN_MARKER_V4="# BEGIN UFW EXTERNAL BLOCKLIST V4 - managed by update-ufw-blocklists.sh"

# Определяем новый маркер конца IPv4 managed-блока.
END_MARKER_V4="# END UFW EXTERNAL BLOCKLIST V4 - managed by update-ufw-blocklists.sh"

# Определяем новый маркер начала IPv6 managed-блока.
BEGIN_MARKER_V6="# BEGIN UFW EXTERNAL BLOCKLIST V6 - managed by update-ufw-blocklists.sh"

# Определяем новый маркер конца IPv6 managed-блока.
END_MARKER_V6="# END UFW EXTERNAL BLOCKLIST V6 - managed by update-ufw-blocklists.sh"

# Определяем старый маркер начала managed-блока от первой SKIPA-only версии.
OLD_BEGIN_MARKER_SKIPA="# BEGIN SKIPA BLOCKLIST - managed by update-skipa-banlist.sh"

# Определяем старый маркер конца managed-блока от первой SKIPA-only версии.
OLD_END_MARKER_SKIPA="# END SKIPA BLOCKLIST - managed by update-skipa-banlist.sh"

# Определяем старый маркер начала IPv4 блока от промежуточной версии со старым именем updater-а.
OLD_BEGIN_MARKER_V4="# BEGIN UFW EXTERNAL BLOCKLIST V4 - managed by update-skipa-banlist.sh"

# Определяем старый маркер конца IPv4 блока от промежуточной версии со старым именем updater-а.
OLD_END_MARKER_V4="# END UFW EXTERNAL BLOCKLIST V4 - managed by update-skipa-banlist.sh"

# Определяем старый маркер начала IPv6 блока от промежуточной версии со старым именем updater-а.
OLD_BEGIN_MARKER_V6="# BEGIN UFW EXTERNAL BLOCKLIST V6 - managed by update-skipa-banlist.sh"

# Определяем старый маркер конца IPv6 блока от промежуточной версии со старым именем updater-а.
OLD_END_MARKER_V6="# END UFW EXTERNAL BLOCKLIST V6 - managed by update-skipa-banlist.sh"

# Создаём временный файл под скачанный SKIPA IPv4 список.
TMP_SKIPA_V4_FILE="$(mktemp)"

# Создаём временный файл под скачанный AS_Network_List IPv4 список.
TMP_AS_NETWORK_V4_FILE="$(mktemp)"

# Создаём временный файл под скачанный AS_Network_List IPv6 список.
TMP_AS_NETWORK_V6_FILE="$(mktemp)"

# Создаём временный файл под очищенный и объединённый IPv4 список.
TMP_CLEAN_V4_FILE="$(mktemp)"

# Создаём временный файл под очищенный IPv6 список.
TMP_CLEAN_V6_FILE="$(mktemp)"

# Создаём временный файл под новый IPv4 managed-блок.
TMP_BLOCK_V4_FILE="$(mktemp)"

# Создаём временный файл под новый IPv6 managed-блок.
TMP_BLOCK_V6_FILE="$(mktemp)"

# Создаём временный файл под кандидатный /etc/ufw/before.rules.
TMP_BEFORE_RULES_FILE="$(mktemp)"

# Создаём временный файл под кандидатный /etc/ufw/before6.rules.
TMP_BEFORE6_RULES_FILE="$(mktemp)"

# Объявляем функцию очистки временных файлов при любом выходе из скрипта.
cleanup() {
  # Удаляем временный файл со скачанным SKIPA IPv4 списком.
  rm -f "${TMP_SKIPA_V4_FILE}"

  # Удаляем временный файл со скачанным AS_Network_List IPv4 списком.
  rm -f "${TMP_AS_NETWORK_V4_FILE}"

  # Удаляем временный файл со скачанным AS_Network_List IPv6 списком.
  rm -f "${TMP_AS_NETWORK_V6_FILE}"

  # Удаляем временный файл с очищенным IPv4 списком.
  rm -f "${TMP_CLEAN_V4_FILE}"

  # Удаляем временный файл с очищенным IPv6 списком.
  rm -f "${TMP_CLEAN_V6_FILE}"

  # Удаляем временный файл с IPv4 managed-блоком.
  rm -f "${TMP_BLOCK_V4_FILE}"

  # Удаляем временный файл с IPv6 managed-блоком.
  rm -f "${TMP_BLOCK_V6_FILE}"

  # Удаляем временный файл с кандидатным before.rules.
  rm -f "${TMP_BEFORE_RULES_FILE}"

  # Удаляем временный файл с кандидатным before6.rules.
  rm -f "${TMP_BEFORE6_RULES_FILE}"
}

# Регистрируем функцию cleanup на завершение скрипта.
trap cleanup EXIT

# Объявляем функцию проверки конфликта со standalone nftables.service.
check_nftables_conflict() {
  # По умолчанию считаем, что nftables.service не включён.
  NFTABLES_ENABLED="no"

  # Проверяем, включён ли standalone nftables.service в автозапуск.
  if systemctl is-enabled "${NFTABLES_SERVICE}" >/dev/null 2>&1; then
    # Запоминаем, что nftables.service включён.
    NFTABLES_ENABLED="yes"
  fi

  # По умолчанию считаем, что nftables.service не активен.
  NFTABLES_ACTIVE="no"

  # Проверяем, активен ли standalone nftables.service прямо сейчас.
  if systemctl is-active "${NFTABLES_SERVICE}" >/dev/null 2>&1; then
    # Запоминаем, что nftables.service активен.
    NFTABLES_ACTIVE="yes"
  fi

  # По умолчанию считаем, что /etc/nftables.conf не содержит осмысленных строк.
  NFTABLES_CONF_HAS_CONTENT="no"

  # Проверяем, содержит ли /etc/nftables.conf осмысленные строки кроме комментариев и пустых строк.
  if [[ -f "${NFTABLES_CONF}" ]] && grep -Eq '^[[:space:]]*[^#[:space:]]' "${NFTABLES_CONF}"; then
    # Запоминаем, что файл native nftables-конфига непустой.
    NFTABLES_CONF_HAS_CONTENT="yes"
  fi

  # Если standalone nftables service включён или активен, считаем это конфликтом.
  if [[ "${NFTABLES_ENABLED}" == "yes" || "${NFTABLES_ACTIVE}" == "yes" ]]; then
    # Печатаем общую причину ошибки.
    echo "ERROR: этот репозиторий рассчитан только на UFW-only сценарий." >&2

    # Печатаем конкретный конфликтующий unit.
    echo "ERROR: обнаружен конфликт с standalone ${NFTABLES_SERVICE}." >&2

    # Печатаем состояние автозапуска nftables.service.
    echo "       is-enabled: ${NFTABLES_ENABLED}" >&2

    # Печатаем состояние активности nftables.service.
    echo "       is-active : ${NFTABLES_ACTIVE}" >&2

    # Если /etc/nftables.conf непустой, отдельно показываем это.
    if [[ "${NFTABLES_CONF_HAS_CONTENT}" == "yes" ]]; then
      # Печатаем пояснение о native nftables-конфиге.
      echo "       /etc/nftables.conf содержит правила или другие осмысленные строки." >&2
    fi

    # Печатаем итоговое сообщение, что updater не будет менять систему.
    echo "ERROR: update-ufw-blocklists.sh не будет вносить изменения в такой конфигурации." >&2

    # Завершаем updater с ошибкой.
    exit 1
  fi

  # Если nftables.service не активен и не включён, но /etc/nftables.conf непустой, печатаем предупреждение.
  if [[ "${NFTABLES_CONF_HAS_CONTENT}" == "yes" ]]; then
    # Печатаем предупреждение о наличии native nftables-конфига.
    echo "WARNING: /etc/nftables.conf содержит данные, но standalone ${NFTABLES_SERVICE} не активен и не включён." >&2

    # Печатаем рекомендацию не включать standalone nftables параллельно.
    echo "WARNING: не включай standalone ${NFTABLES_SERVICE} параллельно с этим репозиторием." >&2
  fi
}

# Объявляем функцию валидации и нормализации IP/CIDR списков.
normalize_networks() {
  # Принимаем номер IP-семейства: 4 или 6.
  local family="$1"

  # Принимаем путь к выходному очищенному файлу.
  local output_file="$2"

  # Сдвигаем первые два аргумента, чтобы дальше остались только входные файлы.
  shift 2

  # Запускаем Python для строгой валидации и нормализации сетей.
  python3 - "${family}" "${output_file}" "$@" <<'PY'
# Импортируем модуль ipaddress для строгой проверки IPv4/IPv6 сетей.
import ipaddress

# Импортируем sys для чтения аргументов командной строки.
import sys

# Получаем номер IP-семейства из первого аргумента.
family = int(sys.argv[1])

# Получаем путь к выходному файлу из второго аргумента.
output_path = sys.argv[2]

# Получаем список входных файлов из остальных аргументов.
input_paths = sys.argv[3:]

# Создаём множество для дедупликации сетей.
seen = set()

# Выбираем ожидаемую версию IP-семейства.
expected_version = 4 if family == 4 else 6

# Проходим по каждому входному файлу.
for input_path in input_paths:
    # Открываем входной файл на чтение в UTF-8.
    with open(input_path, "r", encoding="utf-8") as src:
        # Итерируемся по строкам входного файла.
        for line_number, raw_line in enumerate(src, start=1):
            # Отрезаем inline-комментарий после символа #.
            line_without_comment = raw_line.split("#", 1)[0]

            # Разбиваем строку по любым whitespace-символам, чтобы поддержать и построчный, и однострочный формат.
            tokens = line_without_comment.split()

            # Проходим по каждому найденному токену.
            for token in tokens:
                # Убираем частые хвостовые разделители, если они случайно встретились в источнике.
                candidate = token.strip().strip(",")

                # Пропускаем пустой токен после очистки.
                if not candidate:
                    continue

                # Пробуем интерпретировать токен как IPv4/IPv6 сеть или одиночный адрес.
                try:
                    network = ipaddress.ip_network(candidate, strict=False)
                except ValueError as exc:
                    raise SystemExit(
                        f"ERROR: invalid network '{candidate}' in {input_path}:{line_number}: {exc}"
                    )

                # Проверяем, что сеть относится к ожидаемому IP-семейству.
                if network.version != expected_version:
                    raise SystemExit(
                        f"ERROR: unexpected IPv{network.version} network '{candidate}' "
                        f"in IPv{expected_version} source {input_path}:{line_number}"
                    )

                # Сохраняем сеть в каноническом строковом виде.
                seen.add(str(network))

# Если после обработки всех файлов список пустой, завершаемся с ошибкой.
if not seen:
    raise SystemExit(f"ERROR: normalized IPv{expected_version} network list is empty")

# Открываем выходной файл на запись.
with open(output_path, "w", encoding="utf-8") as out:
    # Сортируем сети сначала по адресу сети, затем по длине префикса.
    for item in sorted(
        seen,
        key=lambda value: (
            int(ipaddress.ip_network(value, strict=False).network_address),
            ipaddress.ip_network(value, strict=False).prefixlen,
        ),
    ):
        # Записываем сеть в выходной файл.
        out.write(item + "\n")
PY
}

# Объявляем функцию генерации IPv4 managed-блока для UFW before.rules.
generate_v4_block() {
  # Принимаем путь к очищенному IPv4 списку.
  local clean_file="$1"

  # Принимаем путь к выходному managed-блоку.
  local block_file="$2"

  # Формируем IPv4 managed-блок.
  {
    # Печатаем маркер начала IPv4 managed-блока.
    printf '%s\n' "${BEGIN_MARKER_V4}"

    # Печатаем комментарий с первым источником.
    printf '# Source v4 #1: %s\n' "${SOURCE_URL_SKIPA_V4}"

    # Печатаем комментарий со вторым источником.
    printf '# Source v4 #2: %s\n' "${SOURCE_URL_AS_NETWORK_V4}"

    # Печатаем комментарий о том, что блок генерируется автоматически.
    printf '# This block is generated automatically. Do not edit it manually.\n'

    # Печатаем пустую строку для читаемости.
    printf '\n'

    # Читаем очищенные IPv4 CIDR по одному.
    while IFS= read -r CIDR; do
      # Генерируем DROP для входящего IPv4 трафика от адресов и подсетей из списка.
      printf -- '-A ufw-before-input -s %s -j DROP\n' "${CIDR}"

      # Генерируем DROP для исходящего IPv4 трафика к адресам и подсетям из списка.
      printf -- '-A ufw-before-output -d %s -j DROP\n' "${CIDR}"

      # Генерируем DROP для форвардимого IPv4 трафика от адресов и подсетей из списка.
      printf -- '-A ufw-before-forward -s %s -j DROP\n' "${CIDR}"

      # Генерируем DROP для форвардимого IPv4 трафика к адресам и подсетям из списка.
      printf -- '-A ufw-before-forward -d %s -j DROP\n' "${CIDR}"
    done < "${clean_file}"

    # Печатаем маркер конца IPv4 managed-блока.
    printf '%s\n' "${END_MARKER_V4}"
  } > "${block_file}"
}

# Объявляем функцию генерации IPv6 managed-блока для UFW before6.rules.
generate_v6_block() {
  # Принимаем путь к очищенному IPv6 списку.
  local clean_file="$1"

  # Принимаем путь к выходному managed-блоку.
  local block_file="$2"

  # Формируем IPv6 managed-блок.
  {
    # Печатаем маркер начала IPv6 managed-блока.
    printf '%s\n' "${BEGIN_MARKER_V6}"

    # Печатаем комментарий с IPv6 источником.
    printf '# Source v6: %s\n' "${SOURCE_URL_AS_NETWORK_V6}"

    # Печатаем комментарий о том, что блок генерируется автоматически.
    printf '# This block is generated automatically. Do not edit it manually.\n'

    # Печатаем пустую строку для читаемости.
    printf '\n'

    # Читаем очищенные IPv6 CIDR по одному.
    while IFS= read -r CIDR; do
      # Генерируем DROP для входящего IPv6 трафика от адресов и подсетей из списка.
      printf -- '-A ufw6-before-input -s %s -j DROP\n' "${CIDR}"

      # Генерируем DROP для исходящего IPv6 трафика к адресам и подсетям из списка.
      printf -- '-A ufw6-before-output -d %s -j DROP\n' "${CIDR}"

      # Генерируем DROP для форвардимого IPv6 трафика от адресов и подсетей из списка.
      printf -- '-A ufw6-before-forward -s %s -j DROP\n' "${CIDR}"

      # Генерируем DROP для форвардимого IPv6 трафика к адресам и подсетям из списка.
      printf -- '-A ufw6-before-forward -d %s -j DROP\n' "${CIDR}"
    done < "${clean_file}"

    # Печатаем маркер конца IPv6 managed-блока.
    printf '%s\n' "${END_MARKER_V6}"
  } > "${block_file}"
}

# Объявляем функцию патчинга UFW rules-файла.
patch_ufw_rules_file() {
  # Принимаем путь к исходному UFW rules-файлу.
  local rules_file="$1"

  # Принимаем путь к новому managed-блоку.
  local block_file="$2"

  # Принимаем путь к кандидатному итоговому UFW rules-файлу.
  local output_file="$3"

  # Принимаем новый маркер начала managed-блока.
  local new_begin_marker="$4"

  # Принимаем новый маркер конца managed-блока.
  local new_end_marker="$5"

  # Сдвигаем первые пять аргументов, чтобы дальше остались старые marker-пары.
  shift 5

  # Запускаем Python для безопасного удаления старых managed-блоков и вставки нового блока.
  python3 - "${rules_file}" "${block_file}" "${output_file}" "${new_begin_marker}" "${new_end_marker}" "$@" <<'PY'
# Импортируем sys для чтения аргументов командной строки.
import sys

# Импортируем Path для удобной работы с файлами.
from pathlib import Path

# Получаем путь к текущему UFW rules-файлу.
rules_path = Path(sys.argv[1])

# Получаем путь к новому managed-блоку.
block_path = Path(sys.argv[2])

# Получаем путь к candidate-файлу.
output_path = Path(sys.argv[3])

# Получаем новый маркер начала managed-блока.
new_begin_marker = sys.argv[4]

# Получаем новый маркер конца managed-блока.
new_end_marker = sys.argv[5]

# Получаем оставшиеся аргументы как старые marker-пары.
old_marker_args = sys.argv[6:]

# Проверяем, что старые marker-пары переданы чётным количеством аргументов.
if len(old_marker_args) % 2 != 0:
    raise SystemExit("ERROR: old marker arguments must be passed as begin/end pairs")

# Собираем список marker-пар, которые нужно удалить перед вставкой нового блока.
marker_pairs = [(new_begin_marker, new_end_marker)]

# Добавляем старые marker-пары в общий список удаления.
for index in range(0, len(old_marker_args), 2):
    marker_pairs.append((old_marker_args[index], old_marker_args[index + 1]))

# Считываем исходный rules-файл построчно с сохранением переводов строк.
lines = rules_path.read_text(encoding="utf-8").splitlines(keepends=True)

# Считываем новый managed-блок построчно с сохранением переводов строк.
block_lines = block_path.read_text(encoding="utf-8").splitlines(keepends=True)

# Создаём словарь begin -> end для быстрого поиска закрывающего маркера.
begin_to_end = {begin: end for begin, end in marker_pairs}

# Создаём множество всех закрывающих маркеров.
known_end_markers = {end for _, end in marker_pairs}

# Создаём список строк после удаления старых managed-блоков.
filtered_lines = []

# По умолчанию считаем, что сейчас мы не внутри удаляемого managed-блока.
active_end_marker = None

# Проходим по каждой строке исходного файла.
for line in lines:
    # Получаем строку без пробелов и переводов строк по краям для сравнения с маркерами.
    stripped = line.strip()

    # Если сейчас находимся внутри удаляемого managed-блока.
    if active_end_marker is not None:
        # Если встретили ожидаемый конец managed-блока, выходим из режима удаления.
        if stripped == active_end_marker:
            active_end_marker = None

        # В любом случае не добавляем строку managed-блока в результат.
        continue

    # Если текущая строка является началом одного из известных managed-блоков.
    if stripped in begin_to_end:
        # Запоминаем ожидаемый закрывающий маркер.
        active_end_marker = begin_to_end[stripped]

        # Не добавляем строку начала managed-блока в результат.
        continue

    # Если встретился закрывающий маркер без открывающего, считаем файл подозрительным.
    if stripped in known_end_markers:
        raise SystemExit(f"ERROR: found unmanaged end marker without matching begin marker: {stripped}")

    # Добавляем обычную строку в результат.
    filtered_lines.append(line)

# Если managed-блок открылся, но не закрылся, считаем файл повреждённым.
if active_end_marker is not None:
    raise SystemExit(f"ERROR: managed block was not closed, expected marker: {active_end_marker}")

# Заменяем исходные строки на очищенные от managed-блоков.
lines = filtered_lines

# Ищем начало *filter секции.
filter_start_index = None

# Проходим по всем строкам файла.
for index, line in enumerate(lines):
    # Если нашли строку *filter, запоминаем индекс.
    if line.strip() == "*filter":
        filter_start_index = index
        break

# Если *filter секция не найдена, безопаснее остановиться.
if filter_start_index is None:
    raise SystemExit(f"ERROR: section *filter was not found in {rules_path}")

# Ищем первый COMMIT после *filter.
filter_commit_index = None

# Проходим по строкам после начала *filter секции.
for index in range(filter_start_index + 1, len(lines)):
    # Если нашли COMMIT, запоминаем индекс.
    if lines[index].strip() == "COMMIT":
        filter_commit_index = index
        break

# Если COMMIT для *filter не найден, безопаснее остановиться.
if filter_commit_index is None:
    raise SystemExit(f"ERROR: COMMIT for *filter section was not found in {rules_path}")

# По умолчанию точка вставки неизвестна.
insert_index = None

# Ищем первое реальное правило внутри *filter секции.
for index in range(filter_start_index + 1, filter_commit_index):
    # Получаем строку без пробелов по краям.
    stripped = lines[index].strip()

    # Пропускаем пустые строки.
    if not stripped:
        continue

    # Пропускаем комментарии.
    if stripped.startswith("#"):
        continue

    # Пропускаем объявления цепочек вида :ufw-before-input - [0:0].
    if stripped.startswith(":"):
        continue

    # Первое не пустое, не комментарий и не объявление цепочки считаем первым правилом.
    insert_index = index
    break

# Если обычных правил внутри *filter нет, вставляем managed-блок перед COMMIT.
if insert_index is None:
    insert_index = filter_commit_index

# Создаём новый список строк для итогового rules-файла.
new_lines = []

# Добавляем все строки до точки вставки.
new_lines.extend(lines[:insert_index])

# Добавляем пустую строку перед managed-блоком для читаемости.
new_lines.append("\n")

# Добавляем строки нового managed-блока.
new_lines.extend(block_lines)

# Добавляем пустую строку после managed-блока для читаемости.
new_lines.append("\n")

# Добавляем оставшуюся часть исходного файла.
new_lines.extend(lines[insert_index:])

# Записываем candidate-файл.
output_path.write_text("".join(new_lines), encoding="utf-8")
PY
}

# Проверяем, что updater запущен от root, потому что он меняет /etc/ufw и делает ufw reload.
if [[ "${EUID}" -ne 0 ]]; then
  # Печатаем понятную ошибку в stderr.
  echo "ERROR: запускай updater от root или через sudo." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем конфликт со standalone nftables.service до любых изменений.
check_nftables_conflict

# Проверяем, что команда ufw доступна.
if ! command -v ufw >/dev/null 2>&1; then
  # Печатаем ошибку, если ufw недоступен.
  echo "ERROR: команда ufw недоступна." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем, что команда curl доступна.
if ! command -v curl >/dev/null 2>&1; then
  # Печатаем ошибку, если curl недоступен.
  echo "ERROR: команда curl недоступна." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем, что команда python3 доступна.
if ! command -v python3 >/dev/null 2>&1; then
  # Печатаем ошибку, если python3 недоступен.
  echo "ERROR: команда python3 недоступна." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем, что IPv4 before.rules существует.
if [[ ! -f "${UFW_BEFORE_RULES}" ]]; then
  # Печатаем ошибку, если before.rules отсутствует.
  echo "ERROR: не найден файл ${UFW_BEFORE_RULES}." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем, что IPv6 before6.rules существует.
if [[ ! -f "${UFW_BEFORE6_RULES}" ]]; then
  # Печатаем ошибку, если before6.rules отсутствует.
  echo "ERROR: не найден файл ${UFW_BEFORE6_RULES}." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем, что /etc/default/ufw существует.
if [[ ! -f "${UFW_DEFAULT}" ]]; then
  # Печатаем ошибку, если /etc/default/ufw отсутствует.
  echo "ERROR: не найден файл ${UFW_DEFAULT}." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем, что UFW активен, потому что дальше будет ufw reload.
if ! ufw status | grep -q '^Status: active'; then
  # Печатаем ошибку, если UFW выключен.
  echo "ERROR: UFW выключен. Сначала включи его командой 'sudo ufw enable'." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Проверяем, что IPv6 поддержка UFW включена.
if ! grep -Eq '^[[:space:]]*IPV6="?yes"?[[:space:]]*$' "${UFW_DEFAULT}"; then
  # Печатаем ошибку, если IPV6=yes не найден.
  echo "ERROR: IPv6-поддержка UFW выключена или не настроена." >&2

  # Печатаем ожидаемую настройку.
  echo "ERROR: ожидается строка IPV6=yes в ${UFW_DEFAULT}." >&2

  # Завершаем updater с ошибкой.
  exit 1
fi

# Скачиваем SKIPA IPv4 список во временный файл.
curl --fail --silent --show-error --location "${SOURCE_URL_SKIPA_V4}" --output "${TMP_SKIPA_V4_FILE}"

# Скачиваем AS_Network_List IPv4 список во временный файл.
curl --fail --silent --show-error --location "${SOURCE_URL_AS_NETWORK_V4}" --output "${TMP_AS_NETWORK_V4_FILE}"

# Скачиваем AS_Network_List IPv6 список во временный файл.
curl --fail --silent --show-error --location "${SOURCE_URL_AS_NETWORK_V6}" --output "${TMP_AS_NETWORK_V6_FILE}"

# Валидируем, объединяем и дедуплицируем IPv4 источники.
normalize_networks 4 "${TMP_CLEAN_V4_FILE}" "${TMP_SKIPA_V4_FILE}" "${TMP_AS_NETWORK_V4_FILE}"

# Валидируем и дедуплицируем IPv6 источник.
normalize_networks 6 "${TMP_CLEAN_V6_FILE}" "${TMP_AS_NETWORK_V6_FILE}"

# Генерируем IPv4 managed-блок.
generate_v4_block "${TMP_CLEAN_V4_FILE}" "${TMP_BLOCK_V4_FILE}"

# Генерируем IPv6 managed-блок.
generate_v6_block "${TMP_CLEAN_V6_FILE}" "${TMP_BLOCK_V6_FILE}"

# Патчим candidate-файл для IPv4 before.rules.
patch_ufw_rules_file \
  "${UFW_BEFORE_RULES}" \
  "${TMP_BLOCK_V4_FILE}" \
  "${TMP_BEFORE_RULES_FILE}" \
  "${BEGIN_MARKER_V4}" \
  "${END_MARKER_V4}" \
  "${OLD_BEGIN_MARKER_SKIPA}" \
  "${OLD_END_MARKER_SKIPA}" \
  "${OLD_BEGIN_MARKER_V4}" \
  "${OLD_END_MARKER_V4}"

# Патчим candidate-файл для IPv6 before6.rules.
patch_ufw_rules_file \
  "${UFW_BEFORE6_RULES}" \
  "${TMP_BLOCK_V6_FILE}" \
  "${TMP_BEFORE6_RULES_FILE}" \
  "${BEGIN_MARKER_V6}" \
  "${END_MARKER_V6}" \
  "${OLD_BEGIN_MARKER_V6}" \
  "${OLD_END_MARKER_V6}"

# Формируем timestamp для backup-файлов.
BACKUP_TIMESTAMP="$(date +%F-%H%M%S)"

# Определяем путь к backup IPv4 before.rules.
BACKUP_BEFORE_RULES="${UFW_BEFORE_RULES}.bak.${BACKUP_TIMESTAMP}"

# Определяем путь к backup IPv6 before6.rules.
BACKUP_BEFORE6_RULES="${UFW_BEFORE6_RULES}.bak.${BACKUP_TIMESTAMP}"

# Делаем backup текущего IPv4 before.rules перед заменой.
cp -a "${UFW_BEFORE_RULES}" "${BACKUP_BEFORE_RULES}"

# Делаем backup текущего IPv6 before6.rules перед заменой.
cp -a "${UFW_BEFORE6_RULES}" "${BACKUP_BEFORE6_RULES}"

# Устанавливаем кандидатный IPv4 before.rules на место.
install -m 0640 "${TMP_BEFORE_RULES_FILE}" "${UFW_BEFORE_RULES}"

# Устанавливаем кандидатный IPv6 before6.rules на место.
install -m 0640 "${TMP_BEFORE6_RULES_FILE}" "${UFW_BEFORE6_RULES}"

# Пытаемся перечитать правила UFW.
if ufw reload; then
  # Считаем количество уникальных IPv4 сетей после нормализации.
  V4_COUNT="$(wc -l < "${TMP_CLEAN_V4_FILE}" | tr -d '[:space:]')"

  # Считаем количество уникальных IPv6 сетей после нормализации.
  V6_COUNT="$(wc -l < "${TMP_CLEAN_V6_FILE}" | tr -d '[:space:]')"

  # Печатаем сообщение об успешном обновлении.
  echo "OK: UFW external blocklists обновлены и применены."

  # Печатаем количество применённых IPv4 сетей.
  echo "OK: IPv4 networks: ${V4_COUNT}"

  # Печатаем количество применённых IPv6 сетей.
  echo "OK: IPv6 networks: ${V6_COUNT}"
else
  # Печатаем ошибку о начале rollback.
  echo "ERROR: ufw reload завершился ошибкой. Выполняется rollback UFW rules files." >&2

  # Восстанавливаем IPv4 before.rules из backup.
  cp -a "${BACKUP_BEFORE_RULES}" "${UFW_BEFORE_RULES}"

  # Восстанавливаем IPv6 before6.rules из backup.
  cp -a "${BACKUP_BEFORE6_RULES}" "${UFW_BEFORE6_RULES}"

  # Пробуем вернуть UFW в предыдущее состояние после rollback.
  ufw reload || true

  # Завершаем updater с ошибкой.
  exit 1
fi
