#!/bin/sh
################################
#  author : 	Daniel.Kang (daniel.kang@ucloud.cn)
#  date:	2016.12.27
################################

#set -x

azone=bj
owner=admin
master_port=5050
slave_port=5051
marathon_port=8080
quorum=2

module=cluster

##private IP
declare -a cluster=("privateip1" "privateip2" "privateip3")
##public IP
declare -a clusterPublic=("publicip1" "publicip2" "publicip3")

#多地域mesos集群部署，在下面定义集群IP信息;
#若无内外网之分，IP填相同值
#若不希望直接暴露应用至公网，publicIP填成privateIP
declare -A clusterMap=(["example"]="示例" ["bj"]="北京" ["new"]="centos7.0")

function get_cluster_by_azone()
{
  case "$1" in
  example)
        cluster=("10.9.9.9" "10.9.9.10" "10.9.9.11")
	clusterPublic=("192.168.1.163" "192.168.1.164" "192.168.1.165")
        ;;
  bj)
        cluster=("10.9.116.242" "10.9.111.248" "10.9.135.146")
    	clusterPublic=("106.75.13.243" "106.75.64.31" "106.75.4.181")
        ;;
  new)
        cluster=("10.9.139.83" "10.9.115.140" "10.9.147.228" "10.9.117.5" "10.9.154.38")
    	clusterPublic=("106.75.67.83" "106.75.67.239" "106.75.64.242" "106.75.13.237" "106.75.50.15")
        ;;
  *)
        echo "no such cluster $1"
        usage
        ;;
  esac
}

function list_all_cluster()
{
  for zone in ${!clusterMap[@]}; do
    get_cluster_by_azone $zone
    printf "%s\t%s\t\t\n" $zone ${clusterMap[$zone]}
    echo private IP:	${cluster[@]} 
    echo public  IP:${clusterPublic[@]}
    echo ..............................................................
  done
}

function usage() {
        echo "usage:"
        echo "$0 -c [update|deploy|delete] -m [cluster|slave] -s ip"
        echo "$0 --cmd=[update|deploy|delete] --module=cluster|slave [--azone=bj] [--owner=admin] [--list] [--sip=ip]"
        echo ""
        echo ">>azone为可用区简称，owner为服务分类，module==cluster时默认为admin"
        echo ">>部署cluster示例：$0 --azone=bj "
        echo ">>部署slave示例：$0 -m slave --azone=bj --owner=admin -s private_ip -p public_ip"
    	echo ">>列出所有azone: $0 --list"

        exit 1
}

function init_node() {
#install docker and docker-compose
  #install docker-compose
  scp ./docker-compose root@$1:/usr/local/bin/docker-compose
  pssh -l root -H $1 --inline-stdout "chmod +x /usr/local/bin/docker-compose; docker-compose -v"
  #install docker
  
  #install from yum source;  
  scp ./docker-main.repo root@$1:/etc/yum.repos.d/docker-main.repo
  pssh -t 0 -l root -H $1 --inline-stdout "yum install -y docker-engine; systemctl daemon-reload; systemctl enable docker; systemctl start docker;"

  #modify config, use overlay storage and set default docker dir to /data/docker
  pssh -l root -H $1 --inline-stdout "sed -i 's#ExecStart=/usr/bin/dockerd#ExecStart=/usr/bin/dockerd -s overlay --default-ulimit nproc=1024:1024 --default-ulimit nofile=65536:65536 -g /data/docker --live-restore#' /usr/lib/systemd/system/docker.service; service docker restart"

}

function init_node_centos6() {
  #check kernel version to update kernel to 4.1.0: for docker bugs: https://github.com/docker/docker/issues/10294
  pssh -l root -H $1 --inline-stdout "uname -r" | grep "4.1.0-13.el6.ucloud.x86_64"

  if [ "$?" != 0 ]; then
      echo "will update kernel to 4.1.0-13.el6.ucloud.x86_64, waiting for reboot......"
      pssh -t 0 -l root -H $1 --inline-stdout "wget http://static.ucloud.cn/kernel/4.1.0-13.el6.ucloud.x86_64.tar.gz; tar xf 4.1.0-13.el6.ucloud.x86_64.tar.gz; cd kernel-4.1.0-13.el6.ucloud; ./install.sh; cd ..; rm -rf kernel-4.1.0-13.el6.ucloud 4.1.0-13.el6.ucloud.x86_64.tar.gz; reboot"
  fi 

  #install docker-compose
  scp ./docker-compose root@$1:/usr/local/bin/docker-compose
  pssh -l root -H $1 --inline-stdout "chmod +x /usr/local/bin/docker-compose; docker-compose -v"

  #install docker
  #install from yum source;
  scp ./docker-ucloud-6.repo root@$1:/etc/yum.repos.d/docker-ucloud-6.repo
  pssh -l root -H $1 --inline-stdout "grep 'tmpfs /var/run/docker tmpfs defaults 0 0' /etc/fstab || echo 'tmpfs /var/run/docker tmpfs defaults 0 0' >> /etc/fstab; mount -a"
  pssh -l root -H $1 --inline-stdout "touch /etc/sysconfig/docker && sed -i '/^other_args=/'d /etc/sysconfig/docker && echo 'other_args=\"-s overlay --default-ulimit nproc=1024:1024 --default-ulimit nofile=65536:65536 -g /data/docker --live-restore\"' >>  /etc/sysconfig/docker"
  pssh -t 0 -l root -H $1 --inline-stdout "yum install -y docker-engine; chkconfig docker on;"

}

# arg1: node_ip arg2: zoo_cluster_id arg3: zk_url arg4: publicIP
function set_master_node()
{
  #copy mesos cluster deployment files to node
  #copy deployment files
  scp -r ./umesos-deploy/etc/umesos root@$1:/etc/

  #modify deploy files by hostip and hostPublic IP
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{zk_url}#$3#' /etc/umesos/compose/*.yml"
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{cluster_name}#${clusterMap[$azone]}#' /etc/umesos/compose/*.yml"
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{private_ip}#$1#' /etc/umesos/compose/*.yml"
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{public_ip}#$4#' /etc/umesos/compose/*.yml"
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{master_port}#$master_port#' /etc/umesos/compose/*.yml"
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{marathon_port}#$marathon_port#' /etc/umesos/compose/*.yml"
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{quorum}#$quorum#' /etc/umesos/compose/*.yml"

  #set zookeeper config
  cluster_len=${#cluster[@]}
  str="";
  for i in $( seq 0 `expr $cluster_len - 1` )
  do
    str+="server.`expr $i + 1`=${cluster[$i]}:2888:3888 ";
    #echo $str;
  done

  pssh -l root -H $1 --inline-stdout "sed -i 's#%{zoo_cluster_id}#$2#' /etc/umesos/compose/*.yml"
  pssh -l root -H $1 --inline-stdout "sed -i 's#%{zoo_cluster_server}#$str#' /etc/umesos/compose/*.yml"

  #set auto-start when power-on
  pssh -l root -H $1 --inline-stdout "cd /etc/umesos/service; chmod 644 umesos-cluster-*.service; cp umesos-cluster-*.service /usr/lib/systemd/system/"

}

# arg1: private_ip arg2: zk_url arg3: owner arg4: public_ip
function set_slave_node_binary()
{
  #echo $1 $2 $azone $owner
  pssh -t 0 -l root -H $1 --inline-stdout "rpm -Uvh http://repos.mesosphere.com/el/7/noarch/RPMS/mesosphere-el-repo-7-2.noarch.rpm; yum -y install mesos-1.1.0-2.0.107.centos701406.x86_64; rm -rf /usr/lib/systemd/system/mesos-*.service; mkdir -p /etc/umesos-slave"  

  #set and copy config file
  env_file="./umesos-slave/etc/umesos-slave/slave_env.sh"
  cp ${env_file} ${env_file}.tmp
  sed -i "s#%{zk_url}#$2#" ${env_file}.tmp
  sed -i "s#%{private_ip}#$1#" ${env_file}.tmp
  sed -i "s#%{public_ip}#$4#" ${env_file}.tmp
  sed -i "s#%{azone}#$azone#" ${env_file}.tmp
  sed -i "s#%{owner}#$3#" ${env_file}.tmp
  sed -i "s#%{slave_port}#$slave_port#" ${env_file}.tmp

  scp ./umesos-slave/etc/umesos-slave/umesos-cluster-slave.service root@$1:/usr/lib/systemd/system/umesos-cluster-slave.service
  scp ${env_file}.tmp root@$1:/etc/umesos-slave/slave_env.sh
  rm -f ${env_file}.tmp

  #TODO: check kernel version to update kernel to 4.1: for docker bugs: https://github.com/docker/docker/issues/10294
  pssh -l root -H ${cluster[$i]} --inline-stdout "uname -r" | grep "4.1.0-13.el7.ucloud.x86_64"

  if [ "$?" != 0 ]; then
      pssh -t 0 -l root -H $1 --inline-stdout "wget http://static.ucloud.cn/kernel/4.1.0-13.el7.ucloud.x86_64.tar.gz; tar xf 4.1.0-13.el7.ucloud.x86_64.tar.gz; cd kernel-4.1.0-13.el7.ucloud; ./install.sh; cd ..; rm -rf kernel-4.1.0-13.el7.ucloud 4.1.0-13.el7.ucloud.x86_64.tar.gz; systemctl daemon-reload; systemctl enable umesos-cluster-slave; reboot"
  else
      pssh -l root -H $1 --inline-stdout "systemctl daemon-reload; systemctl enable umesos-cluster-slave; systemctl start umesos-cluster-slave"
  fi
}

function start_cluster()
{
  cluster_len=${#cluster[@]}
  for i in $( seq 0 `expr $cluster_len - 1` )
  do 
    #TODO: check kernel version to update kernel to 4.1: for docker bugs: https://github.com/docker/docker/issues/10294
    pssh -l root -H ${cluster[$i]} --inline-stdout "uname -r" | grep "4.1.0-13.el7.ucloud.x86_64"
    
    if [ "$?" != 0 ]; then
        #not "4.1.0-13.el7.ucloud.x86_64", should upgrade kernel
        pssh -l root -H ${cluster[$i]} --inline-stdout "wget http://static.ucloud.cn/kernel/4.1.0-13.el7.ucloud.x86_64.tar.gz; tar xf 4.1.0-13.el7.ucloud.x86_64.tar.gz; cd kernel-4.1.0-13.el7.ucloud; ./install.sh; cd ..; rm -rf kernel-4.1.0-13.el7.ucloud 4.1.0-13.el7.ucloud.x86_64.tar.gz; systemctl daemon-reload; systemctl enable umesos-cluster-zookeeper umesos-cluster-master umesos-cluster-marathon; reboot"
    else
        #already "4.1.0-13.el7.ucloud.x86_64"
        pssh -l root -H ${cluster[$i]} --inline-stdout "systemctl daemon-reload; systemctl enable umesos-cluster-zookeeper umesos-cluster-master umesos-cluster-marathon; systemctl start umesos-cluster-zookeeper umesos-cluster-master umesos-cluster-marathon; reboot"
    fi
  done
}

function get_zk_url()
{
  cluster_len=${#cluster[@]}
  zk_url="zk://${cluster[0]}:2181"
  for i in $( seq 1 `expr $cluster_len - 1` )
  do 
    zk_url="${zk_url},${cluster[i]}:2181"
  done
}

function main()
{
  echo ${clusterMap[$azone]}  
  #list_all_cluster
  get_cluster_by_azone $azone

  cluster_len=${#cluster[@]}
  get_zk_url
  echo $zk_url

  if [ "$module" = "cluster" ]; then
    #do cluster deploy
    for id in $( seq 0 `expr $cluster_len - 1` )
    do
      echo "deploy ${cluster[$id]}" 
      init_node ${cluster[$id]}
      set_master_node ${cluster[$id]} `expr $id + 1` $zk_url ${clusterPublic[$id]}
    done
    start_cluster

  elif [ "$module" = "slave" ]; then
    echo "deploy slave node: $azone $owner $slave_ip $slave_pub_ip"
    init_node $slave_ip
    set_slave_node_binary $slave_ip $zk_url $owner $slave_pub_ip

  else
    echo "error parameters!"
    exit 0
  fi
}

TEMP=`getopt -o c:m:s:p:lh -l cmd:,module:,azone:,owner:,sip:,pip:,list,help -- "$@"`
[ $? -ne 0 ] && usage
eval set -- "$TEMP"

[ $# -le 1 ] && usage

while true; do
        case "$1" in
                -c|--cmd)
                        cmd="$2"
                        shift 2
                        ;;
                -m|--module)
                        module="$2"
                        shift 2
                        ;;
                --azone)
                        azone="$2"
                        shift 2
                        ;;
                --owner)
                        owner="$2"
                        shift 2
                        ;;
		-l|--list)
			list_all_cluster
			exit 1
			;;
		-s|--sip)
			slave_ip="$2"
			shift 2
			;;
		-p|--pip)
			slave_pub_ip="$2"
			shift 2
			;;
                -h|--help)
                        usage
                        shift
                        ;;
                --)
                        shift
                        break
                        ;;
                *)
                        break
                        ;;
        esac
done

if [ "$cmd" = "" ]; then
        cmd="update"
fi

  echo "$@"
  main
