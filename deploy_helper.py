#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
部署辅助工具

提供部署和维护MCP服务器的辅助功能
"""

import os
import sys
import socket
import subprocess
import platform
import logging
import json
from typing import Dict, Any, Optional, List, Tuple

# 设置基本日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("deploy_helper")

def get_local_ip() -> str:
    """获取本机IP地址"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception as e:
        logger.warning(f"获取本机IP地址失败: {e}")
        
        try:
            # 尝试获取所有非回环IP地址
            hostname = socket.gethostname()
            ip_list = socket.gethostbyname_ex(hostname)[2]
            for ip in ip_list:
                if not ip.startswith("127."):
                    return ip
        except Exception as e:
            logger.warning(f"获取主机名IP地址失败: {e}")
        
        # 如果仍然失败，尝试使用ifconfig或ipconfig
        system = platform.system()
        try:
            if system == "Darwin" or system == "Linux":  # macOS or Linux
                cmd = "ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1"
                ip = subprocess.check_output(cmd, shell=True).decode().strip()
                if ip:
                    return ip
            elif system == "Windows":
                cmd = "ipconfig | findstr /i \"IPv4\" | findstr /v \"127.0.0.1\" | findstr /v \"IPv4\" | findstr /v \"::\" | more +2"
                output = subprocess.check_output(cmd, shell=True).decode()
                ip = output.strip().split(":")[-1].strip()
                if ip:
                    return ip
        except Exception as e:
            logger.warning(f"通过系统命令获取IP地址失败: {e}")
    
    return "localhost"

def check_python_version() -> Tuple[bool, str]:
    """检查Python版本"""
    try:
        # 获取Python版本
        version = sys.version.split()[0]
        logger.info(f"Python版本: {version}")
        
        # 检查是否是Python 3.6+
        if sys.version_info.major >= 3 and sys.version_info.minor >= 6:
            return True, version
        else:
            return False, version
    except Exception as e:
        logger.error(f"检查Python版本失败: {e}")
        return False, "未知"

def update_server_config():
    """更新服务器配置"""
    try:
        # 获取本机IP
        local_ip = get_local_ip()
        logger.info(f"本机IP: {local_ip}")
        
        # 更新环境变量
        os.environ["MCP_SERVER_HOST"] = local_ip
        os.environ["MCP_LOCAL_IP"] = local_ip
        
        # 尝试更新配置文件
        config_dir = "data/config"
        os.makedirs(config_dir, exist_ok=True)
        
        # HTML服务器配置
        html_config_file = os.path.join(config_dir, "html_server.json")
        html_config = {
            "server_host": local_ip,
            "server_port": 8081,
            "charts_dir": "data/charts",
            "use_ec2_metadata": True,
            "use_public_ip": True
        }
        
        with open(html_config_file, 'w') as f:
            json.dump(html_config, f, indent=2)
        logger.info(f"HTML服务器配置已更新: {html_config_file}")
        
        # 确保日志目录存在
        logs_dir = "data/logs"
        os.makedirs(logs_dir, exist_ok=True)
        
        # 确保charts目录存在
        charts_dir = "data/charts"
        os.makedirs(charts_dir, exist_ok=True)
        
        print(f"服务器配置已更新，本机IP: {local_ip}")
        print(f"HTML服务器将在 http://{local_ip}:8081 上运行")
        print(f"MCP服务器将在 http://{local_ip}:8000 上运行")
        
        return True
    except Exception as e:
        logger.error(f"更新服务器配置失败: {e}")
        return False

def fix_nginx_config():
    """修复Nginx配置"""
    try:
        # 获取系统类型
        system = platform.system()
        
        # 获取本机IP
        local_ip = get_local_ip()
        
        # 检查Nginx是否安装
        try:
            result = subprocess.run(['nginx', '-v'], capture_output=True, text=True)
            nginx_installed = result.returncode == 0
        except:
            nginx_installed = False
        
        if not nginx_installed:
            logger.warning("Nginx未安装，跳过配置")
            print("Nginx未安装，跳过配置")
            return False
        
        # 生成Nginx配置
        nginx_config = f"""
# MCP HTML服务器配置
server {{
    listen 8081;
    server_name _;

    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

    # 禁止访问隐藏文件
    location ~ /\\. {{
        deny all;
    }}

    # 静态文件服务
    location /charts/ {{
        alias {os.path.abspath("data/charts")}/;

        # 只允许访问HTML文件
        location ~* \\.(html)$ {{
            add_header Content-Type text/html;
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            # 允许跨域访问
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        }}

        # 禁止目录列表
        autoindex off;

        # 禁止访问其他类型的文件
        location ~* \\.(php|py|js|json|txt|log|ini|conf)$ {{
            deny all;
        }}
    }}

    # 默认页面 - 生成一个测试页面
    location = / {{
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p><p>当前时间: <span id="time"></span></p><script>document.getElementById("time").textContent = new Date().toLocaleString();</script></body></html>';
        add_header Content-Type text/html;
    }}
}}
"""
        
        # 根据系统确定配置路径
        if system == "Darwin":  # macOS
            config_path = "/opt/homebrew/etc/nginx/servers/mcp_html_server.conf"
        elif system == "Linux":
            config_path = "/etc/nginx/conf.d/mcp_html_server.conf"
        else:
            config_path = "mcp_html_server.conf"
        
        # 保存配置文件
        try:
            with open(config_path, 'w') as f:
                f.write(nginx_config)
            logger.info(f"Nginx配置已保存: {config_path}")
        except PermissionError:
            # 如果没有权限，保存到当前目录
            config_path = "mcp_html_server.conf"
            with open(config_path, 'w') as f:
                f.write(nginx_config)
            logger.warning(f"无权限写入Nginx配置目录，已保存到: {config_path}")
            print(f"无权限写入Nginx配置目录，请手动将以下文件复制到Nginx配置目录: {config_path}")
            return False
        
        # 测试配置
        try:
            result = subprocess.run(['nginx', '-t'], capture_output=True, text=True)
            if result.returncode != 0:
                logger.error(f"Nginx配置测试失败: {result.stderr}")
                print(f"Nginx配置测试失败: {result.stderr}")
                return False
            logger.info("Nginx配置测试成功")
        except Exception as e:
            logger.error(f"Nginx配置测试失败: {e}")
            print(f"Nginx配置测试失败: {e}")
            return False
        
        # 重新加载Nginx
        try:
            if system == "Darwin":  # macOS
                result = subprocess.run(['brew', 'services', 'reload', 'nginx'], capture_output=True, text=True)
            else:
                result = subprocess.run(['nginx', '-s', 'reload'], capture_output=True, text=True)
            
            if result.returncode != 0:
                logger.error(f"重新加载Nginx失败: {result.stderr}")
                print(f"重新加载Nginx失败: {result.stderr}")
                return False
            logger.info("Nginx已重新加载")
            print("Nginx配置已更新并重新加载")
        except Exception as e:
            logger.error(f"重新加载Nginx失败: {e}")
            print(f"重新加载Nginx失败: {e}")
            return False
        
        # 生成测试HTML文件
        test_html_path = os.path.join("data/charts", "test.html")
        os.makedirs(os.path.dirname(test_html_path), exist_ok=True)
        
        with open(test_html_path, 'w') as f:
            f.write(f"""
<!DOCTYPE html>
<html>
<head>
    <title>MCP HTML服务器测试</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }}
        .container {{ max-width: 800px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }}
        .success {{ color: green; }}
        .info {{ color: blue; }}
        .server-info {{ background-color: #f8f9fa; padding: 10px; border-radius: 5px; margin-top: 20px; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>MCP HTML服务器测试</h1>
        <p class="success">如果您看到此页面，说明HTML服务器配置成功。</p>

        <div class="server-info">
            <h2>服务器信息</h2>
            <p><strong>主机地址:</strong> {local_ip}</p>
            <p><strong>端口:</strong> 8081</p>
            <p><strong>生成时间:</strong> <span id="time"></span></p>
            <p><strong>客户端IP:</strong> <span id="client-ip">正在获取...</span></p>
        </div>

        <script>
            document.getElementById('time').textContent = new Date().toLocaleString();

            // 尝试获取客户端IP
            fetch('https://api.ipify.org?format=json')
                .then(response => response.json())
                .then(data => {{
                    document.getElementById('client-ip').textContent = data.ip;
                }})
                .catch(error => {{
                    document.getElementById('client-ip').textContent = '无法获取';
                }});
        </script>
    </div>
</body>
</html>
""")
        
        test_url = f"http://{local_ip}:8081/charts/test.html"
        logger.info(f"测试HTML文件已生成: {test_html_path}")
        logger.info(f"测试URL: {test_url}")
        print(f"测试HTML文件已生成: {test_url}")
        
        return True
    except Exception as e:
        logger.error(f"修复Nginx配置失败: {e}")
        print(f"修复Nginx配置失败: {e}")
        return False

def generate_test_html():
    """生成测试HTML文件"""
    try:
        # 获取本机IP
        local_ip = get_local_ip()
        
        # 生成测试HTML文件
        test_html_path = os.path.join("data/charts", "test.html")
        os.makedirs(os.path.dirname(test_html_path), exist_ok=True)
        
        with open(test_html_path, 'w') as f:
            f.write(f"""
<!DOCTYPE html>
<html>
<head>
    <title>MCP HTML服务器测试</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }}
        .container {{ max-width: 800px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }}
        .success {{ color: green; }}
        .info {{ color: blue; }}
        .server-info {{ background-color: #f8f9fa; padding: 10px; border-radius: 5px; margin-top: 20px; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>MCP HTML服务器测试</h1>
        <p class="success">如果您看到此页面，说明HTML服务器配置成功。</p>

        <div class="server-info">
            <h2>服务器信息</h2>
            <p><strong>主机地址:</strong> {local_ip}</p>
            <p><strong>端口:</strong> 8081</p>
            <p><strong>生成时间:</strong> <span id="time"></span></p>
            <p><strong>客户端IP:</strong> <span id="client-ip">正在获取...</span></p>
        </div>

        <script>
            document.getElementById('time').textContent = new Date().toLocaleString();

            // 尝试获取客户端IP
            fetch('https://api.ipify.org?format=json')
                .then(response => response.json())
                .then(data => {{
                    document.getElementById('client-ip').textContent = data.ip;
                }})
                .catch(error => {{
                    document.getElementById('client-ip').textContent = '无法获取';
                }});
        </script>
    </div>
</body>
</html>
""")
        
        test_url = f"http://{local_ip}:8081/charts/test.html"
        logger.info(f"测试HTML文件已生成: {test_html_path}")
        logger.info(f"测试URL: {test_url}")
        
        print(f"测试HTML文件已生成")
        print(f"测试URL: {test_url}")
        
        return test_url
    except Exception as e:
        logger.error(f"生成测试HTML文件失败: {e}")
        print(f"生成测试HTML文件失败: {e}")
        return None

def print_server_info():
    """打印服务器信息"""
    try:
        # 获取本机IP
        local_ip = get_local_ip()
        
        # 打印服务器信息
        print("\n服务器信息:")
        print(f"本机IP: {local_ip}")
        print(f"MCP服务器地址: http://{local_ip}:8000")
        print(f"MCP服务器SSE端点: http://{local_ip}:8000/sse")
        print(f"HTML服务器地址: http://{local_ip}:8081")
        print(f"测试HTML页面: http://{local_ip}:8081/charts/test.html")
        
        # 检查Python版本
        python_ok, python_version = check_python_version()
        print(f"Python版本: {python_version} {'(OK)' if python_ok else '(需要Python 3.6+)'}")
        
        # 检查Nginx
        try:
            result = subprocess.run(['nginx', '-v'], capture_output=True, text=True)
            nginx_installed = result.returncode == 0
            print(f"Nginx状态: {'已安装' if nginx_installed else '未安装'}")
        except:
            print("Nginx状态: 未安装")
        
        # 检查目录
        print("\n目录信息:")
        dirs = ["data/logs", "data/charts", "data/config", "data/klines", "data/temp", "data/backtest", "data/templates"]
        for d in dirs:
            print(f"{d}: {'已存在' if os.path.exists(d) else '不存在'}")
        
        return True
    except Exception as e:
        logger.error(f"打印服务器信息失败: {e}")
        print(f"打印服务器信息失败: {e}")
        return False

def start_server(transport='sse', host='0.0.0.0', port=8000):
    """启动MCP服务器"""
    try:
        # 获取本机IP
        local_ip = get_local_ip()
        
        # 设置环境变量
        os.environ["MCP_SERVER_HOST"] = local_ip
        os.environ["MCP_LOCAL_IP"] = local_ip
        
        # 构建命令
        python_cmd = sys.executable  # 使用当前Python解释器
        cmd = [python_cmd, "server.py", "--transport", transport, "--host", host, "--port", str(port)]
        
        print(f"启动MCP服务器，命令: {' '.join(cmd)}")
        print(f"服务将在 http://{local_ip}:{port} 上运行")
        if transport == 'sse':
            print(f"SSE端点: http://{local_ip}:{port}/sse")
        elif transport == 'streamable-http':
            print(f"HTTP端点: http://{local_ip}:{port}/mcp")
        
        # 执行命令
        subprocess.run(cmd)
        
        return True
    except Exception as e:
        logger.error(f"启动MCP服务器失败: {e}")
        print(f"启动MCP服务器失败: {e}")
        return False

def main():
    """主函数"""
    if len(sys.argv) < 2:
        print("用法: python3 deploy_helper.py [命令]")
        print("可用命令:")
        print("  info       - 显示服务器信息")
        print("  config     - 更新服务器配置")
        print("  nginx      - 修复Nginx配置")
        print("  html       - 生成测试HTML文件")
        print("  start      - 启动MCP服务器")
        print("  setup      - 执行完整设置 (config + nginx + html)")
        print("  deploy     - 执行完整部署 (setup + start)")
        return
    
    cmd = sys.argv[1]
    
    if cmd == "info":
        print_server_info()
    elif cmd == "config":
        update_server_config()
    elif cmd == "nginx":
        fix_nginx_config()
    elif cmd == "html":
        generate_test_html()
    elif cmd == "start":
        transport = sys.argv[2] if len(sys.argv) > 2 else 'sse'
        port = int(sys.argv[3]) if len(sys.argv) > 3 else 8000
        start_server(transport=transport, port=port)
    elif cmd == "setup":
        update_server_config()
        fix_nginx_config()
        generate_test_html()
        print_server_info()
    elif cmd == "deploy":
        update_server_config()
        fix_nginx_config()
        generate_test_html()
        print_server_info()
        transport = sys.argv[2] if len(sys.argv) > 2 else 'sse'
        port = int(sys.argv[3]) if len(sys.argv) > 3 else 8000
        start_server(transport=transport, port=port)
    else:
        print(f"未知命令: {cmd}")

if __name__ == "__main__":
    main() 