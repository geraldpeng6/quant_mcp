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
import json
from typing import Dict, Any, Optional, List, Tuple
from mcp.server.fastmcp import FastMCP
from mcp.server.middleware import Middleware

from utils.logging_utils import setup_logging, format_json_for_log
from utils.html_server import generate_test_html, is_nginx_available
from utils.auth_utils import set_auth_from_mcp, set_auto_approve_tools
from src.tools import register_all_tools
from src.resources import register_all_resources
from src.prompts import register_all_prompts

# 设置日志
logger = setup_logging('quant_mcp.server')

class AuthMiddleware(Middleware):
    """认证中间件，从MCP客户端配置中提取认证信息"""
    
    def __init__(self):
        self.config_section = "quant_sse"
        logger.info(f"初始化认证中间件，配置节点: {self.config_section}")
    
    def process_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """处理请求，提取认证信息"""
        # 从client_info中获取MCP客户端配置
        client_info = request.get("client_info", {})
        mcp_config = client_info.get("mcp_config", {})
        
        # 记录详细的请求信息，但不记录实际token值
        debug_config = {k: v if k != 'token' else '***' for k, v in mcp_config.items()} if mcp_config else {}
        logger.debug(f"接收到MCP配置: {format_json_for_log(debug_config)}")
        
        # 从quant_sse配置节点获取认证信息
        config = mcp_config.get(self.config_section, {})
        token = config.get("token")
        user_id = config.get("user_id")
        
        # 尝试从两种可能的字段名称获取自动批准工具列表
        auto_approve_tools = config.get("auto_approve_tools", config.get("autoApprove", []))
        
        if token and user_id:
            logger.info(f"从客户端配置获取到认证信息，用户ID: {user_id[:4]}***")
            # 设置认证信息
            set_auth_from_mcp(token, user_id)
            
            # 设置自动批准工具列表
            if auto_approve_tools:
                logger.info(f"从客户端配置获取到自动批准工具列表: {auto_approve_tools}")
                set_auto_approve_tools(auto_approve_tools)
        else:
            logger.warning("从客户端配置中未获取到完整认证信息")
        
        return request

class LoggingMiddleware(Middleware):
    """日志中间件，记录请求和响应信息"""
    
    def process_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """处理请求，记录请求信息"""
        # 避免记录过大的响应，只记录基本信息
        safe_request = self._sanitize_data(request)
        logger.info(f"请求: {format_json_for_log(safe_request)}")
        return request
    
    def process_response(self, response: Dict[str, Any]) -> Dict[str, Any]:
        """处理响应，记录响应信息"""
        # 避免记录过大的响应，只记录基本信息
        safe_response = self._sanitize_data(response)
        logger.info(f"响应: {format_json_for_log(safe_response)}")
        return response
    
    def _sanitize_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        清理数据，避免日志过大
        
        Args:
            data: 原始数据
            
        Returns:
            Dict[str, Any]: 清理后的数据
        """
        if not isinstance(data, dict):
            return {"data_type": str(type(data))}
        
        result = {}
        for key, value in data.items():
            # 敏感信息保护
            if key == "token" or key.endswith("_token"):
                result[key] = "***"
            # 跳过大型内容
            elif key in ["content", "messages", "full_content", "html", "script"]:
                result[key] = f"[{len(str(value))} chars]"
            elif isinstance(value, dict):
                result[key] = self._sanitize_data(value)
            elif isinstance(value, list):
                if len(value) > 10:
                    result[key] = f"[List with {len(value)} items]"
                else:
                    result[key] = [self._sanitize_data(item) if isinstance(item, dict) else item for item in value[:10]]
            else:
                result[key] = value
        
        return result

def create_server(name: str = "量化交易助手") -> FastMCP:
    """
    创建MCP服务器

    Args:
        name: 服务器名称

    Returns:
        FastMCP: MCP服务器实例
    """
    # 创建FastMCP服务器实例
    mcp = FastMCP(name, host="0.0.0.0")
    
    # 注册中间件
    mcp.add_middleware(LoggingMiddleware())  # 先添加日志中间件
    mcp.add_middleware(AuthMiddleware())     # 再添加认证中间件

    # 注册所有MCP组件
    register_all_tools(mcp)      # 注册工具
    register_all_resources(mcp)  # 注册资源
    register_all_prompts(mcp)    # 注册提示模板

    # 打印认证和工具注册状态
    logger.info(f"MCP服务器 '{name}' 创建完成")
    logger.info(f"认证中间件已注册，将从MCP客户端获取认证信息")
    
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
