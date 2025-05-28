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
import traceback
from logging.handlers import RotatingFileHandler, SMTPHandler
import json
import importlib.util

# 尝试导入集中配置，如果不存在则使用默认值
try:
    # 检查配置文件是否存在
    config_path = os.path.join('data', 'config', 'logging_config.py')
    if os.path.exists(config_path):
        spec = importlib.util.spec_from_file_location("logging_config", config_path)
        config = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(config)
        
        # 从配置模块中获取配置
        LOG_DIR = getattr(config, 'LOG_DIR', 'data/logs')
        DEFAULT_LOG_LEVEL = getattr(config, 'DEFAULT_LOG_LEVEL', logging.INFO)
        DEBUG_LOG_LEVEL = getattr(config, 'DEBUG_LOG_LEVEL', logging.DEBUG)
        DEFAULT_LOG_FORMAT = getattr(config, 'DEFAULT_LOG_FORMAT', '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        DETAILED_LOG_FORMAT = getattr(config, 'DETAILED_LOG_FORMAT', '%(asctime)s - %(name)s - %(levelname)s - %(pathname)s:%(lineno)d - %(message)s')
        MAX_LOG_SIZE = getattr(config, 'MAX_LOG_SIZE', 20 * 1024 * 1024)
        MAX_LOG_BACKUPS = getattr(config, 'MAX_LOG_BACKUPS', 10)
        REQUEST_LOG_SIZE = getattr(config, 'REQUEST_LOG_SIZE', 40 * 1024 * 1024)
        WRITE_DEBUG_TO_FILE = getattr(config, 'WRITE_DEBUG_TO_FILE', True)
        CONSOLE_OUTPUT = getattr(config, 'CONSOLE_OUTPUT', True)
        SEPARATE_REQUEST_LOGS = getattr(config, 'SEPARATE_REQUEST_LOGS', True)
        LOG_ENCODING = getattr(config, 'LOG_ENCODING', 'utf-8')
        ENABLE_ERROR_EMAIL = getattr(config, 'ENABLE_ERROR_EMAIL', False)
        ERROR_EMAIL_RECIPIENT = getattr(config, 'ERROR_EMAIL_RECIPIENT', '')
        ERROR_EMAIL_SENDER = getattr(config, 'ERROR_EMAIL_SENDER', '')
        ERROR_EMAIL_SUBJECT = getattr(config, 'ERROR_EMAIL_SUBJECT', '[量化交易助手] 错误日志通知')
        
        # 获取当前环境配置
        CURRENT_ENV = getattr(config, 'CURRENT_ENV', 'development')
        CONFIG_PROFILES = getattr(config, 'LOG_CONFIG_PROFILES', {})
        
        # 应用当前环境的配置
        if CURRENT_ENV in CONFIG_PROFILES:
            env_config = CONFIG_PROFILES[CURRENT_ENV]
            for key, value in env_config.items():
                # 仅使用配置中存在的属性
                if hasattr(config, key):
                    globals()[key.upper()] = value
    else:
        # 使用默认配置
        LOG_DIR = 'data/logs'
        DEFAULT_LOG_LEVEL = logging.INFO
        DEBUG_LOG_LEVEL = logging.DEBUG
        DEFAULT_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        DETAILED_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(pathname)s:%(lineno)d - %(message)s'
        MAX_LOG_SIZE = 20 * 1024 * 1024  # 20MB
        MAX_LOG_BACKUPS = 10
        REQUEST_LOG_SIZE = 40 * 1024 * 1024  # 40MB
        WRITE_DEBUG_TO_FILE = True
        CONSOLE_OUTPUT = True
        SEPARATE_REQUEST_LOGS = True
        LOG_ENCODING = 'utf-8'
        ENABLE_ERROR_EMAIL = False
        ERROR_EMAIL_RECIPIENT = ''
        ERROR_EMAIL_SENDER = ''
        ERROR_EMAIL_SUBJECT = '[量化交易助手] 错误日志通知'
except Exception as e:
    # 如果加载配置失败，使用默认值
    print(f"加载日志配置失败: {e}，将使用默认配置", file=sys.stderr)
    LOG_DIR = 'data/logs'
    DEFAULT_LOG_LEVEL = logging.INFO
    DEBUG_LOG_LEVEL = logging.DEBUG
    DEFAULT_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    DETAILED_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(pathname)s:%(lineno)d - %(message)s'
    MAX_LOG_SIZE = 20 * 1024 * 1024  # 20MB
    MAX_LOG_BACKUPS = 10
    REQUEST_LOG_SIZE = 40 * 1024 * 1024  # 40MB
    WRITE_DEBUG_TO_FILE = True
    CONSOLE_OUTPUT = True
    SEPARATE_REQUEST_LOGS = True
    LOG_ENCODING = 'utf-8'
    ENABLE_ERROR_EMAIL = False
    ERROR_EMAIL_RECIPIENT = ''
    ERROR_EMAIL_SENDER = ''
    ERROR_EMAIL_SUBJECT = '[量化交易助手] 错误日志通知'


def setup_logging(logger_name, log_level=None, log_dir=None, max_bytes=None, backup_count=None):
    """
    设置日志记录器

    Args:
        logger_name: 日志记录器名称
        log_level: 日志级别，默认为配置中的值
        log_dir: 日志目录，默认为配置中的值
        max_bytes: 单个日志文件最大字节数，默认为配置中的值
        backup_count: 备份文件数量，默认为配置中的值

    Returns:
        logging.Logger: 配置好的日志记录器
    """
    # 使用配置值或参数值
    log_level = log_level if log_level is not None else DEFAULT_LOG_LEVEL
    log_dir = log_dir if log_dir is not None else LOG_DIR
    max_bytes = max_bytes if max_bytes is not None else MAX_LOG_SIZE
    backup_count = backup_count if backup_count is not None else MAX_LOG_BACKUPS
    
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
    
    # 创建错误日志文件名
    error_log_file = os.path.join(log_dir, f'{log_basename}_errors_{today}.log')
    
    # 创建基本日志处理器，使用RotatingFileHandler进行日志轮转
    file_handler = RotatingFileHandler(
        log_file,
        maxBytes=max_bytes,
        backupCount=backup_count,
        encoding=LOG_ENCODING
    )
    file_handler.setLevel(log_level)

    # 根据配置决定是否创建请求日志处理器
    request_handler = None
    if SEPARATE_REQUEST_LOGS:
        request_handler = RotatingFileHandler(
            request_log_file,
            maxBytes=REQUEST_LOG_SIZE,
            backupCount=backup_count,
            encoding=LOG_ENCODING
        )
        request_handler.setLevel(DEBUG_LOG_LEVEL)  # 请求日志记录更详细信息
    
    # 创建错误日志处理器
    error_handler = RotatingFileHandler(
        error_log_file,
        maxBytes=max_bytes,
        backupCount=backup_count,
        encoding=LOG_ENCODING
    )
    error_handler.setLevel(logging.ERROR)  # 只记录ERROR及以上级别
    
    # 根据配置决定是否添加控制台处理器
    console_handler = None
    if CONSOLE_OUTPUT:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)  # 控制台只输出INFO及以上级别

    # 设置标准日志格式
    formatter = logging.Formatter(DEFAULT_LOG_FORMAT)
    file_handler.setFormatter(formatter)
    if console_handler:
        console_handler.setFormatter(formatter)
    
    # 设置请求日志格式 - 更详细
    if request_handler:
        request_formatter = logging.Formatter(DEFAULT_LOG_FORMAT)
        request_handler.setFormatter(request_formatter)
    
    # 设置错误日志格式 - 包含更多信息
    error_formatter = logging.Formatter(DETAILED_LOG_FORMAT)
    error_handler.setFormatter(error_formatter)
    
    # 创建过滤器，使请求处理器只处理特定消息
    if request_handler:
        class RequestFilter(logging.Filter):
            def filter(self, record):
                return '请求:' in record.getMessage() or '响应:' in record.getMessage()
        
        request_filter = RequestFilter()
        request_handler.addFilter(request_filter)
    
    # 创建过滤器，使错误处理器只处理错误及以上级别
    class ErrorFilter(logging.Filter):
        def filter(self, record):
            return record.levelno >= logging.ERROR
    
    error_filter = ErrorFilter()
    error_handler.addFilter(error_filter)
    
    # 添加邮件通知处理器（如果配置了）
    if ENABLE_ERROR_EMAIL and ERROR_EMAIL_RECIPIENT and ERROR_EMAIL_SENDER:
        mail_handler = SMTPHandler(
            mailhost=('localhost', 25),
            fromaddr=ERROR_EMAIL_SENDER,
            toaddrs=ERROR_EMAIL_RECIPIENT,
            subject=ERROR_EMAIL_SUBJECT
        )
        mail_handler.setLevel(logging.ERROR)
        mail_handler.setFormatter(error_formatter)
        logger.addHandler(mail_handler)
    
    # 添加处理器到记录器
    logger.addHandler(file_handler)
    if console_handler:
        logger.addHandler(console_handler)
    if request_handler:
        logger.addHandler(request_handler)
    logger.addHandler(error_handler)

    # 防止日志重复输出
    logger.propagate = False

    # 记录初始化信息
    init_msg = f"日志系统初始化完成，基础日志: {log_file}, 错误日志: {error_log_file}"
    if request_handler:
        init_msg += f", 请求日志: {request_log_file}"
    logger.info(init_msg)
    
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


def log_exception(logger, message="发生异常", exc_info=None):
    """
    记录异常信息
    
    Args:
        logger: 日志记录器
        message: 异常信息前缀
        exc_info: 异常信息，如果为None则自动获取
    """
    if exc_info is None:
        exc_info = sys.exc_info()
    
    if exc_info[0] is not None:
        tb_lines = traceback.format_exception(*exc_info)
        tb_text = ''.join(tb_lines)
        logger.error(f"{message}: {exc_info[1]}\n{tb_text}")
    else:
        logger.error(message)


def configure_root_logger(log_dir=None):
    """
    配置根日志记录器，确保所有未捕获的日志都能被记录
    
    Args:
        log_dir: 日志目录，默认为配置中的值
    """
    log_dir = log_dir if log_dir is not None else LOG_DIR
    
    # 确保日志目录存在
    os.makedirs(log_dir, exist_ok=True)
    
    # 获取根日志记录器
    root_logger = logging.getLogger()
    
    # 如果已经有处理器，不再添加
    if root_logger.handlers:
        return
    
    # 设置根日志级别
    root_logger.setLevel(DEFAULT_LOG_LEVEL)
    
    # 创建日志文件名
    today = datetime.datetime.now().strftime('%Y%m%d')
    root_log_file = os.path.join(log_dir, f'root_{today}.log')
    
    # 创建处理器
    handler = RotatingFileHandler(
        root_log_file,
        maxBytes=MAX_LOG_SIZE // 2,  # 根日志文件大小为主日志的一半
        backupCount=MAX_LOG_BACKUPS // 2,  # 根日志备份数量为主日志的一半
        encoding=LOG_ENCODING
    )
    
    # 设置格式
    formatter = logging.Formatter(DEFAULT_LOG_FORMAT)
    handler.setFormatter(formatter)
    
    # 添加处理器
    root_logger.addHandler(handler)
    
    # 添加未捕获异常处理
    def handle_exception(exc_type, exc_value, exc_traceback):
        if issubclass(exc_type, KeyboardInterrupt):
            # 对于键盘中断，使用默认处理
            sys.__excepthook__(exc_type, exc_value, exc_traceback)
            return
        
        # 记录未捕获的异常
        root_logger.error("未捕获的异常", exc_info=(exc_type, exc_value, exc_traceback))
    
    # 设置全局异常钩子
    sys.excepthook = handle_exception
