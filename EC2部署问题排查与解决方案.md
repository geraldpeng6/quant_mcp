# MCP服务器EC2部署问题排查与解决方案

## 问题概述

在AWS EC2实例上部署MCP服务器时，遇到了以下关键问题：

1. **端口绑定问题**：服务器绑定到了`127.0.0.1`而不是`0.0.0.0`，导致只能在服务器本地访问
2. **systemd服务配置错误**：复杂的Python命令在systemd服务文件中的引号嵌套导致语法错误
3. **Nginx权限问题**：Nginx无法访问`data/charts`目录中的HTML文件
4. **函数定义顺序问题**：`get_public_ip`函数在被调用前未定义
5. **防火墙配置不完整**：虽然AWS安全组已配置，但本地防火墙设置未完成

## 问题诊断过程

### 1. 初始状态检查

使用`rustscan`工具扫描EC2实例，发现只有SSH端口(22)是开放的，而我们的服务端口(8000和8081)不可访问：

```
Open 54.173.115.4:22
```

### 2. 服务状态检查

检查MCP服务和Nginx状态，发现它们都处于`inactive`状态：

```
● mcp.service - MCP Server
     Active: inactive (dead)
     
● nginx.service - A high performance web server and a reverse proxy server
     Active: inactive (dead)
```

### 3. 启动服务后的问题

启动服务后，发现MCP服务仍然绑定到`127.0.0.1`而不是`0.0.0.0`：

```
INFO: Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

### 4. 深入问题分析

使用`ss -tulpn`命令检查端口绑定情况，确认了MCP服务确实只绑定到了本地回环地址：

```
tcp   LISTEN 0  2048  127.0.0.1:8000  0.0.0.0:*
```

Nginx日志显示权限问题：

```
open() "/home/ubuntu/quant_mcp/data/charts/test.html" failed (13: Permission denied)
```

## 解决方案

### 1. 修复服务绑定问题

通过两种方式解决绑定问题：

1. **直接修改server.py**：
   找到并修改硬编码的主机地址：
   ```python
   # 原代码
   uvicorn.run(app, host="127.0.0.1", port=port)
   
   # 修改为
   uvicorn.run(app, host="0.0.0.0", port=port)
   ```

2. **创建启动脚本**：
   ```bash
   #!/bin/bash
   # 设置必要的环境变量
   export MCP_ENV="production"
   export MCP_SERVER_HOST="0.0.0.0"
   export UVICORN_HOST="0.0.0.0"
   export HOST="0.0.0.0"
   export BIND="0.0.0.0"

   # 激活虚拟环境
   source "$CURRENT_DIR/.venv/bin/activate"

   # 启动服务器，明确指定主机为0.0.0.0
   python "$CURRENT_DIR/server.py" --transport "$TRANSPORT" --host 0.0.0.0 --port $PORT
   ```

### 2. 修复systemd服务配置

将复杂的内联Python代码替换为简单的shell脚本调用：

```
[Unit]
Description=MCP Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/quant_mcp
ExecStart=/home/ubuntu/quant_mcp/start_mcp.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

### 3. 修复Nginx权限问题

```bash
# 修复目录权限
sudo chmod 755 ~/quant_mcp/data
sudo chmod 755 ~/quant_mcp/data/charts
sudo chmod 644 ~/quant_mcp/data/charts/test.html

# 将Nginx用户添加到你的用户组
sudo usermod -a -G ubuntu www-data

# 或者更改文件所有权
sudo chown -R www-data:www-data ~/quant_mcp/data/charts
```

### 4. 修复函数定义顺序

确保`get_public_ip`函数在脚本开始部分定义，避免"command not found"错误。

### 5. 配置本地防火墙

```bash
sudo ufw allow 8000/tcp
sudo ufw allow 8081/tcp
sudo ufw enable
```

## 验证解决方案

完成上述修复后，服务正常运行：

1. MCP服务器绑定到`0.0.0.0:8000`
2. Nginx服务器绑定到`0.0.0.0:8081`
3. 外部可以通过公网IP访问两个服务

## 经验教训与最佳实践

1. **始终绑定到0.0.0.0**：在服务器应用中，除非有特殊安全需求，否则应始终绑定到`0.0.0.0`
2. **使用独立脚本**：对于复杂的启动命令，使用独立脚本而不是直接在systemd文件中编写
3. **权限检查**：确保Web服务器对静态文件有正确的读取权限
4. **多层检查**：同时检查云平台安全组、本地防火墙、服务绑定和应用配置
5. **使用故障诊断工具**：添加综合性的故障诊断脚本，快速识别和解决问题

## 总结

EC2部署问题主要涉及网络绑定、服务配置和权限设置三个方面。通过系统的排查和合理的配置，我们成功解决了所有问题，使MCP服务器能够在EC2实例上正常运行并对外提供服务。这些经验对于部署其他类型的服务到云平台也有重要的参考价值。 