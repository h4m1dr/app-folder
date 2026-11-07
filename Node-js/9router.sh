#!/usr/bin/env bash

APP_NAME="9router"
ROUTER_PORT="8553"
SERVICE_FILE="/etc/systemd/system/9router.service"

app_is_installed() {
    if command -v 9router &> /dev/null || [ -f "$SERVICE_FILE" ]; then
        return 0
    fi
    return 1
}

resolve_runtime() {
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        echo -e "\033[0;31m[!] Node.js runtime not found.\033[0m"
        return 1
    fi
    CURRENT_NODE_BIN=$(which node)
    return 0
}

app_install() {
    if ! resolve_runtime; then
        echo -e "\033[0;31m[!] Please install Node.js first.\033[0m"
        return
    fi

    echo -e "\033[0;34m[*] Installing 9router globally via npm...\033[0m"
    npm install -g 9router

    local ROUTER_BIN
    ROUTER_BIN=$(which 9router 2>/dev/null)
    if [ -z "$ROUTER_BIN" ]; then
        echo -e "\033[0;31m[!] 9router binary not found in PATH.\033[0m"
        return
    fi

    echo -e "\033[0;34m[*] Setting up systemd unit on port $ROUTER_PORT...\033[0m"
    cat <<SERVICE_EOF > "$SERVICE_FILE"
[Unit]
Description=9router Gateway Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$ROUTER_BIN --port $ROUTER_PORT
Restart=always
RestartSec=3
Environment=PORT=$ROUTER_PORT
Environment=HOST=127.0.0.1
Environment=PATH=$(dirname "$CURRENT_NODE_BIN"):$PATH

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    systemctl enable --now 9router
    sleep 2
    if systemctl is-active --quiet 9router; then
        echo -e "\033[0;32m[+] 9router successfully running on port $ROUTER_PORT\033[0m"
    else
        echo -e "\033[0;31m[!] Failed to start service. Check: journalctl -u 9router -n 20\033[0m"
    fi
}

app_update() {
    if ! resolve_runtime; then
        return
    fi
    echo -e "\033[0;34m[*] Updating 9router to latest version...\033[0m"
    npm install -g 9router@latest
    systemctl restart 9router
    echo -e "\033[0;32m[+] 9router updated and service restarted.\033[0m"
}

app_start() {
    systemctl start 9router
    echo -e "\033[0;32m[+] 9router service started.\033[0m"
}

app_stop() {
    systemctl stop 9router
    echo -e "\033[1;33m[*] 9router service stopped.\033[0m"
}

app_restart() {
    systemctl restart 9router
    echo -e "\033[0;32m[+] 9router service restarted.\033[0m"
}

app_delete() {
    echo -e "\033[0;31m[!] Removing 9router service and binaries...\033[0m"
    systemctl stop 9router 2>/dev/null
    systemctl disable 9router 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    npm uninstall -g 9router 2>/dev/null
    rm -rf /root/.9router
    echo -e "\033[0;32m[+] 9router removed completely.\033[0m"
}

app_menu() {
    while true; do
        clear
        echo "======================================"
        echo "           9Router Menu               "
        echo "======================================"
        echo " 1) Install"
        echo " 2) Update"
        echo " 3) Start"
        echo " 4) Stop"
        echo " 5) Restart"
        echo " 6) Delete"
        echo " b) Back"
        echo "--------------------------------------"
        read -p " Select option: " choice
        case $choice in
            1) app_install; read -p "Press Enter to continue..." ;;
            2) app_update; read -p "Press Enter to continue..." ;;
            3) app_start; read -p "Press Enter to continue..." ;;
            4) app_stop; read -p "Press Enter to continue..." ;;
            5) app_restart; read -p "Press Enter to continue..." ;;
            6) app_delete; read -p "Press Enter to continue..." ;;
            b|B) break ;;
            *) sleep 1 ;;
        esac
    done
}
