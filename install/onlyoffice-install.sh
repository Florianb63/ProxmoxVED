#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  nginx \
  rabbitmq-server \
  ca-certificates \
  software-properties-common
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql

msg_info "Setup Database"
DB_NAME=onlyoffice
DB_USER=onlyoffice_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "OnlyOffice-Credentials"
  echo "OnlyOffice Database User: $DB_USER"
  echo "OnlyOffice Database Password: $DB_PASS"
  echo "OnlyOffice Database Name: $DB_NAME"
} >>~/onlyoffice.creds
msg_ok "Set up Database"

msg_info "Adding ONLYOFFICE GPG Key"
GPG_TMP="/tmp/onlyoffice.gpg"
KEY_URL="https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE"

TMP_KEY_CONTENT=$(mktemp)
if curl -fsSL "$KEY_URL" -o "$TMP_KEY_CONTENT" && grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$TMP_KEY_CONTENT"; then
  gpg --no-default-keyring --keyring "gnupg-ring:$GPG_TMP" --import "$TMP_KEY_CONTENT" >/dev/null
  chmod 644 "$GPG_TMP"
  chown root:root "$GPG_TMP"
  mv "$GPG_TMP" /usr/share/keyrings/onlyoffice.gpg
  msg_ok "GPG Key Added"
else
  msg_error "Failed to download or verify GPG key from $KEY_URL"
  [[ -f "$TMP_KEY_CONTENT" ]] && rm -f "$TMP_KEY_CONTENT"
  exit 1
fi
rm -f "$TMP_KEY_CONTENT"

msg_info "Configuring ONLYOFFICE Repository"
chmod 644 /tmp/onlyoffice.gpg
chown root:root /tmp/onlyoffice.gpg
mv /tmp/onlyoffice.gpg /usr/share/keyrings/onlyoffice.gpg
echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" >/etc/apt/sources.list.d/onlyoffice.list
$STD apt-get update
msg_ok "Repository Added"

msg_info "Preconfiguring ONLYOFFICE Debconf Settings"
echo onlyoffice-documentserver onlyoffice/db-host string localhost | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-user string $DB_USER | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-pwd password $DB_PASS | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-name string $DB_NAME | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/rabbitmq-host string localhost | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/rabbitmq-user string guest | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/rabbitmq-pwd password guest | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/jwt-enabled boolean true | debconf-set-selections
JWT_SECRET=$(openssl rand -hex 16)
echo onlyoffice-documentserver onlyoffice/jwt-secret password $JWT_SECRET | debconf-set-selections
msg_ok "Debconf Preconfiguration Done"

msg_info "Installing ttf-mscorefonts-installer"
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
$STD apt-get install -y ttf-mscorefonts-installer
msg_ok "Installed Microsoft Core Fonts"

msg_info "Installing ONLYOFFICE Docs"
$STD apt-get install -y onlyoffice-documentserver
msg_ok "ONLYOFFICE Docs Installed"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
