[file name]: M2.sh
[file content begin]
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

check_step_V() {
    [ -f "${STATUS_DIR}/step5_completed" ] ||
    [ -f /etc/nginx/sites-enabled/matrix ]
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

    echo -e "\n${GREEN}=== Установка зависимостей ===${NC}"
    
    # Фактические команды для шага 1
    sudo apt-get update
    sudo apt-get install -y apt-transport-https wget
    wget -qO - https://packages.matrix.org/debian/matrix.org-2023.gpg | sudo gpg --dearmor -o /usr/share/keyrings/matrix-org-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ default main" | sudo tee /etc/apt/sources.list.d/matrix-org.list
    
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

    echo -e "\n${GREEN}=== Установка Synapse ===${NC}"
    
    sudo apt-get update
    sudo apt-get install -y matrix-synapse-py3
    
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

    echo -e "\n${GREEN}=== Настройка Synapse ===${NC}"
    
    # Генерация конфига если отсутствует
    if [ ! -f /etc/matrix-synapse/homeserver.yaml ]; then
        sudo python3 -m synapse.app.homeserver \
            --server-name your-domain.com \
            --config-path /etc/matrix-synapse/homeserver.yaml \
            --generate-config \
            --report-stats=no
    fi
    
    sudo touch "${STATUS_DIR}/step3_completed"
    echo -e "${GREEN}=== Настройка Synapse завершена успешно ===${NC}"
    return 0
}

# Шаг 4: Настройка брандмауэра
configure_firewall_step_IV() {
    local -r step_name="Настройка брандмауэра"
    echo -e "\n${GREEN}=== ${step_name} ===${NC}"

    # Автоматическая установка UFW
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}Установка UFW...${NC}"
        sudo apt-get install -y ufw
    fi

    set +e
    trap 'echo -e "${RED}Ошибка в шаге 4${NC}"; sudo ufw --force reset; return 1' ERR

    echo -e "${YELLOW}1. Настройка правил...${NC}"
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 8008/tcp comment "HTTP-API Synapse"
    sudo ufw allow 443/tcp comment "HTTPS"
    
    echo -e "${YELLOW}2. Активация брандмауэра...${NC}"
    echo "y" | sudo ufw enable
    
    echo -e "${YELLOW}3. Итоговые правила:${NC}"
    sudo ufw status numbered
    
    sudo touch "${STATUS_DIR}/step4_completed"
    set -e
    trap - ERR
    
    echo -e "${GREEN}=== ${step_name} завершена успешно ===${NC}"
    return 0
}

# Шаг 5: Настройка Nginx
configure_nginx_step_V() {
    local -r step_name="Настройка обратного прокси (Nginx)"
    if ! $FORCE_MODE && check_step_V; then
        echo -e "${GREEN}Шаг 5 уже выполнен, пропускаем...${NC}"
        return 0
    fi

    echo -e "\n${GREEN}=== ${step_name} ===${NC}"

    echo -e "${YELLOW}1. Установка Nginx...${NC}"
    sudo apt-get install -y nginx

    echo -e "${YELLOW}2. Создание конфигурации...${NC}"
    sudo tee /etc/nginx/sites-available/matrix >/dev/null <<EOL
server {
    listen 80;
    server_name your-domain.com;

    location /_matrix {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;

        proxy_read_timeout 600;
        client_max_body_size 50M;
    }
}
EOL

    echo -e "${YELLOW}3. Активация конфигурации...${NC}"
    sudo ln -sf /etc/nginx/sites-available/matrix /etc/nginx/sites-enabled/
    
    echo -e "${YELLOW}4. Проверка конфигурации...${NC}"
    sudo nginx -t || {
        echo -e "${RED}Ошибка в конфигурации Nginx!${NC}"
        sudo rm -f /etc/nginx/sites-enabled/matrix
        exit 1
    }
    
    echo -e "${YELLOW}5. Перезапуск Nginx...${NC}"
    sudo systemctl restart nginx

    sudo touch "${STATUS_DIR}/step5_completed"
    echo -e "${GREEN}=== ${step_name} завершена успешно ===${NC}"
    return 0
}

check_step_VI() {
    [ -f "${STATUS_DIR}/step6_completed" ] ||
    [ -n "$(sudo -u matrix-synapse psql -c 'SELECT * FROM users;' 2>/dev/null)" ]
}

# Шаг 6: Регистрация первого пользователя
register_admin_user_step_VI() {
    local -r step_name="Регистрация первого пользователя (администратора)"
    if ! $FORCE_MODE && check_step_VI; then
        echo -e "${GREEN}Шаг 6 уже выполнен, пропускаем...${NC}"
        return 0
    fi

    echo -e "\n${GREEN}=== ${step_name} ===${NC}"

    # Проверка и обновление конфигурации Synapse
    echo -e "${YELLOW}Проверка конфигурации сервера...${NC}"
    
    # Создаем резервную копию конфига
    sudo cp /etc/matrix-synapse/homeserver.yaml /etc/matrix-synapse/homeserver.yaml.bak

    # Активируем регистрацию через CLI (только если отключена)
    if ! grep -q "enable_registration: true" /etc/matrix-synapse/homeserver.yaml; then
        echo -e "${YELLOW}Активация регистрации пользователей...${NC}"
        sudo sed -i '/^#enable_registration:/s/^#//; s/enable_registration: false/enable_registration: true/' /etc/matrix-synapse/homeserver.yaml
    fi

    # Генерируем секретный ключ при необходимости
    if ! grep -q "registration_shared_secret:" /etc/matrix-synapse/homeserver.yaml; then
        echo -e "${YELLOW}Генерация секретного ключа регистрации...${NC}"
        SECRET=$(openssl rand -hex 32)
        echo "registration_shared_secret: \"$SECRET\"" | sudo tee -a /etc/matrix-synapse/homeserver.yaml
        
        # Проверка синтаксиса перед перезапуском
        if ! python3 -m synapse.app.homeserver --config-path /etc/matrix-synapse/homeserver.yaml --check-config; then
            echo -e "${RED}Ошибка в конфигурации! Восстанавливаем backup...${NC}"
            sudo mv /etc/matrix-synapse/homeserver.yaml.bak /etc/matrix-synapse/homeserver.yaml
            exit 1
        fi
        
        echo -e "${YELLOW}Перезапуск Synapse...${NC}"
        sudo systemctl restart matrix-synapse || {
            echo -e "${RED}Ошибка перезапуска Synapse!${NC}"
            echo -e "${YELLOW}Попробуйте выполнить вручную:${NC}"
            echo "sudo systemctl status matrix-synapse"
            echo "journalctl -u matrix-synapse -b"
            exit 1
        }
        sleep 10  # Увеличиваем время ожидания
    fi

    # Установка expect для автоматизации ввода
    if ! command -v expect &> /dev/null; then
        echo -e "${YELLOW}Установка пакета expect...${NC}"
        sudo apt-get install -y expect
    fi

    # Запрос данных пользователя
    echo -e "${YELLOW}Введите данные для создания администратора Matrix:${NC}"
    
    while true; do
        read -rp "Логин (только буквы и цифры): " username
        [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]] && break
        echo -e "${RED}Логин может содержать только буквы, цифры, дефисы и подчеркивания!${NC}"
    done

    while true; do
        read -rsp "Пароль (минимум 8 символов): " password
        echo
        [[ ${#password} -ge 8 ]] && break
        echo -e "${RED}Пароль должен быть не менее 8 символов!${NC}"
    done

    # Автоматическая регистрация через expect
    echo -e "${YELLOW}Регистрируем пользователя...${NC}"
    if ! /usr/bin/expect <<EOD
set timeout 30
spawn register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml http://localhost:8008
expect {
    "New user localpart*" { 
        send "$username\r"
        exp_continue 
    }
    "Password*" { 
        send "$password\r"
        exp_continue 
    }
    "Confirm password*" { 
        send "$password\r"
        exp_continue 
    }
    "Make admin*" { 
        send "yes\r"
        exp_continue 
    }
    timeout {
        puts "\n${RED}Таймаут ожидания ответа сервера${NC}"
        exit 1
    }
    eof
}
EOD
    then
        echo -e "${RED}Ошибка при регистрации пользователя!${NC}"
        echo -e "${YELLOW}Возможные причины:${NC}"
        echo "1. Сервер Synapse не отвечает (проверьте: sudo systemctl status matrix-synapse)"
        echo "2. Проблемы с конфигурацией (проверьте: journalctl -u matrix-synapse -b --no-pager | tail -n 20)"
        echo "3. Неверные параметры пользователя"
        exit 1
    fi

    # Фиксация выполнения
    sudo touch "${STATUS_DIR}/step6_completed"
    echo -e "${GREEN}=== Пользователь '@${username}:$(grep "server_name" /etc/matrix-synapse/homeserver.yaml | awk '{print $2}') успешно создан ===${NC}"
    
    # Дополнительные проверки
    echo -e "${YELLOW}Проверка регистрации:${NC}"
    if sudo -u postgres psql -d synapse -c "SELECT name FROM users WHERE name='@${username}:$(grep "server_name" /etc/matrix-synapse/homeserver.yaml | awk '{print $2}')" | grep -q "$username"; then
        echo -e "${GREEN}Пользователь найден в базе данных!${NC}"
    else
        echo -e "${YELLOW}Предупреждение: пользователь не найден в базе, но процесс регистрации завершился успешно${NC}"
    fi
    
    return 0
}


main() {
    init_system
    echo -e "\n${GREEN}=== Начало установки Matrix Synapse ===${NC}"
    
    # ... [существующая проверка] ...

    install_dependencies_step_I
    install_synapse_step_II
    configure_synapse_step_III
    configure_firewall_step_IV
    configure_nginx_step_V
    register_admin_user_step_VI  

    echo -e "\n${GREEN}=== Установка завершена успешно! ===${NC}"
    echo -e "Сервер Matrix Synapse готов к работе"
    echo -e "Основные файлы конфигурации:"
    echo -e " - /etc/matrix-synapse/homeserver.yaml"
    echo -e " - /etc/nginx/sites-available/matrix"
    echo -e "\nДанные администратора:"
    echo -e " - Логин: @${username}:$(grep "server_name" /etc/matrix-synapse/homeserver.yaml | awk '{print $2}')"
    echo -e "\nДля дальнейшей настройки:"
    echo -e "1. Настройте SSL (рекомендуется certbot)"
    echo -e "2. Откройте порты 8448 для федерации (если нужно)"
    echo -e "3. Включите регистрацию новых пользователей в homeserver.yaml"
    
    exit 0
}

main "$@"
[file content end]