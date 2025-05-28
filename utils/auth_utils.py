#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
认证工具模块

提供认证相关的功能，使用MCP配置中的认证信息
"""

import logging
from typing import Dict, Optional, Tuple, List

# 获取日志记录器
logger = logging.getLogger('quant_mcp.auth')

# 认证信息（由MCP传入）
TOKEN = None
USER_ID = None

# 自动批准的工具列表
AUTO_APPROVE_TOOLS = []


def load_auth_config() -> bool:
    """
    加载认证配置（兼容性函数）
    
    新版本不再从本地文件加载认证信息，而是通过MCP客户端传入
    该函数保留为了兼容现有代码结构
    
    Returns:
        bool: 始终返回True表示认证配置已加载
    """
    token, user_id = get_auth_info()
    if token and user_id:
        logger.debug("已加载认证配置")
    else:
        logger.warning("未设置认证信息，可能会导致API请求失败")
    return True


def set_auth_from_mcp(token: Optional[str] = None, user_id: Optional[str] = None) -> None:
    """
    从MCP客户端设置认证信息
    
    Args:
        token: API令牌
        user_id: 用户ID
    """
    global TOKEN, USER_ID
    
    if token:
        TOKEN = token
        logger.info("已从MCP客户端设置token")
    
    if user_id:
        USER_ID = user_id
        logger.info("已从MCP客户端设置user_id")


def set_auto_approve_tools(tools: List[str]) -> None:
    """
    设置自动批准的工具列表
    
    Args:
        tools: 工具名称列表
    """
    global AUTO_APPROVE_TOOLS
    
    AUTO_APPROVE_TOOLS = tools
    logger.info(f"已设置自动批准工具列表: {AUTO_APPROVE_TOOLS}")


def get_auth_info() -> Tuple[Optional[str], Optional[str]]:
    """
    获取认证信息
    
    Returns:
        Tuple[Optional[str], Optional[str]]: (token, user_id)
    """
    return TOKEN, USER_ID


def get_headers() -> Dict[str, str]:
    """
    获取HTTP请求头，包含认证信息
    
    Returns:
        Dict[str, str]: HTTP请求头
    """
    token, _ = get_auth_info()
    if not token:
        logger.warning("未设置认证token，无法生成认证请求头")
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
        'Origin': 'https://hitrader.yueniusz.com',
        'Sec-Fetch-Site': 'same-site',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Dest': 'empty',
        'Referer': 'https://hitrader.yueniusz.com/',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Priority': 'u=1, i'
    }


def get_auto_approve_tools() -> List[str]:
    """
    获取自动批准的工具列表
    
    Returns:
        List[str]: 自动批准的工具列表
    """
    return AUTO_APPROVE_TOOLS
