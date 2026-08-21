#!/bin/bash
# minimal VLESS client panel - Google Cloud Shell
set +e
CONFIG="/usr/local/etc/xray/config.json"
DB="/usr/local/etc/xray/clients.db"
HOST_FILE="/usr/local/etc/xray/cs_host.txt"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

[ "$EUID" -ne 0 ] && { echo -e "${R}sudo: sudo $0${NC}"; exit 1; }

get_host() {
    [ -n "$CS_HOST" ] && { echo "$CS_HOST"; return; }
    [ -f "$HOST_FILE" ] && { cat "$HOST_FILE" 2>/dev/null; return; }
    echo ""
}

restart() {
    pkill -f "xray run" 2>/dev/null; sleep 1
    nohup /usr/local/bin/xray run -c "$CONFIG" >/dev/null 2>&1 &
    sleep 2
    pgrep -f "xray run" >/dev/null
}

header() { clear; echo -e "${C}-- USER PANEL (VLESS+WS, Cloud Shell) --${NC}"; echo ""; }

set_host() {
    header
    echo -e "${C}Enter Cloud Shell hostname (no https://):${NC}"
    read -r h
    [ -z "$h" ] && { echo -e "${R}Empty!${NC}"; read -r _; return; }
    h="${h#https://}"; h="${h#http://}"; h="${h%%/*}"
    echo "$h" > "$HOST_FILE"
    echo -e "${G}Saved: $h${NC}"
    read -r _
}

create_client() {
    header
    host=$(get_host)
    [ -z "$host" ] && { echo -e "${R}Set host first (option 4)${NC}"; read -r _; return; }
    echo -e "${C}Name:${NC}"; read -r name
    [ -z "$name" ] && { echo -e "${R}Empty!${NC}"; read -r _; return; }
    grep -q "NAME:$name|" "$DB" 2>/dev/null && { echo -e "${R}Exists!${NC}"; read -r _; return; }
    uuid=$(/usr/local/bin/xray uuid 2>/dev/null || uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$CONFIG" 2>/dev/null || echo "/")
    penc=$(echo "$path" | sed 's/\//%2F/g')
    echo "NAME:$name|UUID:$uuid|STATUS:active|CREATED:$(date +%s)" >> "$DB"
    jq --arg u "$uuid" --arg e "$name" '.inbounds[0].settings.clients += [{"id":$u,"email":$e}]' "$CONFIG" > /tmp/c.json && mv /tmp/c.json "$CONFIG"
    restart
    echo ""
    echo -e "${G}SHARE LINK:${NC}"
    echo "vless://${uuid}@${host}:443?encryption=none&security=tls&type=ws&host=${host}&path=${penc}&sni=${host}#USER-${name}"
    echo ""
    read -r _
}

list_clients() {
    header
    [ -s "$DB" ] 2>/dev/null || { echo -e "${Y}No clients${NC}"; read -r _; return; }
    nl "$DB" | sed 's/|STATUS.*//'
    read -r _
}

restart_menu() {
    header
    restart && echo -e "${G}Xray restarted${NC}" || echo -e "${R}Failed${NC}"
    read -r _
}

main() {
    while true; do
        header
        echo -e "${G}1${NC}) Create client"
        echo -e "${G}2${NC}) List clients"
        echo -e "${G}3${NC}) Restart Xray"
        echo -e "${G}4${NC}) Set host"
        echo -e "${R}0${NC}) Exit"
        read -r c
        case "$c" in
            1) create_client;; 2) list_clients;; 3) restart_menu;; 4) set_host;;
            0) exit;; *) echo -e "${R}Invalid${NC}"; sleep 1;;
        esac
    done
}

touch "$DB" 2>/dev/null
main