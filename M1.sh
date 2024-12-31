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
    echo "Установка актуальной версии Git..."
    sudo apt install git -y

    echo "Установка Git завершена!"
}

# Вызов функций
update_packages
install_git
