# EC2部署问题排查与解决方案

## 部署环境

- 系统：Ubuntu 24.04.2 LTS
- Python 版本：3.12.3
- Nginx 版本：1.24.0
- MCP 版本：1.9.1

## 主要问题及解决方案

### 1. 端口绑定问题

**问题描述**：
MCP 服务器在默认情况下绑定到 127.0.0.1 地址，导致无法从外部网络访问。

**解决方案**：
1. 修改 server.py 文件，确保服务绑定到 0.0.0.0 而非 127.0.0.1
2. 在启动命令中明确指定 `--host 0.0.0.0` 参数

**相关日志**：
```
INFO: Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

### 2. 端口冲突问题

**问题描述**：
端口 8000 被其他进程占用，导致服务无法启动。

**解决方案**：
1. 使用 `lsof -i :8000` 或 `ss -tulnp` 命令检查端口占用情况
2. 使用 `kill -9 <PID>` 终止占用进程
3. 或者使用不同的端口（如 8001）启动服务

**相关日志**：
```
错误: 端口 8000 已被进程 56674 占用
尝试终止占用进程...
错误: 无法释放端口 8000，仍被进程 56754 56664 占用
```

### 3. Nginx 配置问题

**问题描述**：
Nginx 配置文件语法错误或配置不正确，导致反向代理无法正常工作。

**解决方案**：
1. 使用 `nginx -t` 测试配置文件语法
2. 修复 mcp_html_server.conf 和 mcp_proxy.conf 配置文件中的语法错误
3. 确保 Nginx 监听正确的端口，并正确代理到 MCP 服务

**相关日志**：
```
2025/05/28 05:41:38 [emerg] 56848#56848: invalid PID number "" in "/run/nginx.pid"
2025/05/28 06:59:46 [emerg] 58822#58822: unexpected end of file, expecting ";" or "}" in /etc/nginx/conf.d/mcp_html_server.conf:24
```

### 4. 文件权限问题

**问题描述**：
HTML 文件权限不正确，导致 Nginx 无法访问。

**解决方案**：
1. 修改文件权限：`chmod -R 755 /home/ubuntu/quant_mcp/data/charts`
2. 更改文件所有权：`chown -R www-data:www-data /home/ubuntu/quant_mcp/data/charts`

**相关日志**：
```
HTTP/1.1 403 Forbidden
```

### 5. 防火墙配置问题

**问题描述**：
防火墙未开放相应端口，导致外部无法访问服务。

**解决方案**：
1. 使用 UFW 开放必要端口：`sudo ufw allow 8000` 和 `sudo ufw allow 8081`
2. 确保 AWS 安全组规则允许这些端口的入站流量

**相关命令**：
```
sudo ufw status
sudo ufw allow 8081
sudo ufw allow 8000
```

### 6. systemd 服务管理问题

**问题描述**：
systemd 服务配置不正确，导致服务无法正确启动或重启。

**解决方案**：
1. 正确配置 mcp.service 文件，确保 ExecStart 命令正确
2. 使用 `systemctl daemon-reload` 重新加载服务配置
3. 使用 `systemctl restart mcp` 重启服务

**相关日志**：
```
May 28 05:28:45 ip-172-31-88-57 systemd[1]: mcp.service: Main process exited, code=exited, status=143/n/a
May 28 05:28:45 ip-172-31-88-57 systemd[1]: mcp.service: Failed with result 'exit-code'.
```

### 7. Nginx 与 MCP 通信问题

**问题描述**：
Nginx 无法与 MCP 服务器通信，导致代理失败。

**解决方案**：
1. 确保 MCP 服务器绑定到正确的地址和端口
2. 配置正确的代理地址（使用 127.0.0.1 而非 localhost）
3. 配置必要的代理头信息和超时设置

**相关日志**：
```
2025/05/28 05:28:51 [error] 56152#56152: *763 recv() failed (104: Connection reset by peer) while reading response header from upstream
```

## 最终解决方案

经过多次调试和配置优化，最终通过以下关键步骤解决了部署问题：

1. 修改 server.py 确保绑定到 0.0.0.0 地址
2. 正确配置 Nginx 服务器块，分离静态文件服务和反向代理
3. 调整文件权限确保 Nginx 可以访问静态文件
4. 使用 systemd 管理服务，确保服务开机自启动和自动恢复
5. 配置正确的防火墙规则允许端口访问

最终确认服务可正常访问：
- MCP 服务器地址：http://<服务器IP>:8000
- MCP 服务器 SSE 端点：http://<服务器IP>:8000/sse
- HTML 服务器地址：http://<服务器IP>:8081
- 测试 HTML 页面：http://<服务器IP>:8081/charts/test.html 