#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
工具模块初始化文件

导入并注册所有工具
"""

from mcp.server.fastmcp import FastMCP

def register_all_tools(mcp: FastMCP):
    """
    注册所有工具到MCP服务器

    Args:
        mcp: MCP服务器实例
    """
    # 导入工具模块
    from src.tools.kline_tools import register_tools as register_kline_tools
    from src.tools.symbol_tools import register_tools as register_symbol_tools
    from src.tools.strategy_tools import register_tools as register_strategy_tools
    from src.tools.backtest_tools import register_tools as register_backtest_tools

    # 注册K线数据工具
    register_kline_tools(mcp)

    # 注册股票代码工具
    register_symbol_tools(mcp)

    # 注册交易策略工具
    register_strategy_tools(mcp)

    # 注册回测工具
    register_backtest_tools(mcp)
