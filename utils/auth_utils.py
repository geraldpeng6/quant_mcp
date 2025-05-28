#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
认证工具模块

提供认证相关的功能，包括加载认证配置和生成请求头
"""

import os
import json
import logging
import sys
from typing import Dict, Optional, Tuple

# 获取日志记录器
logger = logging.getLogger('quant_mcp.auth')

# 认证信息
TOKEN = None
USER_ID = None


def load_auth_config(config_file: str = 'data/config/auth.json') -> bool:
    """
    从配置文件加载认证信息

    Args:
        config_file: 配置文件路径，默认为'data/config/auth.json'

    Returns:
        bool: 加载是否成功
    """
    global TOKEN, USER_ID

    # 检查配置文件是否存在
    if not os.path.exists(config_file):
        error_msg = f"错误: 登录配置文件 {config_file} 不存在，请先创建配置文件"
        logger.error(error_msg)
        print(error_msg, file=sys.stderr)
        return False

    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
            TOKEN = config.get('token')
            USER_ID = config.get('user_id')

        if not TOKEN or not USER_ID:
            error_msg = "错误: 配置文件中缺少token或user_id"
            logger.error(error_msg)
            print(error_msg, file=sys.stderr)
            return False

        return True
    except Exception as e:
        error_msg = f"错误: 读取配置文件失败: {e}"
        logger.error(error_msg)
        print(error_msg, file=sys.stderr)
        return False


def get_auth_info() -> Tuple[Optional[str], Optional[str]]:
    """
    获取认证信息

    Returns:
        Tuple[Optional[str], Optional[str]]: (token, user_id)
    """
    if not TOKEN or not USER_ID:
        if not load_auth_config():
            return None, None

    return TOKEN, USER_ID


def get_headers() -> Dict[str, str]:
    """
    获取HTTP请求头，包含认证信息

    Returns:
        Dict[str, str]: HTTP请求头
    """
    token, _ = get_auth_info()
    if not token:
        return {}

    return {
        'Host': 'api.yueniusz.com',
        'Authorization': f'Bearer {token}',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Sec-Ch-Ua': '"Chromium";v="136", "Google Chrome";v="136", "Not.A/Brand";v="99"',
        'Content-Type': 'application/json',
        'Sec-Ch-Ua-Platform': '"macOS"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Origin': 'https://api.yueniusz.com',
        'Sec-Fetch-Site': 'same-site',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Dest': 'empty',
        'Referer': 'https://api.yueniusz.com/',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Priority': 'u=1, i'
    }
