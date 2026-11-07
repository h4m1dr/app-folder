#!/usr/bin/env bash

# ==============================================================================
# CLIProxyAPI Master Control Panel (Golang Architecture)
# ==============================================================================

INSTALL_DIR="/opt/cliproxyapi"
STATIC_DIR="$INSTALL_DIR/static"
BIN_PATH="/usr/local/bin/cliproxyapi"
SERVICE_FILE="/etc/systemd/system/cliproxyapi.service"
CONFIG_FILE="$INSTALL_DIR/config.yaml"

CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_YLW='\033[1;33m'
CLR_BLU='\033[0;34m'
CLR_CYN='\033[0;36m'
CLR_ORG='\033[38;5;208m'
CLR_MUTED='\033[90m'
CLR_NC='\033[0m'

get_version() {
    if [ -x "$BIN_PATH" ]; then
        "$BIN_PATH" -h 2>&1 | grep -i "Version:" | awk '{print $2}' | tr -d ',' || echo "Installed"
    else
        echo "Not Installed"
    fi
}

download_and_extract_assets() {
    echo -e "${CLR_BLU}[*] Fetching latest release from GitHub...${CLR_NC}"
    local tmp_dir="/tmp/cliproxy_setup"
    local tmp_tar="/tmp/cliproxy_latest.tar.gz"
    rm -rf "$tmp_dir" "$tmp_tar"
    mkdir -p "$tmp_dir" "$STATIC_DIR"

    local download_url
    download_url=$(curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest | grep "browser_download_url.*linux.*amd64.tar.gz" | cut -d '"' -f 4 | head -n 1)

    if [ -z "$download_url" ]; then
        download_url="https://github.com/router-for-me/CLIProxyAPI/releases/latest/download/CLIProxyAPI_linux_amd64.tar.gz"
    fi

    if ! curl -fL "$download_url" -o "$tmp_tar"; then
        echo -e "${CLR_RED}[!] Download failed. Check server network.${CLR_NC}"
        rm -rf "$tmp_dir" "$tmp_tar"
        return 1
    fi

    tar -xzf "$tmp_tar" -C "$tmp_dir"

    local bin_source
    bin_source=$(find "$tmp_dir" -maxdepth 2 -type f -exec file {} + | grep "ELF 64-bit" | cut -d: -f1 | head -n 1)

    if [ -n "$bin_source" ] && [ -f "$bin_source" ]; then
        systemctl stop cliproxyapi 2>/dev/null
        mv "$bin_source" "$BIN_PATH"
        chmod +x "$BIN_PATH"
        echo -e "${CLR_GRN}[+] Core binary updated at $BIN_PATH${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Valid executable not found in package.${CLR_NC}"
        rm -rf "$tmp_dir" "$tmp_tar"
        return 1
    fi

    local static_source
    static_source=$(find "$tmp_dir" -type d -name "static" | head -n 1)
    if [ -n "$static_source" ] && [ -d "$static_source" ]; then
        cp -r "$static_source"/* "$STATIC_DIR/" 2>/dev/null
    fi
    find "$tmp_dir" -maxdepth 2 -name "*.html" -exec cp {} "$STATIC_DIR/" \; 2>/dev/null

    rm -rf "$tmp_dir" "$tmp_tar"
    return 0
}

setup_systemd() {
    local mem_limit="$1"
    local cpu_limit="$2"

    local limits_block=""
    if [ -n "$mem_limit" ] && [ "$mem_limit" != "none" ]; then
        limits_block+="MemoryMax=$mem_limit"$'\n'
    fi
    if [ -n "$cpu_limit" ] && [ "$cpu_limit" != "none" ]; then
        limits_block+="CPUQuota=$cpu_limit"$'\n'
    fi

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=CLIProxyAPI LLM Proxy Gateway
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH -config $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=65535
$limits_block
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable cliproxyapi >/dev/null 2>&1
}

setup_nginx_domain() {
    local domain="$1"
    local port="$2"

    if [ -z "$domain" ]; then
        return 0
    fi

    echo -e "${CLR_BLU}[*] Deploying Nginx server block for $domain...${CLR_NC}"
    local nginx_file="/etc/nginx/sites-available/$domain"

    cat <<EOF > "$nginx_file"
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    location = / {
        return 302 /management.html;
    }

    location = /management.html {
        alias $STATIC_DIR/management.html;
        default_type text/html;
    }

    location /static/ {
        alias $STATIC_DIR/;
        autoindex off;
    }

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    ln -sf "$nginx_file" "/etc/nginx/sites-enabled/$domain"
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        echo -e "${CLR_GRN}[+] Nginx configuration active.${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Nginx syntax error. Check configuration manual.${CLR_NC}"
    fi
}

reconfigure_wizard() {
    echo ""
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    echo -e "${CLR_CYN}     Phase 1: Basic Server Configuration            ${CLR_NC}"
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    read -p " Listening Host IP [Default: 127.0.0.1]: " in_host
    local host="${in_host:-127.0.0.1}"

    read -p " Listening Port [Default: 8085]: " in_port
    local port="${in_port:-8085}"

    read -p " Management Secret Key [Default: admin123456]: " in_key
    local key="${in_key:-admin123456}"

    local log_level="info"
    read -p " Would you like to enter Advanced Settings? [y/N]: " adv_choice
    if [[ "$adv_choice" =~ ^[yY]$ ]]; then
        echo ""
        echo " Select Log Level:"
        echo " 1) info (Default)"
        echo " 2) debug (Verbose)"
        echo " 3) warn"
        echo " 4) error"
        read -p " Selection [1-4, Default: 1]: " in_log
        case $in_log in
            2) log_level="debug" ;;
            3) log_level="warn" ;;
            4) log_level="error" ;;
            *) log_level="info" ;;
        esac
    fi

    # نوشتن هر دو کلید management_key و auth_key برای پشتیبانی کامل
    cat <<EOF > "$CONFIG_FILE"
host: "$host"
port: $port
management_key: "$key"
auth_key: "$key"
log_level: "$log_level"
EOF

    local mem_limit=""
    local cpu_limit=""
    read -p " Would you like to configure System Resource Limits? [y/N]: " res_choice
    if [[ "$res_choice" =~ ^[yY]$ ]]; then
        read -p " Memory Limit (e.g. 256M, 512M or 'n' for none) [Default: 256M]: " in_mem
        in_mem="${in_mem:-256M}"
        if [[ "$in_mem" =~ ^[nN]$ ]]; then
            mem_limit=""
        else
            mem_limit="$in_mem"
        fi

        read -p " CPU Quota (e.g. 100%, 150% or 'n' for none) [Default: 100%]: " in_cpu
        in_cpu="${in_cpu:-100%}"
        if [[ "$in_cpu" =~ ^[nN]$ ]]; then
            cpu_limit=""
        else
            cpu_limit="$in_cpu"
        fi
    fi

    setup_systemd "$mem_limit" "$cpu_limit"

    read -p " Would you like to configure Nginx Domain? [y/N]: " dom_choice
    if [[ "$dom_choice" =~ ^[yY]$ ]]; then
        read -p " Enter Domain (e.g. 9c.ykno.ir): " in_domain
        [ -n "$in_domain" ] && setup_nginx_domain "$in_domain" "$port"
    fi

    systemctl restart cliproxyapi
    echo -e "${CLR_GRN}[+] Settings successfully applied!${CLR_NC}"
}

install_fresh() {
    mkdir -p "$INSTALL_DIR"
    download_and_extract_assets || return 1
    reconfigure_wizard
}

update_only() {
    echo -e "${CLR_BLU}[*] Updating CLIProxyAPI binary without touching configurations...${CLR_NC}"
    if download_and_extract_assets; then
        systemctl restart cliproxyapi
        echo -e "${CLR_GRN}[+] CLIProxyAPI updated and service restarted successfully.${CLR_NC}"
    fi
}

edit_config() {
    local editor="${EDITOR:-nano}"
    if [ -f "$CONFIG_FILE" ]; then
        $editor "$CONFIG_FILE"
        read -p "Restart CLIProxyAPI to apply changes? [Y/n]: " ans
        if [[ ! "$ans" =~ ^[nN]$ ]]; then
            systemctl restart cliproxyapi
            echo -e "${CLR_GRN}[+] Service restarted.${CLR_NC}"
        fi
    else
        echo -e "${CLR_RED}[!] Config file not found at $CONFIG_FILE${CLR_NC}"
    fi
}

edit_service() {
    local editor="${EDITOR:-nano}"
    if [ -f "$SERVICE_FILE" ]; then
        $editor "$SERVICE_FILE"
        systemctl daemon-reload
        read -p "Restart CLIProxyAPI to apply systemd changes? [Y/n]: " ans
        if [[ ! "$ans" =~ ^[nN]$ ]]; then
            systemctl restart cliproxyapi
            echo -e "${CLR_GRN}[+] Service reloaded and restarted.${CLR_NC}"
        fi
    else
        echo -e "${CLR_RED}[!] Service file not found at $SERVICE_FILE${CLR_NC}"
    fi
}

while true; do
    clear
    echo -e "${CLR_CYN}======================================================${CLR_NC}"
    echo -e "${CLR_CYN}            CLIProxyAPI Core Control Panel            ${CLR_NC}"
    echo -e "${CLR_CYN}======================================================${CLR_NC}"
    if systemctl is-active --quiet cliproxyapi; then
        echo -e " Service Status : ${CLR_GRN}Active (Running)${CLR_NC}"
    elif [ -f "$SERVICE_FILE" ]; then
        echo -e " Service Status : ${CLR_YLW}Inactive (Stopped)${CLR_NC}"
    else
        echo -e " Service Status : ${CLR_RED}Not Installed${CLR_NC}"
    fi

    echo -e " Core Version   : ${CLR_GRN}$(get_version)${CLR_NC}"
    if [ -f "$CONFIG_FILE" ]; then
        curr_port=$(grep "port:" "$CONFIG_FILE" | head -n1 | awk '{print $2}')
        echo -e " Active Port    : ${CLR_YLW}${curr_port:-Unknown}${CLR_NC}"
    fi
    echo -e "${CLR_CYN}------------------------------------------------------${CLR_NC}"
    if [ ! -f "$BIN_PATH" ]; then
        echo " 1) Install CLIProxyAPI"
    else
        echo " 1) Update Binary Only (Keep Config)"
        echo " 2) Re-configure Settings & Limits"
    fi
    echo " 3) Start Service"
    echo " 4) Stop Service"
    echo " 5) Restart Service"
    echo " 6) View Real-Time Status & Logs"
    echo " 7) Edit Application Config (config.yaml)"
    echo " 8) Edit Systemd Service & Limits (cliproxyapi.service)"
    echo " 9) Uninstall & Clean Everything"
    echo ""
    echo -e " ${CLR_ORG}b) Back${CLR_NC}"
    echo -e "${CLR_CYN}------------------------------------------------------${CLR_NC}"
    read -p " Select an option: " opt
    case $opt in
        1)
            if [ ! -f "$BIN_PATH" ]; then
                install_fresh
            else
                update_only
            fi
            read -p "Press Enter to continue..." ;;
        2)
            reconfigure_wizard
            read -p "Press Enter to continue..." ;;
        3)
            systemctl start cliproxyapi
            echo -e "${CLR_GRN}[+] Service started.${CLR_NC}"
            read -p "Press Enter to continue..." ;;
        4)
            systemctl stop cliproxyapi
            echo -e "${CLR_YLW}[*] Service stopped.${CLR_NC}"
            read -p "Press Enter to continue..." ;;
        5)
            systemctl restart cliproxyapi
            echo -e "${CLR_GRN}[+] Service restarted.${CLR_NC}"
            read -p "Press Enter to continue..." ;;
        6)
            echo -e "${CLR_BLU}[*] Displaying logs (Press Ctrl+C to exit)...${CLR_NC}"
            journalctl -u cliproxyapi -n 35 -f --no-pager
            read -p "Press Enter to continue..." ;;
        7)
            edit_config
            read -p "Press Enter to continue..." ;;
        8)
            edit_service
            read -p "Press Enter to continue..." ;;
        9)
            read -p " Are you sure you want to completely remove CLIProxyAPI? [y/N]: " conf
            if [[ "$conf" =~ ^[yY]$ ]]; then
                systemctl stop cliproxyapi 2>/dev/null
                systemctl disable cliproxyapi 2>/dev/null
                rm -f "$SERVICE_FILE" "$BIN_PATH"
                rm -rf "$INSTALL_DIR"
                systemctl daemon-reload
                echo -e "${CLR_GRN}[+] Successfully uninstalled CLIProxyAPI.${CLR_NC}"
            fi
            read -p "Press Enter to continue..." ;;
        b|B)
            break ;;
        *)
            echo -e "${CLR_RED}Invalid option.${CLR_NC}"
            sleep 1 ;;
    esac
done
