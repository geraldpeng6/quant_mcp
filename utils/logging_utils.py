#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
日志工具模块

提供日志设置和配置功能，支持控制台和文件输出，记录详细的请求和响应信息
"""

import os
import sys
import logging
import datetime
from logging.handlers import RotatingFileHandler
import json
import traceback


def setup_logging(logger_name, log_level=logging.INFO, log_dir='data/logs', max_bytes=20485760, backup_count=10):
    """
    设置日志记录器

    Args:
        logger_name: 日志记录器名称
        log_level: 日志级别，默认为INFO
        log_dir: 日志目录，默认为'data/logs'
        max_bytes: 单个日志文件最大字节数，默认为20MB
        backup_count: 备份文件数量，默认为10

    Returns:
        logging.Logger: 配置好的日志记录器
    """
    # 确保日志目录存在
    os.makedirs(log_dir, exist_ok=True)

    # 创建日志记录器
    logger = logging.getLogger(logger_name)
    logger.setLevel(log_level)

    # 如果已经有处理器，不再添加
    if logger.handlers:
        return logger

    # 创建基本的日志文件名，包含日期
    today = datetime.datetime.now().strftime('%Y%m%d')
    log_basename = logger_name.split(".")[-1]
    log_file = os.path.join(log_dir, f'{log_basename}_{today}.log')
    
    # 创建详细请求日志文件名
    request_log_file = os.path.join(log_dir, f'{log_basename}_requests_{today}.log')
    
    # 创建基本日志处理器，使用RotatingFileHandler进行日志轮转
    file_handler = RotatingFileHandler(
        log_file,
        maxBytes=max_bytes,
        backupCount=backup_count,
        encoding='utf-8'
    )
    file_handler.setLevel(log_level)

    # 创建请求日志处理器
    request_handler = RotatingFileHandler(
        request_log_file,
        maxBytes=max_bytes * 2,  # 请求日志可能更大
        backupCount=backup_count,
        encoding='utf-8'
    )
    request_handler.setLevel(logging.DEBUG)  # 请求日志记录更详细信息
    
    # 添加控制台处理器
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)  # 控制台只输出INFO及以上级别

    # 设置标准日志格式
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    file_handler.setFormatter(formatter)
    console_handler.setFormatter(formatter)
    
    # 设置请求日志格式 - 更详细
    request_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    request_handler.setFormatter(request_formatter)
    
    # 创建过滤器，使请求处理器只处理特定消息
    class RequestFilter(logging.Filter):
        def filter(self, record):
            return '请求:' in record.getMessage() or '响应:' in record.getMessage()
    
    request_filter = RequestFilter()
    request_handler.addFilter(request_filter)
    
    # 添加处理器到记录器
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    logger.addHandler(request_handler)

    # 防止日志重复输出
    logger.propagate = False

    logger.info(f"日志系统初始化完成，基础日志: {log_file}, 请求日志: {request_log_file}")
    return logger


def format_json_for_log(obj, indent=None):
    """
    格式化JSON对象以便于日志记录
    
    Args:
        obj: 要格式化的对象
        indent: 缩进，默认为None
        
    Returns:
        str: 格式化后的JSON字符串
    """
    try:
        return json.dumps(obj, ensure_ascii=False, indent=indent)
    except Exception as e:
        return f"无法序列化对象: {str(e)}, 类型: {type(obj)}"


def log_exception(logger, message: str, exc: Exception = None, exc_info: bool = False) -> None:
    """
    记录异常信息到日志
    
    Args:
        logger: 日志记录器
        message: 日志消息
        exc: 异常对象，如果不提供则尝试从当前异常中获取
        exc_info: 是否包含异常详细信息
    """
    if exc is None:
        exc_info = True
        
    if exc_info:
        logger.error(f"{message}: {str(exc) if exc else ''}", exc_info=True)
    else:
        exc_str = str(exc) if exc else ""
        stack_trace = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__)) if exc else ""
        logger.error(f"{message}: {exc_str}\n{stack_trace}")
