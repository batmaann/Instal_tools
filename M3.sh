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

# Функция для проверки успешности выполнения команды
check_success() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Успешно!${NC}"
  else
    echo -e "${RED}Ошибка!${NC}"
    exit 1
  fi
}

echo -e "${YELLOW}=== Начало настройки SSH-сервера ==="

# 1. Обновление пакетов
echo -e "${YELLOW}Обновление списка пакетов...${NC}"
apt update -q
check_success

# 2. Установка SSH-сервера
echo -e "${YELLOW}Установка OpenSSH-server...${NC}"
apt install -y openssh-server
check_success

# 3. Настройка SSH
echo -e "${YELLOW}Настройка SSH...${NC}"

# Резервное копирование конфига
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Изменение стандартного порта (случайный порт в диапазоне 1024-49151)
NEW_SSH_PORT=$(shuf -i 1024-49151 -n 1)

# Настройка конфигурации SSH
sed -i -e "s/#Port 22/Port $NEW_SSH_PORT/" \
       -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' \
       -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' \
       -e 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
       /etc/ssh/sshd_config

# Добавляем строку для ограничения попыток входа
echo "MaxAuthTries 3" >> /etc/ssh/sshd_config

check_success

# 4. Настройка UFW
echo -e "${YELLOW}Настройка брандмауэра...${NC}"
ufw allow $NEW_SSH_PORT/tcp
echo "y" | ufw enable
check_success

# 5. Генерация SSH-ключей для текущего пользователя (если их нет)
echo -e "${YELLOW}Генерация SSH-ключей...${NC}"
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -q -N ""
  check_success
  echo -e "${YELLOW}Публичный ключ (добавьте его на другие машины):${NC}"
  cat ~/.ssh/id_rsa.pub
else
  echo -e "${YELLOW}SSH-ключи уже существуют.${NC}"
fi

# 6. Перезапуск SSH
echo -e "${YELLOW}Перезапуск SSH-сервера...${NC}"
systemctl restart ssh
check_success

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