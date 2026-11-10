#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster) | Co-Author: CrazyWolf13, MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://changedetection.io/ | Github: https://github.com/dgtlmoon/changedetection.io

APP="Change Detection"
var_tags="${var_tags:-monitoring;crawler}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/changedetection.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies libjpeg-dev poppler-utils file locales xvfb xauth curl

  wait_http() {
    local url="$1" timeout="${2:-30}" code
    local deadline=$((SECONDS + timeout))
    while ((SECONDS < deadline)); do
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)" || code="000"
      [[ "$code" =~ ^([23][0-9][0-9]|401|403)$ ]] && return 0
      sleep 2
    done
    return 1
  }

  msg_info "Generating Locales"
  for l in cs_CZ de_DE en_GB en_US es_ES fr_FR id_ID it_IT ja_JP ko_KR \
    pl_PL pt_BR ru_RU tr_TR uk_UA zh_CN zh_TW; do
    sed -i "s/^# *${l}.UTF-8 UTF-8/${l}.UTF-8 UTF-8/" /etc/locale.gen
  done
  $STD locale-gen
  if ! grep -q "^LC_ALL=" /opt/changedetection/.env 2>/dev/null; then
    echo "LC_ALL=en_US.UTF-8" >>/opt/changedetection/.env
  fi
  msg_ok "Generated Locales"

  NODE_VERSION="24" setup_nodejs

  VENV_PATH="/opt/changedetection/.venv"
  CHANGEDETECTION_BIN="${VENV_PATH}/bin/changedetection.io"

  PYTHON_VERSION="3.13" setup_uv

  if [[ ! -d "$VENV_PATH" || ! -x "$CHANGEDETECTION_BIN" ]]; then
    msg_info "Migrating to uv/venv"
    rm -rf "$VENV_PATH"
    $STD uv venv --clear "$VENV_PATH"
    $STD "$VENV_PATH/bin/python" -m ensurepip --upgrade
    $STD "$VENV_PATH/bin/python" -m pip install --upgrade pip
    $STD "$VENV_PATH/bin/python" -m pip install changedetection.io playwright
    msg_ok "Migrated to uv/venv"
  else
    msg_info "Updating ${APP}"
    $STD "$VENV_PATH/bin/python" -m pip install --upgrade changedetection.io playwright
    msg_ok "Updated ${APP}"
  fi

  SERVICE_FILE="/etc/systemd/system/changedetection.service"
  if ! grep -q "${VENV_PATH}/bin/changedetection.io" "$SERVICE_FILE"; then
    msg_info "Updating systemd service"
    sed -i "s|^ExecStart=.*|ExecStart=${VENV_PATH}/bin/changedetection.io -d /opt/changedetection -p 5000|" "$SERVICE_FILE"
    $STD systemctl daemon-reload
    msg_ok "Updated systemd service"
  fi

  if [[ -f /etc/systemd/system/browserless.service ]]; then
    msg_info "Updating Browserless (Patience)"
    systemctl stop browserless
    if [[ ! -f /opt/browserless/node_modules/@browserless.io/browserless/package.json ]]; then
      rm -rf /opt/browserless
    fi
    mkdir -p /opt/browserless
    $STD npm install --prefix /opt/browserless @browserless.io/browserless@latest
    $STD /opt/browserless/node_modules/playwright-core/cli.js install --with-deps --force chrome
    rm -rf \
      /opt/browserless/node_modules/@browserless.io/browserless/build/routes/chromium \
      /opt/browserless/node_modules/@browserless.io/browserless/build/routes/firefox \
      /opt/browserless/node_modules/@browserless.io/browserless/build/routes/webkit \
      /opt/browserless/node_modules/@browserless.io/browserless/build/routes/edge

    local unit="/etc/systemd/system/browserless.service"
    local unit_changed=0
    if ! grep -Fqx 'WorkingDirectory=/opt/browserless' "$unit"; then
      sed -i "s|^WorkingDirectory=.*|WorkingDirectory=/opt/browserless|" "$unit"
      unit_changed=1
    fi
    if ! grep -q 'node_modules/@browserless.io/browserless/build/index.js' "$unit"; then
      sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/xvfb-run -a -s \"-screen 0 1920x1080x24 -dpi 96 -nolisten tcp\" /usr/bin/node node_modules/@browserless.io/browserless/build/index.js|" "$unit"
      unit_changed=1
    fi
    if ! grep -q '^Environment=NODE_ENV=production' "$unit"; then
      sed -i '/^\[Service\]/a Environment=NODE_ENV=production' "$unit"
      unit_changed=1
    fi
    if [[ "$unit_changed" -eq 1 ]]; then
      $STD systemctl daemon-reload
    fi

    safe_service_restart browserless
    if ! wait_http "http://localhost:3000/json/version" 30; then
      msg_error "Browserless is not responding on port 3000"
      systemctl status browserless --no-pager -l | head -20 || true
      exit 1
    fi
    msg_ok "Updated Browserless"
  else
    msg_error "No Browserless Installation Found!"
  fi

  safe_service_restart changedetection
  if ! wait_http "http://127.0.0.1:5000/" 30; then
    msg_error "changedetection is not responding on port 5000"
    systemctl status changedetection --no-pager -l | head -20 || true
    exit 1
  fi
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:5000${CL}"
