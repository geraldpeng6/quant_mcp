#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
策略提示模块

提供交易策略相关的MCP提示模板
"""

import logging
from typing import Dict, Any, List, Optional
from pydantic import Field
from mcp.server.fastmcp import FastMCP
from mcp.types import PromptMessage, TextContent, EmbeddedResource

# 获取日志记录器
logger = logging.getLogger('quant_mcp.strategy_prompts')

def register_prompts(mcp: FastMCP):
    """
    注册交易策略相关的提示模板到MCP服务器

    Args:
        mcp: MCP服务器实例
    """

    # 注册创建策略提示处理函数
    @mcp.prompt(
        name="create_strategy",
        description="创建新的交易策略"
    )
    async def create_strategy(
        strategy_type: str = Field(description="策略类型 [建议: trend_following, mean_reversion, breakout, momentum, value]"),
        timeframe: str = Field(description="交易时间框架 [默认值: swing] [建议: day, swing, position]"),
        risk_level: str = Field(description="风险水平 [默认值: medium] [建议: low, medium, high]")
    ) -> List[PromptMessage]:
        """创建新的交易策略"""
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请为我创建一个{strategy_type}类型的交易策略，适用于{timeframe}交易，风险水平为{risk_level}。\n\n"
                    f"策略应包括以下内容：\n"
                    f"1. 策略概述和理论基础\n"
                    f"2. 入场条件和信号\n"
                    f"3. 出场条件和信号\n"
                    f"4. 仓位管理和风险控制\n"
                    f"5. 关键参数和指标\n"
                    f"6. 回测方法和评估标准\n"
                    f"7. 策略优缺点分析\n"
                    f"8. 实现代码框架或伪代码\n\n"
                    f"请尽可能详细地描述策略，并提供具体的技术指标和参数。"
                )
            )
        ]

        return messages

    # 注册优化策略提示处理函数
    @mcp.prompt(
        name="optimize_strategy",
        description="优化现有交易策略"
    )
    async def optimize_strategy(
        strategy_description: str = Field(description="现有策略的描述"),
        optimization_goal: str = Field(description="优化目标 [建议: returns, drawdown, sharpe, stability, execution]"),
        market_condition: str = Field(default="normal", description="市场环境 [默认值: normal] [建议: bull, bear, volatile, normal]")
    ) -> List[PromptMessage]:
        """优化现有交易策略"""
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请帮我优化以下交易策略，优化目标是{optimization_goal}，考虑{market_condition}市场环境：\n\n"
                    f"{strategy_description}\n\n"
                    f"优化建议应包括：\n"
                    f"1. 现有策略的问题分析\n"
                    f"2. 针对{optimization_goal}的具体优化方案\n"
                    f"3. 参数调整建议\n"
                    f"4. 额外的过滤条件或规则\n"
                    f"5. 风险管理改进\n"
                    f"6. 预期效果和潜在风险\n"
                    f"7. 优化后的策略框架或伪代码\n\n"
                    f"请提供详细的优化建议，并解释每项改进的理由和预期效果。"
                )
            )
        ]

        return messages


