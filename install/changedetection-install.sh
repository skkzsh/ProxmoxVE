#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster) | Co-Author: CrazyWolf13, MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://changedetection.io/ | Github: https://github.com/dgtlmoon/changedetection.io

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt install -y \
  libjpeg-dev \
  libatk-bridge2.0-0 \
  libasound2 \
  libatk1.0-0 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libexpat1 \
  libgbm-dev \
  libgbm1 \
  libgdk-pixbuf-2.0-0 \
  libglib2.0-0 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  qpdf \
  xdg-utils \
  xvfb \
  xauth \
  ca-certificates \
  locales \
  poppler-utils \
  file
msg_ok "Installed Dependencies"

msg_info "Generating Locales"
for l in cs_CZ de_DE en_GB en_US es_ES fr_FR id_ID it_IT ja_JP ko_KR \
  pl_PL pt_BR ru_RU tr_TR uk_UA zh_CN zh_TW; do
  sed -i "s/^# *${l}.UTF-8 UTF-8/${l}.UTF-8 UTF-8/" /etc/locale.gen
done
$STD locale-gen
msg_ok "Generated Locales"

PYTHON_VERSION="3.13" setup_uv

NODE_VERSION="24" setup_nodejs

msg_info "Installing Change Detection"
mkdir -p /opt/changedetection
$STD uv venv --clear /opt/changedetection/.venv
$STD /opt/changedetection/.venv/bin/python -m ensurepip --upgrade
$STD /opt/changedetection/.venv/bin/python -m pip install --upgrade pip
$STD /opt/changedetection/.venv/bin/python -m pip install changedetection.io
cat <<EOF >/opt/changedetection/.env
PLAYWRIGHT_DRIVER_URL=ws://localhost:3000/chrome?launch=eyJkZWZhdWx0Vmlld3BvcnQiOnsiaGVpZ2h0Ijo3MjAsIndpZHRoIjoxMjgwfSwiaGVhZGxlc3MiOmZhbHNlLCJzdGVhbHRoIjp0cnVlfQ==&blockAds=true
LC_ALL=en_US.UTF-8
EOF
msg_ok "Installed Change Detection"

msg_info "Installing Browserless & Playwright"
$STD /opt/changedetection/.venv/bin/python -m pip install playwright
mkdir -p /opt/browserless
$STD npm install --prefix /opt/browserless @browserless.io/browserless@latest
$STD /opt/browserless/node_modules/playwright-core/cli.js install --with-deps --force chrome &>/dev/null
# Chrome-only: routes for browsers we do not install must be removed or the server refuses to start.
rm -rf \
  /opt/browserless/node_modules/@browserless.io/browserless/build/routes/chromium \
  /opt/browserless/node_modules/@browserless.io/browserless/build/routes/firefox \
  /opt/browserless/node_modules/@browserless.io/browserless/build/routes/webkit \
  /opt/browserless/node_modules/@browserless.io/browserless/build/routes/edge
msg_ok "Installed Browserless & Playwright"

msg_info "Installing Font Packages"
$STD apt install -y \
  fontconfig \
  libfontconfig1 \
  fonts-freefont-ttf \
  fonts-gfs-neohellenic \
  fonts-indic fonts-ipafont-gothic \
  fonts-kacst-one fonts-liberation \
  fonts-noto-cjk \
  fonts-noto-color-emoji \
  fonts-roboto \
  fonts-thai-tlwg \
  fonts-wqy-zenhei
msg_ok "Installed Font Packages"

msg_info "Installing X11 Packages"
$STD apt install -y \
  libx11-6 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxi6 \
  libxrandr2 \
  libxrender1 \
  libxss1 \
  libxtst6
msg_ok "Installed X11 Packages"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/changedetection.service
[Unit]
Description=Change Detection
After=network-online.target
After=network.target browserless.service
Wants=browserless.service

[Service]
Type=simple
EnvironmentFile=/opt/changedetection/.env
WorkingDirectory=/opt/changedetection
ExecStart=/opt/changedetection/.venv/bin/changedetection.io -d /opt/changedetection -p 5000

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/browserless.service
[Unit]
Description=browserless service
After=network.target

[Service]
Environment=CONNECTION_TIMEOUT=60000
Environment=NODE_ENV=production
WorkingDirectory=/opt/browserless
ExecStart=/usr/bin/xvfb-run -a -s "-screen 0 1920x1080x24 -dpi 96 -nolisten tcp" /usr/bin/node node_modules/@browserless.io/browserless/build/index.js
SyslogIdentifier=browserless

[Install]
WantedBy=default.target
EOF
systemctl enable -q --now browserless
systemctl enable -q --now changedetection
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
