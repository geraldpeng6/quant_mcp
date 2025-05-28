#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
HTML服务器模块

提供用于生成HTML URL和测试HTML的函数
"""

import os
import socket
import logging
import tempfile
import datetime
import webbrowser
from pathlib import Path
from urllib.parse import quote

# 获取日志记录器
logger = logging.getLogger('quant_mcp.html_server')

# HTML文件存储目录
HTML_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data', 'charts')


def get_html_url(html_path: str, use_file_protocol: bool = True) -> str:
    """
    获取HTML文件的URL
    
    Args:
        html_path: HTML文件路径
        use_file_protocol: 是否使用file://协议
        
    Returns:
        str: HTML文件URL
    """
    if use_file_protocol:
        # 使用file://协议，直接在浏览器中打开本地文件
        abs_path = os.path.abspath(html_path)
        return f"file://{quote(abs_path)}"
    else:
        # 可以在这里实现简单的HTTP服务器逻辑
        # 目前仅返回文件路径
        return html_path


def generate_test_html(content: str = None, title: str = "测试页面") -> str:
    """
    生成测试HTML文件
    
    Args:
        content: HTML内容
        title: 页面标题
        
    Returns:
        str: HTML文件路径
    """
    if content is None:
        content = "<h1>测试页面</h1><p>这是一个测试页面</p>"
    
    # 确保目录存在
    os.makedirs(HTML_DIR, exist_ok=True)
    
    # 获取当前时间
    current_time = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # 创建临时HTML文件
    fd, html_path = tempfile.mkstemp(suffix='.html', prefix='test_', dir=HTML_DIR)
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{title}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 0; padding: 20px; }}
        h1 {{ color: #333; }}
    </style>
</head>
<body>
    {content}
    <hr>
    <footer>
        <p>生成时间: {current_time}</p>
        <p>主机名: {socket.gethostname()}</p>
    </footer>
</body>
</html>""")
    
    logger.info(f"生成测试HTML文件: {html_path}")
    return html_path


def serve_html(html_path: str, port: int = 8080) -> str:
    """
    启动一个简单的HTTP服务器来提供HTML文件
    
    Args:
        html_path: HTML文件路径
        port: 服务器端口
        
    Returns:
        str: 服务器URL
    """
    # 这个函数是占位符，实际实现可能需要更复杂的HTTP服务器
    # 在实际应用中，您可能需要使用如http.server或Flask来实现
    logger.warning("serve_html函数只是一个占位符，未实际启动HTTP服务器")
    
    # 返回文件URL
    return get_html_url(html_path) 