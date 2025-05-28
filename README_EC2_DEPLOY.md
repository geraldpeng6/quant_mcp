# MCP服务器EC2部署指南

本文档提供了将MCP服务器部署到AWS EC2实例的详细步骤，包括配置HTML服务器以通过外部IP访问。

## 目录

1. [准备工作](#准备工作)
2. [EC2实例设置](#ec2实例设置)
3. [部署MCP服务器](#部署mcp服务器)
4. [配置HTML服务器](#配置html服务器)
5. [测试部署](#测试部署)
6. [故障排除](#故障排除)
7. [本地测试](#本地测试)

## 准备工作

### 所需资源

- AWS账号
- EC2实例（推荐使用Ubuntu Server 20.04 LTS或更高版本）
- 基本的Linux命令行知识

### 所需软件

- Python 3.8+
- Nginx
- Git

## EC2实例设置

### 1. 创建EC2实例

1. 登录AWS管理控制台
2. 导航到EC2服务
3. 点击"启动实例"
4. 选择Ubuntu Server 20.04 LTS (或更高版本)
5. 选择实例类型（推荐至少t2.micro）
6. 配置实例详细信息
7. 添加存储（推荐至少20GB）
8. 添加标签（可选）
9. 配置安全组，开放以下端口：
   - SSH (22)
   - HTTP (80)
   - HTTPS (443)
   - MCP服务器端口 (8000)
   - HTML服务器端口 (8081)
10. 启动实例并下载密钥对

### 2. 连接到EC2实例

```bash
ssh -i your-key.pem ubuntu@your-ec2-public-ip
```

### 3. 更新系统

```bash
sudo apt update
sudo apt upgrade -y
```

## 部署MCP服务器

### 1. 克隆代码库

```bash
git clone https://github.com/your-username/quant_mcp.git
cd quant_mcp
```

### 2. 使用部署脚本

我们提供了一个自动化部署脚本，可以简化部署过程：

```bash
chmod +x deploy_ec2.sh
./deploy_ec2.sh
```

这个脚本会自动执行以下操作：
- 安装系统依赖
- 设置Python虚拟环境
- 配置HTML服务器
- 配置Nginx
- 创建systemd服务
- 启动服务

### 3. 手动部署（如果自动部署脚本失败）

#### 安装依赖

```bash
sudo apt install -y python3 python3-pip python3-venv nginx curl git
```

#### 设置Python虚拟环境

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

#### 配置HTML服务器

```bash
mkdir -p data/config
cat > data/config/html_server.json << EOF
{
    "server_port": 8081,
    "charts_dir": "data/charts",
    "use_ec2_metadata": true,
    "use_public_ip": true
}
EOF
```

#### 配置Nginx

```bash
export MCP_ENV="production"
python -c "
import sys
sys.path.append('.')
from utils.html_server import setup_nginx
success, message = setup_nginx()
print(message)
"
```

#### 创建systemd服务

```bash
sudo bash -c "cat > /etc/systemd/system/mcp.service << EOF
[Unit]
Description=MCP Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
Environment=MCP_ENV=production
ExecStart=$(pwd)/.venv/bin/python server.py --transport sse --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable mcp.service
```

#### 启动服务

```bash
sudo systemctl restart nginx
sudo systemctl start mcp.service
```

## 配置HTML服务器

HTML服务器配置文件位于`data/config/html_server.json`，可以根据需要进行修改：

```json
{
    "server_host": null,
    "server_port": 8081,
    "charts_dir": "data/charts",
    "use_ec2_metadata": true,
    "use_public_ip": true
}
```

- `server_host`: 服务器主机地址，`null`表示自动检测，也可以手动指定
- `server_port`: 服务器端口，默认为8081
- `charts_dir`: 图表目录，默认为"data/charts"
- `use_ec2_metadata`: 是否使用EC2元数据服务获取公网IP，默认为true
- `use_public_ip`: 是否使用公网IP服务获取公网IP，默认为true

## 测试部署

### 1. 检查服务状态

```bash
sudo systemctl status nginx
sudo systemctl status mcp.service
```

### 2. 测试HTML服务器

在浏览器中访问：

```
http://your-ec2-public-ip:8081/charts/test.html
```

如果一切正常，你应该能看到一个测试页面，显示服务器信息。

### 3. 测试MCP服务器

根据你使用的传输协议，可以通过以下URL访问MCP服务器：

- SSE: `http://your-ec2-public-ip:8000/sse`
- Streamable HTTP: `http://your-ec2-public-ip:8000/mcp`

## 故障排除

### 1. 检查日志

```bash
# 检查Nginx日志
sudo tail -f /var/log/nginx/error.log

# 检查MCP服务日志
sudo journalctl -u mcp.service -f
```

### 2. 检查防火墙

确保EC2安全组已开放必要的端口：

- SSH (22)
- HTTP (80)
- HTTPS (443)
- MCP服务器端口 (8000)
- HTML服务器端口 (8081)

### 3. 检查Nginx配置

```bash
sudo nginx -t
```

### 4. 解决文件权限问题

如果遇到"Permission denied"错误，可以尝试以下步骤：

```bash
# 设置正确的文件权限
sudo chmod -R 755 /home/ubuntu/quant_mcp/data/charts
sudo chmod 644 /home/ubuntu/quant_mcp/data/charts/test.html

# 确保目录路径上的所有目录都有执行权限
sudo chmod 755 /home/ubuntu
sudo chmod 755 /home/ubuntu/quant_mcp
sudo chmod 755 /home/ubuntu/quant_mcp/data

# 将文件所有权更改为Nginx用户
sudo chown -R www-data:www-data /home/ubuntu/quant_mcp/data/charts

# 重启Nginx
sudo systemctl restart nginx
```

### 5. 手动重启服务

```bash
sudo systemctl restart nginx
sudo systemctl restart mcp.service
```

## 本地测试

在将MCP服务器部署到EC2之前，你可以在本地macOS环境中模拟EC2环境进行测试：

```bash
chmod +x test_ec2_mode.sh
./test_ec2_mode.sh
```

这个脚本会：
- 创建一个模拟的EC2元数据服务
- 配置HTML服务器使用模拟的EC2公网IP
- 配置本地Nginx
- 启动MCP服务器

测试完成后，可以使用以下命令停止测试环境：

```bash
./stop_ec2_test.sh
```

## 更多信息

- [MCP服务器文档](README.md)
- [传输协议说明](README_TRANSPORT.md)
