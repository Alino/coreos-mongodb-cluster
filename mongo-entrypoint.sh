#!/bin/bash
set -e

if [ "${1:0:1}" = '-' ]; then
  set -- mongod "$@"
fi

if [ "$1" = 'mongod' ]; then
  chown -R mongodb /data/db

  numa='numactl --interleave=all'
  if $numa true &> /dev/null; then
    set -- $numa "$@"
  fi

  exec gosu mongodb "$@"
fi

if [ "$1" = 'config_replica' ]; then
  REPLICA_NAME=$(etcdctl get /mongo/replica/name 2>/dev/null || true)
  SITE_ROOT_PWD=$(etcdctl get /mongo/replica/siteRootAdmin/pwd 2>/dev/null || true )
  REPLICA_KEY=$(etcdctl get /mongo/replica/key 2>/dev/null || true)
  RS_INIT_DONE=$(etcdctl get /mongo/replica/rs_init_done 2>/dev/null || true )
  RS_CONFIG_DONE=$(etcdctl get /mongo/replica/rs_config_done 2>/dev/null || true )
  RS_ADDING_NODES_DONE=$(etcdctl get /mongo/replica/rs_adding_node_done 2>/dev/null || true )
  OTHER_NODES=$(etcdctl ls /mongo/replica/nodes | xargs -I{} basename {} | xargs -I{} echo {}:27017 | grep -v '$COREOS_PRIVATE_IPV4')
  ADD_CMDS=$(etcdctl ls /mongo/replica/nodes | grep -v '$COREOS_PRIVATE_IPV4' | xargs -I{} basename {} | xargs -I{} echo "rs.add('{}:27017');")
  if [ -z "$SITE_ROOT_PWD" ]
  then
      echo 'WAITING.... siteRootAdmin is not yet configured...'
      sleep 60
      /usr/bin/systemctl restart %n
  fi
  echo 'Will configure replica set from now'
  if [ \[ -z "$RS_INIT_DONE" \] && \[ -n $(/usr/bin/docker ps | grep mongodb) \] ]
  then
      echo 'trying to init the replicaset...'
      docker run -t --volumes-from mongo-data
      19hz/mongo-container:latest mongo $COREOS_PRIVATE_IPV4/admin -u siteRootAdmin -p $SITE_ROOT_PW
      --eval 'rs.status().startupStatus === 3 && rs.initiate();'
      etcdctl set /mongo/replica/rs_init_done finished
  fi
  if [ \[ -z "$RS_CONFIG_DONE" \] && \[ -n $(/usr/bin/docker ps | grep mongodb) \] ]
  then
      echo 'fix address of first node...'
      docker run -t  --volumes-from mongo-data
      19hz/mongo-container:latest mongo $COREOS_PRIVATE_IPV4/admin -u siteRootAdmin -p $SITE_ROOT_PW
      --eval 'var config = rs.config(); if (config.members.length === 1) { config.members[0].host = '$COREOS_PRIVATE_IPV4'; rs.reconfig(config); }'
      etcdctl set /mongo/replica/rs_config_done finished
  fi
  if [ \[ -z "$RS_ADDING_NODES_DONE" \] && \[ -n $(/usr/bin/docker ps | grep mongodb) \] ]
  then
      echo 'adding nodes...'
      docker run -t --volumes-from mongo-data
      19hz/mongo-container:latest mongo $COREOS_PRIVATE_IPV4/admin -u siteRootAdmin -p $SITE_ROOT_PWD --eval "$ADD_CMDS"
      etcdctl set /mongo/replica/rs_adding_node_done finished
  fi
  if [ [ -n "$RS_INIT_DONE" ] && [ -n "$RS_CONFIG_DONE" ] && [ -n "$RS_ADDING_NODES_DONE" ] ]
  then
      etcdctl set /mongo/replica/configured finished; exit 0
  else
      sleep 60; /usr/bin/systemctl restart %n
  fi
fi

exec "$@"