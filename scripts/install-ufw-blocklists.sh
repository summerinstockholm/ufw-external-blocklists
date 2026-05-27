#!/usr/bin/env bash

# Включаем строгий режим bash:
# -e завершает скрипт при ошибке команды.
# -u запрещает использовать несуществующие переменные.
# -o pipefail делает ошибкой падение любой команды в pipeline.
set -euo pipefail

# Определяем каталог, в котором лежит текущий installer-скрипт.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Определяем корневой каталог репозитория как каталог уровнем выше папки scripts.
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Определяем путь к updater-скрипту внутри репозитория.
LOCAL_UPDATE_SCRIPT="${REPO_ROOT}/scripts/update-ufw-blocklists.sh"

# Определяем путь к service unit внутри репозитория.
LOCAL_SERVICE_FILE="${REPO_ROOT}/systemd/ufw-blocklists.service"

# Определяем путь к timer unit внутри репозитория.
LOCAL_TIMER_FILE="${REPO_ROOT}/systemd/ufw-blocklists.timer"

# Определяем путь установки updater-скрипта на целевом сервере.
TARGET_UPDATE_SCRIPT="/usr/local/sbin/update-ufw-blocklists.sh"

# Определяем путь установки service unit на целевом сервере.
TARGET_SERVICE_FILE="/etc/systemd/system/ufw-blocklists.service"

# Определяем путь установки timer unit на целевом сервере.
TARGET_TIMER_FILE="/etc/systemd/system/ufw-blocklists.timer"

# Определяем путь к старому updater-скрипту от прежней версии репозитория.
OLD_TARGET_UPDATE_SCRIPT="/usr/local/sbin/update-skipa-banlist.sh"

# Определяем путь к старому service unit от прежней версии репозитория.
OLD_TARGET_SERVICE_FILE="/etc/systemd/system/skipa-banlist.service"

# Определяем путь к старому timer unit от прежней версии репозитория.
OLD_TARGET_TIMER_FILE="/etc/systemd/system/skipa-banlist.timer"

# Определяем имя старого timer unit от прежней версии репозитория.
OLD_TIMER_UNIT="skipa-banlist.timer"

# Определяем путь к основному UFW IPv4 before.rules файлу.
UFW_BEFORE_RULES="/etc/ufw/before.rules"

# Определяем путь к основному UFW IPv6 before6.rules файлу.
UFW_BEFORE6_RULES="/etc/ufw/before6.rules"

# Определяем путь к основному UFW defaults-файлу.
UFW_DEFAULT="/etc/default/ufw"

# Определяем путь к native nftables-конфигу только для проверки конфликта.
NFTABLES_CONF="/etc/nftables.conf"

# Определяем имя standalone nftables unit-файла для проверки конфликта.
NFTABLES_SERVICE="nftables.service"

# Проверяем, что installer запущен от root, потому что дальше будут изменения в /etc, /usr/local/sbin и systemd.
if [[ "${EUID}" -ne 0 ]]; then
  # Печатаем понятную ошибку в stderr.
  echo "ERROR: запускай installer от root или через sudo." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что updater-скрипт действительно существует в репозитории.
if [[ ! -f "${LOCAL_UPDATE_SCRIPT}" ]]; then
  # Печатаем ошибку, если updater не найден.
  echo "ERROR: не найден файл ${LOCAL_UPDATE_SCRIPT}." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что service unit действительно существует в репозитории.
if [[ ! -f "${LOCAL_SERVICE_FILE}" ]]; then
  # Печатаем ошибку, если service unit не найден.
  echo "ERROR: не найден файл ${LOCAL_SERVICE_FILE}." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что timer unit действительно существует в репозитории.
if [[ ! -f "${LOCAL_TIMER_FILE}" ]]; then
  # Печатаем ошибку, если timer unit не найден.
  echo "ERROR: не найден файл ${LOCAL_TIMER_FILE}." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, включён ли standalone nftables.service в автозапуск.
NFTABLES_ENABLED="no"
if systemctl is-enabled "${NFTABLES_SERVICE}" >/dev/null 2>&1; then
  # Запоминаем, что nftables.service включён.
  NFTABLES_ENABLED="yes"
fi

# Проверяем, активен ли standalone nftables.service прямо сейчас.
NFTABLES_ACTIVE="no"
if systemctl is-active "${NFTABLES_SERVICE}" >/dev/null 2>&1; then
  # Запоминаем, что nftables.service активен.
  NFTABLES_ACTIVE="yes"
fi

# Проверяем, содержит ли /etc/nftables.conf осмысленные строки кроме комментариев и пустых строк.
NFTABLES_CONF_HAS_CONTENT="no"
if [[ -f "${NFTABLES_CONF}" ]] && grep -Eq '^[[:space:]]*[^#[:space:]]' "${NFTABLES_CONF}"; then
  # Запоминаем, что файл native nftables-конфига непустой.
  NFTABLES_CONF_HAS_CONTENT="yes"
fi

# Если standalone nftables service включён или активен, считаем это конфликтом и останавливаем установку.
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

  # Печатаем итоговое сообщение, что installer не будет менять систему.
  echo "ERROR: install-ufw-blocklists.sh не будет вносить изменения в такой конфигурации." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Если nftables.service не активен и не включён, но /etc/nftables.conf непустой, печатаем предупреждение.
if [[ "${NFTABLES_CONF_HAS_CONTENT}" == "yes" ]]; then
  # Печатаем предупреждение о наличии native nftables-конфига.
  echo "WARNING: /etc/nftables.conf содержит данные, но standalone ${NFTABLES_SERVICE} не активен и не включён." >&2

  # Печатаем рекомендацию не включать standalone nftables параллельно.
  echo "WARNING: не включай standalone ${NFTABLES_SERVICE} параллельно с этим репозиторием." >&2
fi

# Обновляем индекс пакетов apt перед установкой зависимостей.
apt update

# Устанавливаем ufw, curl и python3, если их ещё нет в системе.
apt install -y ufw curl python3

# Проверяем, что команда ufw доступна в PATH после установки пакета.
if ! command -v ufw >/dev/null 2>&1; then
  # Печатаем ошибку, если ufw всё равно недоступен.
  echo "ERROR: команда ufw недоступна даже после установки пакета." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что команда curl доступна в PATH после установки пакета.
if ! command -v curl >/dev/null 2>&1; then
  # Печатаем ошибку, если curl всё равно недоступен.
  echo "ERROR: команда curl недоступна даже после установки пакета." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что команда python3 доступна в PATH после установки пакета.
if ! command -v python3 >/dev/null 2>&1; then
  # Печатаем ошибку, если python3 всё равно недоступен.
  echo "ERROR: команда python3 недоступна даже после установки пакета." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что основной файл /etc/ufw/before.rules существует.
if [[ ! -f "${UFW_BEFORE_RULES}" ]]; then
  # Печатаем ошибку, если IPv4 before.rules отсутствует.
  echo "ERROR: не найден файл ${UFW_BEFORE_RULES}." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что основной файл /etc/ufw/before6.rules существует.
if [[ ! -f "${UFW_BEFORE6_RULES}" ]]; then
  # Печатаем ошибку, если IPv6 before6.rules отсутствует.
  echo "ERROR: не найден файл ${UFW_BEFORE6_RULES}." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что UFW defaults-файл существует.
if [[ ! -f "${UFW_DEFAULT}" ]]; then
  # Печатаем ошибку, если /etc/default/ufw отсутствует.
  echo "ERROR: не найден файл ${UFW_DEFAULT}." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что UFW уже активен, потому что дальше будет ufw reload внутри updater-а.
if ! ufw status | grep -q '^Status: active'; then
  # Печатаем ошибку с требованием сначала включить UFW вручную.
  echo "ERROR: UFW выключен. Сначала включи UFW командой 'sudo ufw enable', потом запусти installer снова." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Проверяем, что IPv6 поддержка UFW включена.
if ! grep -Eq '^[[:space:]]*IPV6="?yes"?[[:space:]]*$' "${UFW_DEFAULT}"; then
  # Печатаем ошибку, если IPV6=yes не найден.
  echo "ERROR: IPv6-поддержка UFW выключена или не настроена." >&2

  # Печатаем ожидаемую настройку.
  echo "ERROR: ожидается строка IPV6=yes в ${UFW_DEFAULT}." >&2

  # Печатаем подсказку по исправлению.
  echo "ERROR: включи IPv6 в UFW и выполни 'sudo ufw reload', затем запусти installer снова." >&2

  # Завершаем installer с ошибкой.
  exit 1
fi

# Делаем резервную копию /etc/ufw/before.rules перед первой модификацией.
cp -a "${UFW_BEFORE_RULES}" "${UFW_BEFORE_RULES}.bak.$(date +%F-%H%M%S)"

# Делаем резервную копию /etc/ufw/before6.rules перед первой модификацией.
cp -a "${UFW_BEFORE6_RULES}" "${UFW_BEFORE6_RULES}.bak.$(date +%F-%H%M%S)"

# Если старый skipa-banlist.timer существует, останавливаем и отключаем его.
systemctl disable --now "${OLD_TIMER_UNIT}" >/dev/null 2>&1 || true

# Удаляем старый updater-скрипт от прежней версии репозитория, если он существует.
rm -f "${OLD_TARGET_UPDATE_SCRIPT}"

# Удаляем старый service unit от прежней версии репозитория, если он существует.
rm -f "${OLD_TARGET_SERVICE_FILE}"

# Удаляем старый timer unit от прежней версии репозитория, если он существует.
rm -f "${OLD_TARGET_TIMER_FILE}"

# Устанавливаем новый updater-скрипт в /usr/local/sbin с правами на исполнение.
install -m 0755 "${LOCAL_UPDATE_SCRIPT}" "${TARGET_UPDATE_SCRIPT}"

# Устанавливаем новый service unit в каталог systemd unit-файлов.
install -m 0644 "${LOCAL_SERVICE_FILE}" "${TARGET_SERVICE_FILE}"

# Устанавливаем новый timer unit в каталог systemd unit-файлов.
install -m 0644 "${LOCAL_TIMER_FILE}" "${TARGET_TIMER_FILE}"

# Перечитываем unit-файлы systemd после удаления старых unit-файлов и установки новых.
systemctl daemon-reload

# Выполняем updater-скрипт сразу же, чтобы скачать списки и внедрить managed-блоки в before.rules и before6.rules.
"${TARGET_UPDATE_SCRIPT}"

# Включаем новый timer в автозапуск и запускаем его сразу же.
systemctl enable --now ufw-blocklists.timer

# Печатаем итоговое сообщение об успешной установке.
echo "OK: UFW external blocklists установлены, managed-блоки созданы, timer включён."