#!/bin/bash

set -o pipefail

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Лог-файл
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/instal-tools"
LOG_FILE="${LOG_DIR}/installation.log"

init_log() {
    if ! mkdir -p "$LOG_DIR" || ! : > "$LOG_FILE"; then
        echo "Не удалось создать лог-файл: $LOG_FILE" >&2
        exit 1
    fi
}

# Функция для логирования
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функция проверки установки пакета
is_package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii" || command -v "$1" &>/dev/null
}

# Функция для обработки ошибок apt
safe_apt() {
    local command=$1
    shift
    local retries=3
    local delay=5
    local success=0
    
    for ((i=1; i<=retries; i++)); do
        log "${BLUE}Попытка $i: apt-get $command $*${NC}"
        if sudo apt-get "$command" -y "$@" >> "$LOG_FILE" 2>&1; then
            success=1
            break
        else
            log "${YELLOW}Ошибка, повтор через $delay сек...${NC}"
            sleep "$delay"
            sudo apt-get --fix-broken install -y >> "$LOG_FILE" 2>&1
        fi
    done
    
    if [ "$success" -eq 0 ]; then
        log "${RED}Не удалось выполнить: apt-get $command $*${NC}"
        return 1
    fi
    return 0
}

check_supported_apt_system() {
    if [ ! -r /etc/os-release ]; then
        log "${RED}Не удалось определить дистрибутив: /etc/os-release отсутствует${NC}"
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ] && [ "${ID:-}" != "debian" ]; then
        log "${RED}Поддерживаются только Ubuntu и Debian. Обнаружено: ${PRETTY_NAME:-неизвестно}${NC}"
        return 1
    fi
}

# Функция для обновления пакетов
update_packages() {
    # Яркий заголовок с разделителями
    echo -e "${GREEN}\n========================================${NC}"
    echo -e "${GREEN}         ОБНОВЛЕНИЕ СИСТЕМЫ          ${NC}"
    echo -e "${GREEN}========================================${NC}"

    # 1. Подготовка системы (с анимацией)
    log "${BLUE}⚙ Подготовка системы...${NC}"
    spin='-\|/'
    echo -n "[    ] Очистка кэша "
    i=0
    (sudo apt-get clean > /dev/null 2>&1) &
    pid=$!
    while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r[${spin:$i:1}] Очистка кэша "
    sleep 0.1
    done
    printf "\r[${GREEN}✓${NC}] Очистка кэша завершена\n"

    # 2. Проверка проблемных PPA (с визуальным отображением)
    log "${YELLOW}🔍 Поиск проблемных репозиториев...${NC}"
    if grep -R "certbot/certbot" /etc/apt/sources.list.d/; then
        echo -e "${RED}⚠ Обнаружен проблемный PPA certbot${NC}"
        echo -n "Удаление..."
        sudo add-apt-repository --remove ppa:certbot/certbot -y > /dev/null 2>&1
        sudo rm -f /etc/apt/sources.list.d/certbot-ubuntu-certbot-*.list
        echo -e "\r${GREEN}✓ Удаление завершено${NC}"
    else
        echo -e "${GREEN}✓ Проблемные репозитории не обнаружены${NC}"
    fi

    # 3. Обновление пакетов с прогресс-баром
    log "${YELLOW}🔄 Обновление списка пакетов...${NC}"
    echo -n "[    ] Загрузка информации о пакетах"
    if ! safe_apt update; then
        echo -e "\r${RED}✗ Ошибка при обновлении${NC}"
        return 1
    fi
    echo -e "\r[${GREEN}====${NC}] Список пакетов обновлен"

    # 4. Прогресс обновления
    log "${YELLOW}📦 Обновление пакетов...${NC}"
    total=$(apt list --upgradable 2>/dev/null | wc -l)
    ((total--))
    
    if [ $total -gt 0 ]; then
        echo -e "${YELLOW}Найдено обновлений: $total${NC}"
        echo -n "["
        sudo apt-get upgrade -y | while read line; do
            if [[ $line =~ ^Inst ]]; then
                echo -n "="
            fi
        done
        echo -e "] ${GREEN}100%${NC}"
    else
        echo -e "${GREEN}✓ Все пакеты актуальны${NC}"
    fi

    # 5. Завершающие операции
    log "${YELLOW}🧹 Очистка системы...${NC}"
    echo -n "Оптимизация..."
    sudo apt-get dist-upgrade -y > /dev/null 2>&1
    sudo apt-get autoremove -y > /dev/null 2>&1
    echo -e "\r${GREEN}✓ Оптимизация завершена${NC}"

    # Итоговое сообщение
    echo -e "${GREEN}\n✔ Система успешно обновлена!${NC}"
    return 0
}

install_git() {
    if is_package_installed git; then
        log "${YELLOW}Git уже установлен. Версия: $(git --version | awk '{print $3}')${NC}"
        return 0
    fi

    log "${GREEN}Установка Git...${NC}"
    if safe_apt install git; then
        log "${GREEN}Git успешно установлен. Версия: $(git --version | awk '{print $3}')${NC}"
    else
        log "${RED}Ошибка при установке Git${NC}"
        return 1
    fi
}

install_google_chrome() {
    if is_package_installed google-chrome; then
        log "${YELLOW}Google Chrome уже установлен${NC}"
        return 0
    fi

    log "${GREEN}Загрузка Google Chrome...${NC}"
    if wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome.deb >> "$LOG_FILE" 2>&1; then
        log "${GREEN}Установка Google Chrome...${NC}"
        if sudo dpkg -i /tmp/google-chrome.deb >> "$LOG_FILE" 2>&1; then
            safe_apt install -f
            rm -f /tmp/google-chrome.deb
            log "${GREEN}Google Chrome успешно установлен${NC}"
        else
            log "${RED}Ошибка при установке Google Chrome${NC}"
            return 1
        fi
    else
        log "${RED}Ошибка при загрузке Google Chrome${NC}"
        return 1
    fi
}

install_oh_my_zsh() {
    log "${GREEN}Проверка установки Oh My Zsh...${NC}"
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "${GREEN}Установка Oh My Zsh...${NC}"
        if sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)" >> "$LOG_FILE" 2>&1; then
            log "${GREEN}Oh My Zsh успешно установлен${NC}"
            return 0
        else
            log "${RED}Ошибка при установке Oh My Zsh${NC}"
            return 1
        fi
    else
        log "${YELLOW}Oh My Zsh уже установлен${NC}"
        return 0
    fi
}

setup_bira_theme() {
    log "${GREEN}Проверка текущей темы Zsh...${NC}"
    
    local zshrc_file="$HOME/.zshrc"
    
    # Проверяем, установлен ли Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "${RED}Oh My Zsh не установлен. Сначала установите Oh My Zsh.${NC}"
        return 1
    fi
    
    # Проверяем существование файла .zshrc
    if [ ! -f "$zshrc_file" ]; then
        log "${YELLOW}Файл .zshrc не найден, создаем новый...${NC}"
        cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$zshrc_file"
    fi
    
    # Проверяем текущую тему
    if grep -q '^ZSH_THEME="bira"' "$zshrc_file"; then
        log "${YELLOW}Тема bira уже установлена, пропускаем...${NC}"
        return 0
    elif grep -q '^ZSH_THEME=' "$zshrc_file"; then
        log "${YELLOW}Обнаружена другая тема, меняем на bira...${NC}"
    else
        log "${YELLOW}Тема не указана, устанавливаем bira...${NC}"
    fi
    
    # Делаем резервную копию .zshrc, если она еще не существует
    if [ ! -f "${zshrc_file}.bak" ]; then
        cp "$zshrc_file" "${zshrc_file}.bak"
        log "${YELLOW}Создана резервная копия .zshrc: ${zshrc_file}.bak${NC}"
    fi
    
    # Устанавливаем тему bira
    if sed -i 's/^ZSH_THEME=.*/ZSH_THEME="bira"/' "$zshrc_file" 2>> "$LOG_FILE"; then
        log "${GREEN}Тема bira успешно установлена${NC}"
        log "${YELLOW}Для применения изменений перезагрузите терминал или выполните: source ~/.zshrc${NC}"
        return 0
    else
        log "${RED}Ошибка при настройке темы bira${NC}"
        return 1
    fi
}

install_zsh() {
    if is_package_installed zsh; then
        current_shell=$(basename "$SHELL")
        if [ "$current_shell" = "zsh" ]; then
            log "${YELLOW}Zsh уже установлен и установлен как оболочка по умолчанию. Версия: $(zsh --version | awk '{print $2}')${NC}"
        else
            log "${YELLOW}Zsh уже установлен, но не является оболочкой по умолчанию. Текущая оболочка: $current_shell${NC}"
        fi
    else
        log "${GREEN}Установка Zsh...${NC}"
        if safe_apt install zsh; then
            sudo chsh -s "$(command -v zsh)" "$USER"
            log "${GREEN}Zsh успешно установлен и установлен как оболочка по умолчанию. Версия: $(zsh --version | awk '{print $2}')${NC}"
        else
            log "${RED}Ошибка при установке Zsh${NC}"
            return 1
        fi
    fi
    
    # Установка Oh My Zsh и темы bira (если Zsh установлен или уже был установлен)
    if install_oh_my_zsh; then
        setup_bira_theme
    fi
    
    # ДОБАВЛЯЕМ НАСТРОЙКИ BASH
    log "${GREEN}Настройка Bash...${NC}"
    configure_bash_history
    
    log "${YELLOW}Перезагрузите терминал или выполните 'zsh' для входа в Zsh${NC}"
    log "${YELLOW}Для применения настроек Bash выполните: source /etc/bash.bashrc${NC}"
    return 0
}

# Новая функция для настройки Bash
configure_bash_history() {
    local bashrc_file="/etc/bash.bashrc"
    local settings_to_add=(
        "shopt -s histappend"
        "PROMPT_COMMAND='history -a'"
    )
    
    # Проверяем, существуют ли уже эти настройки
    local need_update=false
    
    for setting in "${settings_to_add[@]}"; do
        if ! grep -q "^$(echo "$setting" | sed 's/\[/\\[/g' | sed 's/\]/\\]/g')" "$bashrc_file" 2>/dev/null; then
            need_update=true
            break
        fi
    done
    
    if [ "$need_update" = true ]; then
        log "${YELLOW}Добавление настроек истории Bash в $bashrc_file...${NC}"
        
        # Создаем резервную копию, если ее нет
        if [ ! -f "${bashrc_file}.bak" ]; then
            sudo cp "$bashrc_file" "${bashrc_file}.bak"
            log "${GREEN}Создана резервная копия: ${bashrc_file}.bak${NC}"
        fi
        
        # Добавляем настройки в конец файла
        printf '\n%s\n' "# Настройки истории команд (добавлено скриптом установки)" |
            sudo tee -a "$bashrc_file" > /dev/null
        for setting in "${settings_to_add[@]}"; do
            printf '%s\n' "$setting" | sudo tee -a "$bashrc_file" > /dev/null
            log "${GREEN}Добавлено: $setting${NC}"
        done
        
        log "${GREEN}Настройки Bash успешно добавлены${NC}"
        
        # Применяем настройки для текущей сессии
        if [ -f "$bashrc_file" ]; then
            source "$bashrc_file" 2>/dev/null || true
            log "${YELLOW}Настройки применены для текущей сессии${NC}"
        fi
    else
        log "${YELLOW}Настройки истории Bash уже присутствуют в $bashrc_file, пропускаем...${NC}"
    fi
    
    return 0
}

install_outline_client() {
        if is_package_installed outline-client; then
            log "${YELLOW}Outline Client уже установлен${NC}"
            return 0
        fi

        log "${GREEN}Добавление репозитория Outline Client...${NC}"
        
        # Импорт GPG ключа
        if ! wget -qO- https://us-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/gcloud-artifact-registry-us.gpg 2>> "$LOG_FILE"; then
            log "${RED}Ошибка при импорте GPG ключа${NC}"
            return 1
        fi
        
        # Добавление репозитория
        if ! echo "deb [arch=amd64] https://us-apt.pkg.dev/projects/jigsaw-outline-apps outline-client main" | sudo tee /etc/apt/sources.list.d/outline-client.list >> "$LOG_FILE" 2>&1; then
            log "${RED}Ошибка при добавлении репозитория${NC}"
            return 1
        fi
        
        # Обновление пакетов после добавления репозитория
        if ! safe_apt update; then
            log "${RED}Ошибка при обновлении списка пакетов${NC}"
            return 1
        fi
        
        log "${GREEN}Установка Outline Client...${NC}"
        if safe_apt install outline-client; then
            log "${GREEN}Outline Client успешно установлен${NC}"
        else
            log "${RED}Ошибка при установке Outline Client${NC}"
            return 1
        fi
    }

install_postman() {
    if is_package_installed postman; then
        log "${YELLOW}Postman уже установлен${NC}"
        return 0
    fi

    log "${GREEN}Установка Postman...${NC}"
    
    # Скачивание и установка Postman как snap-пакета
    if sudo snap install postman >> "$LOG_FILE" 2>&1; then
        log "${GREEN}Postman успешно установлен${NC}"
        return 0
    else
        log "${RED}Ошибка при установке Postman через snap${NC}"
        
        # Альтернативный метод установки (через tar.gz)
        log "${YELLOW}Попытка установки через tar.gz...${NC}"
        
        local temp_dir
        temp_dir=$(mktemp -d)
        
        if wget "https://dl.pstmn.io/download/latest/linux64" -O "$temp_dir/postman.tar.gz" >> "$LOG_FILE" 2>&1; then
            log "${GREEN}Распаковка Postman...${NC}"
            sudo tar -xzf "$temp_dir/postman.tar.gz" -C /opt >> "$LOG_FILE" 2>&1
            sudo ln -sf /opt/Postman/Postman /usr/bin/postman
            
            # Создание ярлыка для рабочего стола
            cat <<EOF | sudo tee /usr/share/applications/postman.desktop > /dev/null
[Desktop Entry]
Name=Postman
Exec=/opt/Postman/Postman
Icon=/opt/Postman/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;
EOF
            
            rm -rf "$temp_dir"
            log "${GREEN}Postman успешно установлен в /opt/Postman${NC}"
            return 0
        else
            log "${RED}Ошибка при загрузке Postman${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
}
install_htop() {
    if is_package_installed htop; then
        log "${YELLOW}htop уже установлен. Версия: $(htop --version | head -n1 | awk '{print $2}')${NC}"
        return 0
    fi

    log "${GREEN}Установка htop...${NC}"
    if safe_apt install htop; then
        log "${GREEN}htop успешно установлен. Версия: $(htop --version | head -n1 | awk '{print $2}')${NC}"
        return 0
    else
        log "${RED}Ошибка при установке htop${NC}"
        return 1
    fi
}

install_vscode() {
    if is_package_installed code; then
        log "${YELLOW}Visual Studio Code уже установлен. Версия: $(code --version | head -n1)${NC}"
        return 0
    fi

    log "${GREEN}Установка Visual Studio Code...${NC}"

    # Проверяем snapd
    if ! command -v snap &>/dev/null; then
        log "${YELLOW}snapd не найден, устанавливаем snapd...${NC}"
        if ! safe_apt install snapd; then
            log "${RED}Ошибка при установке snapd${NC}"
            return 1
        fi
        sudo systemctl enable --now snapd >> "$LOG_FILE" 2>&1
    fi

    # Установка VS Code
    if sudo snap install code --classic >> "$LOG_FILE" 2>&1; then
        log "${GREEN}Visual Studio Code успешно установлен${NC}"
        return 0
    else
        log "${RED}Ошибка при установке Visual Studio Code${NC}"
        return 1
    fi
}

install_pycharm() {
    log "${GREEN}Установка PyCharm Community (Flatpak)...${NC}"

    # Уже установлен?
    if flatpak list | grep -q com.jetbrains.PyCharm-Community; then
        log "${YELLOW}PyCharm Community уже установлен${NC}"
        return 0
    fi

    # 1. Зависимости
    log "${BLUE}Проверка и установка Flatpak...${NC}"
    safe_apt install flatpak ca-certificates || return 1

    # 2. Добавление Flathub
    log "${BLUE}Добавление Flathub...${NC}"
    if ! flatpak remote-list | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
            >> "$LOG_FILE" 2>&1 || {
            log "${RED}Ошибка добавления Flathub${NC}"
            return 1
        }
    fi

    # 3. Установка PyCharm
    log "${BLUE}Установка PyCharm Community...${NC}"
    if flatpak install -y flathub com.jetbrains.PyCharm-Community >> "$LOG_FILE" 2>&1; then
        log "${GREEN}✔ PyCharm Community успешно установлен (Flatpak)${NC}"
        log "${YELLOW}Запуск: flatpak run com.jetbrains.PyCharm-Community${NC}"
        return 0
    else
        log "${RED}❌ Ошибка установки PyCharm Community${NC}"
        return 1
    fi
}


download_file() {
    local destination=$1
    shift
    local url
    local display_url

    for url in "$@"; do
        [ -n "$url" ] || continue
        display_url=${url%%\?*}
        log "${BLUE}Загрузка: $display_url${NC}"
        rm -f "$destination"
        if curl -fL --retry 3 --retry-delay 3 --connect-timeout 20 \
            "$url" -o "$destination" >> "$LOG_FILE" 2>&1; then
            return 0
        fi
        log "${YELLOW}Источник недоступен, пробуем следующий...${NC}"
    done

    return 1
}

install_webstorm_archive() {
    local arch
    local download_key
    local temp_dir
    local release_json
    local release_data
    local version
    local download_url
    local checksum_url
    local cdn_url
    local cdn_checksum_url
    local archive_path
    local checksum_path
    local expected_checksum
    local actual_checksum
    local extract_dir
    local source_dir
    local install_dir
    local launcher
    local mem_total_kb
    local available_kb
    local archive_name

    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64)
            download_key="linux"
            ;;
        arm64)
            download_key="linuxARM64"
            ;;
        *)
            log "${RED}WebStorm поддерживает только amd64 и arm64. Обнаружено: $arch${NC}"
            return 1
            ;;
    esac

    mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    if [ "${mem_total_kb:-0}" -lt 8388608 ]; then
        log "${RED}WebStorm требует не менее 8 ГБ оперативной памяти${NC}"
        return 1
    fi

    available_kb=$(df -Pk /opt | awk 'NR == 2 {print $4}')
    if [ "${available_kb:-0}" -lt 10485760 ]; then
        log "${RED}Для WebStorm требуется не менее 10 ГБ свободного места в /opt${NC}"
        return 1
    fi

    if ! find /usr/share/xsessions /usr/share/wayland-sessions -maxdepth 1 \
        -type f -name '*.desktop' -print -quit 2>/dev/null | grep -q .; then
        log "${RED}Не найдена графическая среда для запуска WebStorm${NC}"
        return 1
    fi

    safe_apt install ca-certificates curl tar python3 || return 1

    temp_dir=$(mktemp -d)
    release_json="${temp_dir}/release.json"
    archive_path="${temp_dir}/webstorm.tar.gz"
    checksum_path="${temp_dir}/webstorm.tar.gz.sha256"

    if [ -n "${WEBSTORM_DOWNLOAD_URL:-}" ]; then
        if [[ "$WEBSTORM_DOWNLOAD_URL" != https://* ]]; then
            log "${RED}WEBSTORM_DOWNLOAD_URL должен использовать HTTPS${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
        version="custom"
        download_url="$WEBSTORM_DOWNLOAD_URL"
        checksum_url="${WEBSTORM_CHECKSUM_URL:-}"
        cdn_url=""
        cdn_checksum_url=""
        log "${YELLOW}Используется URL из WEBSTORM_DOWNLOAD_URL${NC}"
    elif [ -n "${WEBSTORM_VERSION:-}" ]; then
        version="$WEBSTORM_VERSION"
        if [ "$download_key" = "linuxARM64" ]; then
            archive_name="WebStorm-${version}-aarch64.tar.gz"
        else
            archive_name="WebStorm-${version}.tar.gz"
        fi
        download_url="https://download.jetbrains.com/webstorm/${archive_name}"
        checksum_url="${download_url}.sha256"
        cdn_url="https://download-cdn.jetbrains.com/webstorm/${archive_name}"
        cdn_checksum_url="${cdn_url}.sha256"
        log "${YELLOW}Используется версия из WEBSTORM_VERSION: $version${NC}"
    else
        log "${GREEN}Получение информации о последнем стабильном WebStorm...${NC}"
        if ! download_file "$release_json" \
            "https://data.services.jetbrains.com/products/releases?code=WS&latest=true&type=release"; then
            rm -rf "$temp_dir"
            log "${RED}Не удалось получить данные о релизе WebStorm${NC}"
            return 1
        fi

        if ! release_data=$(python3 -c '
import json
import sys

key = sys.argv[1]
data = json.load(sys.stdin)["WS"][0]
download = data["downloads"][key]
print("|".join((data["version"], download["link"], download["checksumLink"])))
' "$download_key" < "$release_json"); then
            rm -rf "$temp_dir"
            log "${RED}Не удалось разобрать ответ API JetBrains${NC}"
            return 1
        fi

        IFS='|' read -r version download_url checksum_url <<< "$release_data"
        cdn_url=${download_url/https:\/\/download.jetbrains.com/https:\/\/download-cdn.jetbrains.com}
        cdn_checksum_url=${checksum_url/https:\/\/download.jetbrains.com/https:\/\/download-cdn.jetbrains.com}
    fi

    if [[ ! "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]]; then
        rm -rf "$temp_dir"
        log "${RED}Некорректная версия WebStorm: $version${NC}"
        return 1
    fi

    log "${GREEN}Загрузка WebStorm ${version}...${NC}"
    if ! download_file "$archive_path" "$download_url" "$cdn_url"; then
        rm -rf "$temp_dir"
        log "${RED}Не удалось загрузить WebStorm${NC}"
        log "${YELLOW}Можно задать HTTPS_PROXY или WEBSTORM_DOWNLOAD_URL и повторить запуск.${NC}"
        return 1
    fi

    if [ -n "${WEBSTORM_SHA256:-}" ]; then
        expected_checksum=${WEBSTORM_SHA256,,}
    elif [ -n "$checksum_url" ]; then
        if [[ "$checksum_url" != https://* ]]; then
            rm -rf "$temp_dir"
            log "${RED}WEBSTORM_CHECKSUM_URL должен использовать HTTPS${NC}"
            return 1
        fi
        if ! download_file "$checksum_path" "$checksum_url" "$cdn_checksum_url"; then
            rm -rf "$temp_dir"
            log "${RED}Не удалось загрузить контрольную сумму WebStorm${NC}"
            return 1
        fi
        expected_checksum=$(awk 'NR == 1 {print $1}' "$checksum_path")
    else
        rm -rf "$temp_dir"
        log "${RED}Для пользовательского URL задайте WEBSTORM_SHA256 или WEBSTORM_CHECKSUM_URL${NC}"
        return 1
    fi

    if [[ ! "$expected_checksum" =~ ^[0-9a-f]{64}$ ]]; then
        rm -rf "$temp_dir"
        log "${RED}Некорректная контрольная сумма SHA-256${NC}"
        return 1
    fi

    actual_checksum=$(sha256sum "$archive_path" | awk '{print $1}')
    if [ "$actual_checksum" != "$expected_checksum" ]; then
        rm -rf "$temp_dir"
        log "${RED}Контрольная сумма WebStorm не совпала${NC}"
        return 1
    fi

    extract_dir="${temp_dir}/extracted"
    mkdir -p "$extract_dir"
    if ! tar -xzf "$archive_path" -C "$extract_dir" >> "$LOG_FILE" 2>&1; then
        rm -rf "$temp_dir"
        log "${RED}Не удалось распаковать WebStorm${NC}"
        return 1
    fi

    source_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)
    if [ -z "$source_dir" ]; then
        rm -rf "$temp_dir"
        log "${RED}В архиве WebStorm не найден каталог приложения${NC}"
        return 1
    fi

    launcher=$(find "$source_dir/bin" -maxdepth 1 -type f \
        \( -name 'webstorm' -o -name 'webstorm.sh' \) -print -quit)
    if [ -z "$launcher" ]; then
        rm -rf "$temp_dir"
        log "${RED}Не найден исполняемый файл WebStorm${NC}"
        return 1
    fi

    install_dir="/opt/webstorm-${version}"
    sudo rm -rf "$install_dir"
    sudo mv "$source_dir" "$install_dir"
    sudo ln -sfn "$install_dir" /opt/webstorm
    launcher="${install_dir}/bin/$(basename "$launcher")"
    sudo ln -sfn "$launcher" /usr/local/bin/webstorm

    sudo tee /usr/share/applications/webstorm.desktop > /dev/null <<EOF
[Desktop Entry]
Name=WebStorm
Comment=JavaScript and TypeScript IDE
Exec=/usr/local/bin/webstorm %f
Icon=/opt/webstorm/bin/webstorm.svg
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=jetbrains-webstorm
EOF

    rm -rf "$temp_dir"
    log "${GREEN}WebStorm ${version} успешно установлен из официального архива${NC}"
    log "${YELLOW}Запуск: webstorm${NC}"
    return 0
}

install_webstorm() {
    log "${GREEN}Установка WebStorm...${NC}"
    log "${YELLOW}WebStorm бесплатен для некоммерческого использования, но отдельной Community-редакции нет.${NC}"

    if command -v webstorm > /dev/null || snap list webstorm > /dev/null 2>&1; then
        log "${YELLOW}WebStorm уже установлен${NC}"
        return 0
    fi

    if [ "${WEBSTORM_INSTALL_METHOD:-auto}" != "archive" ] && \
        [ -z "${WEBSTORM_DOWNLOAD_URL:-}" ]; then
        if ! command -v snap > /dev/null; then
            log "${YELLOW}snapd не найден, устанавливаем snapd...${NC}"
            safe_apt install snapd || true
            sudo systemctl enable --now snapd >> "$LOG_FILE" 2>&1 || true
        fi

        if command -v snap > /dev/null; then
            log "${GREEN}Попытка установки WebStorm через официальный Snap Store...${NC}"
            if sudo snap install webstorm --classic >> "$LOG_FILE" 2>&1; then
                log "${GREEN}WebStorm успешно установлен через Snap${NC}"
                return 0
            fi
            log "${YELLOW}Snap Store недоступен. Переходим к официальному архиву JetBrains.${NC}"
        fi
    fi

    install_webstorm_archive
}


install_docker_desktop() {
    local arch
    local distro
    local codename
    local temp_dir
    local package_path
    local docker_repo
    local mem_total_kb

    if dpkg-query -W -f='${Status}' docker-desktop 2>/dev/null | grep -q "install ok installed"; then
        log "${YELLOW}Docker Desktop уже установлен${NC}"
        return 0
    fi

    check_supported_apt_system || return 1

    arch=$(dpkg --print-architecture)
    if [ "$arch" != "amd64" ]; then
        log "${RED}Docker Desktop для Linux поддерживает только amd64. Обнаружено: $arch${NC}"
        return 1
    fi

    if [ ! -d /run/systemd/system ]; then
        log "${RED}Docker Desktop требует systemd${NC}"
        return 1
    fi

    mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    if [ "${mem_total_kb:-0}" -lt 4194304 ]; then
        log "${RED}Docker Desktop требует не менее 4 ГБ оперативной памяти${NC}"
        return 1
    fi

    if ! find /usr/share/xsessions /usr/share/wayland-sessions -maxdepth 1 \
        -type f -name '*.desktop' -print -quit 2>/dev/null | grep -q .; then
        log "${RED}Не найдена поддерживаемая графическая среда рабочего стола${NC}"
        return 1
    fi

    if [ ! -e /dev/kvm ]; then
        log "${YELLOW}Устройство /dev/kvm не найдено. Пытаемся загрузить модуль KVM...${NC}"
        sudo modprobe kvm >> "$LOG_FILE" 2>&1 || true
        if grep -qE 'vendor_id[[:space:]]*: GenuineIntel' /proc/cpuinfo; then
            sudo modprobe kvm_intel >> "$LOG_FILE" 2>&1 || true
        elif grep -qE 'vendor_id[[:space:]]*: AuthenticAMD' /proc/cpuinfo; then
            sudo modprobe kvm_amd >> "$LOG_FILE" 2>&1 || true
        fi
    fi

    if [ ! -e /dev/kvm ]; then
        log "${RED}KVM недоступен. Включите аппаратную виртуализацию в BIOS/UEFI и повторите установку.${NC}"
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    distro="$ID"
    codename="${VERSION_CODENAME:-}"
    if [ -z "$codename" ]; then
        log "${RED}Не удалось определить кодовое имя выпуска Linux${NC}"
        return 1
    fi

    log "${GREEN}Настройка официального репозитория Docker...${NC}"
    safe_apt install ca-certificates curl gnupg qemu-system-x86 pass uidmap dbus-user-session gnome-terminal || return 1
    sudo install -m 0755 -d /etc/apt/keyrings
    if ! sudo curl -fsSL "https://download.docker.com/linux/${distro}/gpg" \
        -o /etc/apt/keyrings/docker.asc; then
        log "${RED}Не удалось загрузить GPG-ключ Docker${NC}"
        return 1
    fi
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    docker_repo="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro} ${codename} stable"
    printf '%s\n' "$docker_repo" |
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    safe_apt update || return 1

    temp_dir=$(mktemp -d)
    package_path="${temp_dir}/docker-desktop-amd64.deb"
    log "${GREEN}Загрузка актуального пакета Docker Desktop...${NC}"
    if ! curl -fL --retry 3 \
        "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb" \
        -o "$package_path" >> "$LOG_FILE" 2>&1; then
        rm -rf "$temp_dir"
        log "${RED}Не удалось загрузить Docker Desktop${NC}"
        return 1
    fi

    log "${GREEN}Установка Docker Desktop...${NC}"
    if ! sudo apt-get install -y "$package_path" >> "$LOG_FILE" 2>&1; then
        rm -rf "$temp_dir"
        log "${RED}Ошибка при установке Docker Desktop${NC}"
        return 1
    fi
    rm -rf "$temp_dir"

    if ! getent group kvm > /dev/null; then
        sudo groupadd kvm
    fi
    sudo usermod -aG kvm "$USER"

    log "${GREEN}Docker Desktop успешно установлен${NC}"
    log "${YELLOW}Выйдите из системы и войдите снова, затем запустите Docker Desktop из меню приложений.${NC}"
    log "${YELLOW}При первом запуске потребуется принять условия Docker Desktop.${NC}"
}

# Интерактивное меню
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}         ИНТЕРАКТИВНОЕ МЕНЮ            ${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}║ ${BLUE}1${NC}. Полная установка               ║"
        echo -e "${GREEN}║ ${CYAN}2${NC}. Только обновление пакетов      ║"
        echo -e "3. Установить Git"
        echo -e "4. Установить Google Chrome"
        echo -e "5. Установить Zsh + Oh My Zsh"
        echo -e "6. Установить Outline Client"
        echo -e "7. Установить Postman"
        echo -e "8. Установить htop"
        echo -e "9. Установить Visual Studio Code"
        echo -e "10. Установить PyCharm"
        echo -e "11. Установить Docker Desktop"
        echo -e "12. Установить WebStorm"
        echo -e "13. Выход"
        echo -e "${GREEN}========================================${NC}"
        read -rp "Выберите действие [1-13]: " choice

        case $choice in
            1)
                # Полная установка
                full_installation
                ;;
            2)
                # Только обновление пакетов
                update_packages
                ;;
            3)
                # Установка Git
                install_git
                ;;
            4)
                # Установка Google Chrome
                install_google_chrome
                ;;
            5)
                # Установка Zsh
                install_zsh
                ;;
            6)
                # Установка Outline Client
                install_outline_client
                ;;
            7)
                install_postman
                ;;
            8)
                install_htop
                ;;
            9)
                install_vscode
                ;;
            10)
                install_pycharm
                ;;
            11)
                install_docker_desktop
                ;;
            12)
                install_webstorm
                ;;
            13)
                echo -e "${GREEN}Выход...${NC}"
                exit 0
                ;;

            *)
                echo -e "${RED}Неверный выбор, попробуйте снова${NC}"
                sleep 2
                ;;
        esac

        read -rp "Нажмите Enter чтобы продолжить..."
    done
}

# Полная установка
full_installation() {
    log "${GREEN}=== Начало полной установки ===${NC}"

    local stages=(
        "Обновление системы:update_packages"
        "Установка Git:install_git"
        "Установка Google Chrome:install_google_chrome"
        "Установка Zsh:install_zsh"
        "Установка Outline Client:install_outline_client"
        "Установка Postman:install_postman"
        "Установка htop:install_htop"
        "Установка Visual Studio Code:install_vscode"
        "Установка PyCharm:install_pycharm"
    )

    local has_errors=0

    for stage in "${stages[@]}"; do
        local name="${stage%%:*}"
        local func="${stage##*:}"

        log "${GREEN}▶ Этап: $name${NC}"
        
        if ! $func; then
            log "${RED}⚠ Ошибка в этапе: $name${NC}"
            has_errors=1
        fi
    done

    if [ $has_errors -eq 0 ]; then
        log "${GREEN}✔ Полная установка успешно завершена!${NC}"
    else
        log "${YELLOW}⚠ Установка завершена с ошибками. Проверьте лог.${NC}"
    fi

    return $has_errors
}

# Точка входа
main() {
    init_log

    if [ "$(id -u)" -eq 0 ]; then
        log "${RED}Не запускайте M1.sh от root. Запустите его обычным пользователем: ./M1.sh${NC}"
        exit 1
    fi

    if ! command -v sudo > /dev/null; then
        log "${RED}Для работы скрипта требуется sudo${NC}"
        exit 1
    fi

    if ! command -v apt-get > /dev/null || ! command -v dpkg > /dev/null; then
        log "${RED}Скрипт поддерживает только системы на базе Debian/Ubuntu${NC}"
        exit 1
    fi

    # Если есть аргументы командной строки, выполнить их
    if [ $# -gt 0 ]; then
        case $1 in
            --full)
                full_installation
                ;;
            --update)
                update_packages
                ;;
            --git)
                install_git
                ;;
            --chrome)
                install_google_chrome
                ;;
            --zsh)
                install_zsh
                ;;
            --outline)
                install_outline_client
                ;;
            --htop)
                install_htop
                ;;
            --postman)
                install_postman
                ;;
            --vscode)
                install_vscode
                ;;
            --pycharm)
                install_pycharm
                ;;
            --docker-desktop)
                install_docker_desktop
                ;;
            --webstorm)
                install_webstorm
                ;;
            --help|-h)
                echo "Использование: $0 [--full|--update|--git|--chrome|--zsh|--outline|--postman|--htop|--vscode|--pycharm|--docker-desktop|--webstorm]"
                ;;
            *)
                echo "Неизвестный аргумент: $1"
                echo "Используйте $0 --help для списка доступных параметров"
                exit 1
                ;;
        esac
    else
        # Если аргументов нет, показать меню
        show_menu
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
