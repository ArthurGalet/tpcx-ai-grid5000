nodefile="$OAR_NODEFILE" # file with requested nodes
workersfile="/home/${USER}/confs/conf-distr-mode-hadoop3/workers" # hadoop workers file
benchmark="/home/${USER}/archives/tpcx-ai.tar.gz" # benchmark archive

echo "Installing pssh, pscp, prsync"
sudo-g5k apt-get -y install pssh
sudo-g5k ln -f /usr/bin/parallel-ssh /usr/local/bin/pssh
sudo-g5k ln -f /usr/bin/parallel-scp /usr/local/bin/pscp
sudo-g5k ln -f /usr/bin/parallel-rsync /usr/local/bin/prsync

uniq $nodefile | tail -n +2 >$workersfile
cp -fr $workersfile /home/${USER}/confs/conf-distr-mode-spark24/slaves
cp -fr $workersfile /home/${USER}/confs/conf-distr-mode-spark24/workers
uniq $nodefile > /home/${USER}/deploy/tpcx-ai/nodes

echo "Deploying benchmark locally"
tar -czf $benchmark -C /home/${USER}/deploy tpcx-ai
tar -xzf $benchmark -C /tmp/
sed -i s/namenode-g5k/$(uniq $nodefile | head -n 1)/g /tmp/tpcx-ai/lib/pdgf/config/tpcxai-generation.xml

echo "Deploying benchmark on all nodes"
prsync -az -h $workersfile $benchmark /tmp/
pssh -h $workersfile "tar -xf /tmp/tpcx-ai.tar.gz -C /tmp/ && rm -f /tmp/tpcx-ai.tar.gz && sed -i s/namenode-g5k/$(uniq $nodefile | head -n 1)/g /tmp/tpcx-ai/lib/pdgf/config/tpcxai-generation.xml"
rm $benchmark

echo "Installing Python3.7"
tar -xf /home/${USER}/archives/Python-3.7.13.tgz -C /tmp/ --overwrite > /dev/null 2> /dev/null
cd /tmp/Python-3.7.13/
/tmp/Python-3.7.13/configure > /dev/null
make -C /tmp/Python-3.7.13 -j8 > /dev/null
sudo-g5k make install -C /tmp/Python-3.7.13 > /dev/null 2>/dev/null
sudo-g5k ln -f /usr/local/bin/python3 /usr/local/bin/python # python symlink to python3 (python3.7)

echo "Deploying Python3.7 on all nodes"
prsync -az -h $workersfile /tmp/Python-3.7.13 /tmp/ > /dev/null
pssh -h $workersfile 'sudo-g5k make install -C /tmp/Python-3.7.13 -f /tmp/Python-3.7.13/Makefile; ln -f /usr/local/bin/python3 /usr/local/bin/python' > /dev/null

echo "Installing Java 8 on all nodes"
sudo-g5k tar -xzf /home/${USER}/archives/java8jdk.tar.gz -C /usr/lib/jvm --overwrite && sudo-g5k update-alternatives --install /usr/bin/java java /usr/lib/jvm/jre1.8.0_333/bin/java 1 && sudo-g5k update-alternatives --set java /usr/lib/jvm/jre1.8.0_333/bin/java
prsync -az -h $workersfile /home/${USER}/archives/java8jdk.tar.gz /tmp/
pssh -h $workersfile sudo-g5k tar -xzf /tmp/java8jdk.tar.gz -C /usr/lib/jvm --overwrite
pssh -h $workersfile sudo-g5k update-alternatives --install /usr/bin/java java /usr/lib/jvm/jre1.8.0_333/bin/java 1
pssh -h $workersfile sudo-g5k update-alternatives --set java /usr/lib/jvm/jre1.8.0_333/bin/java

echo "Installing Anaconda"
wget https://repo.anaconda.com/archive/Anaconda3-2022.05-Linux-x86_64.sh -P /tmp/
sudo-g5k chmod u+x /tmp/Anaconda3-2022.05-Linux-x86_64.sh
/tmp/Anaconda3-2022.05-Linux-x86_64.sh -bf -p /tmp/anaconda3 > /dev/null

rm -rf ~/conf-distr-mode-hadoop3/ ~/config.log ~/config.status ~/Makefile ~/Makefile.pre ~/Misc/ ~/Modules/ ~/Objects/ ~/Parser/ ~/Programs/ ~/pyconfig.h ~/Python/ 2> /dev/null

echo "Building benchmark venv locally"
cd /tmp/tpcx-ai
rm -rf /tmp/tpcx-ai/lib/python-venv # removing previous virtual environment
/tmp/tpcx-ai/setup-spark.sh > /dev/null

echo "Deploying benchmark venv on all nodes"
pssh -h $workersfile rm -rf /tmp/tpcx-ai/lib/python-venv
prsync -az -h ~/deploy/tpcx-ai/nodes /tmp/tpcx-ai/lib/python-venv /tmp/tpcx-ai/lib/ > /dev/null

~/exec-hadoop-deploy.sh distr hadoop3 -deploy
~/exec-hadoop-deploy.sh distr hadoop3 -conf
~/exec-spark-deploy.sh distr spark24 -deploy
~/exec-spark-deploy.sh distr spark24 -conf

ssd=0
hdd=0
echo "Formatting, partitioning and mounting disks on all nodes"
for node in $(uniq $nodefile)
do
    disktype=$(ssh $node lsblk -dno ROTA /dev/sda) # setting prefix for HDFS data dirs
    if [ $disktype -eq 1 ]; then
        datadirs="[DISK]file:///tmp/yarndata/hadoop3/dfs/"
        hdd=1
    elif [ $disktype -eq 0 ]; then
        datadirs="[SSD]file:///tmp/yarndata/hadoop3/dfs/"
        ssd=1
    fi

    counter=1
    for disk in $(ssh $node "lsblk -do NAME | tail -n +3 | grep sd")
    do
        ssh $node "sudo-g5k wipefs /dev/${disk}"
        ssh $node "echo 'type=83' | sudo-g5k sfdisk /dev/${disk}"
        ssh $node "sudo-g5k mkfs.ext4 -m 0 /dev/${disk}1"
        ssh $node "mkdir -p /tmp/disk${counter} /tmp/yarndata/hadoop3/dfs${counter}"
        ssh $node "sudo-g5k mount /dev/${disk}1 /tmp/disk${counter}"
        ssh $node "sudo-g5k mount /dev/${disk}1 /tmp/yarndata/hadoop3/dfs${counter}"
        ssh $node "sudo-g5k chown ${USER} /tmp/yarndata/hadoop3/dfs${counter}"
        ssh $node "mkdir /tmp/yarndata/hadoop3/dfs${counter}/data"

        disktype=$(ssh $node lsblk -dno ROTA /dev/${disk}) # setting prefix for HDFS data dirs
        if [ $disktype -eq 1 ]; then
            datadirs="$datadirs,[DISK]file:///tmp/yarndata/hadoop3/dfs${counter}/"
            hdd=1
        elif [ $disktype -eq 0 ]; then
            datadirs="$datadirs,[SSD]file:///tmp/yarndata/hadoop3/dfs${counter}/"
            ssd=1
        fi

        ((counter++))
    done

    ssh $node sed -i s+datadirs-g5k+$datadirs+g /tmp/hadoop/etc/hadoop/hdfs-site.xml
    ssh $node sed -i s+datadirs-g5k+$(echo $datadirs | sed 's+\[DISK\]file://++g' | sed 's+\[SSD\]file://++g')+g /tmp/spark/conf/spark-env.sh

done

mkdir -p /tmp/yarndata/hadoop3/dfs/name
~/exec-hadoop-deploy.sh distr hadoop3 -clearfs
~/cluster-control.sh start dfs spark

if [ $ssd -eq 1 ]; then
    if [ $hdd -eq 1 ]; then
        hdfs storagepolicies -setStoragePolicy -path /user/agalet -policy One_SSD
        hdfs storagepolicies -satisfyStoragePolicy -path /user/agalet
    else
        hdfs storagepolicies -setStoragePolicy -path /user/agalet -policy All_SSD
        hdfs storagepolicies -satisfyStoragePolicy -path /user/agalet
    fi
fi

source /tmp/tpcx-ai/setenv.sh
/tmp/tpcx-ai/tools/enable_parallel_datagen.sh
/tmp/tpcx-ai/bin/tpcxai.sh -uc 1 3 4 6 7 8 10 -c /tmp/tpcx-ai/driver/config/spark.yaml -sf 30
cp -r /tmp/tpcx-ai/logs /home/agalet/logs/
mv /home/agalet/logs/logs/ "/home/agalet/logs/logs$(ls -l /home/agalet/logs/ | wc -l)"
