#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
测试股票搜索功能

测试搜索"稳健医疗"股票的功能
"""

import sys
import logging
import json
import os

# 检查是否在虚拟环境中运行
def check_virtual_env():
    """检查是否在虚拟环境中运行"""
    return (hasattr(sys, 'real_prefix') or
            (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix))

# 如果不在虚拟环境中运行，提示用户并退出
if not check_virtual_env():
    print("=" * 70)
    print("警告: 脚本未在虚拟环境中运行！")
    print("请按照以下步骤激活虚拟环境后再运行测试:")
    print("1. 激活虚拟环境:")
    print("   - Linux/Mac: source .venv/bin/activate")
    print("   - Windows: .venv\\Scripts\\activate")
    print("2. 运行测试脚本:")
    print("   python test_search_stock.py")
    print("=" * 70)
    sys.exit(1)

# 导入模块（在虚拟环境检查之后导入）
from utils.symbol_utils import search_symbols
from utils.auth_utils import set_auth_from_mcp

# 设置日志级别
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger('test_search')

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

def test_search_stock():
    """测试搜索股票功能"""
    print("=" * 50)
    print("测试搜索稳健医疗股票")
    print("=" * 50)
    
    # 方法1: 手动设置认证信息
    token = "输入您的token"  # 需要替换为有效的token，或使用下面的方法2自动加载
    user_id = "输入您的user_id"  # 需要替换为有效的user_id，或使用下面的方法2自动加载
    
    # 方法2: 从auth.json文件加载认证信息
    if token == "输入您的token" or user_id == "输入您的user_id":
        print("尝试从auth.json文件加载认证信息...")
        token, user_id = load_auth_from_file()
        if not token or not user_id:
            print("错误: 无法获取有效的token和user_id")
            print("请手动在脚本中设置token和user_id，或确保auth.json文件存在且包含有效的认证信息")
            sys.exit(1)
    
    print(f"使用user_id: {user_id[:4]}***")
    
    # 设置认证信息
    set_auth_from_mcp(token, user_id)
    
    # 执行搜索
    query = "稳健医疗"
    print(f"搜索关键词: {query}")
    
    try:
        # 搜索股票
        results = search_symbols(query)
        
        if results is None:
            print("搜索失败，未能获取结果")
            return
            
        # 打印搜索结果
        print(f"找到 {len(results)} 个匹配的结果:")
        print("\n代码\t\t交易所\t类型\t名称")
        print("-" * 50)
        
        for symbol in results:
            code = symbol.get('symbol', '-')
            exchange = symbol.get('exchange', '-')
            symbol_type = symbol.get('type', '-')
            name = symbol.get('description', '-')
            full_name = symbol.get('full_name', f"{code}.{exchange}")
            
            print(f"{code}\t\t{exchange}\t{symbol_type}\t{name}")
            
        # 详细打印第一个结果
        if results and len(results) > 0:
            print("\n第一个结果的详细信息:")
            print(json.dumps(results[0], ensure_ascii=False, indent=2))
            
    except Exception as e:
        print(f"搜索过程中发生错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    # 显示虚拟环境信息
    print(f"Python 解释器路径: {sys.executable}")
    print(f"Python 版本: {sys.version.split()[0]}")
    print(f"运行在虚拟环境中: {'是' if check_virtual_env() else '否'}")
    print("")
    
    # 运行测试
    test_search_stock() 