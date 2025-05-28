#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
HTML服务器工具模块

提供HTML文件服务器相关的功能，包括URL生成和Nginx配置
支持在EC2等云服务器环境中部署和访问
"""

import os
import logging
import socket
import requests
import subprocess
import json
from typing import Optional, Tuple, Dict, Any

from utils.logging_utils import setup_logging, log_exception

# 获取日志记录器
logger = setup_logging('quant_mcp.html_server')

# 默认配置
DEFAULT_SERVER_PORT = 8081  # 本地开发环境使用8081端口
DEFAULT_CHARTS_DIR = "data/charts"
DEFAULT_SERVER_HOST = None  # 将在运行时确定
DEFAULT_CONFIG_FILE = "data/config/html_server.json"  # HTML服务器配置文件


def load_config() -> Dict[str, Any]:
    """
    加载HTML服务器配置

    从配置文件加载HTML服务器配置，如果配置文件不存在则返回默认配置

    Returns:
        Dict[str, Any]: HTML服务器配置
    """
    # 默认配置
    config = {
        "server_host": None,  # 自动检测
        "server_port": DEFAULT_SERVER_PORT,
        "charts_dir": DEFAULT_CHARTS_DIR,
        "use_ec2_metadata": True,  # 是否使用EC2元数据
        "use_public_ip": True,  # 是否使用公网IP
    }

    # 检查配置文件是否存在
    if os.path.exists(DEFAULT_CONFIG_FILE):
        try:
            with open(DEFAULT_CONFIG_FILE, 'r') as f:
                user_config = json.load(f)
                # 更新配置
                config.update(user_config)
                logger.info(f"已加载HTML服务器配置: {DEFAULT_CONFIG_FILE}")
        except Exception as e:
            log_exception(logger, f"加载HTML服务器配置失败")
            logger.warning(f"使用默认配置")

    return config


def get_ec2_metadata() -> Optional[str]:
    """
    获取EC2实例元数据

    尝试从EC2元数据服务获取实例的公网IP

    Returns:
        Optional[str]: EC2实例的公网IP，如果获取失败则返回None
    """
    try:
        # EC2元数据服务的URL
        # 参考: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
        metadata_url = "http://169.254.169.254/latest/meta-data/public-ipv4"
        response = requests.get(metadata_url, timeout=2)
        if response.status_code == 200:
            public_ip = response.text.strip()
            logger.info(f"从EC2元数据服务获取到公网IP: {public_ip}")
            return public_ip
    except Exception as e:
        logger.debug(f"获取EC2元数据失败: {e}")

    return None


def get_server_host() -> str:
    """
    获取服务器主机地址

    按以下顺序尝试获取服务器主机地址:
    1. 从环境变量MCP_SERVER_HOST获取
    2. 从配置文件获取
    3. 尝试从多个公网IP服务获取
    4. 尝试获取本地IP
    5. 如果以上都失败，返回localhost

    Returns:
        str: 服务器主机地址
    """
    # 1. 从环境变量获取
    env_host = os.environ.get('MCP_SERVER_HOST')
    if env_host:
        logger.info(f"从环境变量获取服务器主机地址: {env_host}")
        return env_host

    # 2. 从配置文件获取
    config = load_config()
    if config.get('server_host'):
        logger.info(f"从配置文件获取服务器主机地址: {config['server_host']}")
        return config['server_host']

    # 检查是否是生产环境
    is_production = os.environ.get('MCP_ENV') == 'production'

    # 3. 尝试从多个公网IP服务获取
    if is_production and config.get('use_public_ip', True):
        # 公网IP服务列表
        ip_services = [
            'https://api.ipify.org',
            'https://ifconfig.me',
            'https://checkip.amazonaws.com',
            'https://icanhazip.com',
            'https://ipecho.net/plain'
        ]
        
        # EC2元数据服务
        if config.get('use_ec2_metadata', True):
            ip_services.insert(0, 'http://169.254.169.254/latest/meta-data/public-ipv4')
        
        # 尝试每个服务
        for service in ip_services:
            try:
                response = requests.get(service, timeout=3)
                if response.status_code == 200:
                    public_ip = response.text.strip()
                    logger.info(f"从 {service} 获取到公网IP: {public_ip}")
                    return public_ip
            except Exception as e:
                logger.debug(f"从 {service} 获取公网IP失败: {e}")
                continue

    # 4. 尝试获取本地IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # 使用多个DNS服务器尝试连接
        dns_servers = ["8.8.8.8", "1.1.1.1", "114.114.114.114", "208.67.222.222"]
        
        for dns in dns_servers:
            try:
                s.connect((dns, 53))
                local_ip = s.getsockname()[0]
                s.close()
                logger.info(f"获取到本地IP: {local_ip}")
                return local_ip
            except:
                continue
        
        # 如果所有DNS服务器都失败，尝试一个备用方法
        import subprocess
        
        # 获取操作系统类型
        import platform
        system = platform.system()
        
        if system == "Darwin" or system == "Linux":  # macOS or Linux
            try:
                # 使用ifconfig命令
                cmd = "ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1"
                local_ip = subprocess.check_output(cmd, shell=True).decode().strip()
                if local_ip:
                    logger.info(f"通过ifconfig获取到本地IP: {local_ip}")
                    return local_ip
            except:
                pass
        elif system == "Windows":
            try:
                # 使用ipconfig命令
                cmd = "ipconfig | findstr /i \"IPv4\" | findstr /v \"127.0.0.1\" | findstr /v \"IPv4\" | findstr /v \"::\" | more +2"
                output = subprocess.check_output(cmd, shell=True).decode()
                local_ip = output.strip().split(":")[-1].strip()
                if local_ip:
                    logger.info(f"通过ipconfig获取到本地IP: {local_ip}")
                    return local_ip
            except:
                pass
    except Exception as e:
        logger.warning(f"获取本地IP失败: {e}")

    # 5. 如果以上都失败，返回localhost
    logger.info("无法获取服务器IP，使用localhost")
    return "localhost"


def get_html_url(file_path: str) -> str:
    """
    根据文件路径生成HTML文件的URL

    Args:
        file_path: HTML文件的本地路径

    Returns:
        str: HTML文件的URL
    """
    global DEFAULT_SERVER_HOST

    # 加载配置
    config = load_config()

    # 如果主机地址未初始化，则获取
    if DEFAULT_SERVER_HOST is None:
        DEFAULT_SERVER_HOST = get_server_host()

    # 获取服务器端口
    server_port = config.get('server_port', DEFAULT_SERVER_PORT)

    # 获取charts目录
    charts_dir = os.path.abspath(config.get('charts_dir', DEFAULT_CHARTS_DIR))

    # 确保文件路径是绝对路径
    abs_file_path = os.path.abspath(file_path)

    # 检查文件是否在charts目录下
    if not abs_file_path.startswith(charts_dir):
        logger.error(f"文件不在charts目录下: {abs_file_path}")
        return f"file://{abs_file_path}"  # 如果不在charts目录下，返回本地文件URL

    # 提取相对路径
    rel_path = os.path.relpath(abs_file_path, charts_dir)

    # 构建URL
    url = f"http://{DEFAULT_SERVER_HOST}:{server_port}/charts/{rel_path}"
    logger.debug(f"生成HTML URL: {url}")

    return url


def generate_nginx_config() -> Tuple[bool, str]:
    """
    生成Nginx配置文件

    Returns:
        Tuple[bool, str]: 是否成功和配置文件内容或错误信息
    """
    # 加载配置
    config = load_config()

    # 获取服务器端口
    server_port = config.get('server_port', DEFAULT_SERVER_PORT)

    # 获取charts目录
    charts_dir = os.path.abspath(config.get('charts_dir', DEFAULT_CHARTS_DIR))

    # 检查是否是EC2环境
    is_ec2 = os.environ.get('MCP_ENV') == 'production' and config.get('use_ec2_metadata', True)

    # 生成Nginx配置
    nginx_config = f"""
# MCP HTML服务器配置
server {{
    listen {server_port};
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
        alias {charts_dir}/;

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
    return True, nginx_config


def setup_nginx() -> Tuple[bool, str]:
    """
    设置Nginx配置

    Returns:
        Tuple[bool, str]: 是否成功和成功/错误信息
    """
    try:
        # 加载配置
        user_config = load_config()

        # 生成配置
        success, nginx_config = generate_nginx_config()
        if not success:
            return False, nginx_config

        # 检测操作系统和环境
        import platform
        system = platform.system()

        # 检查是否是EC2环境
        is_ec2 = os.environ.get('MCP_ENV') == 'production' and user_config.get('use_ec2_metadata', True)

        # 根据不同操作系统设置不同的配置路径
        if system == 'Darwin':  # macOS
            config_path = "/opt/homebrew/etc/nginx/servers/mcp_html_server.conf"
        elif system == 'Linux':
            if is_ec2:
                # EC2环境
                config_path = "/etc/nginx/conf.d/mcp_html_server.conf"
            elif os.environ.get('MCP_ENV') == 'production':
                # 其他生产环境
                config_path = "/etc/nginx/conf.d/mcp_html_server.conf"
            else:
                # 本地Linux开发环境
                config_path = "/etc/nginx/conf.d/mcp_html_server.conf"
        else:
            return False, f"不支持的操作系统: {system}"

        # 保存配置文件
        try:
            with open(config_path, 'w') as f:
                f.write(nginx_config)
            logger.info(f"Nginx配置已保存到: {config_path}")
        except PermissionError:
            logger.warning(f"无权限写入配置文件: {config_path}，尝试使用临时文件")
            # 如果没有权限，则保存到当前目录
            with open("mcp_html_server.conf", 'w') as f:
                f.write(nginx_config)
            return False, f"无权限写入配置文件: {config_path}，已保存到当前目录的mcp_html_server.conf文件，请手动复制到Nginx配置目录"

        # 测试配置
        try:
            result = subprocess.run(['nginx', '-t'], capture_output=True, text=True)
            if result.returncode != 0:
                return False, f"Nginx配置测试失败: {result.stderr}"
            logger.info("Nginx配置测试成功")
        except Exception as e:
            logger.warning(f"Nginx配置测试失败: {e}")
            return False, f"Nginx配置测试失败: {e}"

        # 重新加载Nginx
        try:
            if system == 'Darwin':  # macOS
                result = subprocess.run(['brew', 'services', 'reload', 'nginx'], capture_output=True, text=True)
            else:
                result = subprocess.run(['nginx', '-s', 'reload'], capture_output=True, text=True)

            if result.returncode != 0:
                return False, f"重新加载Nginx失败: {result.stderr}"
            logger.info("Nginx已重新加载")
        except Exception as e:
            logger.warning(f"重新加载Nginx失败: {e}")
            return False, f"重新加载Nginx失败: {e}"

        # 生成测试HTML文件
        charts_dir = user_config.get('charts_dir', DEFAULT_CHARTS_DIR)
        test_html_path = os.path.join(charts_dir, "test.html")
        os.makedirs(os.path.dirname(test_html_path), exist_ok=True)

        # 获取服务器主机地址
        server_host = get_server_host()
        server_port = user_config.get('server_port', DEFAULT_SERVER_PORT)

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
            <p><strong>主机地址:</strong> {server_host}</p>
            <p><strong>端口:</strong> {server_port}</p>
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

        # 获取测试URL
        test_url = get_html_url(test_html_path)
        logger.info(f"测试HTML文件已生成: {test_html_path}")
        logger.info(f"测试URL: {test_url}")

        return True, f"Nginx配置成功，测试URL: {test_url}"

    except Exception as e:
        logger.error(f"设置Nginx失败: {e}")
        return False, f"设置Nginx失败: {e}"


def is_nginx_available() -> bool:
    """
    检查Nginx是否可用

    Returns:
        bool: Nginx是否可用
    """
    try:
        result = subprocess.run(['nginx', '-v'], capture_output=True, text=True)
        return result.returncode == 0
    except Exception:
        return False


def generate_test_html() -> Optional[str]:
    """
    生成测试HTML文件

    Returns:
        Optional[str]: 测试HTML文件的URL，如果生成失败则返回None
    """
    try:
        # 加载配置
        config = load_config()

        # 获取charts目录
        charts_dir = config.get('charts_dir', DEFAULT_CHARTS_DIR)

        # 生成测试HTML文件
        test_html_path = os.path.join(charts_dir, "test.html")
        os.makedirs(os.path.dirname(test_html_path), exist_ok=True)

        # 获取服务器主机地址和端口
        server_host = get_server_host()
        server_port = config.get('server_port', DEFAULT_SERVER_PORT)

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
            <p><strong>主机地址:</strong> {server_host}</p>
            <p><strong>端口:</strong> {server_port}</p>
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

        # 获取测试URL
        test_url = get_html_url(test_html_path)
        logger.info(f"测试HTML文件已生成: {test_html_path}")
        logger.info(f"测试URL: {test_url}")

        return test_url

    except Exception as e:
        logger.error(f"生成测试HTML文件失败: {e}")
        return None
