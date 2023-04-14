#!/bin/bash

# Define exit script
function cleanup {
    pkill -f "kubectl port-forward service/mysql 3306:3306" > /dev/null
}

# When receiving the EXIT signal (ex. CTRL+C), run the cleanup function
trap cleanup EXIT

# Port forward MySQL's service to localhost
kubectl port-forward service/mysql 3306:3306 &>/dev/null &

# Connect to MySQL
mysql -h 127.0.0.1 -u root -p