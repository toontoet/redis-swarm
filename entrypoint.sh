#!/bin/sh

# Function to fetch all Redis task IPs
get_redis_nodes() {
  getent hosts tasks.redis | awk '{ print $1 }'
}

# Wait for other Redis nodes to become available
echo "Waiting for Redis nodes to be ready..."
sleep 10

# Get the IP of the current container
SELF_IP=$(hostname -i)

# Fetch all Redis task IPs
REDIS_NODES=$(get_redis_nodes)

# Define function to create the cluster
create_cluster() {
  echo "Creating Redis Cluster..."

  # Create a space-separated list of nodes
  NODE_LIST=$(echo "$REDIS_NODES" | awk '{ print $1 ":6379" }' | paste -sd " ")

  # Initialize the cluster
  echo "yes" | redis-cli --cluster create $NODE_LIST --cluster-replicas 1
}

# Define function to add new nodes to the cluster
add_nodes() {
  echo "Adding new nodes to the cluster..."
  CURRENT_NODES=$(redis-cli -c cluster nodes | awk '{ print $2 }' | grep -oE '^[^@]+')
  for NODE in $REDIS_NODES; do
    if ! echo "$CURRENT_NODES" | grep -q "$NODE:6379"; then
      echo "Adding $NODE to the cluster..."
      redis-cli --cluster add-node "$NODE:6379" "$(echo "$CURRENT_NODES" | head -n 1)"
    fi
  done
}

# Define function to remove nodes from the cluster
remove_nodes() {
  echo "Removing missing nodes from the cluster..."
  CURRENT_NODES=$(redis-cli -c cluster nodes | awk '{ print $2 }' | grep -oE '^[^@]+')
  for NODE in $CURRENT_NODES; do
    if ! echo "$REDIS_NODES" | grep -q "${NODE%%:*}"; then
      echo "Removing $NODE from the cluster..."
      redis-cli --cluster del-node "$NODE" "$(redis-cli cluster nodes | grep "$NODE" | awk '{ print $1 }')"
    fi
  done
}

# Check if this is the primary container based on IP
if [ "$SELF_IP" = "$(echo "$REDIS_NODES" | head -n 1)" ]; then
  echo "This container is the primary node."

  # Check if the cluster is already initialized
  CLUSTER_INFO=$(redis-cli -c cluster info 2>/dev/null | grep "cluster_state:ok")
  if [ -z "$CLUSTER_INFO" ]; then
    echo "Cluster not initialized. Creating cluster..."
    create_cluster
  else
    echo "Cluster already initialized. Checking for updates..."
    add_nodes
    remove_nodes
  fi
else
  echo "This container is not the primary node. Skipping cluster management."
fi

# Start Redis server
redis-server /usr/local/etc/redis/redis.conf

