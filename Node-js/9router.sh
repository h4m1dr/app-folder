#!/usr/bin/env bash

APP_NAME="9router"
SERVICE_FILE="/etc/systemd/system/9router.service"

CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_YLW='\033[1;33m'
CLR_BLU='\033[0;34m'
CLR_ORG='\033[38;5;208m'
CLR_MUTED='\033[90m'
CLR_NC='\033[0m'

app_is_installed() {
    [ -f "$SERVICE_FILE" ] && return 0
    return 1
}

get_current_port() {
    if [ -f "$SERVICE_FILE" ]; then
        local p
        p=$(grep -oP '(?<=--port )\d+' "$SERVICE_FILE" 2>/dev/null || grep -oP '(?<=PORT=)\d+' "$SERVICE_FILE" 2>/dev/null | head -n1)
        [ -n "$p" ] && echo "$p" && return
    fi
    echo "8553"
}

get_app_version() {
    if command -v 9router &> /dev/null; then
        local ver
        ver=$(9router -v 2>/dev/null || 9router --version 2>/dev/null)
        [ -n "$ver" ] && echo "$ver" && return
        echo "Installed"
    else
        echo "Not Installed"
    fi
}

resolve_runtime() {
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        echo -e "${CLR_RED}[!] Node.js runtime not found.${CLR_NC}"
        return 1
    fi
    CURRENT_NODE_BIN=$(which node)
    return 0
}

# Function to build and write the systemd unit file
generate_systemd_unit() {
    local port="$1"
    local host="$2"
    local mem_max="$3"
    local mem_high="$4"
    local node_heap="$5"
    local cpu_quota="$6"

    local ROUTER_BIN
    ROUTER_BIN=$(which 9router 2>/dev/null)
    if [ -z "$ROUTER_BIN" ]; then
        echo -e "${CLR_RED}[!] 9router binary not found in PATH.${CLR_NC}"
        return 1
    fi

    local exec_cmd="$ROUTER_BIN --port $port"
    if [ -n "$node_heap" ]; then
        exec_cmd="$CURRENT_NODE_BIN --max-old-space-size=$node_heap $ROUTER_BIN --port $port"
    fi

    cat <<SERVICE_EOF > "$SERVICE_FILE"
[Unit]
Description=9router Gateway Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$exec_cmd
Restart=always
RestartSec=3
Environment=PORT=$port
Environment=HOST=$host
Environment=NODE_ENV=production
Environment=PATH=$(dirname "$CURRENT_NODE_BIN"):$PATH
SERVICE_EOF

    # Inject optional resource limits if provided
    [ -n "$mem_max" ] && echo "MemoryMax=$mem_max" >> "$SERVICE_FILE"
    [ -n "$mem_high" ] && echo "MemoryHigh=$mem_high" >> "$SERVICE_FILE"
    [ -n "$cpu_quota" ] && echo "CPUQuota=$cpu_quota" >> "$SERVICE_FILE"
    [ -n "$mem_max" ] && echo "TasksMax=100" >> "$SERVICE_FILE"

    cat <<SERVICE_EOF >> "$SERVICE_FILE"

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    return 0
}

app_configure_wizard() {
    echo ""
    echo -e "${CLR_BLU}=== Standard Configuration ===${CLR_NC}"
    
    # 1. Port setup
    local cur_p
    cur_p=$(get_current_port)
    echo -e " Enter listening Port ${CLR_MUTED}(Default: $cur_p)${CLR_NC}:"
    read -p " > " in_port
    local cfg_port="${in_port:-$cur_p}"

    # 2. Host setup
    echo -e " Enter listening Host IP ${CLR_MUTED}(Default: 127.0.0.1)${CLR_NC}:"
    read -p " > " in_host
    local cfg_host="${in_host:-127.0.0.1}"

    # 3. Advanced setup prompt
    echo ""
    echo -e "${CLR_BLU}=== Advanced Limits (Optional) ===${CLR_NC}"
    echo -e " Do you want to configure memory & CPU constraints? [y/N]:"
    read -p " > " in_adv

    local cfg_mem_max=""
    local cfg_mem_high=""
    local cfg_node_heap=""
    local cfg_cpu=""

    if [[ "$in_adv" =~ ^([yY]|[yY][eE][sS])$ ]]; then
        echo ""
        echo -e "${CLR_MUTED}[Type 'n' to skip/disable any specific limit]${CLR_NC}"

        # MemoryMax
        echo -e " Systemd Hard Memory Limit ${CLR_MUTED}(Default: 450M | 'n' to skip)${CLR_NC}:"
        read -p " > " in_mmax
        if [[ ! "$in_mmax" =~ ^[nN]$ ]]; then
            cfg_mem_max="${in_mmax:-450M}"
        fi

        # MemoryHigh
        echo -e " Systemd Throttle Memory Limit ${CLR_MUTED}(Default: 380M | 'n' to skip)${CLR_NC}:"
        read -p " > " in_mhigh
        if [[ ! "$in_mhigh" =~ ^[nN]$ ]]; then
            cfg_mem_high="${in_mhigh:-380M}"
        fi

        # Node Heap Limit
        echo -e " Node.js V8 Engine Heap Limit in MB ${CLR_MUTED}(Default: 384 | 'n' to skip)${CLR_NC}:"
        read -p " > " in_heap
        if [[ ! "$in_heap" =~ ^[nN]$ ]]; then
            cfg_node_heap="${in_heap:-384}"
        fi

        # CPU Quota
        echo -e " Maximum CPU Core Quota ${CLR_MUTED}(Default: 80% | 'n' to skip)${CLR_NC}:"
        read -p " > " in_cpu
        if [[ ! "$in_cpu" =~ ^[nN]$ ]]; then
            cfg_cpu="${in_cpu:-80%}"
        fi
    fi

    echo -e "${CLR_BLU}[*] Applying configuration and updating service...${CLR_NC}"
    if generate_systemd_unit "$cfg_port" "$cfg_host" "$cfg_mem_max" "$cfg_mem_high" "$cfg_node_heap" "$cfg_cpu"; then
        systemctl restart 9router
        sleep 1
        if systemctl is-active --quiet 9router; then
            echo -e "${CLR_GRN}[+] 9router successfully running with updated settings!${CLR_NC}"
        else
            echo -e "${CLR_RED}[!] Service failed to start. Check option 6 (Status & Logs).${CLR_NC}"
        fi
    fi
}

app_install() {
    if ! resolve_runtime; then
        echo -e "${CLR_RED}[!] Please install Node.js first.${CLR_NC}"
        return
    fi

    echo -e "${CLR_BLU}[*] Installing 9router globally via npm...${CLR_NC}"
    npm install -g 9router

    app_configure_wizard
    systemctl enable 9router 2>/dev/null
}

app_edit_config() {
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] 9router is not installed yet.${CLR_NC}"
        return
    fi
    if ! resolve_runtime; then
        return
    fi

    echo -e "${CLR_YLW}[*] Initiating 9router configuration wizard...${CLR_NC}"
    app_configure_wizard
}

app_update() {
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] 9router is not installed yet. Please install it first.${CLR_NC}"
        return
    fi
    if ! resolve_runtime; then
        return
    fi
    echo -e "${CLR_BLU}[*] Updating 9router to latest version...${CLR_NC}"
    npm install -g 9router@latest
    systemctl restart 9router
    echo -e "${CLR_GRN}[+] 9router updated and service restarted.${CLR_NC}"
}

app_status() {
    clear
    echo "======================================"
    echo "       9Router Status & Logs          "
    echo "======================================"
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] 9router service is not installed.${CLR_NC}"
        return
    fi

    echo -e "${CLR_BLU}[*] Service Status:${CLR_NC}"
    systemctl status 9router --no-pager
    echo ""
    echo -e "${CLR_BLU}[*] Recent Logs (30 lines):${CLR_NC}"
    journalctl -u 9router -n 30 --no-pager
}

app_start() {
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] 9router is not installed.${CLR_NC}"
        return
    fi
    if systemctl start 9router; then
        echo -e "${CLR_GRN}[+] 9router service started.${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Failed to start 9router service.${CLR_NC}"
    fi
}

app_stop() {
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] 9router is not installed.${CLR_NC}"
        return
    fi
    if systemctl stop 9router; then
        echo -e "${CLR_YLW}[*] 9router service stopped.${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Failed to stop 9router service.${CLR_NC}"
    fi
}

app_restart() {
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] 9router is not installed.${CLR_NC}"
        return
    fi
    if systemctl restart 9router; then
        echo -e "${CLR_GRN}[+] 9router service restarted.${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Failed to restart 9router service.${CLR_NC}"
    fi
}

app_delete() {
    echo -e "${CLR_RED}[!] Removing 9router service and files...${CLR_NC}"
    systemctl stop 9router 2>/dev/null
    systemctl disable 9router 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    npm uninstall -g 9router 2>/dev/null
    rm -rf /root/.9router
    echo -e "${CLR_GRN}[+] 9router removed completely.${CLR_NC}"
}

app_menu() {
    while true; do
        clear
        echo "======================================"
        echo "           9Router Menu               "
        echo "======================================"
        local v_info cur_port
        v_info=$(get_app_version)
        cur_port=$(get_current_port)
        if app_is_installed; then
            echo -e " Status  : ${CLR_GRN}Installed (Active)${CLR_NC}"
            echo -e " Version : ${CLR_BLU}$v_info${CLR_NC}"
            echo -e " Port    : ${CLR_YLW}$cur_port${CLR_NC}"
        else
            echo -e " Status  : ${CLR_RED}Not Installed${CLR_NC}"
            echo -e " Version : ${CLR_RED}$v_info${CLR_NC}"
        fi
        echo "--------------------------------------"
        echo " 1) Install"
        echo " 2) Update"
        echo " 3) Edit Config & Limits"
        echo " 4) Start"
        echo " 5) Stop"
        echo " 6) Restart"
        echo " 7) Status & Logs"
        echo " 8) Delete"
        echo ""
        echo -e " ${CLR_ORG}b) Back${CLR_NC}"
        echo -e " ${CLR_RED}e) Exit${CLR_NC}"
        echo "--------------------------------------"
        read -p " Select option: " choice
        case $choice in
            1) app_install; read -p "Press Enter to continue..." ;;
            2) app_update; read -p "Press Enter to continue..." ;;
            3) app_edit_config; read -p "Press Enter to continue..." ;;
            4) app_start; read -p "Press Enter to continue..." ;;
            5) app_stop; read -p "Press Enter to continue..." ;;
            6) app_restart; read -p "Press Enter to continue..." ;;
            7) app_status; read -p "Press Enter to continue..." ;;
            8) app_delete; read -p "Press Enter to continue..." ;;
            b|B) break ;;
            e|E) clear; exit 0 ;;
            *) ;;
        esac
    done
}
