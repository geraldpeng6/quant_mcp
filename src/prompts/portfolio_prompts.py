#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
投资组合管理提示模块

提供投资组合管理相关的MCP提示模板，包括资产配置、风险管理和绩效分析等
"""

import logging
from typing import Dict, Any, List, Optional
from pydantic import Field
from mcp.server.fastmcp import FastMCP
from mcp.types import PromptMessage, TextContent, EmbeddedResource, TextResourceContents

# 获取日志记录器
logger = logging.getLogger('quant_mcp.portfolio_prompts')

def register_prompts(mcp: FastMCP):
    """
    注册投资组合管理相关的提示模板到MCP服务器

    Args:
        mcp: MCP服务器实例
    """

    # 注册资产配置提示处理函数
    @mcp.prompt(
        name="asset_allocation",
        description="提供资产配置建议和投资组合构建方案"
    )
    async def asset_allocation(
        risk_profile: str = Field(description="风险偏好 [默认值: moderate] [建议: conservative, moderate, aggressive]"),
        investment_horizon: str = Field(description="投资期限 [默认值: medium] [建议: short, medium, long]"),
        investment_goal: str = Field(default="balanced", description="投资目标 [默认值: balanced] [建议: income, growth, balanced, preservation]"),
        constraints: str = Field(default="none", description="投资限制 [默认值: none] [建议: liquidity, tax, esg, none]")
    ) -> List[PromptMessage]:
        """
        提供资产配置建议和投资组合构建方案
        
        Args:
            risk_profile: 风险偏好
            investment_horizon: 投资期限
            investment_goal: 投资目标
            constraints: 投资限制
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 风险偏好映射
        risk_map = {
            "conservative": "保守型",
            "moderate": "稳健型",
            "aggressive": "进取型"
        }
        
        # 投资期限映射
        horizon_map = {
            "short": "短期（1-3年）",
            "medium": "中期（3-10年）",
            "long": "长期（10年以上）"
        }
        
        # 投资目标映射
        goal_map = {
            "income": "收入型",
            "growth": "增长型",
            "balanced": "平衡型",
            "preservation": "保本型"
        }
        
        # 投资限制映射
        constraint_map = {
            "liquidity": "流动性需求",
            "tax": "税务考虑",
            "esg": "ESG因素",
            "none": "无特殊限制"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请为{risk_map.get(risk_profile, '稳健型')}投资者提供资产配置建议，"
                    f"投资期限为{horizon_map.get(investment_horizon, '中期')}，"
                    f"投资目标为{goal_map.get(investment_goal, '平衡型')}，"
                    f"投资限制为{constraint_map.get(constraints, '无特殊限制')}。\n\n"
                    f"资产配置方案应包括：\n"
                    f"1. 大类资产配置比例（股票、债券、现金、另类资产等）\n"
                    f"2. 各类资产的细分配置（行业、地区、久期等）\n"
                    f"3. 配置建议的理论依据和市场逻辑\n"
                    f"4. 当前市场环境下的战术性调整建议\n"
                    f"5. 推荐的投资工具和产品类型\n"
                    f"6. 再平衡策略和调整频率\n"
                    f"7. 预期收益和风险评估\n"
                    f"8. 投资组合构建步骤和实施建议\n\n"
                    f"请提供详细的资产配置方案，并解释各类资产的作用和配置逻辑。"
                )
            )
        ]

        return messages

    # 注册风险管理提示处理函数
    @mcp.prompt(
        name="risk_management",
        description="提供投资组合风险管理建议"
    )
    async def risk_management(
        portfolio_type: str = Field(description="组合类型 [默认值: stock] [建议: stock, mixed, bond, quantitative]"),
        risk_metrics: str = Field(default="all", description="风险指标 [默认值: all] [建议: volatility, drawdown, var, correlation, all]"),
        market_condition: str = Field(default="normal", description="市场环境 [默认值: normal] [建议: bull, bear, volatile, normal]"),
        portfolio_size: str = Field(default="medium", description="组合规模 [默认值: medium] [建议: small, medium, large]")
    ) -> List[PromptMessage]:
        """
        提供投资组合风险管理建议
        
        Args:
            portfolio_type: 组合类型
            risk_metrics: 风险指标
            market_condition: 市场环境
            portfolio_size: 组合规模
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 组合类型映射
        portfolio_map = {
            "stock": "股票型",
            "mixed": "混合型",
            "bond": "债券型",
            "quantitative": "量化型"
        }
        
        # 市场环境映射
        market_map = {
            "bull": "牛市",
            "bear": "熊市",
            "volatile": "波动市",
            "normal": "常态市"
        }
        
        # 组合规模映射
        size_map = {
            "small": "小型（<100万）",
            "medium": "中型（100万-1000万）",
            "large": "大型（>1000万）"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请为{portfolio_map.get(portfolio_type, '股票型')}投资组合提供风险管理建议，"
                    f"重点关注{'所有主要风险指标' if risk_metrics == 'all' else risk_metrics}，"
                    f"考虑当前{market_map.get(market_condition, '常态市')}环境，"
                    f"组合规模为{size_map.get(portfolio_size, '中型')}。\n\n"
                    f"风险管理建议应包括：\n"
                    f"1. 主要风险指标分析和监控方法\n"
                    f"2. 风险预算和风险分配策略\n"
                    f"3. 仓位管理和调整策略\n"
                    f"4. 止损策略和执行方法\n"
                    f"5. 分散化策略和相关性管理\n"
                    f"6. 对冲策略和工具选择\n"
                    f"7. 压力测试和情景分析方法\n"
                    f"8. 风险报告和定期审查建议\n\n"
                    f"请提供详细的风险管理建议，并解释各项措施的实施方法和预期效果。"
                )
            )
        ]

        return messages

    # 注册绩效分析提示处理函数
    @mcp.prompt(
        name="performance_analysis",
        description="分析投资组合的绩效表现"
    )
    async def performance_analysis(
        portfolio_data: str = Field(description="投资组合数据，包括持仓和历史表现"),
        benchmark: str = Field(default="default", description="基准指数 [默认值: default] [建议: CSI300, CSI500, SSE50, default]"),
        time_period: str = Field(default="1y", description="分析周期 [默认值: 1y] [建议: 3m, 6m, 1y, 3y, 5y]"),
        metrics: str = Field(default="all", description="绩效指标 [默认值: all] [建议: return, risk_adjusted, attribution, all]")
    ) -> List[PromptMessage]:
        """
        分析投资组合的绩效表现
        
        Args:
            portfolio_data: 投资组合数据
            benchmark: 基准指数
            time_period: 分析周期
            metrics: 绩效指标
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 基准指数映射
        benchmark_map = {
            "CSI300": "沪深300",
            "CSI500": "中证500",
            "SSE50": "上证50",
            "default": "默认基准"
        }
        
        # 分析周期映射
        period_map = {
            "3m": "近3个月",
            "6m": "近6个月",
            "1y": "近1年",
            "3y": "近3年",
            "5y": "近5年"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析以下投资组合在{period_map.get(time_period, '近1年')}的绩效表现，"
                    f"使用{benchmark_map.get(benchmark, '默认基准')}作为比较基准，"
                    f"重点关注{'所有主要绩效指标' if metrics == 'all' else metrics}。\n\n"
                    f"投资组合数据：\n{portfolio_data}\n\n"
                    f"绩效分析应包括：\n"
                    f"1. 总收益率和年化收益率\n"
                    f"2. 风险调整收益指标（夏普比率、索提诺比率等）\n"
                    f"3. 波动率和最大回撤分析\n"
                    f"4. 与基准的比较（超额收益、信息比率、跟踪误差等）\n"
                    f"5. 业绩归因分析（资产配置、行业选择、个股选择等）\n"
                    f"6. 不同市场环境下的表现\n"
                    f"7. 持仓分析和集中度评估\n"
                    f"8. 绩效改进建议\n\n"
                    f"请提供详细的绩效分析，并解释各项指标的含义和投资意义。"
                )
            )
        ]

        return messages
