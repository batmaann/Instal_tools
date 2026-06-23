#!/bin/bash

set -euo pipefail

# Быстрая и дружелюбная настройка SSH-сервера для Debian/Ubuntu.
# Скрипт можно запускать обычным пользователем: он сам попросит sudo.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TOTAL_STEPS=9
CURRENT_STEP=0
SSH_DROPIN='/etc/ssh/sshd_config.d/99-instal-tools.conf'
SSH_MAIN_CONFIG='/etc/ssh/sshd_config'
APT_UPDATED=false
TARGET_USER=''
SSH_PORT=''
AUTH_MODE=''
SETUP_FIREWALL=''
SERVICE_NAME='ssh'

show_header() {
  [ -t 1 ] && clear || true
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}      БЫСТРАЯ НАСТРОЙКА SSH-СЕРВЕРА     ${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo
  echo -e "Скрипт установит SSH, выберет порт, настроит вход и покажет команду подключения."
  echo -e "Рекомендация: вход по SSH-ключу безопаснее, чем вход по паролю."
  echo
}

progress_bar() {
  local percent=$1
  local label=$2
  local width=30
  local filled=$((percent * width / 100))
  local empty=$((width - filled))
  local bar=''

  for ((i=0; i<filled; i++)); do bar+='#'; done
  for ((i=0; i<empty; i++)); do bar+='-'; done

  echo -e "${CYAN}[${bar}] ${percent}%${NC} ${label}"
}

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local label=$1
  local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  echo
  progress_bar "$percent" "$label"
}

fail() {
  echo -e "${RED}Ошибка: $*${NC}" >&2
  exit 1
}

info() {
  echo -e "${BLUE}$*${NC}"
}

warn() {
  echo -e "${YELLOW}$*${NC}"
}

ok() {
  echo -e "${GREEN}$*${NC}"
}

require_root() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    fail "запустите скрипт от root или установите sudo"
  fi

  echo -e "${YELLOW}Для настройки SSH нужны права администратора. Сейчас будет запрос sudo.${NC}"
  exec sudo -E bash "$0" "$@"
}

check_supported_system() {
  [ -r /etc/os-release ] || fail "не удалось определить систему: нет /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release

  if [ "${ID:-}" != "ubuntu" ] && [ "${ID:-}" != "debian" ]; then
    warn "Скрипт рассчитан на Debian/Ubuntu. Обнаружено: ${PRETTY_NAME:-неизвестная система}."
    read -rp "Продолжить на свой риск? [y/N]: " answer
    case "$answer" in
      y|Y|yes|YES|д|Д) ;;
      *) exit 1 ;;
    esac
  fi
}

apt_update_once() {
  if [ "$APT_UPDATED" = false ]; then
    info "Обновляю список пакетов..."
    apt-get update -y >/dev/null
    APT_UPDATED=true
  fi
}

install_package() {
  local package=$1
  if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
    ok "$package уже установлен"
    return 0
  fi

  apt_update_once
  info "Устанавливаю $package..."
  apt-get install -y "$package" >/dev/null
}

service_exists() {
  systemctl list-unit-files "$1.service" >/dev/null 2>&1
}

detect_ssh_service() {
  if service_exists ssh; then
    SERVICE_NAME='ssh'
  elif service_exists sshd; then
    SERVICE_NAME='sshd'
  else
    SERVICE_NAME='ssh'
  fi
}

restart_ssh_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$SERVICE_NAME"
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
  else
    service "$SERVICE_NAME" restart
  fi
}

ensure_ssh_running() {
  detect_ssh_service

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      ok "SSH-сервис уже запущен"
    else
      info "Запускаю SSH-сервис..."
      systemctl start "$SERVICE_NAME"
    fi
  else
    service "$SERVICE_NAME" start
  fi
}

find_default_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi

  awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd
}

ask_target_user() {
  local default_user
  default_user=$(find_default_user)

  while true; do
    if [ -n "$default_user" ]; then
      read -rp "Для какого пользователя настроить вход по SSH? [$default_user]: " TARGET_USER
      TARGET_USER=${TARGET_USER:-$default_user}
    else
      read -rp "Введите имя пользователя для входа по SSH: " TARGET_USER
    fi

    if id "$TARGET_USER" >/dev/null 2>&1; then
      break
    fi
    warn "Пользователь '$TARGET_USER' не найден. Попробуйте ещё раз."
  done
}

random_recommended_port() {
  shuf -i 20000-49151 -n 1
}

current_configured_port() {
  if [ -f "$SSH_DROPIN" ]; then
    awk '/^[[:space:]]*Port[[:space:]]+/ {print $2; exit}' "$SSH_DROPIN"
  elif [ -f "$SSH_MAIN_CONFIG" ]; then
    awk '/^[[:space:]]*Port[[:space:]]+/ {print $2; exit}' "$SSH_MAIN_CONFIG"
  fi
}

valid_port() {
  local port=$1
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

ask_port() {
  local current_port recommended_port port_answer
  current_port=$(current_configured_port || true)
  recommended_port=$(random_recommended_port)

  echo
  echo -e "${YELLOW}Порт SSH${NC}"
  echo "Лучше выбрать нестандартный порт, например $recommended_port."
  echo "Так сервер будет меньше получать автоматический шум от сканеров."
  echo "Порт 22 проще запомнить, но его чаще всего пробуют атаковать."
  [ -n "$current_port" ] && echo "Сейчас в конфиге найден порт: $current_port"

  while true; do
    echo
    echo "1. Использовать рекомендованный порт: $recommended_port"
    [ -n "$current_port" ] && echo "2. Оставить текущий порт: $current_port" || echo "2. Использовать стандартный порт: 22"
    echo "3. Ввести свой порт"
    read -rp "Выберите вариант [1]: " port_answer
    port_answer=${port_answer:-1}

    case "$port_answer" in
      1)
        SSH_PORT=$recommended_port
        break
        ;;
      2)
        SSH_PORT=${current_port:-22}
        break
        ;;
      3)
        read -rp "Введите порт от 1 до 65535: " SSH_PORT
        if valid_port "$SSH_PORT"; then
          break
        fi
        warn "Некорректный порт. Нужна цифра от 1 до 65535."
        ;;
      *)
        warn "Выберите 1, 2 или 3."
        ;;
    esac
  done

  if [ "$SSH_PORT" = "22" ]; then
    warn "Вы выбрали порт 22. Это рабочий вариант, но для интернета безопаснее нестандартный порт."
  fi
}

ask_auth_mode() {
  local answer
  echo
  echo -e "${YELLOW}Способ входа${NC}"
  echo "1. SSH-ключ / токен доступа (рекомендуется)"
  echo "2. Пароль"
  echo "3. Оба варианта"
  echo
  echo "Если не знаете, что выбрать: используйте вариант 2 для быстрого старта,"
  echo "а после настройки перейдите на SSH-ключ."

  while true; do
    read -rp "Выберите способ входа [1]: " answer
    answer=${answer:-1}
    case "$answer" in
      1) AUTH_MODE='key'; break ;;
      2) AUTH_MODE='password'; break ;;
      3) AUTH_MODE='both'; break ;;
      *) warn "Выберите 1, 2 или 3." ;;
    esac
  done
}

ask_firewall() {
  local answer
  echo
  echo -e "${YELLOW}Брандмауэр${NC}"
  echo "Скрипт может открыть выбранный SSH-порт в UFW."
  echo "Это полезно, если UFW включён или вы хотите включить его сейчас."
  read -rp "Настроить UFW для порта $SSH_PORT? [Y/n]: " answer
  case "$answer" in
    n|N|no|NO|н|Н) SETUP_FIREWALL='no' ;;
    *) SETUP_FIREWALL='yes' ;;
  esac
}

setup_authorized_key() {
  local key home_dir ssh_dir auth_file owner_group

  if [ "$AUTH_MODE" != 'key' ] && [ "$AUTH_MODE" != 'both' ]; then
    return 0
  fi

  echo
  echo -e "${YELLOW}SSH-ключ / токен доступа${NC}"
  echo "Вставьте публичный SSH-ключ одной строкой."
  echo "Он обычно начинается с ssh-ed25519, ssh-rsa или ecdsa-sha2."
  echo "Если ключа пока нет, нажмите Enter: скрипт продолжит, но войти по ключу не получится."
  read -rp "Публичный SSH-ключ: " key

  if [ -z "$key" ]; then
    warn "Ключ не добавлен. Без ключа войти в режиме 'SSH-ключ / токен' не получится."
    if [ "$AUTH_MODE" = 'key' ]; then
      read -rp "Переключиться на вход по паролю, чтобы не потерять доступ? [Y/n]: " answer
      case "$answer" in
        n|N|no|NO|н|Н)
          warn "Продолжаю без ключа и без пароля. Используйте это только если ключ уже добавлен вручную."
          ;;
        *)
          AUTH_MODE='password'
          warn "Ок, дальше скрипт настроит вход по паролю."
          ;;
      esac
    fi
    return 0
  fi

  case "$key" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *) ;;
    *)
      warn "Строка не похожа на публичный SSH-ключ. Добавление отменено."
      if [ "$AUTH_MODE" = 'key' ]; then
        read -rp "Переключиться на вход по паролю, чтобы не потерять доступ? [Y/n]: " answer
        case "$answer" in
          n|N|no|NO|н|Н) ;;
          *)
            AUTH_MODE='password'
            warn "Ок, дальше скрипт настроит вход по паролю."
            ;;
        esac
      fi
      return 0
      ;;
  esac

  home_dir=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  ssh_dir="$home_dir/.ssh"
  auth_file="$ssh_dir/authorized_keys"
  owner_group=$(id -gn "$TARGET_USER")

  install -d -m 700 -o "$TARGET_USER" -g "$owner_group" "$ssh_dir"
  touch "$auth_file"
  chown "$TARGET_USER:$owner_group" "$auth_file"
  chmod 600 "$auth_file"

  if grep -Fxq "$key" "$auth_file"; then
    ok "Этот ключ уже есть в authorized_keys"
  else
    printf '%s\n' "$key" >> "$auth_file"
    ok "Ключ добавлен для пользователя $TARGET_USER"
  fi
}

setup_password() {
  local answer

  if [ "$AUTH_MODE" != 'password' ] && [ "$AUTH_MODE" != 'both' ]; then
    return 0
  fi

  echo
  echo -e "${YELLOW}Пароль пользователя${NC}"
  echo "Пользователь для входа: $TARGET_USER"
  read -rp "Хотите сейчас создать или изменить пароль этого пользователя? [Y/n]: " answer
  case "$answer" in
    n|N|no|NO|н|Н)
      warn "Пароль не изменён. Убедитесь, что вы его знаете, иначе вход по паролю не сработает."
      ;;
    *)
      passwd "$TARGET_USER"
      ;;
  esac
}

backup_file() {
  local file=$1
  [ -f "$file" ] || return 0
  local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$file" "$backup"
  echo "$backup"
}

ensure_sshd_include() {
  local main_backup_created='no'
  mkdir -p /etc/ssh/sshd_config.d

  if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*\.conf' "$SSH_MAIN_CONFIG"; then
    backup_file "$SSH_MAIN_CONFIG" >/dev/null
    main_backup_created='yes'
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$SSH_MAIN_CONFIG"
  fi

  if grep -Eq '^[[:space:]]*Port[[:space:]]+' "$SSH_MAIN_CONFIG"; then
    [ "$main_backup_created" = 'yes' ] || backup_file "$SSH_MAIN_CONFIG" >/dev/null
    sed -i -E 's/^[[:space:]]*Port[[:space:]]+/# Disabled by Instal_tools: &/' "$SSH_MAIN_CONFIG"
  fi
}

write_ssh_config() {
  local password_auth='no'
  local keyboard_auth='no'

  if [ "$AUTH_MODE" = 'password' ] || [ "$AUTH_MODE" = 'both' ]; then
    password_auth='yes'
    keyboard_auth='yes'
  fi

  ensure_sshd_include
  [ -f "$SSH_DROPIN" ] && backup_file "$SSH_DROPIN" >/dev/null

  cat > "$SSH_DROPIN" <<EOF
# Managed by Instal_tools M3.sh
Port $SSH_PORT
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication $password_auth
KbdInteractiveAuthentication $keyboard_auth
ChallengeResponseAuthentication $keyboard_auth
UsePAM yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
}

test_ssh_config() {
  if command -v sshd >/dev/null 2>&1; then
    sshd -t
  elif [ -x /usr/sbin/sshd ]; then
    /usr/sbin/sshd -t
  else
    fail "не найден sshd для проверки конфигурации"
  fi
}

setup_firewall() {
  if [ "$SETUP_FIREWALL" != 'yes' ]; then
    warn "Настройка UFW пропущена. Если есть другой firewall, откройте порт $SSH_PORT/tcp вручную."
    return 0
  fi

  install_package ufw

  ufw allow "$SSH_PORT/tcp" comment 'SSH configured by Instal_tools' >/dev/null
  ok "Порт $SSH_PORT/tcp открыт в UFW"

  if ufw status | grep -q 'Status: inactive'; then
    warn "UFW установлен, но сейчас выключен."
    read -rp "Включить UFW сейчас? Скрипт уже открыл SSH-порт $SSH_PORT. [y/N]: " answer
    case "$answer" in
      y|Y|yes|YES|д|Д)
        ufw --force enable >/dev/null
        ok "UFW включён"
        ;;
      *)
        warn "UFW оставлен выключенным."
        ;;
    esac
  fi
}

network_value() {
  local command=$1
  local fallback=$2
  local result=''

  result=$(eval "$command" 2>/dev/null || true)
  if [ -n "$result" ]; then
    printf '%s\n' "$result"
  else
    printf '%s\n' "$fallback"
  fi
}

print_summary() {
  local local_ip public_ip auth_text
  local_ip=$(network_value "hostname -I | awk '{print \\$1}'" 'не удалось определить')
  public_ip=$(network_value "curl -fsS --max-time 5 https://ifconfig.me" 'не удалось определить')

  case "$AUTH_MODE" in
    key) auth_text='SSH-ключ / токен доступа' ;;
    password) auth_text='пароль' ;;
    both) auth_text='SSH-ключ / токен доступа и пароль' ;;
  esac

  echo
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}        SSH НАСТРОЕН И ГОТОВ К РАБОТЕ   ${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo -e "Пользователь: ${GREEN}$TARGET_USER${NC}"
  echo -e "Порт SSH:     ${GREEN}$SSH_PORT${NC}"
  echo -e "Вход:         ${GREEN}$auth_text${NC}"
  echo -e "Локальный IP: ${GREEN}$local_ip${NC}"
  echo -e "Публичный IP: ${GREEN}$public_ip${NC}"
  echo
  echo -e "Команда для подключения из локальной сети:"
  echo -e "${YELLOW}ssh -p $SSH_PORT $TARGET_USER@$local_ip${NC}"
  echo
  echo -e "Команда для подключения через интернет, если настроен проброс порта на роутере:"
  echo -e "${YELLOW}ssh -p $SSH_PORT $TARGET_USER@$public_ip${NC}"
  echo
  echo -e "${YELLOW}Важно:${NC} если подключаетесь из интернета, на роутере нужно пробросить TCP-порт $SSH_PORT на эту машину."
}

main() {
  require_root "$@"
  show_header

  step 'Проверка системы и прав доступа'
  check_supported_system

  step 'Выбор пользователя, порта и способа входа'
  ask_target_user
  ask_port
  ask_auth_mode
  ask_firewall

  step 'Проверка и установка OpenSSH Server'
  if dpkg-query -W -f='${Status}' openssh-server 2>/dev/null | grep -q 'install ok installed'; then
    ok 'OpenSSH Server уже установлен'
  else
    install_package openssh-server
    ok 'OpenSSH Server установлен'
  fi

  step 'Запуск SSH и включение автозапуска'
  ensure_ssh_running

  step 'Настройка входа по ключу или паролю'
  setup_authorized_key
  setup_password

  step 'Запись безопасной SSH-конфигурации'
  write_ssh_config
  ok "Конфигурация записана в $SSH_DROPIN"

  step 'Проверка SSH-конфигурации'
  test_ssh_config
  ok 'Проверка sshd -t прошла успешно'

  step 'Настройка брандмауэра'
  setup_firewall

  step 'Перезапуск SSH и вывод инструкции'
  restart_ssh_service
  ok 'SSH-сервис перезапущен'
  print_summary
}

main "$@"
