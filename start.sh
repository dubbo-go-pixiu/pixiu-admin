#!/bin/bash

# 打印脚本执行的开始信息
echo "Starting the Pixiu admin panel, frontend, and etcd..."

# ------------------------------
# 启动 etcd 服务（如果尚未启动）
# ------------------------------

# 使用 docker ps 获取所有容器的名称和镜像，并通过 grep 匹配 etcd 镜像
ETCD_CONTAINER_NAME=$(docker ps -a --format "{{.Names}} {{.Image}}" | grep -i "etcd" | awk '{print $1}')
ETCD_CONTAINER_IMAGE=$(docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}" | grep -i "etcd" | awk '{print $2}')
ETCD_CONTAINER_STATUS=$(docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}" | grep -i "etcd" | awk '{print $3" "$4" "$5}') # 获取容器状态

# 如果没有找到正在运行的 etcd 容器，启动一个新的
if [ -z "$ETCD_CONTAINER_NAME" ]; then
    echo "Starting etcd service in Docker..."

    # 启动 etcd 容器
    docker run -d --name pixiu-etcd \
        -p 2379:2379 \
        -p 2380:2380 \
        --env ALLOW_NONE_AUTHENTICATION=yes \
        quay.io/coreos/etcd:latest \
        /usr/local/bin/etcd --name pixiu-etcd --listen-peer-urls http://0.0.0.0:2380 --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://localhost:2379 --data-dir /etcd-data

    if [ $? -ne 0 ]; then
        echo "Failed to start etcd container."
        exit 1
    else
        echo "etcd service started successfully."
    fi
else
echo "etcd service is already running with container name: $ETCD_CONTAINER_NAME and image: $ETCD_CONTAINER_IMAGE"

    # 检查容器的运行状态
    if [[ "$ETCD_CONTAINER_STATUS" == *"Exited"* ]]; then
        echo "etcd container is not running. Restarting it..."

        # 重启 etcd 容器
        docker start $ETCD_CONTAINER_NAME

        # 再次检查容器是否成功启动
        if [ $? -ne 0 ]; then
            echo "Failed to restart etcd container."
            exit 1
        else
            echo "etcd container restarted successfully."
        fi
    else
        echo "etcd container is already running and healthy."
    fi
fi

# 等待 etcd 服务准备好（等待一段时间）
echo "Waiting for etcd to be ready..."
sleep 5 # 等待 5 秒，确保 etcd 服务已启动并可用

# ------------------------------
# 启动后端服务（Pixiu 管理面板）
# ------------------------------

# 进入后端目录，假设后端项目位于根目录
cd ./ # 如果你的后端项目路径不同，记得修改这里

# 启动后端服务
echo "Starting backend service..."
go run cmd/admin/admin.go &  # 启动后端服务并将其置于后台
BACKEND_PID=$!  # 获取后端服务的进程ID

# 检查后端是否启动成功
if [ -z "$BACKEND_PID" ]; then
    echo "Failed to start backend service."
    exit 1
else
    echo "Backend service started with PID $BACKEND_PID."
fi

# ------------------------------
# 启动前端服务（Vue.js）
# ------------------------------

# 进入前端目录
cd ./web  # 进入前端项目目录

# 安装前端依赖
echo "Installing frontend dependencies..."
yarn install

# 启动前端服务
echo "Starting frontend service..."
yarn run serve &  # 启动前端服务并将其置于后台
FRONTEND_PID=$!  # 获取前端服务的进程ID

# 检查前端是否启动成功
if [ -z "$FRONTEND_PID" ]; then
    echo "Failed to start frontend service."
    exit 1
else
    echo "Frontend service started with PID $FRONTEND_PID."
fi

# ------------------------------
# 提示一键启动完成
# ------------------------------
echo "Both backend and frontend services have been started successfully."

# 监听 Ctrl+C 来终止所有进程
trap 'echo "Stopping services..."; kill $BACKEND_PID $FRONTEND_PID; docker stop $ETCD_CONTAINER_NAME; exit 0' SIGINT

# 保持脚本运行，直到手动停止
wait $BACKEND_PID $FRONTEND_PID
