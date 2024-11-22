# redis-swarm
Docker Swarm experiment with scalable Redis cluster


## Usage

Deploy the stack:
```
docker stack deploy -c docker-compose.yml redis-cluster
```
Scale up the service:
```
docker service scale redis=5
```
Scale down the service:
```
docker service scale redis=2
```
Verify the cluster configuration:
```
redis-cli -c -h <any_node_ip> -p 6379 cluster nodes
```
