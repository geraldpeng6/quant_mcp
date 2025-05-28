#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
MCP服务器入口
启动MCP服务器，注册工具、资源、提示模板
"""

import sys
import logging
import os
import inspect
from mcp.server.fastmcp import FastMCP

from utils.logging_utils import setup_logging
from utils.html_server import generate_test_html, is_nginx_available
from src.tools import register_all_tools
from src.resources import register_all_resources
from src.prompts import register_all_prompts

# 设置日志
logger = setup_logging('quant_mcp.server')

def create_server(name: str = "量化交易助手") -> FastMCP:
    """
    创建MCP服务器

    Args:
        name: 服务器名称

    Returns:
        FastMCP: MCP服务器实例
    """
    # 创建FastMCP服务器实例
    mcp = FastMCP(name)

    # 注册所有MCP组件
    register_all_tools(mcp)      # 注册工具
    register_all_resources(mcp)  # 注册资源
    register_all_prompts(mcp)    # 注册提示模板

    return mcp

def run_server(transport: str = 'stdio', host: str = '0.0.0.0', port: int = 8000):
    """
    运行MCP服务器

    Args:
        transport: 传输协议，默认为stdio，支持 'stdio', 'sse', 'streamable-http'
        host: 主机地址，当使用 'sse' 或 'streamable-http' 传输协议时有效
        port: 端口号，当使用 'sse' 或 'streamable-http' 传输协议时有效
    """
    try:
        # 确保必要的目录存在
        os.makedirs('data/logs', exist_ok=True)
        os.makedirs('data/klines', exist_ok=True)
        os.makedirs('data/charts', exist_ok=True)
        os.makedirs('data/temp', exist_ok=True)
        os.makedirs('data/config', exist_ok=True)
        os.makedirs('data/backtest', exist_ok=True)
        os.makedirs('data/templates', exist_ok=True)

        # 检查配置文件
        if not os.path.exists('data/config/auth.json'):
            logger.warning("认证配置文件不存在，请复制 data/config/auth.json.example 并填写认证信息")
            print("警告: 认证配置文件不存在，请复制 data/config/auth.json.example 并填写认证信息", file=sys.stderr)

        # 生成测试HTML文件
        try:
            test_url = generate_test_html()
            if test_url:
                logger.info(f"测试HTML文件已生成，URL: {test_url}")
                print(f"测试HTML文件已生成，URL: {test_url}")

                # 检查Nginx是否可用
                if is_nginx_available():
                    logger.info("检测到Nginx已安装，HTML文件可通过Web服务器访问")
                    print("检测到Nginx已安装，HTML文件可通过Web服务器访问")
                else:
                    logger.warning("未检测到Nginx，HTML文件将通过本地文件URL访问")
                    print("警告: 未检测到Nginx，HTML文件将通过本地文件URL访问", file=sys.stderr)
            else:
                logger.warning("生成测试HTML文件失败")
                print("警告: 生成测试HTML文件失败", file=sys.stderr)
        except Exception as e:
            logger.error(f"生成测试HTML文件时发生错误: {e}")
            print(f"错误: 生成测试HTML文件时发生错误: {e}", file=sys.stderr)

        # 确保host是0.0.0.0以允许外部访问
        if host != '0.0.0.0':
            logger.warning(f"主机地址已从 {host} 更改为 0.0.0.0 以允许外部访问")
            print(f"警告: 主机地址已从 {host} 更改为 0.0.0.0 以允许外部访问", file=sys.stderr)
            host = '0.0.0.0'

        # 创建服务器
        mcp = create_server()

        # 启动服务器
        logger.info(f"启动MCP服务器，使用 {transport} 传输协议")
        print(f"启动量化交易助手MCP服务器，使用 {transport} 传输协议")

        # 根据传输协议选择不同的启动方式
        if transport == 'stdio':
            mcp.run(transport=transport)
        elif transport == 'sse':
            print(f"SSE服务器将在 http://{host}:{port}/sse 上运行")
            logger.info(f"SSE服务器将在 http://{host}:{port}/sse 上运行")

            # 强制设置环境变量确保监听在0.0.0.0
            os.environ['MCP_SSE_HOST'] = '0.0.0.0'
            os.environ['MCP_SSE_PORT'] = str(port)

            # 检查MCP版本，不同版本的API可能不同
            run_params = inspect.signature(mcp.run).parameters

            if 'host' in run_params and 'port' in run_params:
                # 新版本API - 明确传入0.0.0.0
                mcp.run(transport=transport, host='0.0.0.0', port=port)
            else:
                # 旧版本API - 使用环境变量
                mcp.run(transport=transport)

        elif transport == 'streamable-http':
            print(f"Streamable HTTP服务器将在 http://{host}:{port}/mcp 上运行")
            logger.info(f"Streamable HTTP服务器将在 http://{host}:{port}/mcp 上运行")

            # 强制设置环境变量确保监听在0.0.0.0
            os.environ['MCP_HTTP_HOST'] = '0.0.0.0'
            os.environ['MCP_HTTP_PORT'] = str(port)
            os.environ['MCP_HTTP_PATH'] = '/mcp'

            # 检查MCP版本，不同版本的API可能不同
            run_params = inspect.signature(mcp.run).parameters

            if 'host' in run_params and 'port' in run_params and 'path' in run_params:
                # 新版本API - 明确传入0.0.0.0
                mcp.run(transport=transport, host='0.0.0.0', port=port, path='/mcp')
            else:
                # 旧版本API - 使用环境变量
                mcp.run(transport=transport)
        else:
            raise ValueError(f"不支持的传输协议: {transport}")
    except Exception as e:
        logger.error(f"启动MCP服务器失败: {e}")
        print(f"错误: 启动MCP服务器失败: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    import argparse

    # 创建命令行参数解析器
    parser = argparse.ArgumentParser(description='启动MCP服务器')
    parser.add_argument('--transport', '-t', type=str, default='stdio',
                        choices=['stdio', 'sse', 'streamable-http'],
                        help='传输协议 (stdio, sse, streamable-http)')
    parser.add_argument('--host', '-H', type=str, default='0.0.0.0',
                        help='主机地址，当使用 sse 或 streamable-http 传输协议时有效')
    parser.add_argument('--port', '-p', type=int, default=8000,
                        help='端口号，当使用 sse 或 streamable-http 传输协议时有效')

    # 解析命令行参数
    args = parser.parse_args()

    # 运行服务器
    run_server(transport=args.transport, host=args.host, port=args.port)
