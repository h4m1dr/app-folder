#!/usr/bin/env bash

# Module: CLIProxyAPI Manager (Go Binary)
APP_NAME="CLIProxyAPI"
SERVICE_FILE="/etc/systemd/system/cliproxyapi.service"
INSTALL_DIR="/opt/cliproxyapi"
BIN_PATH="/usr/local/bin/cliproxyapi"

CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_YLW='\033[1;33m'
CLR_BLU='\033[0;34m'
CLR_CYN='\033[0;36m'
CLR_ORG='\033[38;5;208m'
CLR_MUTED='\033[90m'
CLR_NC='\033[0m'

CACHED_CLIPROXY_LOCAL=""
CACHED_CLIPROXY_LATEST=""

app_is_installed() {
    [ -f "$SERVICE_FILE" ] && [ -f "$BIN_PATH" ] && return 0
    return 1
}

app_init_metadata() {
    if [ -f "$BIN_PATH" ]; then
        CACHED_CLIPROXY_LOCAL=$($BIN_PATH -v 2>/dev/null || $BIN_PATH --version 2>/dev/null || echo "Installed")
    else
        CACHED_CLIPROXY_LOCAL="Not Installed"
    fi

    if [ -z "$CACHED_CLIPROXY_LATEST" ]; then
        CACHED_CLIPROXY_LATEST=$(curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest 2>/dev/null | grep -Po '"tag_name": "\K.*?(?=")')
    fi
}

get_current_port() {
    if [ -f "$SERVICE_FILE" ]; then
        local p
        p=$(grep -oP '(?<=--port )\d+' "$SERVICE_FILE" 2>/dev/null || grep -oP '(?<=-p )\d+' "$SERVICE_FILE" 2>/dev/null || grep -oP '(?<=PORT=)\d+' "$SERVICE_FILE" 2>/dev/null | head -n1)
        [ -n "$p" ] && echo "$p" && return
    fi
    echo "8554"
}

get_version_status() {
    [ -z "$CACHED_CLIPROXY_LOCAL" ] && app_init_metadata

    if [ "$CACHED_CLIPROXY_LOCAL" != "Not Installed" ]; then
        if [ -n "$CACHED_CLIPROXY_LATEST" ]; then
            if [ "$CACHED_CLIPROXY_LOCAL" == "$CACHED_CLIPROXY_LATEST" ]; then
                echo -e "${CLR_GRN}$CACHED_CLIPROXY_LOCAL ${CLR_MUTED}(latest)${CLR_NC}"
            else
                echo -e "${CLR_YLW}$CACHED_CLIPROXY_LOCAL ${CLR_MUTED}-> ${CLR_GRN}$CACHED_CLIPROXY_LATEST${CLR_NC}"
            fi
        else
            echo -e "${CLR_GRN}$CACHED_CLIPROXY_LOCAL${CLR_NC}"
        fi
    else
        echo -e "${CLR_RED}Not Installed${CLR_NC}"
    fi
}

download_binary() {
    echo -e "${CLR_BLU}[*] Detecting system architecture...${CLR_NC}"
    local arch
    arch=$(uname -m)
    local target_arch=""

    case "$arch" in
        x86_64|amd64) target_arch="linux_amd64" ;;
        aarch64|arm64) target_arch="linux_arm64" ;;
        *) echo -e "${CLR_RED}[!] Unsupported architecture: $arch${CLR_NC}"; return 1 ;;
    esac

    local release_tag="$CACHED_CLIPROXY_LATEST"
    if [ -z "$release_tag" ]; then
        release_tag=$(curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest 2>/dev/null | grep -Po '"tag_name": "\K.*?(?=")')
    fi
    [ -z "$release_tag" ] && release_tag="latest"

    echo -e "${CLR_BLU}[*] Downloading CLIProxyAPI binary (${release_tag})...${CLR_NC}"
    local tmp_tar="/tmp/cliproxy.tar.gz"
    local dl_url="https://github.com/router-for-me/CLIProxyAPI/releases/download/${release_tag}/cliproxyapi_${release_tag#v}_${target_arch}.tar.gz"

    mkdir -p "$INSTALL_DIR"
    if ! curl -fsSL "$dl_url" -o "$tmp_tar"; then
        # Fallback to direct latest release asset if pattern differed
        dl_url=$(curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest 2>/dev/null | grep "browser_download_url" | grep "$target_arch" | cut -d '"' -f 4 | head -n1)
        curl -fsSL "$dl_url" -o "$tmp_tar" || { echo -e "${CLR_RED}[!] Download failed.${CLR_NC}"; return 1; }
    fi

    tar -xzf "$tmp_tar" -C "$INSTALL_DIR" 2>/dev/null || tar -xzf "$tmp_tar" -C "/tmp/"
    rm -f "$tmp_tar"

    local extracted_bin
    extracted_bin=$(find "$INSTALL_DIR" /tmp -name "cliproxyapi" -type f 2>/dev/null | head -n1)
    if [ -n "$extracted_bin" ]; then
        mv "$extracted_bin" "$BIN_PATH"
        chmod +x "$BIN_PATH"
        echo -e "${CLR_GRN}[+] Binary installed to $BIN_PATH${CLR_NC}"
        return 0
    fi

    echo -e "${CLR_RED}[!] Failed to extract binary.${CLR_NC}"
    return 1
}

generate_systemd_unit() {
    local port="$1"
    local host="$2"
    local mem_max="$3"
    local mem_high="$4"
    local cpu_quota="$5"

    cat <<SERVICE_EOF > "$SERVICE_FILE"
[Unit]
Description=CLIProxyAPI Service (Go Router)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH --port $port --host $host
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SERVICE_EOF

    [ -n "$mem_max" ] && echo "MemoryMax=$mem_max" >> "$SERVICE_FILE"
    [ -n "$mem_high" ] && echo "MemoryHigh=$mem_high" >> "$SERVICE_FILE"
    [ -n "$cpu_quota" ] && echo "CPUQuota=$cpu_quota" >> "$SERVICE_FILE"
    [ -n "$mem_max" ] && echo "TasksMax=50" >> "$SERVICE_FILE"

    cat <<SERVICE_EOF >> "$SERVICE_FILE"

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    return 0
}

app_configure_wizard() {
    echo ""
    echo -e "${CLR_BLU}=== CLIProxyAPI Configuration ===${CLR_NC}"
    
    local cur_p
    cur_p=$(get_current_port)
    echo -e " Enter listening Port ${CLR_MUTED}(Default: $cur_p)${CLR_NC}:"
    read -p " > " in_port
    local cfg_port="${in_port:-$cur_p}"

    echo -e " Enter listening Host IP ${CLR_MUTED}(Default: 127.0.0.1)${CLR_NC}:"
    read -p " > " in_host
    local cfg_host="${in_host:-127.0.0.1}"

    echo ""
    echo -e "${CLR_BLU}=== Resource Constraints (Optional) ===${CLR_NC}"
    echo -e " Do you want to configure memory & CPU constraints? [y/N]:"
    read -p " > " in_adv

    local cfg_mem_max=""
    local cfg_mem_high=""
    local cfg_cpu=""

    if [[ "$in_adv" =~ ^[yY]([eE][sS])?$ ]]; then
        echo ""
        echo -e "${CLR_MUTED}[Type 'n' to skip/disable any specific limit]${CLR_NC}"

        echo -e " Systemd Hard Memory Limit ${CLR_MUTED}(Default: 120M | 'n' to skip)${CLR_NC}:"
        read -p " > " in_mmax
        [[ ! "$in_mmax" =~ ^[nN]$ ]] && cfg_mem_max="${in_mmax:-120M}"

        echo -e " Systemd Throttle Memory Limit ${CLR_MUTED}(Default: 80M | 'n' to skip)${CLR_NC}:"
        read -p " > " in_mhigh
        [[ ! "$in_mhigh" =~ ^[nN]$ ]] && cfg_mem_high="${in_mhigh:-80M}"

        echo -e " Maximum CPU Core Quota ${CLR_MUTED}(Default: 50% | 'n' to skip)${CLR_NC}:"
        read -p " > " in_cpu
        [[ ! "$in_cpu" =~ ^[nN]$ ]] && cfg_cpu="${in_cpu:-50%}"
    fi

    echo -e "${CLR_BLU}[*] Generating service unit...${CLR_NC}"
    generate_systemd_unit "$cfg_port" "$cfg_host" "$cfg_mem_max" "$cfg_mem_high" "$cfg_cpu"

    echo ""
    echo -e " Do you want to manually edit the unit file before starting? [y/N]:"
    read -p " > " in_manual
    if [[ "$in_manual" =~ ^[yY]([eE][sS])?$ ]]; then
        local editor_bin="${EDITOR:-nano}"
        command -v "$editor_bin" &> /dev/null || editor_bin="vi"
        "$editor_bin" "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    echo -e "${CLR_BLU}[*] Starting CLIProxyAPI service...${CLR_NC}"
    systemctl restart cliproxyapi
    sleep 2
    if systemctl is-active --quiet cliproxyapi; then
        echo -e "${CLR_GRN}[+] CLIProxyAPI successfully running on port $cfg_port!${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Service failed to start. Check option 7 (Status & Logs).${CLR_NC}"
    fi
}

app_install() {
    if ! download_binary; then
        return
    fi
    app_configure_wizard
    systemctl enable cliproxyapi 2>/dev/null
    CACHED_CLIPROXY_LOCAL=""
    app_init_metadata
}

app_update() {
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] CLIProxyAPI is not installed yet.${CLR_NC}"
        return
    fi
    echo -e "${CLR_BLU}[*] Updating CLIProxyAPI binary...${CLR_NC}"
    systemctl stop cliproxyapi
    download_binary
    systemctl restart cliproxyapi
    CACHED_CLIPROXY_LOCAL=""
    CACHED_CLIPROXY_LATEST=""
    app_init_metadata
    echo -e "${CLR_GRN}[+] CLIProxyAPI updated successfully.${CLR_NC}"
}

app_status() {
    clear
    echo "======================================"
    echo "     CLIProxyAPI Status & Logs        "
    echo "======================================"
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] CLIProxyAPI service is not installed.${CLR_NC}"
        return
    fi
    echo -e "${CLR_BLU}[*] Service Status:${CLR_NC}"
    systemctl status cliproxyapi --no-pager
    echo ""
    echo -e "${CLR_BLU}[*] Recent Logs (30 lines):${CLR_NC}"
    journalctl -u cliproxyapi -n 30 --no-pager
}

app_start() {
    if ! app_is_installed; then echo -e "${CLR_RED}[!] Not installed.${CLR_NC}"; return; fi
    systemctl start cliproxyapi && echo -e "${CLR_GRN}[+] Started.${CLR_NC}"
}

app_stop() {
    if ! app_is_installed; then echo -e "${CLR_RED}[!] Not installed.${CLR_NC}"; return; fi
    systemctl stop cliproxyapi && echo -e "${CLR_YLW}[*] Stopped.${CLR_NC}"
}

app_restart() {
    if ! app_is_installed; then echo -e "${CLR_RED}[!] Not installed.${CLR_NC}"; return; fi
    systemctl restart cliproxyapi && echo -e "${CLR_GRN}[+] Restarted.${CLR_NC}"
}

app_delete() {
    echo -e "${CLR_RED}[!] Removing CLIProxyAPI...${CLR_NC}"
    systemctl stop cliproxyapi 2>/dev/null
    systemctl disable cliproxyapi 2>/dev/null
    rm -f "$SERVICE_FILE" "$BIN_PATH"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    CACHED_CLIPROXY_LOCAL=""
    echo -e "${CLR_GRN}[+] CLIProxyAPI removed completely.${CLR_NC}"
}

app_menu() {
    while true; do
        clear
        echo "======================================"
        echo "          CLIProxyAPI Menu            "
        echo "======================================"
        local cur_port
        cur_port=$(get_current_port)
        if app_is_installed; then
            echo -e " Status  : ${CLR_GRN}Installed (Active)${CLR_NC}"
            echo -e " Version : $(get_version_status)"
            echo -e " Port    : ${CLR_YLW}$cur_port${CLR_NC}"
        else
            echo -e " Status  : ${CLR_RED}Not Installed${CLR_NC}"
            echo -e " Version : $(get_version_status)"
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
            3) app_configure_wizard; read -p "Press Enter to continue..." ;;
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
