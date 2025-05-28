#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
股票符号工具模块

提供股票符号相关的功能，包括获取股票符号详细信息
"""

import json
import logging
import requests
import sys
from datetime import datetime
from typing import Dict, Optional, Any, Tuple, List

from utils.auth_utils import load_auth_config, get_auth_info, get_headers

# 获取日志记录器
logger = logging.getLogger('quant_mcp.symbol_utils')

# API基础URL
BASE_URL = "https://api.yueniusz.com"


def get_symbol_info(full_name: str) -> Optional[Dict[str, Any]]:
    """
    获取股票符号详细信息

    Args:
        full_name: 完整的股票代码，例如 "600000.XSHG"

    Returns:
        Optional[Dict[str, Any]]: 股票符号详细信息，获取失败时返回None
    """
    # 加载认证配置
    if not load_auth_config():
        return None

    if not full_name:
        error_msg = "错误: 股票代码不能为空"
        logger.error(error_msg)
        print(error_msg, file=sys.stderr)
        return None

    # 获取认证信息
    _, user_id = get_auth_info()
    if not user_id:
        logger.error("错误: 无法获取认证信息")
        return None

    url = f"{BASE_URL}/trader-service/symbols"
    params = {
        "full_name": full_name,
        "user_id": user_id
    }

    headers = get_headers()
    logger.debug(f"发送GET请求到: {url}")
    logger.debug(f"请求参数: {params}")
    logger.debug(f"请求头: {headers}")

    try:
        response = requests.get(url, params=params, headers=headers)
        response.raise_for_status()
        data = response.json()

        logger.debug(f"收到响应: {data}")

        if data.get('code') == 1 and data.get('msg') == 'ok':
            symbol_info = data.get('data', {})
            logger.info(f"获取股票信息成功，股票代码: {symbol_info.get('symbol')}")
            return symbol_info
        else:
            logger.error(f"获取股票信息失败: {data}")
            return None

    except requests.exceptions.RequestException as e:
        logger.error(f"请求失败: {e}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"解析响应JSON失败: {e}")
        return None
    except Exception as e:
        logger.error(f"获取股票信息时发生未知错误: {e}")
        return None


def search_symbols(query: str, exchange: str = "ANY", symbol_type: str = "") -> Optional[List[Dict[str, Any]]]:
    """
    搜索股票符号，支持通过股票代码或名称进行搜索

    Args:
        query: 搜索关键词，可以是股票代码或名称
        exchange: 交易所代码，默认为"ANY"表示所有交易所
        symbol_type: 股票类型，默认为空字符串表示所有类型

    Returns:
        Optional[List[Dict[str, Any]]]: 搜索结果列表，每个结果包含股票代码、名称等信息，搜索失败时返回None
    """
    # 加载认证配置
    if not load_auth_config():
        return None

    # 获取认证信息
    _, user_id = get_auth_info()
    if not user_id:
        logger.error("错误: 无法获取认证信息")
        return None

    if not query:
        error_msg = "错误: 搜索关键词不能为空"
        logger.error(error_msg)
        print(error_msg, file=sys.stderr)
        return None

    url = f"{BASE_URL}/trader-service/search-symbols"
    params = {
        "query": query,
        "exchange": exchange,
        "type": symbol_type,
        "user_id": user_id
    }

    headers = get_headers()
    logger.debug(f"发送GET请求到: {url}")
    logger.debug(f"请求参数: {params}")
    logger.debug(f"请求头: {headers}")

    try:
        response = requests.get(url, params=params, headers=headers)
        response.raise_for_status()
        data = response.json()

        logger.debug(f"收到响应: {data}")

        if data.get('code') == 1 and data.get('msg') == 'ok':
            symbols = data.get('data', [])
            logger.info(f"搜索股票成功，找到 {len(symbols)} 个结果")
            return symbols
        else:
            logger.error(f"搜索股票失败: {data}")
            return None

    except requests.exceptions.RequestException as e:
        logger.error(f"请求失败: {e}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"解析响应JSON失败: {e}")
        return None
    except Exception as e:
        logger.error(f"搜索股票时发生未知错误: {e}")
        return None


def validate_date_range(
    full_name: str,
    from_date: Optional[str] = None,
    to_date: Optional[str] = None
) -> Tuple[str, str, Dict[str, Any]]:
    """
    验证并调整回测日期范围，确保日期在股票的上市日期和最后交易日期之间

    Args:
        full_name: 完整的股票代码，例如 "600000.XSHG"
        from_date: 开始日期，格式为YYYY-MM-DD，可选
        to_date: 结束日期，格式为YYYY-MM-DD，可选

    Returns:
        Tuple[str, str, Dict[str, Any]]:
            - 调整后的开始日期
            - 调整后的结束日期
            - 包含调整信息的字典，包括是否进行了调整和调整原因
    """
    # 初始化结果信息
    result_info = {
        'from_date_adjusted': False,
        'to_date_adjusted': False,
        'original_from_date': from_date,
        'original_to_date': to_date,
        'listing_date': None,
        'last_date': None,
        'message': []
    }

    # 获取股票信息
    symbol_info = get_symbol_info(full_name)
    if not symbol_info:
        logger.warning(f"无法获取股票 {full_name} 的信息，将使用原始日期范围")
        return from_date, to_date, result_info

    # 提取上市日期和最后交易日期
    listing_date = symbol_info.get('start_date')
    last_date = symbol_info.get('end_date')

    # 保存到结果信息中
    result_info['listing_date'] = listing_date
    result_info['last_date'] = last_date

    # 如果没有获取到日期信息，直接返回原始日期
    if not listing_date or not last_date:
        logger.warning(f"股票 {full_name} 的上市日期或最后交易日期信息不完整，将使用原始日期范围")
        return from_date, to_date, result_info

    # 如果没有提供日期，使用默认值
    if not from_date:
        from_date = (datetime.now().replace(year=datetime.now().year - 1)).strftime("%Y-%m-%d")
        result_info['original_from_date'] = from_date

    if not to_date:
        to_date = datetime.now().strftime("%Y-%m-%d")
        result_info['original_to_date'] = to_date

    # 转换日期为datetime对象进行比较
    try:
        from_date_dt = datetime.strptime(from_date, "%Y-%m-%d")
        to_date_dt = datetime.strptime(to_date, "%Y-%m-%d")
        listing_date_dt = datetime.strptime(listing_date, "%Y-%m-%d")

        # 处理最后交易日期格式，可能包含时间部分
        if ' ' in last_date:
            last_date = last_date.split(' ')[0]  # 只取日期部分
        last_date_dt = datetime.strptime(last_date, "%Y-%m-%d")

        # 检查并调整开始日期
        if from_date_dt < listing_date_dt:
            from_date = listing_date
            result_info['from_date_adjusted'] = True
            result_info['message'].append(f"开始日期 {result_info['original_from_date']} 早于股票上市日期 {listing_date}，已调整为上市日期")
            logger.info(f"开始日期 {result_info['original_from_date']} 早于股票上市日期 {listing_date}，已调整为上市日期")

        # 检查并调整结束日期
        if to_date_dt > last_date_dt:
            to_date = last_date
            result_info['to_date_adjusted'] = True
            result_info['message'].append(f"结束日期 {result_info['original_to_date']} 晚于股票最后交易日期 {last_date}，已调整为最后交易日期")
            logger.info(f"结束日期 {result_info['original_to_date']} 晚于股票最后交易日期 {last_date}，已调整为最后交易日期")

    except ValueError as e:
        logger.error(f"日期格式错误: {e}，将使用原始日期范围")
        result_info['message'].append(f"日期格式错误: {e}，使用原始日期范围")
        return from_date, to_date, result_info

    return from_date, to_date, result_info
