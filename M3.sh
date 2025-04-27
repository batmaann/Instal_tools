#!/bin/bash

# Проверка на root
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен запускаться с правами root. Используйте sudo!" >&2
  exit 1
fi

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция проверки успешности выполнения
check_success() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Успешно!${NC}"
  else
    echo -e "${RED}Ошибка!${NC}"
    exit 1
  fi
}


# Проверка и установка curl
check_curl() {
  if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Установка curl...${NC}"
    apt install -y curl
    check_success
  fi
}

echo -e "${YELLOW}=== Начало проверки и настройки SSH-сервера ==="

# 1. Проверка и установка curl
check_curl

# 2. Проверка установки SSH-сервера
if ! dpkg -l | grep -q openssh-server; then
  echo -e "${YELLOW}Установка OpenSSH-server...${NC}"
  apt update -q
  apt install -y openssh-server
  check_success
else
  echo -e "${YELLOW}OpenSSH-server уже установлен.${NC}"
fi

# 3. Проверка статуса SSH
if ! systemctl is-active --quiet ssh; then
  echo -e "${YELLOW}Запуск SSH-сервера...${NC}"
  systemctl start ssh
  check_success
fi

# 4. Включение автозапуска SSH
if ! systemctl is-enabled --quiet ssh; then
  echo -e "${YELLOW}Включение автозапуска SSH...${NC}"
  systemctl enable ssh
  check_success
fi

# 5. Проверка и настройка UFW
if ! dpkg -l | grep -q ufw; then
  echo -e "${YELLOW}Установка UFW...${NC}"
  apt install -y ufw
  check_success
fi

# Получаем текущий SSH-порт из конфига
CURRENT_SSH_PORT=$(grep -oP '^Port\s+\K\d+' /etc/ssh/sshd_config || echo "22")

# Если порт не стандартный (не 22), используем его, иначе генерируем новый
if [ "$CURRENT_SSH_PORT" != "22" ]; then
  NEW_SSH_PORT=$CURRENT_SSH_PORT
  echo -e "${YELLOW}Обнаружен нестандартный SSH-порт: $NEW_SSH_PORT${NC}"
else
  # Генерация случайного порта
  NEW_SSH_PORT=$(shuf -i 1024-49151 -n 1)
  echo -e "${YELLOW}Настройка SSH-порта...${NC}"
  
  # Резервное копирование конфига
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
  
  # Настройка конфигурации SSH
  sed -i -e "s/^#Port 22/Port $NEW_SSH_PORT/" \
         -e 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' \
         -e 's/^#PasswordAuthentication yes/PasswordAuthentication no/' \
         -e 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
         /etc/ssh/sshd_config
  
  # Добавляем строку для ограничения попыток входа
  grep -q "^MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
  
  check_success
  
  # Перезапуск SSH
  echo -e "${YELLOW}Перезапуск SSH-сервера...${NC}"
  systemctl restart ssh
  check_success
fi

# Настройка UFW
if ! ufw status | grep -q "$NEW_SSH_PORT/tcp"; then
  echo -e "${YELLOW}Настройка брандмауэра для порта $NEW_SSH_PORT...${NC}"
  ufw allow $NEW_SSH_PORT/tcp
  echo "y" | ufw enable
  check_success
fi

# 6. Генерация SSH-ключей для текущего пользователя (если их нет)
echo -e "${YELLOW}Проверка SSH-ключей...${NC}"
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -q -N ""
  check_success
  echo -e "${YELLOW}Публичный ключ (добавьте его на другие машины):${NC}"
  cat ~/.ssh/id_rsa.pub
else
  echo -e "${YELLOW}SSH-ключи уже существуют.${NC}"
fi

# 7. Получение сетевой информации
LOCAL_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me)

echo -e "\n${GREEN}=== Настройка завершена успешно! ==="
echo -e "${YELLOW}Важные данные для подключения:${NC}"
echo -e "Локальный IP: ${GREEN}$LOCAL_IP${NC}"
echo -e "Публичный IP: ${GREEN}$PUBLIC_IP${NC}"
echo -e "Порт SSH: ${GREEN}$NEW_SSH_PORT${NC}"
echo -e "\n${YELLOW}Для подключения используйте:${NC}"
echo -e "ssh -p $NEW_SSH_PORT $(whoami)@$PUBLIC_IP"
echo -e "\n${RED}ВАЖНО:${NC}"
echo -e "1. Настройте проброс порта $NEW_SSH_PORT на вашем роутере для IP $LOCAL_IP"
echo -e "2. Сохраните эту информацию в безопасном месте!"
echo -e "3. Для максимальной безопасности рекомендуется:"
echo -e "   - Установить fail2ban"
echo -e "   - Настроить двухфакторную аутентификацию"
echo -e "   - Регулярно обновлять систему${NC}"