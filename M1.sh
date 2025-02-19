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


install_google_chrome() {
    # Проверяем, установлен ли Google Chrome
    if command -v google-chrome &> /dev/null; then
        echo "Google Chrome уже установлен. Пропускаем установку."
        return
    fi

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

install_zsh() {
    # Проверяем, установлен ли Zsh
    if command -v zsh &> /dev/null; then
        echo "Zsh уже установлен. Пропускаем установку."
        return
    fi

    # Обновляем список пакетов
    sudo apt update

    # Устанавливаем Zsh
    sudo apt install -y zsh

    # Устанавливаем Zsh по умолчанию
    chsh -s $(which zsh)

    # Выводим сообщение об успешной установке
    echo "Zsh установлен и установлен по умолчанию. Пожалуйста, перезагрузите терминал или выполните 'zsh' для входа в Zsh."
}

# Основная функция
main() {
    update_packages
    install_git
    #set_bottom_panel
    install_google_chrome
    install_zsh
}

# Вызов основной функции
main
