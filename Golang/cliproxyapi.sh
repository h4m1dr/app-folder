#!/usr/bin/env bash

CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_YLW='\033[1;33m'
CLR_BLU='\033[0;34m'
CLR_CYN='\033[0;36m'
CLR_ORG='\033[38;5;208m'
CLR_MUTED='\033[90m'
CLR_NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RAW_URL="https://raw.githubusercontent.com/h4m1dr/app-folder/main/Golang"
CACHE_DIR="/tmp/app-folder-golang-cache"
PERM_DIR="/opt/app-folder/Golang"

KNOWN_APPS=("authelia.sh" "cliproxyapi.sh")

if [ "$EUID" -ne 0 ]; then
    echo -e "${CLR_RED}[!] Please run as root (sudo).${CLR_NC}"
    exit 1
fi

is_go_installed() {
    command -v go &> /dev/null && return 0
    return 1
}

TARGET_GO_VER=""
CACHED_GO_LOCAL=""

init_runtime_metadata() {
    echo -e "${CLR_MUTED}[*] Initializing Go environment and metadata cache...${CLR_NC}"
    if is_go_installed; then
        CACHED_GO_LOCAL=$(go version 2>/dev/null | awk '{print $3}')
    fi
}

get_go_version_status() {
    if is_go_installed; then
        echo -e "${CLR_GRN}${CACHED_GO_LOCAL:-Installed}${CLR_NC}"
    else
        echo -e "${CLR_MUTED}Not Installed (Native Binaries Used)${CLR_NC}"
    fi
}

others_menu() {
    local uninstalled_files=("$@")
    while true; do
        clear
        echo "======================================"
        echo "          Available Apps (Others)     "
        echo "======================================"
        if [ ${#uninstalled_files[@]} -eq 0 ]; then
            echo " (No uninstalled apps found)"
            echo "--------------------------------------"
            echo -e " ${CLR_ORG}b) Back${CLR_NC}"
            echo -e " ${CLR_RED}e) Exit${CLR_NC}"
            read -p " Select option: " choice
            [[ "$choice" =~ ^[bB]$ ]] && break
            [[ "$choice" =~ ^[eE]$ ]] && { clear; exit 0; }
            continue
        fi

        local idx=1
        for f in "${uninstalled_files[@]}"; do
            local base_name
            base_name=$(basename "$f" .sh)
            echo " $idx) $base_name"
            ((idx++))
        done
        echo ""
        echo -e " ${CLR_ORG}b) Back${CLR_NC}"
        echo -e " ${CLR_RED}e) Exit${CLR_NC}"
        echo "--------------------------------------"
        read -p " Select option: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#uninstalled_files[@]} ]; then
            local selected_file="${uninstalled_files[$((choice - 1))]}"
            if [ -f "$selected_file" ]; then
                source "$selected_file"
                declare -f app_menu > /dev/null && app_menu
                break
            fi
        elif [[ "$choice" =~ ^[bB]$ ]]; then
            break
        elif [[ "$choice" =~ ^[eE]$ ]]; then
            clear
            exit 0
        fi
    done
}

main_menu() {
    init_runtime_metadata

    local target_scripts=()
    for f in "$SCRIPT_DIR"/*.sh; do
        [ -f "$f" ] && target_scripts+=("$f")
    done

    if [ ${#target_scripts[@]} -eq 0 ]; then
        mkdir -p "$CACHE_DIR"
        for app_script in "${KNOWN_APPS[@]}"; do
            [ ! -f "$CACHE_DIR/$app_script" ] && curl -fsSL "$REPO_RAW_URL/$app_script" -o "$CACHE_DIR/$app_script" 2>/dev/null
            [ -f "$CACHE_DIR/$app_script" ] && target_scripts+=("$CACHE_DIR/$app_script")
        done
    fi

    for f in "${target_scripts[@]}"; do
        if [ -f "$f" ]; then
            source "$f"
            declare -f app_init_metadata > /dev/null && app_init_metadata
        fi
    done

    while true; do
        clear
        echo "======================================"
        echo "          GolangEasy Manager          "
        echo "======================================"
        echo -e " Go Runtime    : $(get_go_version_status)"
        echo "--------------------------------------"

        local installed_files=()
        local uninstalled_files=()

        for f in "${target_scripts[@]}"; do
            if [ -f "$f" ]; then
                source "$f"
                if declare -f app_is_installed > /dev/null && app_is_installed; then
                    installed_files+=("$f")
                else
                    uninstalled_files+=("$f")
                fi
            fi
        done

        local idx=1
        for f in "${installed_files[@]}"; do
            local base_name
            base_name=$(basename "$f" .sh)
            echo " $idx) $base_name"
            ((idx++))
        done

        local others_idx=$idx
        echo " $others_idx) others"
        echo ""
        echo -e " ${CLR_RED}e) Exit${CLR_NC}"
        echo "======================================"
        read -p " Select option: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -lt "$others_idx" ]; then
                local selected_file="${installed_files[$((choice - 1))]}"
                if [ -f "$selected_file" ]; then
                    source "$selected_file"
                    declare -f app_menu > /dev/null && app_menu
                fi
            elif [ "$choice" -eq "$others_idx" ]; then
                others_menu "${uninstalled_files[@]}"
            fi
        elif [[ "$choice" =~ ^[eE]$ ]]; then
            clear
            exit 0
        fi
    done
}

main_menu
