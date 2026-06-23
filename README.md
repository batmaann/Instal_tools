# Instal_tools

Инструмент для автоматической установки необходимого ПО на виртуальные машины и не только.

## Скрипты

- `M1.sh` - интерактивная установка программ для Debian/Ubuntu.
- `M2.sh` - установка и настройка Matrix Synapse.
- `M3.sh` - настройка SSH-сервера.

`M1.sh` умеет устанавливать Git, Google Chrome, Tor Browser, Zsh и Oh My Zsh, Outline
Client, Postman, htop, Visual Studio Code, PyCharm Community, Docker Desktop и WebStorm.

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
./M1.sh --tor-browser
./M1.sh --docker-desktop
./M1.sh --webstorm
./M1.sh --help
```

## Tor Browser

Установка Tor Browser выполняется через пакет `torbrowser-launcher` из
репозиториев Debian/Ubuntu:

```bash
./M1.sh --tor-browser
```

При первом запуске лаунчер самостоятельно загрузит и проверит Tor Browser.
Запуск после установки: `torbrowser-launcher`.

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

## WebStorm

Отдельной Community-редакции WebStorm не существует. Полная версия WebStorm
официально бесплатна для некоммерческого использования; соответствующий тип
лицензии выбирается при первом запуске.

Обычная установка:

```bash
./M1.sh --webstorm
```

Скрипт сначала использует официальный Snap Store. Если он недоступен, скрипт
получает последнюю стабильную версию через API JetBrains, скачивает архив с
основного или резервного официального CDN и проверяет SHA-256. Перед установкой
проверяются архитектура, графическая среда, 8 ГБ RAM и 10 ГБ свободного места.

Для сетей с ограниченным доступом поддерживаются стандартные переменные
`HTTPS_PROXY` и `HTTP_PROXY`. Чтобы сразу использовать архив без Snap:

```bash
WEBSTORM_INSTALL_METHOD=archive ./M1.sh --webstorm
```

Если API релизов недоступен, можно указать известную версию:

```bash
WEBSTORM_INSTALL_METHOD=archive WEBSTORM_VERSION=2026.1.3 ./M1.sh --webstorm
```

Можно указать доступное HTTPS-зеркало вручную. Для безопасности обязательна
контрольная сумма или ссылка на нее:

```bash
WEBSTORM_DOWNLOAD_URL=https://mirror.example/WebStorm.tar.gz \
WEBSTORM_SHA256=<sha256> \
./M1.sh --webstorm
```

Официальные сведения о лицензии:
https://www.jetbrains.com/help/webstorm/register.html
