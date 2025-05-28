# MCP服务器部署问题修复总结

## 核心问题

MCP服务器部署在EC2实例上时，存在以下主要问题：
1. **端口绑定问题**：服务默认只绑定到127.0.0.1，导致外部无法访问
2. **配置文件不一致**：多个配置文件需要协同修改
3. **权限问题**：静态文件权限不正确
4. **服务管理问题**：缺乏持久化的服务配置

## 有效的修复操作

### 1. 修改服务器绑定地址

最关键的修复是将服务器绑定地址从127.0.0.1修改为0.0.0.0：

```python
# 在FastMCP初始化时显式传入host参数
mcp = FastMCP(name, host="0.0.0.0")

# 确保运行时使用正确的地址
run_server(transport=args.transport, host="0.0.0.0", port=args.port)
```

### 2. 设置关键环境变量

确保设置了正确的环境变量：

```bash
# FastMCP库使用的环境变量
export FASTMCP_HOST=0.0.0.0
export FASTMCP_PORT=8000

# 兼容性环境变量
export MCP_SSE_HOST=0.0.0.0
export MCP_SSE_PORT=8000
```

### 3. 正确配置Nginx

创建正确的Nginx配置，确保代理和静态文件服务：

```nginx
server {
    listen 8081;
    server_name _;
    
    # 静态文件服务
    location /charts/ {
        alias /path/to/quant_mcp/data/charts/;
        # 允许跨域等配置...
    }
    
    # 代理SSE请求
    location /sse {
        proxy_pass http://127.0.0.1:8000/sse;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_buffering off;
    }
}
```

### 4. 修复文件权限

确保Nginx可以访问静态文件：

```bash
chmod -R 755 /home/ubuntu/quant_mcp/data/charts
chown -R www-data:www-data /home/ubuntu/quant_mcp/data/charts
```

### 5. 创建systemd服务

创建systemd服务确保服务持久运行：

```ini
[Unit]
Description=MCP Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/quant_mcp
Environment=MCP_ENV=production
Environment=FASTMCP_HOST=0.0.0.0
Environment=MCP_SSE_HOST=0.0.0.0
ExecStart=/home/ubuntu/quant_mcp/.venv/bin/python server.py --transport sse --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

## 同步到启动脚本

项目中的`deploy_start.sh`脚本已经包含了所有必要的修复操作。以下是如何使用该脚本进行部署：

### 1. 基本部署

```bash
# 部署并启动服务
sudo ./deploy_start.sh -d
```

### 2. 重新部署（应用所有修复）

```bash
# 重新部署，应用所有修复
sudo ./deploy_start.sh --redeploy
```

### 3. 自定义端口

```bash
# 使用自定义端口
sudo ./deploy_start.sh -d -p 8001 --html-port 8082
```

### 4. 验证部署

部署完成后，可以通过以下方式验证：

```bash
# 检查服务状态
sudo systemctl status mcp

# 检查端口监听
sudo ss -tulnp | grep '8000\|8081'

# 测试连接
curl http://localhost:8000/sse
curl http://localhost:8081/charts/test.html
```

## 确保修复永久生效

为确保修复永久生效，`deploy_start.sh`脚本执行了以下关键操作：

1. **修补server.py文件**：通过`patch_server_py`函数确保服务器绑定到0.0.0.0
2. **创建systemd服务**：通过`create_systemd_service`函数创建自启动服务
3. **配置Nginx**：通过`setup_nginx_improved`函数配置Nginx代理
4. **设置文件权限**：通过`generate_test_html`函数确保正确的文件权限

无需手动修改，使用`--redeploy`参数即可应用所有修复。 