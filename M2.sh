#!/usr/bin/env bash

set -euo pipefail

# Конфигурация
STATUS_DIR="/var/lib/matrix-synapse/status"
FORCE_MODE=false

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Обработка аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --force) FORCE_MODE=true ;;
        *) echo -e "${RED}Неизвестный аргумент: $1${NC}"; exit 1 ;;
    esac
    shift
done

# Функции проверки выполненных шагов
check_step_I() {
    [ -f "${STATUS_DIR}/step1_completed" ] || 
    [ -f /etc/apt/sources.list.d/matrix-org.list ]
}

check_step_II() {
    [ -f "${STATUS_DIR}/step2_completed" ] ||
    dpkg -l matrix-synapse-py3 &> /dev/null
}

check_step_III() {
    [ -f "${STATUS_DIR}/step3_completed" ] ||
    [ -f /etc/matrix-synapse/homeserver.yaml ]
}

check_step_IV() {
    [ -f "${STATUS_DIR}/step4_completed" ]
}

# Инициализация системы
init_system() {
    sudo mkdir -p "${STATUS_DIR}"
    sudo chmod 755 "${STATUS_DIR}"
}

# Шаг 1: Установка зависимостей
install_dependencies_step_I() {
    if ! $FORCE_MODE && check_step_I; then
        echo -e "${GREEN}Шаг 1 уже выполнен, пропускаем...${NC}"
        return 0
    fi

    if ! install_dependencies_step_I; then
        echo -e "${RED}Ошибка на шаге 1. Прерывание работы.${NC}" >&2
        exit 1
    fi

    sudo touch "${STATUS_DIR}/step1_completed"
    echo -e "${GREEN}=== Установка зависимостей завершена успешно ===${NC}"
    return 0
}

# Шаг 2: Установка Synapse
install_synapse_step_II() {
    if ! $FORCE_MODE && check_step_II; then
        echo -e "${GREEN}Шаг 2 уже выполнен, пропускаем...${NC}"
        return 0
    fi

    if ! install_synapse_step_II; then
        echo -e "${RED}Ошибка на шаге 2. Прерывание работы.${NC}" >&2
        exit 1
    fi

    sudo touch "${STATUS_DIR}/step2_completed"
    echo -e "${GREEN}=== Установка Synapse завершена успешно ===${NC}"
    return 0
}

# Шаг 3: Настройка Synapse
configure_synapse_step_III() {
    if ! $FORCE_MODE && check_step_III; then
        echo -e "${GREEN}Шаг 3 уже выполнен, пропускаем...${NC}"
        return 0
    fi

    if ! configure_synapse_step_III; then
        echo -e "${RED}Ошибка на шаге 3. Прерывание работы.${NC}" >&2
        exit 1
    fi

    sudo touch "${STATUS_DIR}/step3_completed"
    echo -e "${GREEN}=== Настройка Synapse завершена успешно ===${NC}"
    return 0
}

# Шаг 4: Настройка брандмауэра
configure_firewall_step_IV() {
    local -r step_name="Настройка брандмауэра"
    echo -e "\n${GREEN}=== ${step_name} ===${NC}"

    # Проверка UFW
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}UFW не установлен. Установите его командой:"
        echo -e "sudo apt install ufw${NC}"
        return 0
    fi

    # Защита от сбоев
    set +e
    trap 'echo -e "${RED}Ошибка в шаге 4${NC}"; sudo ufw --force reset; return 1' ERR

    # Настройка правил
    echo -e "${YELLOW}1. Настройка правил...${NC}"
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Основные правила
    sudo ufw allow 8008/tcp comment "HTTP-API Synapse"
    sudo ufw allow 443/tcp comment "HTTPS"
    
    # Включение
    echo -e "${YELLOW}2. Активация брандмауэра...${NC}"
    echo "y" | sudo ufw enable
    
    # Проверка
    echo -e "${YELLOW}3. Итоговые правила:${NC}"
    sudo ufw status numbered
    
    # Фиксация успешного выполнения
    sudo touch "${STATUS_DIR}/step4_completed"
    set -e
    trap - ERR
    
    echo -e "${GREEN}=== ${step_name} завершена успешно ===${NC}"
    return 0
}

main() {
    init_system
    echo -e "\n${GREEN}=== Начало установки Matrix Synapse ===${NC}"
    
    # Запрос подтверждения при повторном запуске
    if ! $FORCE_MODE && { check_step_I || check_step_II || check_step_III; }; then
        echo -e "${YELLOW}Обнаружены следы предыдущей установки. Хотите продолжить? (yes/no) [no]:${NC}"
        read continue_install
        if [ "${continue_install:-no}" != "yes" ]; then
            echo -e "${YELLOW}Установка прервана пользователем${NC}"
            exit 0
        fi
    fi

    install_dependencies_step_I
    install_synapse_step_II
    configure_synapse_step_III
    configure_firewall_step_IV

      echo -e "\n${GREEN}=== Установка завершена успешно! ===${NC}"
    echo -e "Сервер Matrix Synapse готов к работе"
    echo -e "Основные файлы конфигурации:"
    echo -e " - /etc/matrix-synapse/homeserver.yaml"
    echo -e " - /etc/matrix-synapse/conf.d/server.yaml"
    echo -e "\nДля дальнейшей настройки:"
    echo -e "1. Откройте порт 8008 в брандмауэре (если нужен внешний доступ)"
    echo -e "2. Настройте обратный прокси (Nginx/Apache) для HTTPS"
    echo -e "3. Для регистрации пользователей установите enable_registration: true"
    
    exit 0
}

main "$@"