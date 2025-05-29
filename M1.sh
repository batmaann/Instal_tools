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
    # Яркий заголовок с разделителями
    echo -e "${GREEN}\n========================================${NC}"
    echo -e "${GREEN}         ОБНОВЛЕНИЕ СИСТЕМЫ          ${NC}"
    echo -e "${GREEN}========================================${NC}"

    # 1. Подготовка системы (с анимацией)
    log "${YELLOW}⚙ Подготовка системы...${NC}"
    echo -n "[    ] Очистка кэша"
    sudo dpkg --configure -a > /dev/null 2>&1 &
    sudo apt-get clean > /dev/null 2>&1 &
    sudo apt-get autoclean > /dev/null 2>&1 &
    echo -e "\r[${GREEN}====${NC}] Очистка кэша завершена"

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

main() {
    # --- Инициализация ---
    # Проверка прав sudo (если скрипт требует root)
    if [ "$(id -u)" -ne 0 ]; then
        log "${RED}Ошибка: этот скрипт требует прав root/sudo. Запустите с sudo.${NC}"
        exit 1
    fi

    # Очистка лог-файла
    > "$LOG_FILE"
    log "${GREEN}=== Начало установки ===${NC}"

    # --- Проверка зависимостей ---
    local dependencies=("wget" "curl" "gpg")  # Пример зависимостей
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log "${YELLOW}Установка недостающей зависимости: $dep...${NC}"
            safe_apt install "$dep" || {
                log "${RED}Ошибка: не удалось установить $dep. Пропускаем...${NC}"
                continue
            }
        fi
    done

    # --- Основные этапы ---
    local stages=(
        "Обновление системы:update_packages"
        "Установка Git:install_git"
        "Установка Google Chrome:install_google_chrome"
        "Установка Zsh:install_zsh"
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

    # --- Завершение ---
    if [ $has_errors -eq 0 ]; then
        log "${GREEN}✔ Установка успешно завершена!${NC}"
    else
        log "${YELLOW}⚠ Установка завершена с ошибками. Проверьте лог.${NC}"
    fi

    # Краткая сводка
    log "Лог-файл: $LOG_FILE"
    echo -e "\n${YELLOW}=== Последние строки лога ===${NC}"
    tail -n 10 "$LOG_FILE" | sed -e 's/\x1b\[[0-9;]*m//g'  # Удаляем цвета для лога

    # Возвращаем код ошибки, если были проблемы
    return $has_errors
}



main