# Instal_tools

Инструмент для автоматической установки необходимого ПО на виртуальные машины и не только.

## Скрипты

- `M1.sh` - интерактивная установка программ для Debian/Ubuntu.
- `M2.sh` - установка и настройка Matrix Synapse.
- `M3.sh` - настройка SSH-сервера.

`M1.sh` умеет устанавливать Git, Google Chrome, Zsh и Oh My Zsh, Outline
Client, Postman, htop, Visual Studio Code, PyCharm Community и Docker Desktop.

## Установка и запуск

1. Клонируйте репозиторий:

```bash
git clone https://github.com/batmaann/Instal_tools.git
cd Instal_tools
```

2. Запустите нужный скрипт:

```bash
./M1.sh
```

`M1.sh` нужно запускать от обычного пользователя. Скрипт сам вызывает `sudo`
только для системных операций.

Для запуска отдельной установки без интерактивного меню:

```bash
./M1.sh --docker-desktop
./M1.sh --help
```

## Docker Desktop

Установка Docker Desktop поддерживается на 64-битных Ubuntu и Debian с
`systemd`, минимум 4 ГБ RAM, графической средой и доступным KVM. Скрипт:

- проверяет архитектуру и наличие `/dev/kvm`;
- подключает официальный APT-репозиторий Docker;
- скачивает актуальный пакет Docker Desktop с официального сайта;
- добавляет текущего пользователя в группу `kvm`.

После установки нужно выйти из пользовательской сессии и войти снова. При
первом запуске Docker Desktop потребуется принять лицензионные условия.

Официальная инструкция: https://docs.docker.com/desktop/setup/install/linux/
