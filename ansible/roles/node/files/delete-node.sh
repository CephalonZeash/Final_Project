#!/bin/bash

kubectl drain $1 --ignore-daemonsets --delete-emptydir-data
kubectl delete node $1