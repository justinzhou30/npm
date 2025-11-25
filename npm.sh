#!/bin/bash

set -e  # 遇到错误立即退出

# --- 预设配置 ---
# 如果 API 获取失败，使用此版本作为兜底
DEFAULT_COMPOSE_VERSION="v2.29.1"

# --- 颜色输出 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# --- 核心：获取架构名称（适配 Docker 官方命名） ---
get_docker_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
}

# ================== 开始执行 ==================

log_info "🚀 检查 Docker 是否安装..."
if ! command -v docker &> /dev/null; then
    log_info "🔹 未检测到 Docker，开始安装..."
    # 官方脚本能自动处理 x86 和 arm
    curl -fsSL https://get.docker.com | bash
    sudo systemctl enable --now docker
else
    log_info "🔹 Docker 已安装，跳过。"
fi

log_info "🚀 检查 Docker Compose 是否安装..."
if ! command -v docker-compose &> /dev/null; then
    log_info "🔹 未检测到 Docker Compose，准备安装..."
    
    # 1. 确定架构
    COMPOSE_ARCH=$(get_docker_arch)
    log_info "🔹 当前系统架构: $(uname -m) -> 目标文件后缀: $COMPOSE_ARCH"

    # 2. 获取版本号 (带防失败机制)
    log_info "🔹 正在获取最新版本号..."
    LATEST_VERSION=$(curl -s -m 5 https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)
    
    if [ -z "$LATEST_VERSION" ]; then
        log_info "⚠️  无法通过 API 获取最新版本（可能是 GitHub 限流），使用默认版本: $DEFAULT_COMPOSE_VERSION"
        LATEST_VERSION="$DEFAULT_COMPOSE_VERSION"
    else
        log_info "🔹 获取成功，最新版本: $LATEST_VERSION"
    fi

    # 3. 拼接下载地址
    DOWNLOAD_URL="https://github.com/docker/compose/releases/download/$LATEST_VERSION/docker-compose-linux-$COMPOSE_ARCH"
    
    log_info "🔹 开始下载: $DOWNLOAD_URL"
    sudo curl -L --fail "$DOWNLOAD_URL" -o /usr/local/bin/docker-compose
    
    # 4. 校验下载是否成功
    if [ ! -s /usr/local/bin/docker-compose ]; then
        log_error "下载失败或文件为空！请检查网络连接。"
        rm -f /usr/local/bin/docker-compose
        exit 1
    fi

    sudo chmod +x /usr/local/bin/docker-compose
    
    # 5. 尝试运行一下看是否报错
    VERSION_CHECK=$(docker-compose --version)
    log_info "✅ Docker Compose 安装成功: $VERSION_CHECK"
else
    log_info "🔹 Docker Compose 已安装，跳过。"
fi

log_info "🚀 创建 Nginx Proxy Manager 目录..."
mkdir -p /etc/docker/npm && cd /etc/docker/npm

# 交互输入端口
read -rp "请输入 HTTP 端口（默认80）: " PORT_HTTP
PORT_HTTP=${PORT_HTTP:-80}

read -rp "请输入 管理面板端口（默认81）: " PORT_PANEL
PORT_PANEL=${PORT_PANEL:-81}

read -rp "请输入 HTTPS 端口（默认443）: " PORT_HTTPS
PORT_HTTPS=${PORT_HTTPS:-443}

log_info "🔹 端口设置: HTTP:$PORT_HTTP | 面板:$PORT_PANEL | HTTPS:$PORT_HTTPS"

log_info "🚀 生成 docker-compose.yml..."
cat > docker-compose.yml <<EOF
services:
  npm:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '${PORT_HTTP}:80'
      - '${PORT_PANEL}:81'
      - '${PORT_HTTPS}:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

# 优先 IPv4
sed -i 's/^#\s*precedence ::ffff:0:0\/96 100/precedence ::ffff:0:0\/96 100/' /etc/gai.conf || true
systemctl restart docker || true

log_info "🚀 启动 Nginx Proxy Manager..."
docker-compose up -d

log_info "✅ 安装完成！"
# 获取 IP (尝试多个命令确保能在精简版系统上获取)
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
fi

echo "================================================"
echo -e "   管理面板地址: http://${HOST_IP}:$PORT_PANEL"
echo -e "   默认账号:     admin@example.com"
echo -e "   默认密码:     changeme"
echo "================================================"
