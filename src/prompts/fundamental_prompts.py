#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
基本面分析提示模块

提供基本面分析相关的MCP提示模板，包括财务分析、估值分析和公司研究等
"""

import logging
from typing import Dict, Any, List, Optional
from pydantic import Field
from mcp.server.fastmcp import FastMCP
from mcp.types import PromptMessage, TextContent, EmbeddedResource, TextResourceContents

# 获取日志记录器
logger = logging.getLogger('quant_mcp.fundamental_prompts')

def register_prompts(mcp: FastMCP):
    """
    注册基本面分析相关的提示模板到MCP服务器

    Args:
        mcp: MCP服务器实例
    """

    # 注册财务分析提示处理函数
    @mcp.prompt(
        name="analyze_financials",
        description="分析公司财务报表和财务指标"
    )
    async def analyze_financials(
        symbol: str = Field(description="股票代码 [建议: 600000, 601398, 000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        report_type: str = Field(default="latest", description="报表类型 [默认值: latest] [建议: latest, annual, quarterly, trend]"),
        focus_areas: str = Field(default="all", description="关注领域 [默认值: all] [建议: profitability, growth, solvency, efficiency, all]")
    ) -> List[PromptMessage]:
        """
        分析公司财务报表和财务指标
        
        Args:
            symbol: 股票代码
            exchange: 交易所代码
            report_type: 报表类型
            focus_areas: 关注领域
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 构建资源URI
        resource_uri = f"fundamental://{exchange}/{symbol}/financials"
        
        # 报表类型映射
        report_map = {
            "latest": "最新",
            "annual": "年度",
            "quarterly": "季度",
            "trend": "趋势"
        }
        
        # 关注领域映射
        focus_map = {
            "profitability": "盈利能力",
            "growth": "成长能力",
            "solvency": "偿债能力",
            "efficiency": "运营效率",
            "all": "全面"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析 {symbol} 在 {exchange} 交易所的{report_map.get(report_type, '最新')}财务报表，"
                    f"提供{focus_map.get(focus_areas, '全面')}财务分析。\n\n"
                    f"分析应包括：\n"
                    f"1. 收入和利润分析（规模、增长、质量）\n"
                    f"2. 主要财务比率分析（ROE、ROA、毛利率、净利率等）\n"
                    f"3. 资产负债结构和质量\n"
                    f"4. 现金流状况和质量\n"
                    f"5. 财务指标的历史趋势和行业对比\n"
                    f"6. 财务风险评估\n"
                    f"7. 财务造假风险筛查\n"
                    f"8. 基于财务分析的投资建议\n\n"
                    f"请提供详细的财务分析，并解释各项指标的含义和投资意义。"
                )
            ),
            # 添加资源消息
            PromptMessage(
                role="user",
                content=EmbeddedResource(
                    type="resource",
                    resource=TextResourceContents(
                        uri=resource_uri,
                        mimeType="application/json",
                        text=""  # 添加必需的text字段
                    )
                )
            )
        ]

        return messages

    # 注册估值分析提示处理函数
    @mcp.prompt(
        name="analyze_valuation",
        description="分析公司估值水平和合理价值"
    )
    async def analyze_valuation(
        symbol: str = Field(description="股票代码 [建议: 600000, 601398, 000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        methods: str = Field(default="all", description="估值方法 [默认值: all] [建议: pe, pb, dcf, relative, all]"),
        comparison: str = Field(default="both", description="比较基准 [默认值: both] [建议: historical, industry, market, both]")
    ) -> List[PromptMessage]:
        """
        分析公司估值水平和合理价值
        
        Args:
            symbol: 股票代码
            exchange: 交易所代码
            methods: 估值方法
            comparison: 比较基准
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 构建资源URI
        resource_uri = f"fundamental://{exchange}/{symbol}/valuation"
        
        # 估值方法映射
        method_map = {
            "pe": "市盈率",
            "pb": "市净率",
            "dcf": "贴现现金流",
            "relative": "相对估值",
            "all": "多种估值方法"
        }
        
        # 比较基准映射
        comparison_map = {
            "historical": "历史",
            "industry": "行业",
            "market": "市场",
            "both": "历史和行业"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请分析 {symbol} 在 {exchange} 交易所的估值水平，"
                    f"使用{method_map.get(methods, '多种估值方法')}，"
                    f"与{comparison_map.get(comparison, '历史和行业')}水平进行比较。\n\n"
                    f"分析应包括：\n"
                    f"1. 当前主要估值指标（PE、PB、PS、EV/EBITDA等）\n"
                    f"2. 历史估值区间和当前估值位置\n"
                    f"3. 与行业和市场平均水平的比较\n"
                    f"4. 估值溢价/折价的合理性分析\n"
                    f"5. 未来业绩预期对估值的影响\n"
                    f"6. 贴现现金流模型分析（如适用）\n"
                    f"7. 合理价值区间估计\n"
                    f"8. 基于估值的投资建议和目标价\n\n"
                    f"请提供详细的估值分析，并解释各估值方法的优缺点和适用条件。"
                )
            ),
            # 添加资源消息
            PromptMessage(
                role="user",
                content=EmbeddedResource(
                    type="resource",
                    resource=TextResourceContents(
                        uri=resource_uri,
                        mimeType="application/json",
                        text=""  # 添加必需的text字段
                    )
                )
            )
        ]

        return messages

    # 注册公司研究提示处理函数
    @mcp.prompt(
        name="research_company",
        description="全面研究公司的基本面情况"
    )
    async def research_company(
        symbol: str = Field(description="股票代码 [建议: 600000, 601398, 000001]"),
        exchange: str = Field(description="交易所代码 [默认值: XSHG] [建议: XSHG, XSHE]"),
        research_depth: str = Field(default="comprehensive", description="研究深度 [默认值: comprehensive] [建议: brief, comprehensive, detailed]"),
        focus: str = Field(default="all", description="研究重点 [默认值: all] [建议: business, financials, management, risks, catalysts, all]")
    ) -> List[PromptMessage]:
        """
        全面研究公司的基本面情况
        
        Args:
            symbol: 股票代码
            exchange: 交易所代码
            research_depth: 研究深度
            focus: 研究重点
            
        Returns:
            List[PromptMessage]: 提示消息列表
        """
        # 构建资源URI
        resource_uri = f"fundamental://{exchange}/{symbol}/company"
        
        # 研究深度映射
        depth_map = {
            "brief": "简要",
            "comprehensive": "全面",
            "detailed": "详细"
        }
        
        # 研究重点映射
        focus_map = {
            "business": "业务模式",
            "financials": "财务状况",
            "management": "管理团队",
            "risks": "风险因素",
            "catalysts": "催化剂",
            "all": "全方位"
        }
        
        # 构建提示消息
        messages = [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"请提供 {symbol} 在 {exchange} 交易所的{depth_map.get(research_depth, '全面')}公司研究报告，"
                    f"重点关注{focus_map.get(focus, '全方位')}分析。\n\n"
                    f"研究报告应包括：\n"
                    f"1. 公司概况和发展历史\n"
                    f"2. 业务模式和收入构成\n"
                    f"3. 行业地位和竞争优势\n"
                    f"4. 财务状况和趋势分析\n"
                    f"5. 管理团队评估\n"
                    f"6. 成长驱动因素和战略方向\n"
                    f"7. 主要风险因素\n"
                    f"8. 潜在催化剂\n"
                    f"9. 估值分析和合理价值\n"
                    f"10. 投资评级和建议\n\n"
                    f"请提供{depth_map.get(research_depth, '全面')}的分析，并尽可能引用最新的公司数据和行业信息。"
                )
            ),
            # 添加资源消息
            PromptMessage(
                role="user",
                content=EmbeddedResource(
                    type="resource",
                    resource=TextResourceContents(
                        uri=resource_uri,
                        mimeType="application/json",
                        text=""  # 添加必需的text字段
                    )
                )
            )
        ]

        return messages
