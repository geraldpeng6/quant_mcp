#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
K线数据提示模块

提供K线数据分析相关的MCP提示模板
"""

import logging
from typing import Dict, Any, List, Optional
from pydantic import Field
from mcp.server.fastmcp import FastMCP
from mcp.types import PromptMessage, TextContent, EmbeddedResource, TextResourceContents

# 获取日志记录器
logger = logging.getLogger('quant_mcp.kline_prompts')

def register_prompts(mcp: FastMCP):
    """
    注册K线数据相关的提示模板到MCP服务器

    Args:
        mcp: MCP服务器实例
    """

    # 注册K线分析提示处理函数
    @mcp.prompt(
        name="analyze_kline",
        description="分析股票K线数据并提供见解"
    )
    async def analyze_kline(
        symbol: str = Field(description="股票代码 [建议: 600000, 601398, 000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        resolution: str = Field(description="时间周期 [默认值: 1D] [建议: 1D, 1W, 60, 30, 15]"),
        analysis_type: str = Field(default="all", description="分析类型 [默认值: all] [建议: trend, pattern, indicator, all]")
    ) -> List[PromptMessage]:
        """分析股票K线数据并提供见解"""
        # 构建资源URI
        resource_uri = f"kline://{exchange}/{symbol}/{resolution}"

        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析 {symbol} 在 {exchange} 交易所的 {resolution} K线数据。"
                    f"我需要{'全面' if analysis_type == 'all' else analysis_type}分析，"
                    f"包括{'趋势分析、形态分析和指标分析' if analysis_type == 'all' else analysis_type}。"
                    f"分析应包括：\n"
                    f"1. 价格趋势和关键支撑/阻力位\n"
                    f"2. 成交量分析\n"
                    f"3. 主要技术指标（如MACD、RSI等）\n"
                    f"4. 形态识别（如头肩顶、双底等）\n"
                    f"5. 总体市场观点和可能的交易机会"
                )
            ),
            # 添加资源消息
            PromptMessage(
                role="user",
                content=EmbeddedResource(
                    type="resource",
                    resource=TextResourceContents(
                        uri=resource_uri,
                        mimeType="text/csv",
                        text=""  # 添加必需的text字段
                    )
                )
            )
        ]

        return messages

    # 注册股票比较提示处理函数
    @mcp.prompt(
        name="compare_stocks",
        description="比较多只股票的K线数据"
    )
    async def compare_stocks(
        symbols: str = Field(description="股票代码列表，用逗号分隔 [建议: 600000,601398,000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        resolution: str = Field(description="时间周期 [默认值: 1D] [建议: 1D, 1W, 60, 30]"),
        comparison_period: str = Field(default="3m", description="比较周期 [默认值: 3m] [建议: 1m, 3m, 6m, 1y]")
    ) -> List[PromptMessage]:
        """比较多只股票的K线数据"""
        # 解析股票代码列表
        symbol_list = symbols.split(",")

        # 构建提示消息
        symbols_text = ", ".join(symbol_list)

        # 创建基本提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请比较以下股票在{comparison_period}期间的表现：{symbols_text}。\n\n"
                    f"比较应包括：\n"
                    f"1. 价格走势对比\n"
                    f"2. 相对强弱分析\n"
                    f"3. 波动性比较\n"
                    f"4. 成交量对比\n"
                    f"5. 相关性分析\n"
                    f"6. 总体评估和投资建议"
                )
            )
        ]

        # 为每个股票添加资源消息
        for symbol in symbol_list:
            symbol = symbol.strip()
            resource_uri = f"kline://{exchange}/{symbol}/{resolution}"

            messages.append(
                PromptMessage(
                    role="user",
                    content=EmbeddedResource(
                        type="resource",
                        resource=TextResourceContents(
                            uri=resource_uri,
                            mimeType="text/csv",
                            text=""  # 添加必需的text字段
                        )
                    )
                )
            )

        return messages


