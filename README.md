[![Docker Repository on Quay.io](https://quay.io/repository/jaigouk/mongo-container/status "Docker Repository on Quay.io")](https://quay.io/repository/jaigouk/mongo-container)

Deploy a replicaset to coreos like a boss.
Auto-discover new members via etcd. this repo is little bit different from auth0/coreos-mongodb repo. I use data volume container. simple steps to setup replica and nginx loadbalancer altogether, please visit [zero-to-dockerized-meteor-cluster](https://github.com/jaigouk/zero-to-dockerized-meteor-cluster/)

## Setup

### STEP1) Add these to your shell rc file (~/.zsh_aliases)

```
fleetctl-switch(){
  ssh-add ~/.docker/certs/key.pem
  DOCKER_HOST=tcp://$1:2376
  export FLEETCTL_TUNNEL=$1:22
  #alias etcdctl="ssh -A core@$1 'etcdctl'"
  alias fleetctl-ssh="fleetctl ssh $(fleetctl list-machines | cut -c1-8 | sed -n 2p)"
  RPROMPT="%{$fg[magenta]%}[fleetctl:$1]%{$reset_color%}"
}

setup_fleet_ui(){
  do_droplets=($1 $2 $3)

  for droplet in ${do_droplets[@]}
  do
    ssh -A core@$droplet 'rm -rf ~/.ssh/id_rsa'
    scp /Users/jaigouk/.docker/certs/key.pem core@$droplet:.ssh/id_rsa
    ssh -A core@$droplet 'chown -R core:core /home/core/.ssh; chmod 700 /home/core/.ssh; chmod 600 /home/core/.ssh/authorized_keys'
  done
  FLEETCTL_TUNNEL=$droplet:22 fleetctl destroy fleet-ui@{1..3}.service
  FLEETCTL_TUNNEL=$droplet:22 fleetctl destroy fleet-ui@.service
  FLEETCTL_TUNNEL=$droplet:22 fleetctl submit  /Users/user_name/path_to_templates/fleet-ui@.service
  FLEETCTL_TUNNEL=$droplet:22 fleetctl start /Users/user_name/path_to_templates/fleet-ui@{1..3}.service
}


start_mongo_replica(){
  CONTROL_IP=$1
  export FLEETCTL_TUNNEL=$CONTROL_IP:22
  ssh -A core@$CONTROL_IP 'etcdctl set /mongo/replica/name myreplica'
  FLEETCTL_TUNNEL=$1:22 fleetctl submit mongo-data@.service  mongo@.service mongo-replica-config.service
  FLEETCTL_TUNNEL=$1:22 fleetctl start mongo-data@{1..3}.service
  FLEETCTL_TUNNEL=$1:22 fleetctl start mongo@{1..3}.service
  FLEETCTL_TUNNEL=$1:22 fleetctl start mongo-replica-config.service
}
destroy_mongo_replica() {
  CONTROL_IP=$1
  export FLEETCTL_TUNNEL=$CONTROL_IP:22
  alias etcdctl="ssh -A core@$CONTROL_IP 'etcdctl'"
  FLEETCTL_TUNNEL=$1:22 fleetctl destroy mongo-data@{1..3}.service
  FLEETCTL_TUNNEL=$1:22 fleetctl destroy mongo@{1..3}.service
  FLEETCTL_TUNNEL=$1:22 fleetctl destroy mongo-data@.service
  FLEETCTL_TUNNEL=$1:22 fleetctl destroy mongo@.service
  FLEETCTL_TUNNEL=$1:22 fleetctl destroy mongo-replica-config.service
  ssh -A core@$CONTROL_IP 'etcdctl rm /mongo/replica/url'
  ssh -A core@$CONTROL_IP 'etcdctl rm /mongo/replica/siteRootAdmin --recursive'
  ssh -A core@$CONTROL_IP 'etcdctl rm /mongo/replica/siteUserAdmin --recursive'
  ssh -A core@$CONTROL_IP 'etcdctl rm /mongo/replica --recursive'
  ssh -A core@$CONTROL_IP 'etcdctl set /mongo/replica/name myreplica'
}

```

Since we need dockercfg file to pull private / public repos from hub.docker.com, 
`docker login`

### STEP2) Setup data volume container and mongodb replica set

I use fleet-ui to see which services are running on the cluster. And then setup mongo repilca set. Once you launched fleet-ui, you might notice that it takes some time to configure replica set. Please be patient.

```
source ~/.zsh_aliases
fleetctl-switch <do-ip-1>
setup_fleet_ui <do-ip-1> <do-ip-2> <do-ip-3>
cd ./fleet/coreos-mongodb-cluster
start_mongo_replica <do-ip-1>
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

## Backup : docker-volumes

If you destroy mongo-data{1..3}.service, your data is going to be lost. Use [docker-volumes tool](https://github.com/cpuguy83/docker-volumes) to backup your data. 

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