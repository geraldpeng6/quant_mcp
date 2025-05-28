#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
市场分析提示模块

提供市场分析相关的MCP提示模板，包括宏观经济分析、行业分析和市场情绪分析等
"""

import logging
from typing import Dict, Any, List, Optional
from pydantic import Field
from mcp.server.fastmcp import FastMCP
from mcp.types import PromptMessage, TextContent, EmbeddedResource, TextResourceContents

# 获取日志记录器
logger = logging.getLogger('quant_mcp.market_prompts')

def register_prompts(mcp: FastMCP):
    """
    注册市场分析相关的提示模板到MCP服务器

    Args:
        mcp: MCP服务器实例
    """

    # 注册宏观经济分析提示处理函数
    @mcp.prompt(
        name="analyze_macro_economy",
        description="分析宏观经济形势及其对市场的影响"
    )
    async def analyze_macro_economy(
        region: str = Field(description="地区或国家 [默认值: 中国] [建议: 中国, 美国, 欧洲, 全球]"),
        focus_areas: str = Field(description="关注领域 [默认值: all] [建议: 货币政策, 财政政策, 通胀, 就业, 增长, all]"),
        time_horizon: str = Field(default="short", description="时间范围 [默认值: short] [建议: short, medium, long]")
    ) -> List[PromptMessage]:
        """
        分析宏观经济形势及其对市场的影响
        
        Args:
            region: 地区或国家
            focus_areas: 关注领域
            time_horizon: 时间范围
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 时间范围映射
        time_map = {
            "short": "短期（1-3个月）",
            "medium": "中期（3-12个月）",
            "long": "长期（1-3年）"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析{region}的宏观经济形势，重点关注{focus_areas if focus_areas != 'all' else '所有主要经济指标'}，"
                    f"并评估其在{time_map.get(time_horizon, '短期')}内对金融市场的潜在影响。\n\n"
                    f"分析应包括：\n"
                    f"1. 当前宏观经济状况概述\n"
                    f"2. 关键经济指标分析（GDP、通胀、就业、利率等）\n"
                    f"3. 货币政策和财政政策走向\n"
                    f"4. 潜在风险和不确定性因素\n"
                    f"5. 对股票、债券、商品等不同资产类别的影响\n"
                    f"6. {time_map.get(time_horizon, '短期')}经济展望\n"
                    f"7. 投资策略建议\n\n"
                    f"请提供详细、客观的分析，并引用相关数据支持你的观点。"
                )
            )
        ]

        return messages

    # 注册行业分析提示处理函数
    @mcp.prompt(
        name="analyze_industry",
        description="分析特定行业的发展趋势和投资机会"
    )
    async def analyze_industry(
        industry: str = Field(description="行业名称 [建议: 科技, 金融, 医疗, 消费, 能源, 制造业]"),
        analysis_depth: str = Field(default="comprehensive", description="分析深度 [默认值: comprehensive] [建议: brief, comprehensive, detailed]"),
        focus: str = Field(default="investment", description="分析重点 [默认值: investment] [建议: trends, competition, policy, technology, investment]")
    ) -> List[PromptMessage]:
        """
        分析特定行业的发展趋势和投资机会
        
        Args:
            industry: 行业名称
            analysis_depth: 分析深度
            focus: 分析重点
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 分析深度映射
        depth_map = {
            "brief": "简要",
            "comprehensive": "全面",
            "detailed": "详细"
        }
        
        # 分析重点映射
        focus_map = {
            "trends": "发展趋势",
            "competition": "竞争格局",
            "policy": "政策环境",
            "technology": "技术创新",
            "investment": "投资机会"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请提供一份{depth_map.get(analysis_depth, '全面')}的{industry}行业分析，"
                    f"重点关注{focus_map.get(focus, '投资机会')}。\n\n"
                    f"分析应包括：\n"
                    f"1. 行业概况和发展阶段\n"
                    f"2. 市场规模和增长潜力\n"
                    f"3. 行业竞争格局和主要参与者\n"
                    f"4. 关键驱动因素和挑战\n"
                    f"5. 政策环境和监管趋势\n"
                    f"6. 技术创新和颠覆性趋势\n"
                    f"7. 投资机会和风险分析\n"
                    f"8. 代表性公司分析\n"
                    f"9. 未来展望和建议\n\n"
                    f"请提供{depth_map.get(analysis_depth, '全面')}的分析，并尽可能引用最新的行业数据和研究。"
                )
            )
        ]

        return messages

    # 注册市场情绪分析提示处理函数
    @mcp.prompt(
        name="analyze_market_sentiment",
        description="分析市场情绪和投资者心理状态"
    )
    async def analyze_market_sentiment(
        market: str = Field(description="市场名称 [默认值: A股] [建议: A股, 港股, 美股, 全球]"),
        indicators: str = Field(default="all", description="情绪指标 [默认值: all] [建议: vix, put_call, fund_flow, margin, breadth, all]"),
        time_period: str = Field(default="current", description="时间周期 [默认值: current] [建议: current, historical, forecast]")
    ) -> List[PromptMessage]:
        """
        分析市场情绪和投资者心理状态
        
        Args:
            market: 市场名称
            indicators: 情绪指标
            time_period: 时间周期
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 时间周期映射
        period_map = {
            "current": "当前",
            "historical": "历史",
            "forecast": "预测"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析{market}的{period_map.get(time_period, '当前')}市场情绪状态，"
                    f"{'关注所有主要情绪指标' if indicators == 'all' else f'重点关注{indicators}指标'}。\n\n"
                    f"分析应包括：\n"
                    f"1. 市场情绪总体评估（恐惧/贪婪程度）\n"
                    f"2. 关键情绪指标分析（波动率指数、看跌/看涨期权比率、资金流向等）\n"
                    f"3. 市场宽度和参与度\n"
                    f"4. 机构投资者vs.散户投资者情绪对比\n"
                    f"5. 技术指标反映的情绪状态\n"
                    f"6. 市场情绪与历史周期的对比\n"
                    f"7. 情绪指标与市场表现的相关性\n"
                    f"8. 基于情绪分析的市场前景和投资建议\n\n"
                    f"请提供详细的分析，并解释各情绪指标的含义及其对市场的指导意义。"
                )
            )
        ]

        return messages
