#!/bin/bash

# 这个脚本修复Nginx权限问题，解决403 Forbidden错误

echo "修复Nginx权限问题..."

# 确保charts目录存在
mkdir -p data/charts

# 创建测试HTML文件
cat > "data/charts/test.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>MCP测试页面</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>MCP测试页面</h1>
    <p>这是一个测试页面，如果您能看到此内容，说明HTML服务器配置正确。</p>
    <p>当前时间: <span id="time"></span></p>
    <script>document.getElementById("time").textContent = new Date().toLocaleString();</script>
</body>
</html>
EOF

# 设置目录和文件权限
echo "设置目录和文件权限..."
sudo chmod -R 755 data/charts
sudo find data/charts -type f -exec sudo chmod 644 {} \;

# 更改目录所有者为www-data
echo "设置目录所有者为www-data..."
sudo chown -R www-data:www-data data/charts

# 确保nginx用户可以访问整个路径
sudo chmod 755 $(pwd)
sudo chmod 755 $(pwd)/data
sudo chmod a+r data/charts/*

# 修改Nginx配置
echo "修改Nginx配置..."
NGINX_CONF_FILE="/etc/nginx/conf.d/mcp_html_server.conf"

# 检查配置文件是否存在
if [ -f "$NGINX_CONF_FILE" ]; then
    # 备份原始配置
    sudo cp "$NGINX_CONF_FILE" "${NGINX_CONF_FILE}.bak"
    
    # 添加allow all指令
    sudo sed -i '/location \/charts\//,/}/s/autoindex off;/autoindex off;\n        allow all;/' "$NGINX_CONF_FILE"
    
    # 测试Nginx配置
    echo "测试Nginx配置..."
    if sudo nginx -t; then
        # 重启Nginx
        echo "重启Nginx..."
        sudo systemctl restart nginx
        echo "Nginx已重启，请再次尝试访问测试页面"
    else
        echo "Nginx配置测试失败，恢复备份"
        sudo cp "${NGINX_CONF_FILE}.bak" "$NGINX_CONF_FILE"
    fi
else
    echo "未找到Nginx配置文件: $NGINX_CONF_FILE"
    echo "可能需要重新运行 deploy_start.sh 进行配置"
fi

echo "权限修复完成。请尝试访问: http://YOUR_SERVER_IP:8081/charts/test.html" 