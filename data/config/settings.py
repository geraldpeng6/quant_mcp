#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
全局设置
包含项目的全局配置参数
"""

import os
import logging
from pathlib import Path

# 项目根目录
ROOT_DIR = Path(__file__).parent.parent

# 配置目录
CONFIG_DIR = ROOT_DIR / 'config'

# 数据目录
DATA_DIR = ROOT_DIR / 'data'

# 日志目录
LOG_DIR = ROOT_DIR / 'logs'

# 临时文件目录
TEMP_DIR = ROOT_DIR / 'temp'

# 图表输出目录
CHARTS_DIR = ROOT_DIR / 'charts'

# 模板目录
TEMPLATES_DIR = ROOT_DIR / 'templates'

# API基础URL
BASE_URL = "https://api.yueniusz.com"

# 确保目录存在
for directory in [LOG_DIR, TEMP_DIR, CHARTS_DIR]:
    directory.mkdir(exist_ok=True)

# 日志配置
LOG_LEVEL = logging.INFO
LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
LOG_FILE = LOG_DIR / 'quant_mcp.log'

# 认证信息 - 由MCP客户端配置提供，不再从文件加载
# 具体实现在utils/auth_utils.py中
