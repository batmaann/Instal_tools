#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Лог файл
LOG_FILE="installation.log"

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
    
    for ((i=1; i<=retries; i++)); do
        if sudo apt-get $command -y "$@" >> "$LOG_FILE" 2>&1; then
            return 0
        else
            log "${YELLOW}Попытка $i из $retries не удалась. Повтор через $delay секунд...${NC}"
            sleep $delay
            sudo apt-get --fix-broken install -y >> "$LOG_FILE" 2>&1
        fi
    done
    
    log "${RED}Ошибка при выполнении apt-get $command${NC}"
    return 1
}

# Функция для обновления пакетов
update_packages() {
    log "${GREEN}Обновление списка пакетов...${NC}"
    
    # Очистка кэша и исправление возможных проблем с пакетами
    sudo dpkg --configure -a 2>&1 | tee -a "$LOG_FILE"
    sudo apt-get clean 2>&1 | tee -a "$LOG_FILE"
    sudo apt-get autoclean 2>&1 | tee -a "$LOG_FILE"
    
    # Удаление проблемных PPA если есть
    if grep -R "certbot/certbot" /etc/apt/sources.list.d/; then
        log "${YELLOW}Обнаружен проблемный PPA certbot, удаление...${NC}"
        sudo add-apt-repository --remove ppa:certbot/certbot -y >> "$LOG_FILE" 2>&1
        sudo rm -f /etc/apt/sources.list.d/certbot-ubuntu-certbot-*.list
    fi
    
    # Попытка обновления
    if ! safe_apt update; then
        log "${RED}Критическая ошибка при обновлении пакетов${NC}"
        log "${YELLOW}Проверьте интернет-соединение и настройки репозиториев${NC}"
        return 1
    fi
    
    log "${GREEN}Обновление установленных пакетов...${NC}"
    safe_apt upgrade
    
    log "${GREEN}Обновление дистрибутива...${NC}"
    safe_apt dist-upgrade
    
    log "${GREEN}Удаление неиспользуемых пакетов...${NC}"
    safe_apt autoremove
    
    log "${GREEN}Обновление пакетов завершено!${NC}"
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

install_zsh() {
    if is_package_installed zsh; then
        current_shell=$(basename "$SHELL")
        if [ "$current_shell" = "zsh" ]; then
            log "${YELLOW}Zsh уже установлен и установлен как оболочка по умолчанию. Версия: $(zsh --version | awk '{print $2}')${NC}"
        else
            log "${YELLOW}Zsh уже установлен, но не является оболочкой по умолчанию. Текущая оболочка: $current_shell${NC}"
        fi
        return 0
    fi

    log "${GREEN}Установка Zsh...${NC}"
    if safe_apt install zsh; then
        chsh -s "$(which zsh)"
        log "${GREEN}Zsh успешно установлен и установлен как оболочка по умолчанию. Версия: $(zsh --version | awk '{print $2}')${NC}"
        log "${YELLOW}Перезагрузите терминал или выполните 'zsh' для входа в Zsh${NC}"
    else
        log "${RED}Ошибка при установке Zsh${NC}"
        return 1
    fi
}

main() {
    log "=== Начало установки ==="
    
    # Создаем пустой лог-файл
    > "$LOG_FILE"
    
    update_packages || log "${RED}Продолжаем несмотря на ошибки обновления${NC}"
    
    declare -a functions=(
        install_git
        install_google_chrome
        install_zsh
    )
    
    for func in "${functions[@]}"; do
        if ! $func; then
            log "${RED}Ошибка в функции $func, продолжаем установку...${NC}"
        fi
    done
    
    log "=== Установка завершена ==="
    log "Подробности в лог-файле: $LOG_FILE"
    
    # Вывод последних 10 строк лога для быстрого просмотра
    echo -e "\n${YELLOW}=== Последние строки лога ===${NC}"
    tail -n 10 "$LOG_FILE"
}

main