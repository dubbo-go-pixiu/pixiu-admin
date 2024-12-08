#!/bin/bash

echo "Starting the Pixiu admin panel, frontend, and etcd..."

# ------------------------------
#Start the etcd service (if it is not already started)
# ------------------------------

# Use docker ps to get the names and images of all containers, and use grep to match etcd images
ETCD_CONTAINER_NAME=$(docker ps -a --format "{{.Names}} {{.Image}}" | grep -i "etcd" | awk '{print $1}')
ETCD_CONTAINER_IMAGE=$(docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}" | grep -i "etcd" | awk '{print $2}')
ETCD_CONTAINER_STATUS=$(docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}" | grep -i "etcd" | awk '{print $3" "$4" "$5}') # 获取容器状态

# If no running etcd container is found, start a new one
if [ -z "$ETCD_CONTAINER_NAME" ]; then
    echo "Starting etcd service in Docker..."

    # Start etcd container
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

    # Check the running status of the container
    if [[ "$ETCD_CONTAINER_STATUS" == *"Exited"* ]]; then
        echo "etcd container is not running. Restarting it..."

        # Restart etcd container
        docker start $ETCD_CONTAINER_NAME

        # Check again whether the container started successfully
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

echo "Waiting for etcd to be ready..."
sleep 5 # Wait 5 seconds to make sure the etcd service is started and available

# ------------------------------
# Start the backend service (Pixiu admin panel)
# ------------------------------

# Enter the backend directory, assuming the backend project is in the root directory
cd ./ # If your backend project path is different, remember to modify this

# Start backend service
echo "Starting backend service..."
go run cmd/admin/admin.go -c configs/admin_config.yaml &
BACKEND_PID=$!  # Get the process ID of the backend service

# Check whether the backend started successfully
if [ -z "$BACKEND_PID" ]; then
    echo "Failed to start backend service."
    exit 1
else
    echo "Backend service started with PID $BACKEND_PID."
fi

# ------------------------------
# Start the front-end service (Vue.js)
# ------------------------------

cd ./web  # Enter the front-end project directory

# Install front-end dependencies
echo "Installing frontend dependencies..."
yarn install

# Start front-end service
echo "Starting frontend service..."
yarn run serve &
FRONTEND_PID=$!

# Check whether the front end is started successfully
if [ -z "$FRONTEND_PID" ]; then
    echo "Failed to start frontend service."
    exit 1
else
    echo "Frontend service started with PID $FRONTEND_PID."
fi

# ------------------------------
# One-click startup complete
# ------------------------------
echo "Both backend and frontend services have been started successfully."

trap 'echo "Stopping services..."; kill $BACKEND_PID $FRONTEND_PID; docker stop $ETCD_CONTAINER_NAME; exit 0' SIGINT

wait $BACKEND_PID $FRONTEND_PID
