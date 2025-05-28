#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
股票符号工具模块

提供股票符号相关的MCP工具
"""

import logging
from typing import Optional, List
from mcp.server.fastmcp import FastMCP

from utils.symbol_utils import get_symbol_info, search_symbols

# 获取日志记录器
logger = logging.getLogger('quant_mcp.symbol_tools')


async def get_stock_info(full_name: str) -> str:
    """
    获取股票详细信息

    Args:
        full_name: 完整的股票代码，例如 "600000.XSHG"

    Returns:
        str: 格式化的股票信息，或错误信息
    """
    try:
        # 从utils模块获取股票信息
        symbol_info = get_symbol_info(full_name)

        if not symbol_info:
            return f"获取股票信息失败: {full_name}"

        # 格式化输出
        result_str = f"股票信息 - {full_name}\n\n"

        # 添加基本信息
        result_str += "基本信息:\n"
        result_str += f"- 代码: {symbol_info.get('symbol', '-')}\n"
        result_str += f"- 交易所: {symbol_info.get('exchange', '-')}\n"
        result_str += f"- 名称: {symbol_info.get('name', symbol_info.get('description', '-'))}\n"
        result_str += f"- 类型: {symbol_info.get('type', '-')}\n"

        # 添加交易信息
        result_str += "\n交易信息:\n"
        result_str += f"- 状态: {symbol_info.get('data_status', '-')}\n"
        result_str += f"- 上市日期: {symbol_info.get('start_date', '-')}\n"
        result_str += f"- 最后日期: {symbol_info.get('end_date', '-')}\n"

        # 添加价格信息
        result_str += "\n价格信息:\n"
        result_str += f"- 最小变动价位: {symbol_info.get('minmov', '-')}\n"
        result_str += f"- 价格精度: {symbol_info.get('pricescale', '-')}\n"

        # 添加交易时段信息
        if symbol_info.get('session'):
            result_str += f"\n交易时段: {symbol_info.get('session', '-')}\n"

        # 添加时区信息
        if symbol_info.get('timezone'):
            result_str += f"时区: {symbol_info.get('timezone', '-')}\n"

        # 添加支持的分辨率
        if symbol_info.get('supported_resolutions'):
            resolutions = symbol_info.get('supported_resolutions', [])
            if isinstance(resolutions, list) and resolutions:
                result_str += f"支持的时间周期: {', '.join(resolutions)}\n"

        # 添加描述信息
        if symbol_info.get('description'):
            result_str += f"\n描述: {symbol_info.get('description', '-')}\n"

        if symbol_info.get('volume_precision') is not None:
            result_str += f"\n成交量精度: {symbol_info.get('volume_precision', '-')}\n"

        return result_str

    except Exception as e:
        logger.error(f"获取股票信息时发生错误: {e}")
        return f"获取股票信息时发生错误: {e}"


async def search_stocks(query: str, exchange: str = "ANY", symbol_type: str = "") -> str:
    """
    搜索股票，支持通过股票代码或名称进行搜索

    Args:
        query: 搜索关键词，可以是股票代码或名称
        exchange: 交易所代码，默认为"ANY"表示所有交易所
        symbol_type: 股票类型，默认为空字符串表示所有类型

    Returns:
        str: 格式化的搜索结果，或错误信息
    """
    try:
        # 从utils模块搜索股票
        symbols = search_symbols(query, exchange, symbol_type)

        if not symbols:
            return f"未找到与 '{query}' 匹配的股票"

        # 格式化输出
        result_str = f"搜索结果 - 关键词: '{query}'\n\n"
        result_str += f"找到 {len(symbols)} 个匹配的股票:\n\n"

        # 添加表头
        result_str += "代码\t\t交易所\t类型\t名称\n"
        result_str += "----\t\t----\t----\t----\n"

        # 添加搜索结果
        for symbol in symbols:
            code = symbol.get('symbol', '-')
            exchange = symbol.get('exchange', '-')
            symbol_type = symbol.get('type', '-')
            name = symbol.get('description', '-')
            full_name = symbol.get('full_name', f"{code}.{exchange}")

            result_str += f"{code}\t\t{exchange}\t{symbol_type}\t{name}\n"

        # 添加使用提示
        result_str += "\n可以使用 get_stock_info 工具获取详细信息，例如:\n"
        if symbols and len(symbols) > 0:
            example_symbol = symbols[0].get('full_name', "600000.XSHG")
            result_str += f"get_stock_info(full_name='{example_symbol}')"

        return result_str

    except Exception as e:
        logger.error(f"搜索股票时发生错误: {e}")
        return f"搜索股票时发生错误: {e}"


def register_tools(mcp: FastMCP):
    """
    注册股票符号相关的工具到MCP服务器

    Args:
        mcp: MCP服务器实例
    """
    # 注册获取股票信息工具
    mcp.tool()(get_stock_info)

    # 注册搜索股票工具
    mcp.tool()(search_stocks)
