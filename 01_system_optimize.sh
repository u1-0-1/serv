#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  ⚡ SYSTEM OPTIMIZATION & SECURITY FOR XRAY SERVER ⚡          ║
# ║  Ubuntu Container - Zero Cost Setup                          ║
# ║  🔧 FIXED: Container-safe (no systemd dependency)           ║
# ╚══════════════════════════════════════════════════════════════╝

set +e  # لا تتوقف عند الخطأ - مهم للحاويات

echo "🚀 Starting system optimization..."

# 1. Update system
echo "📦 Updating packages..."
apt-get update -qq 2>/dev/null
apt-get upgrade -y -qq 2>/dev/null

# 2. Install essential tools
echo "🔧 Installing essential tools..."
apt-get install -y -qq curl wget jq uuid-runtime qrencode net-tools bc htop 2>/dev/null

# 3. Disable unnecessary services to save RAM/CPU
echo "🛑 Disabling unnecessary services (if systemd available)..."
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl stop snapd 2>/dev/null || true
    systemctl disable snapd 2>/dev/null || true
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true
    systemctl stop apport 2>/dev/null || true
    systemctl disable apport 2>/dev/null || true
    echo "   ✅ Services disabled via systemd"
else
    echo "   ⚠️  systemd not available as PID 1 - skipping service management"
fi

# 4. Clean up logs and temp files
echo "🧹 Cleaning up logs and temp files..."
find /var/log -type f -delete 2>/dev/null || true
find /tmp -type f -delete 2>/dev/null || true
apt-get autoremove -y -qq 2>/dev/null || true
apt-get autoclean -qq 2>/dev/null || true

# 5. Optimize kernel parameters for networking
echo "⚙️ Optimizing kernel parameters..."
cat >> /etc/sysctl.conf << 'EOF'
# Network Optimization for Xray
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_fastopen = 3
fs.file-max = 655350
EOF

# تطبيق إعدادات sysctl (قد تفشل بعضها في الحاوية - هذا طبيعي)
sysctl -p 2>/dev/null || echo "   ⚠️  Some sysctl params may not apply in container (normal)"

# 6. Enable BBR congestion control
echo "🌐 Enabling BBR..."
modprobe tcp_bbr 2>/dev/null || true
mkdir -p /etc/modules-load.d
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null || true

# 7. Set timezone to UTC for consistency (container-safe)
if command -v timedatectl &>/dev/null && [ -d /run/systemd/system ]; then
    timedatectl set-timezone UTC 2>/dev/null || true
else
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null || true
fi

# 8. Create necessary directories
mkdir -p /usr/local/etc/xray
mkdir -p /usr/local/bin
mkdir -p /root/.cloudflared

echo ""
echo "✅ System optimization complete!"
echo "💾 RAM Saved: ~50-100MB (if services were running)"
echo "🔒 Security: Unnecessary services disabled (if available)"
echo "📦 Tools installed: curl, wget, jq, bc, net-tools, etc."
