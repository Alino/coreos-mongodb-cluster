[![Docker Repository on Quay.io](https://quay.io/repository/jaigouk/mongo-container/status "Docker Repository on Quay.io")](https://quay.io/repository/jaigouk/mongo-container)

Deploy a replicaset to coreos like a boss.
Auto-discover new members via etcd.

## Deploy
`docker login`
`docker login quay.io`
If you destroy mongo-data{1..3}.service, your data is going to be lost. Use [docker-volumes](https://github.com/cpuguy83/docker-volumes) to backup your data. If you are already running replica set, destroy them first.

```
fleetctl destroy mongo-data@{1..3}.service mongo@{1..3}.service  mongo-replica-config.service 

etcdctl set /mongo/replica/name myreplica

fleetctl start mongo-data@{1..3}.service mongo@{1..3}.service mongo-replica-config.service
```

## Connect

You can test connecting to your replica from one of your nodes as follows:

```
fleetctl-ssh

COREOS_PRIVATE_IPV4=xx.xx.xx.xxx; echo $COREOS_PRIVATE_IPV4

SITE_ROOT_PWD=$(etcdctl get /mongo/replica/siteRootAdmin/pwd); echo $SITE_ROOT_PWD

docker run -i -t  --volumes-from mongo-data1 19hz/mongo-container:latest mongo $COREOS_PRIVATE_IPV4/admin -u siteRootAdmin -p $SITE_ROOT_PWD


$ Welcome to the MongoDB shell.
```

## Backup

You need to setup your server with docker-tcp.socket as mentioned in [this coreos document](https://coreos.com/docs/launching-containers/building/customizing-docker/) to use [docker-volumes](https://github.com/cpuguy83/docker-volumes). You can use https://coreos.com/validate/ to validate your cloud-init file.


```
$ brew install go; cd ~/
$ mkdir -p go/{src,bin,pkg}
```

add following lines to zshrc or bashrc and source it.
```
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
export PATH="$PATH:/usr/local/opt/go/libexec/bin"
```

```
git clone git@github.com:cpuguy83/docker-volumes.git ~/go/src/docker-volumes
cd ~/go/src/docker-volumes
go get
go build
```

### Trouble shooting

In my shell rc file (~/.zsh_aliases)
```
fleetctl-switch(){
  ssh-add ~/.docker/certs/key.pem
  DOCKER_HOST=tcp://$1:2376
  export FLEETCTL_TUNNEL=$1:22
  alias etcdctl="ssh -A core@$1 'etcdctl'"
  alias fleetctl-ssh="fleetctl ssh $(fleetctl list-machines | cut -c1-8 | sed -n 2p)"
  RPROMPT="%{$fg[magenta]%}[fleetctl:$1]%{$reset_color%}"
}
destroy_mongo_replica() {
  export FLEETCTL_TUNNEL=$1:22
  alias etcdctl="ssh -A core@$1 'etcdctl'"
  fleetctl destroy mongo-data@{1..3}.service 
  fleetctl destroy mongo@{1..3}.service
  fleetctl destroy mongo@.service
  fleetctl destroy mongo-replica-config.service
  fleetctl destroy mongo-data@{1..3}.service
  etcdctl rm /mongo/replica/siteRootAdmin --recursive
  etcdctl rm /mongo/replica/siteUserAdmin --recursive
  etcdctl rm /mongo/replica --recursive
  etcdctl set /mongo/replica/name myreplica
}
```

To start,
```
fleetctl-switch xx.xx.xx.xx
fleetctl start mongo-data@{1..3}.service mongo@{1..3}.service mongo-replica-config.service
```

To see what's going on with a service,
```
fleetctl journal -f mongo@1.service
```

To delete all mongodb files,
```
destroy_mongo_replica <cluser ip 1> <cluser ip 2> <cluser ip 3>
```

## How it works?

The units follow the process explained in this [tutorial](http://docs.mongodb.org/manual/tutorial/deploy-replica-set-with-auth/).

I've split the process in 3 different phases.

### Phase 1

During the initial phase, mongo needs to be run without the authentication option and without the keyFile.

We just run the first node of the replicaset while the other are waiting the key file in etcd.

-  The `siteUserAdmin` and `siteRootAdmin` are created on the first node with random passwords stored in etcd.
-  The keyfile is generated and added to etcd.
-  All mongodb are started.

### Phase 2

During the second phase, we have all the nodes of the replica running and ready to bind each other.

-  `rs.initiate` is run in the first node.
-  `rs.add` is run for every node except the fisrt one which is automatically added.

### Phase 3

The third phase is the final state, we keep watching etcd for new nodes and these new nodes.

## Destroy and revert everything

```
# remove all units
$ fleetctl destroy mongo@{1..3}.service
$ fleetctl destroy mongo-replica-config.service
# or
$ fleetctl list-units --no-legend | awk '{print $1}' | xargs -I{} fleetctl destroy {}

# clean directories
$ fleetctl list-machines --fields="machine" --full --no-legend | xargs -I{} fleetctl ssh {} "sudo rm -rf /var/mongo/*"

(from inside one of the nodes)
$ etcdctl rm /mongo/replica/key
$ etcdctl rm --recursive /mongo/replica/siteRootAdmin
$ etcdctl rm --recursive /mongo/replica/siteUserAdmin
$ etcdctl rm --recursive /mongo/replica/nodes
```

## License

MIT - Copyright (c) 2014 AUTH0 INC.