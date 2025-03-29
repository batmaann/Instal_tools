#!/usr/bin/env bash

# Функция для проверки обновляемых пакетов
check_upgradable_packages() {
    echo "Проверка доступных обновлений пакетов..."
    local upgradable=$(apt list --upgradable 2>/dev/null | grep -v "^Листинг...$" | wc -l)
    
    if [[ $upgradable -gt 0 ]]; then
        echo "Найдено пакетов для обновления: $upgradable"
        echo "Список обновляемых пакетов:"
        apt list --upgradable 2>/dev/null | grep -v "^Листинг...$"
        return 0
    else
        echo "Нет доступных обновлений для установленных пакетов."
        return 1
    fi
}

# Установка зависимостей и настройка репозитория Matrix.org
install_dependencies_step_I() {
    local -r step_name="Установка зависимостей и настройка Matrix.org"
    echo "=== ${step_name} ==="
    
    # 1. Обновление системы
    echo "1. Обновление списка пакетов и системы..."
    if ! sudo apt update; then
        echo "Ошибка при обновлении списка пакетов" >&2
        return 1
    fi
    
    # Проверка доступных обновлений перед установкой
    check_upgradable_packages
    
    if ! sudo apt upgrade -y; then
        echo "Ошибка при обновлении пакетов" >&2
        return 1
    fi
    
    # 2. Установка базовых зависимостей
    echo "2. Установка необходимых пакетов..."
    local -a base_packages=("curl" "gnupg" "apt-transport-https" "lsb-release")
    if ! sudo apt install -y "${base_packages[@]}"; then
        echo "Ошибка при установке базовых пакетов" >&2
        return 1
    fi
    
    # 3. Настройка репозитория Matrix.org
    echo "3. Настройка репозитория Matrix.org..."
    
    # 3.1. Добавление GPG ключа
    echo "3.1. Импорт GPG ключа..."
    if ! curl -s https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/matrix-org-archive-keyring.gpg; then
        echo "Ошибка при импорте GPG ключа" >&2
        return 1
    fi
    
    # 3.2. Добавление репозитория
    echo "3.2. Добавление репозитория в sources.list..."
    local -r distro_codename=$(lsb_release -cs)
    if ! echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ ${distro_codename} main" | sudo tee /etc/apt/sources.list.d/matrix-org.list >/dev/null; then
        echo "Ошибка при добавлении репозитория" >&2
        return 1
    fi
    
    # 4. Обновление после добавления репозитория
    echo "4. Обновление списка пакетов..."
    if ! sudo apt update; then
        echo "Ошибка при обновлении после добавления репозитория" >&2
        return 1
    fi
    
    # Повторная проверка обновлений после всех изменений
    check_upgradable_packages
    
    echo "=== ${step_name} завершена успешно ==="
    return 0
}

# Шаг 2: Установка Synapse (сервер Matrix)
install_synapse_step_II() {
    local -r step_name="Установка Synapse (Matrix сервер)"
    echo "=== ${step_name} ==="

    # 1. Установка пакета
    echo "1. Установка matrix-synapse-py3..."
    if ! sudo apt install -y matrix-synapse-py3; then
        echo "Ошибка при установке Synapse" >&2
        return 1
    fi

    # 2. Конфигурация сервера
    echo "2. Настройка сервера Synapse"
    
    # Запрос имени сервера
    local server_name
    read -p "Введите имя сервера (например, example.com или IP-адрес): " server_name
    
    # Проверка ввода
    if [[ -z "$server_name" ]]; then
        echo "Имя сервера не может быть пустым!" >&2
        return 1
    fi

    # Запрос об отправке отчетов
    local report_stats
    while true; do
        read -p "Отправлять отчеты об ошибках разработчикам? (yes/no) [no]: " report_stats
        report_stats=${report_stats:-no}
        case "$report_stats" in
            [Yy]|[Yy][Ee][Ss]) report_stats="yes"; break ;;
            [Nn]|[Nn][Oo]) report_stats="no"; break ;;
            *) echo "Пожалуйста, введите yes или no" ;;
        esac
    done

    # 3. Генерация конфигурации
    echo "3. Генерация конфигурации..."
    sudo bash -c "cat > /etc/matrix-synapse/conf.d/server.yaml << EOF
server_name: $server_name
report_stats: $report_stats
EOF"

    # 4. Перезапуск службы
    echo "4. Перезапуск Synapse..."
    if ! sudo systemctl restart matrix-synapse; then
        echo "Ошибка при перезапуске Synapse" >&2
        return 1
    fi

    # 5. Проверка статуса
    echo "5. Проверка статуса сервиса..."
    sudo systemctl status matrix-synapse --no-pager

    echo "=== ${step_name} завершена успешно ==="
    return 0
}

main() {
    echo "=== Начало выполнения скрипта ==="
    
    # Выполняем Шаг 1: Установка зависимостей
    echo "Запуск Шага 1: Установка зависимостей..."
    if ! install_dependencies_step_I; then
        echo "Ошибка на Шаге 1: Установка зависимостей не удалась" >&2
        exit 1
    fi
    echo "Шаг 1 успешно завершен"
    
    # Выполняем Шаг 2: Установка Synapse
    echo "Запуск Шага 2: Установка Synapse..."
    if ! install_synapse_step_II; then
        echo "Ошибка на Шаге 2: Установка Synapse не удалась" >&2
        exit 1
    fi
    echo "Шаг 2 успешно завершен"
    
    # Завершение скрипта
    echo "=== Все шаги успешно выполнены ==="
    echo "Сервер Matrix Synapse установлен и настроен"
    echo "Дополнительные настройки можно выполнить в файле конфигурации:"
    echo "/etc/matrix-synapse/conf.d/server.yaml"
    exit 0
}

main "$@"