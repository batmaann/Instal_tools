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
            chsh -s "$(which zsh)"
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
    
    log "${YELLOW}Перезагрузите терминал или выполните 'zsh' для входа в Zsh${NC}"
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
install_docker_desktop() {
    if is_package_installed docker-desktop || [ -x "$(command -v docker)" ]; then
        log "${YELLOW}Docker уже установлен. Версия: $(docker --version 2>/dev/null || echo 'не определена')${NC}"
        return 0
    fi

    log "${GREEN}Начало установки Docker Desktop...${NC}"

    # 1. Попытка установки через официальный .deb пакет
    log "${GREEN}Попытка установки через официальный .deb пакет...${NC}"
    if wget https://desktop.docker.com/linux/main/amd64/docker-desktop-4.27.2-amd64.deb -O /tmp/docker-desktop.deb 2>> "$LOG_FILE"; then
        if sudo apt-get install -y /tmp/docker-desktop.deb 2>> "$LOG_FILE"; then
            rm -f /tmp/docker-desktop.deb
            log "${GREEN}Docker Desktop успешно установлен через .deb пакет${NC}"
            post_docker_installation
            return 0
        else
            log "${YELLOW}Ошибка при установке .deb пакета, пробуем альтернативный метод...${NC}"
            rm -f /tmp/docker-desktop.deb
        fi
    else
        log "${YELLOW}Не удалось загрузить .deb пакет, пробуем альтернативный метод...${NC}"
    fi

    # 2. Альтернативный метод через официальный скрипт
    log "${GREEN}Попытка установки через официальный скрипт...${NC}"
    if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>> "$LOG_FILE"; then
        if sudo sh /tmp/get-docker.sh 2>> "$LOG_FILE"; then
            rm -f /tmp/get-docker.sh
            log "${GREEN}Docker Engine успешно установлен${NC}"
            
            # Установка Docker Desktop
            if wget https://desktop.docker.com/linux/main/amd64/docker-desktop-4.27.2-amd64.deb -O /tmp/docker-desktop.deb 2>> "$LOG_FILE"; then
                if sudo apt-get install -y /tmp/docker-desktop.deb 2>> "$LOG_FILE"; then
                    rm -f /tmp/docker-desktop.deb
                    log "${GREEN}Docker Desktop успешно установлен${NC}"
                    post_docker_installation
                    return 0
                else
                    log "${YELLOW}Не удалось установить Docker Desktop, но Docker Engine установлен${NC}"
                    return 0
                fi
            else
                log "${YELLOW}Не удалось загрузить Docker Desktop, но Docker Engine установлен${NC}"
                return 0
            fi
        else
            log "${RED}Ошибка при выполнении официального скрипта установки${NC}"
            return 1
        fi
    else
        log "${RED}Не удалось загрузить официальный скрипт установки${NC}"
        return 1
    fi
}

post_docker_installation() {
    log "${GREEN}Настройка Docker после установки...${NC}"
    
    # Добавление пользователя в группу docker
    if ! sudo usermod -aG docker $USER 2>> "$LOG_FILE"; then
        log "${YELLOW}Не удалось добавить пользователя в группу docker${NC}"
    fi
    
    # Запуск Docker Desktop
    if ! systemctl --user start docker-desktop 2>> "$LOG_FILE"; then
        log "${YELLOW}Не удалось запустить Docker Desktop автоматически${NC}"
        log "${YELLOW}Попробуйте запустить вручную: systemctl --user start docker-desktop${NC}"
    fi
    
    # Включение автозапуска
    if ! systemctl --user enable docker-desktop 2>> "$LOG_FILE"; then
        log "${YELLOW}Не удалось настроить автозапуск Docker Desktop${NC}"
    fi
    
    log "${GREEN}Настройка завершена. Может потребоваться перезагрузка системы.${NC}"
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
        install_outline_client
        install_docker_desktop
        post_docker_installation
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