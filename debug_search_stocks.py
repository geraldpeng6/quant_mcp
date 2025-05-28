#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
调试股票搜索功能

比较直接调用search_symbols和通过MCP工具search_stocks的区别
"""

import sys
import logging
import json
import os
import asyncio
from utils.symbol_utils import search_symbols
from utils.auth_utils import set_auth_from_mcp
from src.tools.symbol_tools import search_stocks

# 设置日志级别
logging.basicConfig(
    level=logging.DEBUG,  # 使用DEBUG级别以查看更多日志
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger('debug_search')

def load_auth_from_file(auth_file="data/config/auth.json"):
    """
    从auth.json文件加载认证信息
    
    Args:
        auth_file: 认证文件路径
        
    Returns:
        tuple: (token, user_id)
    """
    if not os.path.exists(auth_file):
        print(f"认证文件不存在: {auth_file}")
        return None, None
    
    try:
        with open(auth_file, 'r') as f:
            auth_data = json.load(f)
            return auth_data.get("token"), auth_data.get("user_id")
    except Exception as e:
        print(f"加载认证文件失败: {e}")
        return None, None

async def debug_search():
    """比较两种搜索方法的差异"""
    print("=" * 70)
    print("调试股票搜索功能: 比较直接调用search_symbols和通过MCP工具search_stocks")
    print("=" * 70)
    
    # 加载认证信息
    token, user_id = load_auth_from_file()
    if not token or not user_id:
        print("错误: 无法获取有效的token和user_id")
        sys.exit(1)
    
    print(f"使用user_id: {user_id[:4]}***")
    
    # 设置认证信息
    set_auth_from_mcp(token, user_id)
    
    # 执行搜索
    query = "稳健医疗"
    print(f"\n搜索关键词: {query}")
    
    try:
        print("\n=== 方法1: 直接调用utils.symbol_utils.search_symbols ===")
        # 直接调用搜索函数
        direct_results = search_symbols(query)
        
        if direct_results is None:
            print("直接调用search_symbols失败，未能获取结果")
        else:
            print(f"直接调用search_symbols成功，找到 {len(direct_results)} 个结果")
            # 打印第一个结果（如果有）
            if direct_results and len(direct_results) > 0:
                print("\n第一个结果:")
                print(json.dumps(direct_results[0], ensure_ascii=False, indent=2))
        
        print("\n=== 方法2: 调用MCP工具函数src.tools.symbol_tools.search_stocks ===")
        # 调用MCP工具函数
        mcp_result = await search_stocks(query)
        print(f"MCP工具函数search_stocks返回结果:")
        print(mcp_result)
        
        # 比较两种方法的差异
        if direct_results and "未找到" in mcp_result:
            print("\n=== 调试信息 ===")
            print("发现问题: 直接调用search_symbols成功，但MCP工具函数search_stocks报告未找到结果")
            print("可能的原因:")
            print("1. 参数传递问题")
            print("2. search_stocks函数内部处理逻辑问题")
            print("3. 请求格式化或结果处理问题")
            
            # 检查exchange和symbol_type参数
            print("\n=== 尝试不同参数组合 ===")
            print("使用默认exchange='ANY'和symbol_type='':")
            test_result1 = search_symbols(query, "ANY", "")
            print(f"结果: 找到 {len(test_result1) if test_result1 else 0} 个结果")
            
            print("\n使用exchange='XSHE'(深交所):")
            test_result2 = search_symbols(query, "XSHE", "")
            print(f"结果: 找到 {len(test_result2) if test_result2 else 0} 个结果")
            
            print("\n使用symbol_type='stock':")
            test_result3 = search_symbols(query, "ANY", "stock")
            print(f"结果: 找到 {len(test_result3) if test_result3 else 0} 个结果")
            
    except Exception as e:
        print(f"调试过程中发生错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(debug_search()) 