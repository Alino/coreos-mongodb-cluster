```
[Unit]
Description=ReplicaSet Configurator
BindsTo=mongo@1.service

[Service]
KillMode=none
TimeoutStartSec=360
TimeoutStopSec=400
EnvironmentFile=/etc/environment
ExecStartPre=/bin/bash -c "docker pull 19hz/mongo-container:latest"

#===============================================================
# each ExecStart or Pre, Post should be smaller than 2000 characters. (Jan 21st, 2015. fleet version 0.8.3)
# systemd hides the fact that there exists a maximum unit file line length (https://github.com/coreos/fleet/issues/992).
# Fail unit option parsing if line longer than 2000 characters(https://github.com/coreos/go-systemd/issues/69)
#
#
# we need to know that users are saved or not
# SITE_ROOT_PWD : to check password is saved in etcd
# REPLICA_KEY : replica key is generated after users are saved in post start steps for mongo@.service
# REPLICA_MODE: to use rs.initiate(), mongod should be running in replica mode
#===============================================================

ExecStartPre=/bin/bash -c "set -e; \
    SITE_ROOT_PWD=$(etcdctl get /mongo/replica/siteRootAdmin/pwd 2>/dev/null || true ); \
    REPLICA_KEY=$(etcdctl get /mongo/replica/key 2>/dev/null || true); \
    REPLICA_MODE=$(etcdctl get /mongo/replica/switched_to_replica_mode 2>/dev/null); \
    if (test -z \"$SITE_ROOT_PWD\") && (test -z \"$REPLICA_KEY\") && (test -n \"$REPLICA_MODE\"); \
    then \
        echo \"WAITING.... Not yet ready to configure...\"; \
        sleep 30; \
        /usr/bin/systemctl restart %n; \
    fi; \
"
ExecStart=/bin/bash -c "set -e; \
    echo \"STARTING....\"; \
    CHECK_MONGO=$(/usr/bin/docker ps | grep mongodb); \
    SITE_ROOT_PWD=$(etcdctl get /mongo/replica/siteRootAdmin/pwd 2>/dev/null || true ); \
    RS_INIT_DONE=$(etcdctl get /mongo/replica/rs_init_done 2>/dev/null || true ); \
    ADD_CMDS=$(etcdctl ls /mongo/replica/nodes | grep -v '$COREOS_PRIVATE_IPV4' | xargs -I{} basename {} | xargs -I{} echo \"rs.add('{}:27017');\"); \
    \
    if (test -z \"$RS_INIT_DONE\") && (test -n \"$CHECK_MONGO\" ); \
    then \
        docker run -t --volumes-from mongo-data1 19hz/mongo-container:latest \
            mongo $COREOS_PRIVATE_IPV4/admin -u siteRootAdmin -p $SITE_ROOT_PWD \
            --eval \"rs.status().startupStatus === 3 && rs.initiate();\"; \
        etcdctl set /mongo/replica/rs_init_done finished; \
        echo \"RS_INIT_DONE....\"; \
        /usr/bin/sleep 60; \
        docker run -t  --volumes-from mongo-data1 \
        19hz/mongo-container:latest mongo $COREOS_PRIVATE_IPV4/admin -u siteRootAdmin -p $SITE_ROOT_PWD \
        --eval \"var config = rs.config(); if (config.members.length === 1) { config.members[0].host = '$COREOS_PRIVATE_IPV4'; rs.reconfig(config); }\"; \
        etcdctl set /mongo/replica/rs_config_done finished; \
        echo \"RS_CONFIG_DONE....\"; \
        docker run -t --volumes-from mongo-data1 \
        19hz/mongo-container:latest mongo $COREOS_PRIVATE_IPV4/admin -u siteRootAdmin -p $SITE_ROOT_PWD --eval \"$ADD_CMDS\"; \
        etcdctl set /mongo/replica/rs_adding_node_done finished; \
        echo \"RS_ADDING_NODES_DONE....\"; \
    else \
        sleep 30; /usr/bin/systemctl restart %n; \
    fi; \
"
#===============================================================
# initiate, reconfig, add nodes
# once initiated, we wait 60s to let mongodb do it's job.
# even though, this script exits because of timeout, ExecStartPost will check it
# and restart.
#===============================================================
ExecStartPost=/bin/bash -c "set -e; \
    RS_INIT_DONE=$(etcdctl get /mongo/replica/rs_init_done 2>/dev/null || true ); \
    RS_CONFIG_DONE=$(etcdctl get /mongo/replica/rs_config_done 2>/dev/null || true ); \
    RS_ADDING_NODES_DONE=$(etcdctl get /mongo/replica/rs_adding_node_done 2>/dev/null || true ); \
    if (test -n \"$RS_ADDING_NODES_DONE\"); \
    then \
        echo \"YOUR MONGO REPLICA SET IS CONFIGURED!!\"; \
        sleep 60; exit 0; \
    fi; \
    if (test -n \"$RS_INIT_DONE\") && (test -n \"$RS_CONFIG_DONE\") && (test -n \"$RS_ADDING_NODES_DONE\"); \
    then \
        echo \"EXIT 0....\"; \
        etcdctl set /mongo/replica/configured finished; exit 0; \
    else \
        echo \"RESTARTING....\"; \
        sleep 30; /usr/bin/systemctl restart %n; \
    fi; \
"
Restart=on-failure
[X-Fleet]
MachineOf=mongo@1.service
```