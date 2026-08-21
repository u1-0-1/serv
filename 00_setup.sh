#!/bin/bash
# ==================================================================
#  VLESS+WS OPTIMIZED FOR MAX SPEED - Google Cloud Shell
#  - NO logs at all (access+error disabled)
#  - No unnecessary code (no sysctl, no systemd)
#  - Minimal config for best performance
# ==================================================================
set +e
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${R}sudo: sudo bash $0${NC}"; exit 1; fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${Y}[1/3] Installing tools...${NC}"
apt-get update -qq 2>/dev/null
apt-get install -y -qq curl jq uuid-runtime unzip 2>/dev/null

echo -e "${Y}[2/3] Installing Xray...${NC}"
rm -f /usr/local/bin/xray 2>/dev/null
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null

if [ ! -x /usr/local/bin/xray ]; then
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)  XRAY_ARCH="Xray-linux-64" ;;
        aarch64|arm64) XRAY_ARCH="Xray-linux-arm64-v8a" ;;
        *) echo -e "${R}Unsupported arch${NC}"; exit 1 ;;
    esac
    VER=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name 2>/dev/null || echo "v25.8.25")
    cd /tmp
    curl -sL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${VER}/${XRAY_ARCH}.zip"
    unzip -o xray.zip -d /tmp/xe >/dev/null 2>&1
    mkdir -p /usr/local/bin
    cp /tmp/xe/xray /usr/local/bin/xray
    chmod +x /usr/local/bin/xray
    rm -rf /tmp/xray.zip /tmp/xe
    cd /
fi

if [ ! -x /usr/local/bin/xray ]; then echo -e "${R}Xray install FAILED${NC}"; exit 1; fi
echo -e "${G}Xray OK: $(/usr/local/bin/xray version | head -1)${NC}"

echo -e "${Y}[3/3] Config (no logs) + start...${NC}"
mkdir -p /usr/local/etc/xray

# MAX PERFORMANCE, ZERO LOGS:
# - log: all disabled -> no access log on client connect, no error log
# - single freedom outbound (direct)
# - no routing rules -> less CPU
# - ws path "/" (simplest for Google proxy)
cat > /usr/local/etc/xray/config.json << 'XRAY'
{
  "log": { "access": "none", "error": "none", "loglevel": "none" },
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": 8080,
    "protocol": "vless",
    "settings": { "clients": [], "decryption": "none" },
    "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/" } }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
XRAY

pkill -f "xray run" 2>/dev/null; sleep 1
nohup /usr/local/bin/xray run -c /usr/local/etc/xray/config.json > /dev/null 2>&1 &
sleep 2

if pgrep -f "xray run" >/dev/null; then
    echo -e "${G}OK: Xray running on 8080 (no logs)${NC}"
else
    echo -e "${R}Start failed.${NC}"
    exit 1
fi

# panel
if [ -f "$SCRIPT_DIR/user-panel.sh" ]; then
    cp "$SCRIPT_DIR/user-panel.sh" /usr/local/bin/user-panel.sh
    chmod +x /usr/local/bin/user-panel.sh
fi
printf '#!/bin/bash\nexec bash /usr/local/bin/user-panel.sh "$@"\n' > /usr/local/bin/user-panel
chmod +x /usr/local/bin/user-panel
grep -q /usr/local/bin /root/.bashrc || echo 'export PATH="/usr/local/bin:$PATH"' >> /root/.bashrc

echo -e "${G}DONE. Next: Web Preview -> port 8080${NC}"
echo -e "${G}Then: sudo user-panel${NC}"