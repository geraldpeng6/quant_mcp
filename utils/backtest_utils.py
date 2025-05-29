#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
回测工具模块

提供回测相关的核心功能，包括MQTT连接、回测请求发送和结果处理
"""

import os
import json
import time
import logging
import requests
import gzip
import io
import re
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List, Tuple, Union
import paho.mqtt.client as mqtt
import socks  # 用于SOCKS代理支持

from utils.auth_utils import load_auth_config, get_auth_info, get_headers
from utils.kline_utils import fetch_and_save_kline
from utils.chart_generator import open_in_browser, generate_backtest_html, load_backtest_data
from utils.symbol_utils import validate_date_range

# 获取日志记录器
logger = logging.getLogger('quant_mcp.backtest_utils')

# API基础URL
BASE_URL = "https://api.yueniusz.com"

# 数据目录
DATA_DIR = 'data'
BACKTEST_DIR = os.path.join(DATA_DIR, 'backtest')
CHARTS_DIR = os.path.join(DATA_DIR, 'charts')
TEMPLATES_DIR = os.path.join(DATA_DIR, 'templates')

# 确保目录存在
os.makedirs(BACKTEST_DIR, exist_ok=True)
os.makedirs(CHARTS_DIR, exist_ok=True)


def load_proxy_config() -> Tuple[Optional[Dict[str, str]], Optional[str]]:
    """
    加载代理配置

    从config/proxy.json加载代理配置，支持动态启用/禁用代理

    Returns:
        Tuple[Optional[Dict[str, str]], Optional[str]]: (HTTP代理配置, WebSocket代理配置)
    """
    try:
        proxy_file = 'data/config/proxy.json'
        if os.path.exists(proxy_file):
            with open(proxy_file, 'r', encoding='utf-8') as f:
                proxy_config = json.load(f)

            # 检查是否启用代理
            proxy_enabled = proxy_config.get('enabled', True)

            if not proxy_enabled:
                logger.info("代理已在配置中明确禁用，将使用直接连接")
                return None, None

            # 检查配置是否为空或无效
            if not proxy_config or len(proxy_config) <= 1:  # 只有enabled字段或空
                logger.warning("代理配置文件存在但内容为空，将使用直接连接")
                return None, None
            else:
                # 设置HTTP/HTTPS代理
                http_proxy = proxy_config.get('http')
                https_proxy = proxy_config.get('https')

                # 只有当代理值不为空时才设置
                proxies = {}
                if http_proxy:
                    proxies['http'] = http_proxy
                if https_proxy:
                    proxies['https'] = https_proxy

                # 如果没有有效代理，设置为None
                if not proxies:
                    proxies = None

                # 设置WebSocket代理（确保不为空）
                websocket_proxy = proxy_config.get('websocket')

                logger.info(f"已加载代理配置: HTTP={proxies.get('http') if proxies else 'None'}, "
                            f"HTTPS={proxies.get('https') if proxies else 'None'}, "
                            f"WebSocket={websocket_proxy if websocket_proxy else 'None'}")
                return proxies, websocket_proxy
        else:
            logger.info("未找到代理配置文件，将使用直接连接")
            return None, None
    except Exception as e:
        logger.error(f"加载代理配置异常: {e}")
        return None, None


def get_mqtt_info() -> Optional[Dict[str, Any]]:
    """
    获取MQTT连接信息

    Returns:
        Optional[Dict[str, Any]]: MQTT连接信息，包含instance_id, client_id, trader_id, username, password
    """
    # 获取认证信息
    token, user_id = get_auth_info()
    if not token or not user_id:
        logger.error("无法获取认证信息")
        return None

    try:
        # 构建请求URL
        url = f"{BASE_URL}/trader-service/strategy/back-test/mqtt-info"

        # 构建请求参数
        params = {
            'user_id': user_id
        }

        # 获取请求头
        headers = get_headers()

        # 加载代理配置
        proxies, _ = load_proxy_config()

        # 发送请求
        response = requests.get(
            url,
            params=params,
            headers=headers,
            proxies=proxies,
            verify=True
        )

        # 检查响应状态
        if response.status_code == 200:
            result = response.json()
            if result.get('code') == 1 and result.get('msg') == 'ok':
                mqtt_info = result.get('data')
                logger.info(f"获取MQTT连接信息成功: instance_id={mqtt_info.get('instance_id')}, client_id={mqtt_info.get('client_id')}")
                return mqtt_info
            else:
                logger.error(f"获取MQTT连接信息失败: {result.get('msg')}")
        else:
            logger.error(f"获取MQTT连接信息请求失败，状态码: {response.status_code}")

    except Exception as e:
        logger.error(f"获取MQTT连接信息异常: {e}")

    return None


def send_backtest_request(
    strategy_id: str,
    mqtt_info: Dict[str, Any],
    strategy_data: Optional[Dict[str, Any]] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None
) -> Optional[str]:
    """
    发送回测请求

    Args:
        strategy_id: 策略ID
        mqtt_info: MQTT连接信息
        strategy_data: 策略数据，可选，如果提供则使用此数据而不是从API获取
        start_date: 回测开始日期，格式为 "YYYY-MM-DD"，可选，默认为一年前
        end_date: 回测结束日期，格式为 "YYYY-MM-DD"，可选，默认为今天

    Returns:
        Optional[str]: 回测token，如果请求失败则返回None
    """
    # 获取认证信息
    token, user_id = get_auth_info()
    if not token or not user_id:
        logger.error("无法获取认证信息")
        return None

    try:
        # 处理日期参数
        # 默认时间范围：一年前到今天
        default_start_date = (datetime.now() - timedelta(days=365)).strftime("%Y-%m-%d")
        default_end_date = datetime.now().strftime("%Y-%m-%d")

        # 使用提供的日期或默认值
        start_date = start_date or default_start_date
        end_date = end_date or default_end_date

        logger.info(f"回测时间范围: {start_date} 到 {end_date}")

        # 转换为时间戳（毫秒）
        try:
            start_timestamp = int(datetime.strptime(start_date, "%Y-%m-%d").timestamp() * 1000)
            end_timestamp = int(datetime.strptime(end_date, "%Y-%m-%d").timestamp() * 1000)
            time_range = [f"{start_date} 00:00:00", f"{end_date} 23:59:59"]
        except ValueError as e:
            logger.error(f"日期格式错误: {e}，使用默认时间范围")
            # 出错时使用默认值
            start_date = default_start_date
            end_date = default_end_date
            start_timestamp = int(datetime.strptime(start_date, "%Y-%m-%d").timestamp() * 1000)
            end_timestamp = int(datetime.strptime(end_date, "%Y-%m-%d").timestamp() * 1000)
            time_range = [f"{start_date} 00:00:00", f"{end_date} 23:59:59"]

        # 构建回测请求URL
        url = f"{BASE_URL}/trader-service/strategy/back-test"

        # 构建请求参数
        params = {
            'user_id': user_id
        }

        # 加载代理配置
        proxies, _ = load_proxy_config()

        # 构建请求数据
        data = {
            "strategy_name": "双均线策略",
            "message": {
                "title": "双均线策略",
                "riskfreerate": 0.01,
                "capital": 200000,
                "order": 500,
                "margin": 0.05,
                "commission": 0.0003,
                "pyramiding": 1,
                "currency": "CNY",
                "fq": "post",
                "resolution": "1D",
                # 使用已处理好的时间戳
                "rangTime": [start_timestamp, end_timestamp],
                "startDate": start_date,
                "endDate": end_date,
                "indicators": '''def indicators(context):
    """指标"""
    # 计算15日均价，赋值给变量context.sma
    context.sma = SMA(period=15)
''',
                "choose_stocks": '''def choose_stock(context):
    """选股"""
    context.symbol_list = ["600000.XSHG"]
''',
                "timing": '''def timing(context):
    """择时"""
    # 判断是否持仓，如果不持仓，则判断是否出现买入信号
    if not context.position:
        # 当股票收盘价低于并且交叉穿过15日均价时，出现买入信号
        if context.data.close[-1] < context.sma[-1] and context.data.close[0] > context.sma[0]:
            # 买入信号出现时，发送买入指令，系统自动执行买入交易
            context.order = context.buy(price=context.data.close[0]*1.1)

    # 如果持仓，则判断是否出现卖出信号
    else:
        # 当股票收盘价小于15日均价时，出现卖出信号
        if context.data.close[-1] > context.sma[-1] and context.data.close[0] < context.sma[0]:
            # 卖出信号出现时，发送卖出指令，系统自动执行卖出交易
            context.order = context.sell(price=context.data.close[0]*0.9)
''',
                "control_risk": '''def control_risk(context):
    """风控"""
    pass
''',
                "frequency": "D",
                "time_range": time_range,
                "env": "prod",
                "size": 500,
                "channel": 0,
                "mode": "backtest",
                "instance_id": mqtt_info.get('instance_id'),
                "client_id": mqtt_info.get('client_id'),
                "trader_id": mqtt_info.get('trader_id'),
                "username": mqtt_info.get('username'),
                "password": mqtt_info.get('password')
            },
            "user_id": user_id
        }

        # 如果提供了策略数据，使用策略中的参数
        if strategy_data:
            # 更新策略名称
            if strategy_data.get('name'):
                data["strategy_name"] = strategy_data.get('name')
                data["message"]["title"] = strategy_data.get('name')
            elif strategy_data.get('strategy_name'):
                data["strategy_name"] = strategy_data.get('strategy_name')
                data["message"]["title"] = strategy_data.get('strategy_name')

            # 更新策略参数
            if strategy_data.get('indicator'):
                data["message"]["indicators"] = strategy_data.get('indicator')

            if strategy_data.get('control_risk'):
                data["message"]["control_risk"] = strategy_data.get('control_risk')

            if strategy_data.get('timing'):
                data["message"]["timing"] = strategy_data.get('timing')

            # 更新选股代码
            if strategy_data.get('choose_stock'):
                data["message"]["choose_stocks"] = strategy_data.get('choose_stock')
                logger.info(f"使用策略中的选股代码: {strategy_data.get('choose_stock')[:100]}...")

        # 添加策略ID
        data["message"]["strategy_id"] = strategy_id

        # 发送请求
        logger.info(f"发送回测请求，策略ID: {strategy_id}")

        # 获取请求头
        headers = get_headers()

        # 发送请求
        response = requests.post(
            url,
            params=params,
            headers=headers,
            json=data,
            proxies=proxies,
            verify=True
        )

        # 检查响应状态
        if response.status_code == 200:
            result = response.json()
            if result.get('code') == 1 and result.get('msg') == 'ok':
                backtest_token = result.get('data', {}).get('token')
                logger.info(f"发送回测请求成功，获取到token: {backtest_token}")
                return backtest_token
            else:
                logger.error(f"发送回测请求失败: {result.get('msg')}")
        else:
            logger.error(f"发送回测请求失败，状态码: {response.status_code}")

    except Exception as e:
        logger.error(f"发送回测请求异常: {e}")

    return None


class MQTTBacktestClient:
    """MQTT回测客户端类，用于连接MQTT服务器并接收回测数据"""

    def __init__(self):
        """初始化MQTT回测客户端"""
        self.mqtt_client = None
        self.mqtt_info = None
        self.is_connected = False
        self.subscribed_topics = set()
        self.position_data = []
        self.proxies, self.websocket_proxy = load_proxy_config()

    def connect(self, mqtt_info: Dict[str, Any], use_websockets: bool = True) -> bool:
        """
        连接到MQTT服务器

        Args:
            mqtt_info: MQTT连接信息
            use_websockets: 是否使用WebSocket连接，默认为True

        Returns:
            bool: 连接是否成功
        """
        self.mqtt_info = mqtt_info

        try:
            # 准备MQTT CONNECT连接参数
            instance_id = mqtt_info.get('instance_id')
            client_id = mqtt_info.get('client_id')
            username = mqtt_info.get('username')
            password = mqtt_info.get('password')

            # 构建GID格式的客户端ID (Alibaba Cloud MQTT要求)
            gid_client_id = f"GID_human@@@{client_id}"

            if use_websockets:
                # WebSockets连接参数
                host = f"{instance_id}.mqtt.aliyuncs.com"
                port = 443
                transport = "websockets"
                path = "/mqtt"

                logger.info(f"准备WebSockets MQTT连接: wss://{host}:{port}{path}")
            else:
                # TCP连接参数
                host = f"{instance_id}.mqtt.aliyuncs.com"
                port = 1883
                transport = "tcp"
                path = None

                logger.info(f"准备TCP MQTT连接: mqtt://{host}:{port}")

            # 创建MQTT客户端
            self.mqtt_client = mqtt.Client(client_id=gid_client_id, transport=transport)

            # 设置认证信息
            self.mqtt_client.username_pw_set(username=username, password=password)

            # 设置回调函数
            self.mqtt_client.on_connect = self._on_connect
            self.mqtt_client.on_disconnect = self._on_disconnect
            self.mqtt_client.on_message = self._on_message

            # 配置WebSocket选项（如果使用WebSocket）
            if use_websockets:
                self.mqtt_client.ws_set_options(path=path)

                # 启用TLS/SSL
                import ssl
                self.mqtt_client.tls_set(cert_reqs=ssl.CERT_NONE)
                self.mqtt_client.tls_insecure_set(True)

            # 配置代理（如果有）
            if self.proxies and 'http' in self.proxies:
                proxy_url = self.proxies['http']
                if proxy_url.startswith('http://'):
                    proxy_url = proxy_url[7:]  # 移除http://前缀

                if ':' in proxy_url:
                    proxy_host, proxy_port = proxy_url.split(':')
                    proxy_port = int(proxy_port)

                    logger.info(f"设置MQTT代理: {proxy_host}:{proxy_port}")

                    # 设置SOCKS代理
                    self.mqtt_client.proxy_set(proxy_type=socks.HTTP, proxy_addr=proxy_host, proxy_port=proxy_port)

            # 连接到MQTT服务器
            logger.info(f"正在连接到MQTT服务器: {host}:{port}")
            self.mqtt_client.connect(host, port, 60)

            # 启动网络循环
            self.mqtt_client.loop_start()

            # 等待连接成功或超时
            for _ in range(10):  # 最多等待10秒
                if self.is_connected:
                    logger.info("MQTT连接成功建立")
                    return True
                time.sleep(1)

            logger.error("MQTT连接超时")
            return False

        except Exception as e:
            logger.error(f"连接MQTT服务器异常: {e}")
            if self.mqtt_client:
                try:
                    self.mqtt_client.loop_stop()
                    self.mqtt_client.disconnect()
                except:
                    pass
            return False

    def disconnect(self) -> bool:
        """
        断开MQTT连接

        Returns:
            bool: 断开连接是否成功
        """
        if not self.mqtt_client:
            logger.warning("MQTT客户端未初始化，无需断开连接")
            return True

        try:
            # 停止网络循环
            self.mqtt_client.loop_stop()

            # 断开连接
            if self.is_connected:
                self.mqtt_client.disconnect()
                # 等待断开连接完成
                for _ in range(5):  # 最多等待5秒
                    if not self.is_connected:
                        break
                    time.sleep(1)

            # 清理状态
            self.is_connected = False
            self.subscribed_topics.clear()
            logger.info("MQTT连接已断开，资源已清理")
            return True

        except Exception as e:
            logger.error(f"断开MQTT连接异常: {e}")

            # 强制清理状态
            self.is_connected = False
            self.subscribed_topics.clear()
            return False

    def _on_connect(self, client, userdata, flags, rc):
        """
        MQTT连接回调函数

        Args:
            client: MQTT客户端实例
            userdata: 用户数据
            flags: 连接标志
            rc: 连接结果代码
        """
        rc_messages = {
            0: "连接成功",
            1: "连接被拒绝 - 协议版本不正确",
            2: "连接被拒绝 - 客户端标识符无效",
            3: "连接被拒绝 - 服务器不可用",
            4: "连接被拒绝 - 用户名或密码错误",
            5: "连接被拒绝 - 未授权"
        }

        if rc == 0:
            self.is_connected = True
            logger.info("已成功连接到MQTT服务器")

            # 连接成功后订阅position主题
            if self.mqtt_info and 'client_id' in self.mqtt_info:
                client_id = self.mqtt_info['client_id']
                # 订阅position主题
                topic = f"accounts/{client_id}/position"
                client.subscribe(topic, 1)  # QoS=1
                self.subscribed_topics.add(topic)
                logger.info(f"已订阅position主题: {topic}")
        else:
            rc_message = rc_messages.get(rc, f"未知错误 ({rc})")
            logger.error(f"连接失败，错误代码: {rc} - {rc_message}")

    def _on_message(self, client, userdata, msg):
        """
        MQTT消息接收回调函数

        Args:
            client: MQTT客户端实例
            userdata: 用户数据
            msg: 接收到的消息
        """
        try:
            topic = msg.topic
            payload = msg.payload

            # 检查是否是position主题
            if 'position' in topic:
                logger.info(f"收到position数据，大小: {len(payload)} 字节")

                # 检查是否是gzip压缩数据 (gzip头部通常以0x1f 0x8b开始)
                is_gzip = False
                if len(payload) > 2 and payload[0] == 0x1f and payload[1] == 0x8b:
                    is_gzip = True
                    logger.info("检测到gzip压缩数据，尝试解压...")

                    try:
                        # 解压gzip数据
                        with gzip.GzipFile(fileobj=io.BytesIO(payload), mode='rb') as f:
                            decompressed_data = f.read()

                        # 尝试解码为UTF-8
                        try:
                            json_str = decompressed_data.decode('utf-8')
                            logger.info(f"成功解压并解码数据: {json_str[:100]}...")

                            # 解析JSON
                            position_data = json.loads(json_str)

                            # 添加时间戳
                            if isinstance(position_data, dict):
                                position_data['received_at'] = datetime.now().isoformat()
                                # 直接添加到position_data列表
                                self.position_data.append(position_data)
                            elif isinstance(position_data, list):
                                # 对于列表，将每个元素单独添加到position_data
                                for item in position_data:
                                    if isinstance(item, dict):
                                        item['received_at'] = datetime.now().isoformat()
                                        self.position_data.append(item)

                            # 打印关键信息
                            self._log_position_data(position_data)

                        except UnicodeDecodeError:
                            logger.warning("解压后的数据不是有效的UTF-8格式")
                            # 存储原始解压数据
                            self.position_data.append({
                                'raw_data': decompressed_data.hex(),
                                'format': 'hex',
                                'received_at': datetime.now().isoformat()
                            })

                    except Exception as e:
                        logger.error(f"解压数据异常: {e}")
                        # 存储原始压缩数据
                        self.position_data.append({
                            'raw_data': payload.hex(),
                            'format': 'hex (gzip)',
                            'received_at': datetime.now().isoformat()
                        })

                # 如果不是gzip数据，尝试直接解析
                if not is_gzip:
                    try:
                        # 尝试直接解码为UTF-8
                        json_str = payload.decode('utf-8')
                        logger.info(f"成功解码数据: {json_str[:100]}...")

                        # 解析JSON
                        position_data = json.loads(json_str)

                        # 添加时间戳
                        if isinstance(position_data, dict):
                            position_data['received_at'] = datetime.now().isoformat()
                            # 直接添加到position_data列表
                            self.position_data.append(position_data)
                        elif isinstance(position_data, list):
                            # 对于列表，将每个元素单独添加到position_data
                            for item in position_data:
                                if isinstance(item, dict):
                                    item['received_at'] = datetime.now().isoformat()
                                    self.position_data.append(item)

                        # 打印关键信息
                        self._log_position_data(position_data)

                    except (UnicodeDecodeError, json.JSONDecodeError):
                        # 如果不是UTF-8或JSON，存储为二进制数据
                        logger.warning("数据不是有效的UTF-8或JSON格式，存储为二进制数据")
                        self.position_data.append({
                            'raw_data': payload.hex(),
                            'format': 'hex',
                            'received_at': datetime.now().isoformat()
                        })
            else:
                # 对于非position主题，简单记录
                logger.info(f"收到来自主题 {topic} 的消息，大小: {len(payload)} 字节")

        except Exception as e:
            logger.error(f"处理消息异常: {e}")
            # 尝试保存原始数据
            try:
                self.position_data.append({
                    'raw_data': payload.hex() if payload else None,
                    'format': 'hex (error)',
                    'error': str(e),
                    'received_at': datetime.now().isoformat()
                })
            except:
                pass

    def _log_position_data(self, position_data):
        """
        记录持仓数据的关键信息

        Args:
            position_data: 持仓数据
        """
        if isinstance(position_data, dict):
            # 尝试从不同字段中提取股票信息
            symbols = position_data.get('symbols', [])
            symbol = position_data.get('symbol', 'unknown')
            if not symbol and symbols and len(symbols) > 0:
                symbol = symbols[0]

            # 尝试从positions中提取信息
            positions = position_data.get('positions', [])
            if positions and len(positions) > 0:
                for pos in positions:
                    if pos.get('symbol') and pos.get('category') == 1:  # 通常category=1表示股票
                        pos_symbol = pos.get('symbol', 'unknown')
                        pos_size = pos.get('size', 0)
                        pos_profit = pos.get('profit_and_loss', 0)
                        logger.info(f"持仓信息 - 股票: {pos_symbol}, 数量: {pos_size}, 盈亏: {pos_profit}")
            else:
                # 如果没有positions，使用顶层字段
                quantity = position_data.get('quantity', position_data.get('size', 0))
                profit_loss = position_data.get('profit_loss', position_data.get('profit_and_loss', 0))
                logger.info(f"持仓信息 - 股票: {symbol}, 数量: {quantity}, 盈亏: {profit_loss}")

        elif isinstance(position_data, list) and position_data:
            logger.info(f"收到{len(position_data)}条持仓记录")
            for pos in position_data[:3]:  # 只显示前3条
                if isinstance(pos, dict):
                    # 尝试从不同字段中提取股票信息
                    symbols = pos.get('symbols', [])
                    symbol = pos.get('symbol', 'unknown')
                    if not symbol and symbols and len(symbols) > 0:
                        symbol = symbols[0]

                    # 尝试从positions中提取信息
                    positions = pos.get('positions', [])
                    if positions and len(positions) > 0:
                        for p in positions:
                            if p.get('symbol') and p.get('category') == 1:  # 通常category=1表示股票
                                pos_symbol = p.get('symbol', 'unknown')
                                pos_size = p.get('size', 0)
                                pos_profit = p.get('profit_and_loss', 0)
                                logger.info(f"持仓信息 - 股票: {pos_symbol}, 数量: {pos_size}, 盈亏: {pos_profit}")
                                break  # 只显示第一个持仓
                    else:
                        # 如果没有positions，使用顶层字段
                        quantity = pos.get('quantity', pos.get('size', 0))
                        profit_loss = pos.get('profit_loss', pos.get('profit_and_loss', 0))
                        logger.info(f"持仓信息 - 股票: {symbol}, 数量: {quantity}, 盈亏: {profit_loss}")

            if len(position_data) > 3:
                logger.info(f"... 还有{len(position_data)-3}条记录")

    def _on_disconnect(self, client, userdata, rc):
        """
        MQTT断开连接回调函数

        Args:
            client: MQTT客户端实例
            userdata: 用户数据
            rc: 断开连接结果代码
        """
        self.is_connected = False
        if rc == 0:
            logger.info("已正常断开MQTT连接")
        else:
            logger.warning(f"意外断开MQTT连接，错误代码: {rc}")

    def save_position_data(self, strategy_id: str, strategy_name: Optional[str] = None) -> Optional[str]:
        """
        保存position数据到文件

        Args:
            strategy_id: 策略ID
            strategy_name: 策略名称，可选

        Returns:
            Optional[str]: 保存的文件路径，如果保存失败则返回None
        """
        try:
            # 确保strategy_id不为None
            if strategy_id is None:
                strategy_id = "unknown_strategy"
                logger.warning("策略ID为空，使用默认值'unknown_strategy'")

            # 创建策略目录
            strategy_dir = os.path.join(BACKTEST_DIR, strategy_id)
            os.makedirs(strategy_dir, exist_ok=True)

            # 生成文件名
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            if strategy_name:
                # 替换文件名中的非法字符
                safe_name = ''.join(c if c.isalnum() or c in '._- ' else '_' for c in strategy_name)
                filename = f"{safe_name}_{timestamp}.json"
            else:
                filename = f"backtest_{timestamp}.json"

            file_path = os.path.join(strategy_dir, filename)

            # 保存数据
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(self.position_data, f, ensure_ascii=False, indent=2)

            logger.info(f"已保存{len(self.position_data)}条position数据到: {file_path}")
            return file_path

        except Exception as e:
            logger.error(f"保存position数据异常: {e}")

            # 尝试保存到备用位置
            try:
                backup_path = os.path.join(BACKTEST_DIR, f"backup_position_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
                with open(backup_path, 'w', encoding='utf-8') as f:
                    json.dump(self.position_data, f, ensure_ascii=False, indent=2)
                logger.info(f"已保存备份数据到: {backup_path}")
                return backup_path
            except:
                logger.error("保存备份数据也失败了")
                return None


def extract_symbols_from_strategy(strategy_data: Dict[str, Any]) -> List[Dict[str, str]]:
    """
    从策略中提取股票代码

    Args:
        strategy_data: 策略信息

    Returns:
        List[Dict[str, str]]: 股票代码列表，格式为 [{"symbol": "600000", "exchange": "XSHG"}, ...]

    Raises:
        ValueError: 如果策略中没有选股代码或无法提取股票代码
    """
    symbols = []
    try:
        # 获取选股代码
        choose_stock_code = strategy_data.get('choose_stock')
        if not choose_stock_code:
            error_msg = "策略中没有选股代码"
            logger.error(error_msg)
            raise ValueError(error_msg)

        # 使用正则表达式提取股票代码
        # 匹配 context.symbol_list = ["600000.XSHG", "000001.XSHE"] 这样的模式
        pattern = r'context\.symbol_list\s*=\s*\[(.*?)\]'
        match = re.search(pattern, choose_stock_code, re.DOTALL)

        if match:
            symbols_str = match.group(1)
            # 提取引号中的股票代码
            symbol_pattern = r'["\']([\w\.]+)["\']'
            symbol_matches = re.findall(symbol_pattern, symbols_str)

            if not symbol_matches:
                error_msg = "无法从策略中提取股票代码，symbol_list为空"
                logger.error(error_msg)
                raise ValueError(error_msg)

            for symbol_full in symbol_matches:
                # 分割股票代码和交易所
                if '.' in symbol_full:
                    symbol, exchange = symbol_full.split('.')
                    symbols.append({"symbol": symbol, "exchange": exchange})
                else:
                    logger.warning(f"无效的股票代码格式: {symbol_full}")
        else:
            error_msg = "无法从策略中提取股票代码，未找到context.symbol_list定义"
            logger.error(error_msg)
            raise ValueError(error_msg)

        if not symbols:
            error_msg = "未能成功提取任何有效的股票代码"
            logger.error(error_msg)
            raise ValueError(error_msg)

        return symbols
    except Exception as e:
        if isinstance(e, ValueError):
            # 如果是我们自己抛出的ValueError，直接向上传递
            raise
        else:
            # 其他异常转换为ValueError并向上传递
            error_msg = f"提取股票代码异常: {e}"
            logger.error(error_msg)
            raise ValueError(error_msg)


def extract_backtest_params(strategy_data: Dict[str, Any], custom_start_date: Optional[str] = None,
                           custom_end_date: Optional[str] = None) -> Dict[str, str]:
    """
    从策略中提取回测参数

    Args:
        strategy_data: 策略信息
        custom_start_date: 自定义回测开始日期，可选
        custom_end_date: 自定义回测结束日期，可选

    Returns:
        Dict[str, str]: 回测参数，包含 start_date, end_date, resolution, fq 等
    """
    # 默认参数 - 使用一年前到今天
    default_start_date = (datetime.now() - timedelta(days=365)).strftime("%Y-%m-%d")
    default_end_date = datetime.now().strftime("%Y-%m-%d")

    # 初始化参数
    params = {
        "start_date": custom_start_date or default_start_date,
        "end_date": custom_end_date or default_end_date,
        "resolution": "1D",  # 默认日线
        "fq": "post"  # 默认后复权
    }

    try:
        # 尝试从策略中提取参数
        if isinstance(strategy_data, dict):
            # 提取周期
            resolution = strategy_data.get('resolution')
            if resolution:
                params['resolution'] = resolution

            # 提取复权方式
            fq = strategy_data.get('fq')
            if fq:
                params['fq'] = fq

            # 如果没有提供自定义日期，尝试从策略中提取
            if not custom_start_date or not custom_end_date:
                # 尝试从time_range中提取
                time_range = strategy_data.get('time_range')
                if time_range and isinstance(time_range, list) and len(time_range) >= 2:
                    # 只有在没有提供自定义日期时才使用策略中的日期
                    if not custom_start_date and time_range[0]:
                        try:
                            # 尝试解析日期格式
                            start_date_str = time_range[0].split(' ')[0]  # 提取日期部分
                            datetime.strptime(start_date_str, "%Y-%m-%d")  # 验证格式
                            params['start_date'] = start_date_str
                        except (ValueError, IndexError):
                            pass

                    if not custom_end_date and time_range[1]:
                        try:
                            # 尝试解析日期格式
                            end_date_str = time_range[1].split(' ')[0]  # 提取日期部分
                            datetime.strptime(end_date_str, "%Y-%m-%d")  # 验证格式
                            params['end_date'] = end_date_str
                        except (ValueError, IndexError):
                            pass

        # 记录使用的日期范围
        logger.info(f"回测参数: 开始日期 {params['start_date']}, 结束日期 {params['end_date']}, 周期 {params['resolution']}, 复权 {params['fq']}")
        return params
    except Exception as e:
        logger.error(f"提取回测参数异常: {e}")
        return params


def extract_buy_sell_points(position_data: List[Dict[str, Any]]) -> Tuple[List[List[Any]], List[List[Any]]]:
    """
    从回测结果中提取买入卖出点，通过分析持仓变化来确定

    Args:
        position_data: 回测结果数据

    Returns:
        Tuple[List[List[Any]], List[List[Any]]]: (buy_points, sell_points)
            buy_points: 买入点列表，格式为 [[index, price, time], ...]
            sell_points: 卖出点列表，格式为 [[index, price, time], ...]
    """
    buy_points = []
    sell_points = []

    try:
        # 用于跟踪每个股票的持仓
        symbol_positions = {}

        # 遍历回测结果数据
        for item_index, item in enumerate(position_data):
            # 检查是否是有效的数据
            if not isinstance(item, dict):
                continue

            # 获取时间戳
            timestamp = item.get('tm')
            if not timestamp:
                continue

            # 转换时间戳为日期时间
            try:
                trade_time = datetime.fromtimestamp(timestamp / 1000).strftime('%Y-%m-%d %H:%M:%S')
            except:
                continue

            # 获取持仓信息
            positions = item.get('positions', [])

            # 遍历持仓信息
            for position in positions:
                if not isinstance(position, dict):
                    continue

                symbol = position.get('symbol', '')
                if not symbol:
                    continue

                # 获取当前持仓数量和价格
                current_size = position.get('size', 0)
                price = position.get('price', 0)

                # 如果是新股票，初始化持仓记录
                if symbol not in symbol_positions:
                    symbol_positions[symbol] = 0

                # 比较持仓变化
                prev_size = symbol_positions[symbol]

                # 持仓增加，表示买入
                if current_size > prev_size and current_size > 0:
                    # 添加买入点 [x轴索引, 价格, 时间]
                    buy_points.append([item_index, price, trade_time])
                    logger.debug(f"检测到买入点: {symbol}, 价格: {price}, 时间: {trade_time}")

                # 持仓减少，表示卖出
                elif current_size < prev_size and prev_size > 0:
                    # 添加卖出点 [x轴索引, 价格, 时间]
                    sell_points.append([item_index, price, trade_time])
                    logger.debug(f"检测到卖出点: {symbol}, 价格: {price}, 时间: {trade_time}")

                # 更新持仓记录
                symbol_positions[symbol] = current_size

        logger.info(f"提取交易点成功，买入点: {len(buy_points)}，卖出点: {len(sell_points)}")
        return buy_points, sell_points

    except Exception as e:
        logger.error(f"提取买入卖出点异常: {e}")
        return [], []


def calculate_performance_metrics(position_data: List[Dict[str, Any]]) -> Dict[str, float]:
    """
    计算回测性能指标

    Args:
        position_data: 回测结果数据

    Returns:
        Dict[str, float]: 性能指标，包含总收益率、年化收益率、最大回撤等
    """
    # 默认指标
    metrics = {
        "total_return": 0.0,
        "annual_return": 0.0,
        "benchmark_return": 0.0,
        "benchmark_annual": 0.0,
        "trade_count": 0,
        "win_rate": 0.0,
        "sharpe_ratio": 0.0,
        "max_drawdown": 0.0,
        "avg_return": 0.0
    }

    try:
        # 从回测结果中提取性能指标
        for item in position_data:
            if not isinstance(item, dict):
                continue

            # 提取性能指标
            performance = item.get('performance', {})
            if not performance:
                continue

            # 更新指标
            metrics["total_return"] = round(performance.get('total_return', 0) * 100, 2)
            metrics["annual_return"] = round(performance.get('annual_return', 0) * 100, 2)
            metrics["benchmark_return"] = round(performance.get('benchmark_return', 0) * 100, 2)
            metrics["benchmark_annual"] = round(performance.get('benchmark_annual', 0) * 100, 2)
            metrics["trade_count"] = performance.get('trade_count', 0)
            metrics["win_rate"] = round(performance.get('win_rate', 0) * 100, 2)
            metrics["sharpe_ratio"] = round(performance.get('sharpe_ratio', 0), 2)
            metrics["max_drawdown"] = round(performance.get('max_drawdown', 0) * 100, 2)
            metrics["avg_return"] = round(performance.get('avg_return', 0) * 100, 2)

            # 只处理第一个有效的性能指标
            break

        logger.info(f"计算性能指标成功: 总收益率 {metrics['total_return']}%, 年化收益率 {metrics['annual_return']}%")
        return metrics

    except Exception as e:
        logger.error(f"计算性能指标异常: {e}")
        return metrics


def format_choose_stock(symbol_str: str) -> str:
    """
    将股票代码格式化为choose_stock函数字符串

    Args:
        symbol_str: 股票代码字符串，可以是单个代码如"600000.XSHG"，
                   也可以是多个代码如"160632.XSHE&161029.XSHE"（使用&分隔）

    Returns:
        str: 格式化后的choose_stock函数字符串
    """
    # 分割并清理股票代码（使用&作为分隔符）
    symbols = [s.strip() for s in symbol_str.split('&')]

    # 构建格式化的股票代码列表字符串
    if len(symbols) == 1:
        symbol_list_str = f'["{symbols[0]}"]'
    else:
        # 对于多个股票，使用格式 ["000001.XSHG", "510300.XSHG"]
        formatted_symbols = [f'"{symbol}"' for symbol in symbols]
        symbol_list_str = f'[{", ".join(formatted_symbols)}]'

    return f'def choose_stock(context):\n    """标的"""\n    context.symbol_list = {symbol_list_str}\n'


def run_backtest(
    strategy_id: str,
    listen_time: int = 30,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    indicator: Optional[str] = None,
    control_risk: Optional[str] = None,
    timing: Optional[str] = None,
    choose_stock: Optional[str] = None
) -> Dict[str, Any]:
    """
    运行回测并监听position数据

    Args:
        strategy_id: 策略ID
        listen_time: 监听时间（秒），默认30秒
        start_date: 回测开始日期，格式为 "YYYY-MM-DD"，可选
        end_date: 回测结束日期，格式为 "YYYY-MM-DD"，可选
        indicator: 自定义指标代码，可选
        control_risk: 自定义风控代码，可选
        timing: 自定义择时代码，可选
        choose_stock: 自定义标的代码或股票代码，可选

    Returns:
        Dict[str, Any]: 回测结果，包含以下字段：
            - success: 是否成功
            - strategy_id: 策略ID
            - strategy_name: 策略名称
            - position_count: 接收到的position数据数量
            - file_path: 保存的文件路径
            - chart_path: 生成的图表路径
            - error: 错误信息（如果有）
    """
    result = {
        'success': False,
        'strategy_id': strategy_id,
        'strategy_name': None,
        'position_count': 0,
        'file_path': None,
        'chart_path': None,
        'error': None,
        'date_validation': {
            'from_date_adjusted': False,
            'to_date_adjusted': False,
            'original_from_date': start_date,
            'original_to_date': end_date,
            'adjusted_from_date': start_date,
            'adjusted_to_date': end_date,
            'listing_date': None,
            'last_date': None,
            'messages': []
        }
    }

    # 获取认证信息
    token, user_id = get_auth_info()
    if not token or not user_id:
        error_msg = "无法获取认证信息，请检查认证配置"
        logger.error(error_msg)
        result['error'] = error_msg
        return result

    # 从API获取策略详情
    from utils.strategy_utils import get_strategy_detail
    strategy_data = get_strategy_detail(strategy_id, "user")
    if not strategy_data:
        error_msg = f"未找到策略: {strategy_id}"
        logger.error(error_msg)
        result['error'] = error_msg
        return result

    strategy_name = strategy_data.get('name') or strategy_data.get('strategy_name', '未命名策略')
    result['strategy_name'] = strategy_name

    logger.info(f"开始运行回测，策略: {strategy_name} (ID: {strategy_id})，监听时间: {listen_time}秒")

    try:
        # 如果提供了自定义参数，修改策略
        modified = False

        # 处理自定义指标
        if indicator:
            strategy_data['indicator'] = indicator
            modified = True
            logger.info("使用自定义指标代码")

        # 处理自定义风控
        if control_risk:
            strategy_data['control_risk'] = control_risk
            modified = True
            logger.info("使用自定义风控代码")

        # 处理自定义择时
        if timing:
            strategy_data['timing'] = timing
            modified = True
            logger.info("使用自定义择时代码")

        # 处理自定义标的
        if choose_stock:
            # 判断是否是已格式化的choose_stock函数
            if isinstance(choose_stock, str) and choose_stock.strip().startswith("def choose_stock(context):"):
                # 直接使用提供的choose_stock代码
                strategy_data['choose_stock'] = choose_stock
                logger.info("使用自定义选股代码")
            else:
                # 将股票代码转换为choose_stock函数
                strategy_data['choose_stock'] = format_choose_stock(choose_stock)
                logger.info(f"使用自定义标的: {choose_stock}")
            modified = True

        if modified:
            logger.info("策略已修改，使用修改后的策略运行回测")

        # 提取股票代码
        try:
            symbols = extract_symbols_from_strategy(strategy_data)
        except ValueError as e:
            error_msg = f"无法从策略中提取股票代码: {str(e)}"
            logger.error(error_msg)
            result['error'] = error_msg
            return result

        # 验证日期范围
        if symbols and len(symbols) > 0:
            # 获取第一个股票的完整代码
            symbol = symbols[0].get('symbol')
            exchange = symbols[0].get('exchange')
            if symbol and exchange:
                full_name = f"{symbol}.{exchange}"

                # 验证并调整日期范围
                logger.info(f"验证股票 {full_name} 的回测日期范围")
                validated_start_date, validated_end_date, validation_info = validate_date_range(
                    full_name=full_name,
                    from_date=start_date,
                    to_date=end_date
                )

                # 更新结果中的日期验证信息
                result['date_validation']['from_date_adjusted'] = validation_info.get('from_date_adjusted', False)
                result['date_validation']['to_date_adjusted'] = validation_info.get('to_date_adjusted', False)
                result['date_validation']['original_from_date'] = validation_info.get('original_from_date', start_date)
                result['date_validation']['original_to_date'] = validation_info.get('original_to_date', end_date)
                result['date_validation']['adjusted_from_date'] = validated_start_date
                result['date_validation']['adjusted_to_date'] = validated_end_date
                result['date_validation']['listing_date'] = validation_info.get('listing_date')
                result['date_validation']['last_date'] = validation_info.get('last_date')
                result['date_validation']['messages'] = validation_info.get('message', [])

                # 使用验证后的日期
                start_date = validated_start_date
                end_date = validated_end_date

                # 记录日期调整信息
                if validation_info.get('from_date_adjusted') or validation_info.get('to_date_adjusted'):
                    logger.info(f"回测日期范围已调整: {start_date} 到 {end_date}")
                    for msg in validation_info.get('message', []):
                        logger.info(msg)

        # 获取MQTT连接信息
        mqtt_info = get_mqtt_info()
        if not mqtt_info:
            error_msg = "无法获取MQTT连接信息，无法运行回测"
            logger.error(error_msg)
            result['error'] = error_msg
            return result

        # 创建MQTT客户端
        mqtt_client = MQTTBacktestClient()

        # 连接MQTT服务器
        if not mqtt_client.connect(mqtt_info):
            error_msg = "连接MQTT服务器失败，无法运行回测"
            logger.error(error_msg)
            result['error'] = error_msg
            return result

        # 发送回测请求，使用可能已经过验证调整的日期
        backtest_token = send_backtest_request(
            strategy_id=strategy_id,
            mqtt_info=mqtt_info,
            strategy_data=strategy_data,
            start_date=start_date,
            end_date=end_date
        )

        if not backtest_token:
            error_msg = "发送回测请求失败"
            logger.error(error_msg)
            result['error'] = error_msg
            mqtt_client.disconnect()
            return result

        # 监听position数据
        logger.info(f"开始监听position数据，将持续{listen_time}秒...")
        start_time = time.time()
        position_count = 0
        no_new_data_count = 0
        max_no_new_data_count = 10  # 增加到10秒无新数据才结束，以确保有足够时间接收数据
        min_positions_required = 5  # 需要至少收到5条数据才考虑提前结束

        try:
            while time.time() - start_time < listen_time:
                # 检查是否有新的position数据
                current_count = len(mqtt_client.position_data)
                if current_count > position_count:
                    logger.info(f"收到{current_count - position_count}条新的position数据，总计: {current_count}条")
                    position_count = current_count
                    no_new_data_count = 0  # 重置无新数据计数器
                else:
                    no_new_data_count += 1  # 增加无新数据计数器
                
                # 提前结束条件：
                # 1. 已经收集了足够的数据（至少min_positions_required条）
                # 2. 连续max_no_new_data_count秒没有新数据
                # 3. 已经过去了至少30秒（确保给回测系统足够的启动时间）
                elapsed_time = time.time() - start_time
                if (position_count >= min_positions_required and 
                    no_new_data_count >= max_no_new_data_count and 
                    elapsed_time >= 30):
                    logger.info(f"已接收到{position_count}条数据，且连续{no_new_data_count}秒无新数据，提前结束监听（已等待{elapsed_time:.1f}秒）")
                    break

                # 每秒检查一次
                time.sleep(1)

            logger.info(f"监听结束，共收到{len(mqtt_client.position_data)}条position数据，用时: {time.time() - start_time:.1f}秒")

            # 保存position数据
            file_path = mqtt_client.save_position_data(strategy_id, strategy_name)
            result['file_path'] = file_path
            result['position_count'] = len(mqtt_client.position_data)
            result['success'] = True

            # 提取回测参数，优先使用传入的自定义时间范围（可能已经过验证调整）
            backtest_params = extract_backtest_params(strategy_data, start_date, end_date)

            # 提取买入卖出点
            buy_points, sell_points = extract_buy_sell_points(mqtt_client.position_data)

            # 计算性能指标
            metrics = calculate_performance_metrics(mqtt_client.position_data)

            # 对每个股票生成图表
            for symbol_info in symbols:
                symbol = symbol_info.get('symbol')
                exchange = symbol_info.get('exchange')

                # 获取K线数据
                success, df, kline_file_path = fetch_and_save_kline(
                    symbol=symbol,
                    exchange=exchange,
                    from_date=backtest_params.get('start_date'),
                    to_date=backtest_params.get('end_date'),
                    resolution=backtest_params.get('resolution'),
                    fq=backtest_params.get('fq')
                )

                if success and df is not None and not df.empty:
                    # 生成回测结果图表
                    chart_path = generate_backtest_html(
                        backtest_data=mqtt_client.position_data,
                        strategy_name=strategy_name,
                        strategy_id=strategy_id,
                        kline_df=df,
                        symbol=symbol,
                        exchange=exchange
                    )

                    if chart_path:
                        result['chart_path'] = chart_path
                        # 在浏览器中打开图表
                        open_in_browser(chart_path)
                    else:
                        # 如果回测图表生成失败，尝试生成普通K线图表
                        from utils.chart_generator import generate_html
                        chart_path = generate_html(
                            df=df,
                            symbol=symbol,
                            exchange=exchange,
                            resolution=backtest_params.get('resolution'),
                            fq=backtest_params.get('fq')
                        )

                        if chart_path:
                            result['chart_path'] = chart_path
                            # 在浏览器中打开图表
                            open_in_browser(chart_path)
                else:
                    logger.warning(f"获取K线数据失败或数据为空: {symbol}.{exchange}")

            return result

        finally:
            # 断开MQTT连接
            mqtt_client.disconnect()

    except Exception as e:
        error_msg = f"回测过程中发生异常: {str(e)}"
        logger.exception(error_msg)
        result['error'] = error_msg
        return result