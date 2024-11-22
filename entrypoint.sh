#!/bin/sh

# Wait for other Redis nodes to become available
echo "Waiting for Redis nodes to be ready..."
sleep 10

# Get the IPs of the Redis replicas
REDIS_NODES=$(getent hosts tasks.redis | awk '{ print $1 }')

# Get the current cluster configuration
CURRENT_NODES=$(redis-cli -c cluster nodes | awk '{ print $2 }' | grep -oE '^[^@]+' | sort)

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
  for NODE in $CURRENT_NODES; do
    if ! echo "$REDIS_NODES" | grep -q "${NODE%%:*}"; then
      echo "Removing $NODE from the cluster..."
      redis-cli --cluster del-node "$NODE" "$(redis-cli cluster nodes | grep "$NODE" | awk '{ print $1 }')"
    fi
  done
}

# Check if this is the first container starting the cluster
if [ "$(hostname)" = "$(getent hosts tasks.redis | awk '{ print $2 }' | head -n 1)" ]; then
  if [ -z "$CURRENT_NODES" ]; then
    # If no cluster exists, create one
    create_cluster
  else
    # If a cluster exists, update it with new nodes
    add_nodes
    remove_nodes
  fi
else
  echo "Not the primary container. Skipping cluster management."
fi

# Start Redis server
redis-server /usr/local/etc/redis/redis.conf

