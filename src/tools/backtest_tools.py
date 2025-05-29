#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
回测工具模块

提供回测相关的MCP工具
"""

import logging
from typing import Optional
from mcp.server.fastmcp import FastMCP

from utils.backtest_utils import run_backtest, format_choose_stock

# 获取日志记录器
logger = logging.getLogger('quant_mcp.backtest_tools')


async def run_strategy_backtest(
    strategy_id: str,
    listen_time: int = 180,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    indicator: Optional[str] = None,
    control_risk: Optional[str] = None,
    timing: Optional[str] = None,
    choose_stock: Optional[str] = None
) -> str:
    """
    运行策略回测

    Args:
        strategy_id: 策略ID
        listen_time: 监听和处理时间（秒），默认180秒。对于大型回测请增加此值以避免客户端超时。
                    注意：此值可以设置得比较大（最大600秒），因为回测系统会在没有新数据时提前结束监听。
                    服务器会在连续5秒没有新数据且已收集到至少10条记录时提前返回结果。
        start_date: 回测开始日期，格式为 "YYYY-MM-DD"，可选，默认为一年前
        end_date: 回测结束日期，格式为 "YYYY-MM-DD"，可选，默认为今天
        indicator: 自定义指标代码，可选
        control_risk: 自定义风控代码，可选
        timing: 自定义择时代码，可选
        choose_stock: 自定义标的代码，可以是以下几种形式：
                     1. 完整的choose_stock函数代码，以"def choose_stock(context):"开头
                     2. 单个股票代码，如"600000.XSHG"
                     3. 多个股票代码，如"600000.XSHG&000001.XSHE"，用"&"符号分隔多个股票代码

    Returns:
        str: 回测结果信息，或错误信息
    """
    # 检查listen_time是否超过安全值，如果超过则发出警告
    max_listen_time = 600  # 最大允许600秒
    if listen_time > max_listen_time:
        logger.warning(f"listen_time值({listen_time}秒)超过最大允许值({max_listen_time}秒)，自动调整为{max_listen_time}秒")
        listen_time = max_listen_time
        
    try:
        # 检查策略ID
        if not strategy_id:
            return "错误: 策略ID不能为空"

        # 处理choose_stock参数
        stock_info = ""
        if choose_stock:
            # 判断是否已经是完整的choose_stock函数
            if choose_stock.strip().startswith("def choose_stock(context):"):
                # 已经是完整的函数代码，直接使用
                stock_info = choose_stock.strip()
                logger.info("使用提供的choose_stock函数代码进行回测")
            else:
                # 不是函数代码，将其格式化为choose_stock函数
                stock_info = choose_stock
                choose_stock = format_choose_stock(choose_stock)
                logger.info(f"使用指定股票 {stock_info} 进行回测")

        # 准备策略代码数据
        strategy_code = {}
        if indicator:
            strategy_code['indicator'] = indicator
        if control_risk:
            strategy_code['control_risk'] = control_risk
        if timing:
            strategy_code['timing'] = timing
        if choose_stock:
            strategy_code['choose_stock'] = choose_stock

        # 记录策略代码信息，用于调试
        logger.info(f"准备自定义策略代码数据:")
        for key, value in strategy_code.items():
            if value:
                logger.info(f"自定义策略代码 {key} 长度: {len(value)} 字符")
                # 记录代码的前50个字符，用于调试
                logger.info(f"自定义策略代码 {key} 前50个字符: {value[:50]}")

        # 记录传递的参数，用于调试
        logger.info(f"运行回测参数: strategy_id={strategy_id}, 自定义代码: indicator={bool(indicator)}, control_risk={bool(control_risk)}, timing={bool(timing)}, choose_stock={bool(choose_stock)}")

        # 运行回测
        result = run_backtest(
            strategy_id=strategy_id,
            listen_time=listen_time,
            start_date=start_date,
            end_date=end_date,
            indicator=indicator,
            control_risk=control_risk,
            timing=timing,
            choose_stock=choose_stock
        )

        # 格式化输出
        if result['success']:
            # 根据是否使用指定股票生成不同的标题
            if stock_info and not stock_info.startswith("def choose_stock"):
                result_str = f"使用股票 {stock_info} 回测成功完成！\n\n"
            else:
                result_str = f"使用策略自带标的进行，回测成功完成！\n\n"

            result_str += f"策略: {result['strategy_name']} (ID: {result['strategy_id']})\n"
            result_str += f"接收到 {result['position_count']} 条position数据\n"
            result_str += f"数据已保存到: {result['file_path']}\n"

            if result.get('chart_path'):
                result_str += f"\n回测结果图表已生成并在浏览器中打开: {result['chart_path']}"
            else:
                result_str += "\n未生成回测结果图表"

            # 添加日期验证信息
            date_validation = result.get('date_validation', {})
            if date_validation.get('from_date_adjusted') or date_validation.get('to_date_adjusted'):
                result_str += "\n\n日期范围已自动调整:"
                if date_validation.get('from_date_adjusted'):
                    result_str += f"\n- 开始日期从 {date_validation.get('original_from_date')} 调整为 {date_validation.get('adjusted_from_date')} (股票上市日期: {date_validation.get('listing_date')})"
                if date_validation.get('to_date_adjusted'):
                    result_str += f"\n- 结束日期从 {date_validation.get('original_to_date')} 调整为 {date_validation.get('adjusted_to_date')} (股票最后交易日期: {date_validation.get('last_date')})"

            return result_str
        else:
            return f"回测失败: {result.get('error', '未知错误')}"

    except Exception as e:
        logger.error(f"运行回测时发生错误: {e}")
        return f"运行回测时发生错误: {e}"


def register_tools(mcp: FastMCP):
    """
    注册回测相关的工具到MCP服务器

    Args:
        mcp: MCP服务器实例
    """
    # 注册运行策略回测工具
    mcp.tool()(run_strategy_backtest)
