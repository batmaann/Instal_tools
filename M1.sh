#!/bin/bash

# Функция для обновления пакетов
update_packages() {
    echo "Обновление списка пакетов..."
    sudo apt update
    echo "Обновление установленных пакетов..."
    sudo apt upgrade -y
    echo "Обновление дистрибутива..."
    sudo apt dist-upgrade -y
    echo "Удаление неиспользуемых пакетов..."
    sudo apt autoremove -y
    echo "Обновление пакетов завершено!"
}

# Функция для установки актуальной версии Git
install_git() {
    # Проверка, установлен ли Git
    if command -v git &> /dev/null; then
        echo "Git уже установлен. Пропускаем установку."
    else
        echo "Установка актуальной версии Git..."
        sudo apt install git -y
        echo "Установка Git завершена!"
    fi
}

set_bottom_panel() {
    # Убедитесь, что gsettings установлен
    if ! command -v gsettings &> /dev/null; then
        echo "gsettings не установлен. Установите его и попробуйте снова."
        return 1
    fi
    # Проверка наличия расширения dash-to-panel
    if ! gnome-extensions list | grep -q "dash-to-panel@jderose9.github.com"; then
        echo "Расширение 'dash-to-panel' не установлено. Установите его и попробуйте снова."
        return 1
    fi
    # Установка боковой панели внизу
    gsettings set org.gnome.shell.extensions.dash-to-panel panel-position 'bottom'
    echo "Боковая панель настроена внизу."
}
# Функция для установки актуальной версии Google Chrome
install_google_chrome() {
    echo "Загрузка последней версии Google Chrome..."

    # Загрузка .deb файла Google Chrome
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O google-chrome.deb

    # Установка Google Chrome
    echo "Установка Google Chrome..."
    sudo dpkg -i google-chrome.deb

    # Исправление зависимостей, если они есть
    sudo apt-get install -f

    # Удаление загруженного .deb файла
    rm google-chrome.deb

    echo "Установка Google Chrome завершена!"
}

# Основная функция
main() {
    update_packages
    install_git
    #set_bottom_panel
    install_google_chrome
}

# Вызов основной функции
main
