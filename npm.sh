#!/bin/bash

set -e  # 遇到错误立即退出

# --- 核心修改部分：定义架构检测函数 ---
get_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo "不支持的架构: $ARCH"
            return 1
            ;;
    esac
}
# ------------------------------------

echo "🚀 检查 Docker 是否安装..."
if ! command -v docker &> /dev/null; then
    echo "🔹 未检测到 Docker，开始安装..."
    # 官方脚本会自动处理 x86 和 ARM 的区别
    curl -fsSL https://get.docker.com | bash
    sudo systemctl enable --now docker
fi

echo "🚀 检查 Docker Compose 是否安装..."
if ! command -v docker-compose &> /dev/null; then
    echo "🔹 未检测到 Docker Compose，开始安装..."
    
    # 获取系统架构名称 (x86_64 或 aarch64)
    COMPOSE_ARCH=$(get_arch)
    if [ -z "$COMPOSE_ARCH" ]; then exit 1; fi
    
    echo "🔹 检测到系统架构为: $COMPOSE_ARCH"
    
    LATEST_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)
    
    # 动态构建下载链接
    DOWNLOAD_URL="https://github.com/docker/compose/releases/download/$LATEST_VERSION/docker-compose-linux-$COMPOSE_ARCH"
    
    echo "🔹 正在下载: $DOWNLOAD_URL"
    sudo curl -SL "$DOWNLOAD_URL" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

echo "🚀 创建 Nginx Proxy Manager 目录..."
mkdir -p /etc/docker/npm && cd /etc/docker/npm

# 交互输入端口，默认80、81、443
read -rp "请输入 HTTP 端口（默认80）: " PORT_HTTP
PORT_HTTP=${PORT_HTTP:-80}

read -rp "请输入 管理面板端口（默认81）: " PORT_PANEL
PORT_PANEL=${PORT_PANEL:-81}

read -rp "请输入 HTTPS 端口（默认443）: " PORT_HTTPS
PORT_HTTPS=${PORT_HTTPS:-443}

echo "🔹 设置端口映射为：HTTP $PORT_HTTP，管理面板 $PORT_PANEL，HTTPS $PORT_HTTPS"

echo "🚀 生成 docker-compose.yml..."
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

# 优先 IPv4，避免拉镜像走 IPv6 报错
sed -i 's/^#\s*precedence ::ffff:0:0\/96 100/precedence ::ffff:0:0\/96 100/' /etc/gai.conf || true
systemctl restart docker || true

echo "🚀 启动 Nginx Proxy Manager..."
# 尝试启动
docker-compose up -d

echo "✅ 安装完成！"
# 获取 IP 地址 (稍微优化了一下获取逻辑，使其更通用)
HOST_IP=$(hostname -I | awk '{print $1}')
echo "🔹 访问管理面板：http://${HOST_IP}:$PORT_PANEL"
echo "🔹 默认账号：admin@example.com / changeme"
