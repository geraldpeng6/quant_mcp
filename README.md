# MCP量化交易助手服务器

MCP (Model Context Protocol) 服务器，用于提供量化交易相关的工具和服务。

## 特点

- 支持多种传输协议 (stdio, sse, streamable-http)
- 自动配置Nginx服务器提供HTML文件访问
- 提供量化交易相关工具和服务
- 支持本地运行和服务器部署

## 快速开始

### 基本使用

使用默认设置启动服务器：

```bash
./deploy_start.sh
```

### 自定义选项

```bash
# 使用STDIO传输协议启动
./deploy_start.sh -t stdio

# 使用自定义端口启动
./deploy_start.sh -p 9000 --html-port 9001

# 部署模式，安装依赖并配置系统服务
./deploy_start.sh -d

# 生产环境部署
./deploy_start.sh -d --production
```

### 命令行选项

| 选项 | 描述 |
|------|------|
| `-h, --help` | 显示帮助信息 |
| `-t, --transport TRANSPORT` | 指定传输协议 (stdio, sse, streamable-http) |
| `-H, --host HOST` | 指定主机地址 (默认: 0.0.0.0) |
| `-p, --port PORT` | 指定端口号 (默认: 8000) |
| `--html-port PORT` | 指定HTML服务器端口号 (默认: 8081) |
| `-d, --deploy` | 部署模式，安装依赖并配置系统服务 |
| `--production` | 生产环境模式，设置MCP_ENV=production |

## 部署说明

### 本地部署

1. 克隆代码库并进入目录
2. 运行`./deploy_start.sh`启动服务器
3. 访问`http://localhost:8000`使用MCP服务器
4. 访问`http://localhost:8081`访问HTML服务

### 服务器部署

1. 在服务器上克隆代码库并进入目录
2. 运行`./deploy_start.sh -d --production`进行部署
3. 部署完成后，系统会显示服务器访问地址
4. MCP服务器会作为系统服务自动启动和重启

## 系统要求

- Python 3.8+
- Nginx
- 支持的操作系统: Linux, macOS

## 配置文件

### HTML服务器配置

配置文件位置: `data/config/html_server.json`

```json
{
  "server_port": 8081,
  "charts_dir": "data/charts",
  "use_public_ip": true
}
```

## 开发说明

### 添加新工具

1. 在`src/tools/`目录下创建新的工具模块
2. 在模块中实现工具函数
3. 添加一个`register_tools`函数来注册工具到MCP服务器
4. 在`src/tools/__init__.py`中导入并调用`register_tools`函数

### 添加新提示模板

1. 在`src/prompts/`目录下创建新的提示模板模块
2. 在模块中定义提示模板
3. 添加一个`register_prompts`函数来注册提示模板到MCP服务器
4. 在`src/prompts/__init__.py`中导入并调用`register_prompts`函数 