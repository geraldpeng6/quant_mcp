#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
技术分析提示模块

提供技术分析相关的MCP提示模板，包括技术指标分析、形态识别和趋势分析等
"""

import logging
from typing import Dict, Any, List, Optional
from pydantic import Field
from mcp.server.fastmcp import FastMCP
from mcp.types import PromptMessage, TextContent, EmbeddedResource, TextResourceContents

# 导入采样工具
# from src.utils.sampling_utils import request_sampling, SYSTEM_PROMPTS, MODEL_PREFERENCES (已删除)

# 获取日志记录器
logger = logging.getLogger('quant_mcp.technical_prompts')

def register_prompts(mcp: FastMCP):
    """
    注册技术分析相关的提示模板到MCP服务器

    Args:
        mcp: MCP服务器实例
    """

    # 注册技术指标分析提示处理函数
    @mcp.prompt(
        name="analyze_indicators",
        description="分析股票的技术指标并提供交易建议"
    )
    async def analyze_indicators(
        symbol: str = Field(description="股票代码 [建议: 600000, 601398, 000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        indicators: str = Field(default="all", description="技术指标 [默认值: all] [建议: MACD, RSI, KDJ, BOLL, MA, all]"),
        timeframe: str = Field(default="daily", description="时间周期 [默认值: daily] [建议: daily, weekly, monthly, 60min]")
    ) -> List[PromptMessage]:
        """
        分析股票的技术指标并提供交易建议
        
        Args:
            symbol: 股票代码
            exchange: 交易所代码
            indicators: 技术指标
            timeframe: 时间周期
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 构建资源URI
        resource_uri = f"kline://{exchange}/{symbol}/{timeframe}"
        
        # 时间周期映射
        timeframe_map = {
            "daily": "日线",
            "weekly": "周线",
            "monthly": "月线",
            "60min": "60分钟线"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析 {symbol} 在 {exchange} 交易所的{timeframe_map.get(timeframe, '日线')}数据，"
                    f"{'分析所有主要技术指标' if indicators == 'all' else f'重点分析{indicators}指标'}。\n\n"
                    f"分析应包括：\n"
                    f"1. 各技术指标的当前状态和信号\n"
                    f"2. 指标之间的相互验证或背离情况\n"
                    f"3. 指标历史表现与当前市场环境的对比\n"
                    f"4. 基于技术指标的支撑位和阻力位\n"
                    f"5. 短期、中期和长期技术走势预测\n"
                    f"6. 具体的交易建议（买入、卖出、持有）\n"
                    f"7. 止损和止盈位置建议\n"
                    f"8. 技术分析的局限性和风险提示\n\n"
                    f"请提供详细的分析，并解释各指标的计算方法和信号含义。"
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

    # 注册形态识别提示处理函数
    @mcp.prompt(
        name="identify_patterns",
        description="识别股票K线图中的技术形态"
    )
    async def identify_patterns(
        symbol: str = Field(description="股票代码 [建议: 600000, 601398, 000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        pattern_types: str = Field(default="all", description="形态类型 [默认值: all] [建议: reversal, continuation, candlestick, all]"),
        timeframe: str = Field(default="daily", description="时间周期 [默认值: daily] [建议: daily, weekly, 60min, 30min]")
    ) -> List[PromptMessage]:
        """
        识别股票K线图中的技术形态
        
        Args:
            symbol: 股票代码
            exchange: 交易所代码
            pattern_types: 形态类型
            timeframe: 时间周期
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 构建资源URI
        resource_uri = f"kline://{exchange}/{symbol}/{timeframe}"
        
        # 形态类型映射
        pattern_map = {
            "reversal": "反转形态",
            "continuation": "持续形态",
            "candlestick": "蜡烛图形态",
            "all": "所有形态"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请识别 {symbol} 在 {exchange} 交易所的{timeframe}K线图中的{pattern_map.get(pattern_types, '所有形态')}。\n\n"
                    f"分析应包括：\n"
                    f"1. 已形成的技术形态识别和描述\n"
                    f"2. 正在形成的潜在形态\n"
                    f"3. 每种形态的理论含义和历史可靠性\n"
                    f"4. 形态完成后的目标价位预测\n"
                    f"5. 形态失效的判断标准\n"
                    f"6. 配合成交量的形态确认\n"
                    f"7. 基于形态分析的交易策略建议\n"
                    f"8. 多个时间周期的形态协同分析\n\n"
                    f"请详细描述每个识别出的形态，并提供形成原因、确认条件和交易建议。"
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

    # 注册趋势分析提示处理函数
    @mcp.prompt(
        name="analyze_trend",
        description="分析股票的价格趋势和趋势强度"
    )
    async def analyze_trend(
        symbol: str = Field(description="股票代码 [建议: 600000, 601398, 000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        timeframe: str = Field(default="daily", description="时间周期 [默认值: daily] [建议: daily, weekly, monthly, 60min]"),
        methods: str = Field(default="all", description="趋势分析方法 [默认值: all] [建议: moving_average, trendline, adr, momentum, all]")
    ) -> List[PromptMessage]:
        """
        分析股票的价格趋势和趋势强度
        
        Args:
            symbol: 股票代码
            exchange: 交易所代码
            timeframe: 时间周期
            methods: 趋势分析方法
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 构建资源URI
        resource_uri = f"kline://{exchange}/{symbol}/{timeframe}"
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析 {symbol} 在 {exchange} 交易所的{timeframe}数据的价格趋势和趋势强度，"
                    f"{'使用所有主要趋势分析方法' if methods == 'all' else f'重点使用{methods}方法'}。\n\n"
                    f"分析应包括：\n"
                    f"1. 当前主要趋势方向（上升、下降或横盘）\n"
                    f"2. 趋势的时间框架（短期、中期、长期）\n"
                    f"3. 趋势强度和持续性评估\n"
                    f"4. 移动平均线分析（多条均线的关系和交叉）\n"
                    f"5. 趋势线和通道分析\n"
                    f"6. 支撑位和阻力位识别\n"
                    f"7. 动量指标对趋势的确认或背离\n"
                    f"8. 趋势变化的早期信号\n"
                    f"9. 基于趋势分析的交易策略建议\n\n"
                    f"请提供详细的趋势分析，并解释各种趋势特征的意义和交易含义。"
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
