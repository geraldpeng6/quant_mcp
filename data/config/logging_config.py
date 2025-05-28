#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
日志配置模块

提供集中的日志配置，用于所有模块的日志记录
"""

import os
import logging
from pathlib import Path

# 日志目录
LOG_DIR = 'data/logs'

# 确保日志目录存在
os.makedirs(LOG_DIR, exist_ok=True)

# 日志级别配置
DEFAULT_LOG_LEVEL = logging.INFO
DEBUG_LOG_LEVEL = logging.DEBUG
ERROR_LOG_LEVEL = logging.ERROR

# 日志格式
DEFAULT_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
DETAILED_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(pathname)s:%(lineno)d - %(message)s'

# 日志文件配置
MAX_LOG_SIZE = 20 * 1024 * 1024  # 20MB
MAX_LOG_BACKUPS = 10
REQUEST_LOG_SIZE = 40 * 1024 * 1024  # 40MB

# 默认日志记录器名称
DEFAULT_LOGGER_NAME = 'quant_mcp'

# 是否将DEBUG日志写入文件
WRITE_DEBUG_TO_FILE = True

# 是否将INFO及以上级别日志输出到控制台
CONSOLE_OUTPUT = True

# 是否分离请求和响应日志到单独的文件
SEPARATE_REQUEST_LOGS = True

# 是否记录请求和响应的详细内容
LOG_DETAILED_REQUESTS = False

# 日志记录到文件的编码
LOG_ENCODING = 'utf-8'

# 错误邮件通知配置
ENABLE_ERROR_EMAIL = False
ERROR_EMAIL_RECIPIENT = ''
ERROR_EMAIL_SENDER = ''
ERROR_EMAIL_SUBJECT = '[量化交易助手] 错误日志通知'

# 配置字典，用于在不同环境中快速切换配置
LOG_CONFIG_PROFILES = {
    'development': {
        'log_level': DEBUG_LOG_LEVEL,
        'write_debug_to_file': True,
        'console_output': True,
        'log_detailed_requests': True
    },
    'production': {
        'log_level': DEFAULT_LOG_LEVEL,
        'write_debug_to_file': False,
        'console_output': True,
        'log_detailed_requests': False,
        'max_log_size': 50 * 1024 * 1024,  # 50MB
        'max_log_backups': 20
    },
    'testing': {
        'log_level': DEBUG_LOG_LEVEL,
        'write_debug_to_file': True,
        'console_output': True,
        'log_detailed_requests': True
    }
}

# 当前环境，可以通过环境变量设置
CURRENT_ENV = os.environ.get('QUANT_MCP_ENV', 'development') 