set -e            # Stop the script if some command fails
set -o nounset    # Check for unbound variables
set -o pipefail   # Fail if some part of a pipe fails

hadoopDeployDir="/tmp/hadoop"
ssh_opts=""
scp_opts=""

scriptName=`basename "$0"`
usage="Usage: $scriptName (pseudo | distr) (original | octapus | hadoop3) (-all | [-package] [-deploy] [-conf]) ([-clearfs] [-clearlogs])"

# Show usage if no arguments
if [ $# -eq 0 ] ; then
  echo $usage
  exit 1
fi

# Get the distribution mode
if [ "$1" = "pseudo" ] ; then
      echo "Using pseudo distributed mode"
      dmode="pseudo"
elif [ "$1" = "distr" ] ; then
      echo "Using fully distributed mode"
      dmode="distr"
else
    echo "Invalid mode $1. Use pseudo or distr"
    echo $usage
    exit 1
fi
shift

# Get the hadoop version 
if [ "$1" = "original" ] ; then
      echo "Using HDFS 2.7.0 original version"
      hadoopSrcDir="/home/agalet/hadoop-2.7.0-orig"
      hadoopDistDir="${hadoopSrcDir}/hadoop-dist/target/hadoop-2.7.0"
      hadoopConfDir="/home/agalet/confs/conf-${dmode}-mode-original"
      fsversion="original"
elif [ "$1" = "octapus" ] ; then
      echo "Using MTFS octapus version"
      hadoopSrcDir="/home/agalet/octapus/hadoop-2.7.0"
      hadoopDistDir="${hadoopSrcDir}/hadoop-dist/target/hadoop-2.7.0"
      hadoopConfDir="/home/agalet/confs/conf-${dmode}-mode-octapus"
      fsversion="octapus"
elif [ "$1" = "hadoop3" ] ; then
      echo "Using Hadoop 3.3.2 version"
      hadoopDistDir="/home/agalet/deploy/hadoop/"
      hadoopConfDir="/home/agalet/confs/conf-${dmode}-mode-hadoop3"
      fsversion="hadoop3"
else
    echo "Invalid version $1. Use octapus or original or hadoop3"
    echo $usage
    exit 1
fi
shift

if [[ ! -d "$hadoopConfDir" ]]
then
    echo "${hadoopConfDir=} does not exist. Exiting"
    exit 1
fi

# Get the slave nodes
if [ "$fsversion" = "hadoop3" ] ; then
    SLAVE_FILE=${HADOOP_SLAVES:-$hadoopConfDir/workers}
else
    SLAVE_FILE=${HADOOP_SLAVES:-$hadoopConfDir/slaves}
fi

SLAVE_NAMES=$(cat "$SLAVE_FILE" | sed  's/#.*$//;/^$/d')
if [ "$dmode" = "pseudo" ] ; then
   SLAVE_NAMES=""
fi


optAll=false
optPackage=false
optDeploy=false
optConf=false
optClearfs=false
optClearlogs=false
optClearall=false

# Get the input arguments
for argument in "$@"
do
  case "$argument" in
    (-all)
      optAll=true
      ;;
    (-package)
      optPackage=true
      ;;
    (-deploy)
      optDeploy=true
      ;;
    (-conf)
      optConf=true
      ;;
    (-clearfs)
      optClearfs=true
      ;;
    (-clearlogs)
      optClearlogs=true
      ;;
    (-clearall)
      optClearall=true
      ;;
    (*)
      echo "Invalid argument: $argument"
      echo $usage
      exit 1
      ;;
  esac
done

# Generate the Hadoop package
if [ $optAll == true ] || [ $optPackage == true ]; then
   if [ "$fsversion" = "hadoop3" ]; then
      echo "Option 'package' is not supported for hadoop3. Skipping."
   else
      echo "Generating the Hadoop package"
      currDir=`pwd`
      cd $hadoopSrcDir
      trap "echo 'Compilation Error: Check $currDir/build_output.txt'; exit 1" EXIT
      mvn package -Pdist -Pnative -DskipTests -Dmaven.javadoc.skip=true -Dtar 2>&1 | tee "$currDir/build_output.txt" | grep 'Building Apache Hadoop'
      trap - EXIT
      cd $currDir
   fi
fi


# Function to deploy package to a slave
function deploy_package_to_slave {
   local slave=$1
   echo "Deploying the Hadoop package to $slave:$hadoopDeployDir"
   ssh ${ssh_opts} $slave rm -rf "$hadoopDeployDir"
   scp ${scp_opts} hadoop-temp.tar.gz $slave:~/ > /dev/null
   ssh ${ssh_opts} $slave tar -xzf hadoop-temp.tar.gz 2>&1 | awk '!/future/'
   ssh ${ssh_opts} $slave mv hadoop "$hadoopDeployDir"
   ssh ${ssh_opts} $slave rm hadoop-temp.tar.gz
}

# Deploy the Hadoop package
if [ $optAll == true ] || [ $optDeploy == true ]; then
   echo "Deploying the Hadoop package to $hadoopDeployDir"
   rm -rf "$hadoopDeployDir" 
   cp -p -R "$hadoopDistDir" "$hadoopDeployDir"
   rm -f "$hadoopDeployDir"/bin/*.cmd
   rm -f "$hadoopDeployDir"/sbin/*.cmd
   rm -f "$hadoopDeployDir"/etc/hadoop/*.cmd

   currDir=`pwd`
   cd $( dirname $hadoopDeployDir ) 
   folderName=`basename "$hadoopDeployDir"` 
   tar -czf hadoop-temp.tar.gz "${folderName}"/* 

   for slave in $SLAVE_NAMES ; do
      deploy_package_to_slave $slave 
   done

   wait

   rm hadoop-temp.tar.gz
   cd $currDir
fi


# Function to deploy conf to a slave
function deploy_conf_to_slave {
   local slave=$1
   echo "Deploying the configuration to $slave - $folderName"
   scp ${scp_opts} "$folderName".tar.gz $slave:~/ > /dev/null
   ssh ${ssh_opts} $slave tar -xzf "$folderName".tar.gz 2>&1 | awk '!/future/'
   ssh ${ssh_opts} $slave sed -i s/datanode-g5k/$slave/g "$folderName"/hdfs-site.xml
   ssh ${ssh_opts} $slave sed -i s/datanode-g5k/$slave/g "$folderName"/yarn-site.xml
   ssh ${ssh_opts} $slave sed -i s/namenode-g5k/$(uniq $OAR_NODEFILE | head -n 1)/g "$folderName"/*.xml
   ssh ${ssh_opts} $slave cp "$folderName/"* "$hadoopDeployDir/etc/hadoop/."
   ssh ${ssh_opts} $slave rm "$folderName".tar.gz
   ssh ${ssh_opts} $slave rm -rf "$folderName"
}

# Deploy the configuration
if [ $optAll == true ] || [ $optConf == true ]; then
   echo "Deploying the configuration from $hadoopConfDir"
   currDir=`pwd`
   cd $( dirname $hadoopConfDir )
   folderName=`basename "$hadoopConfDir"`
   cp "$hadoopConfDir/"* "$hadoopDeployDir/etc/hadoop/."
   sed -i s/namenode-g5k/$(uniq $OAR_NODEFILE | head -n 1)/g "$hadoopDeployDir/etc/hadoop/"*.xml
   tar -czf "$folderName".tar.gz "$folderName"/*	

   for slave in $SLAVE_NAMES ; do
      deploy_conf_to_slave $slave
   done

   sed -i s/datanode-g5k/$(uniq $OAR_NODEFILE | head -n 1)/g "$hadoopDeployDir/etc/hadoop/"*.xml

   wait

   rm "$folderName".tar.gz
   cd $currDir	 	
fi


# Function to clear HDFS directories from a slave
function clear_dfs_from_slave {
   local slave=$1
   echo "Clearing all HDFS directories from $slave"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion/dfs"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion/dfs"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion/dfs"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion/dfs"
}

# Clear all HDFS directories
if [ $optClearfs == true ]; then
   echo "Clearing all HDFS directories"
   rm -rf "/tmp/yarndata/$fsversion/dfs"
   rm -rf "/tmp/yarndata/$fsversion/dfs"

   trap "echo 'Failed to format the NameNode'; exit 1" EXIT
   $hadoopDeployDir/sbin/stop-dfs.sh
   $hadoopDeployDir/bin/hdfs namenode -format 2>&1 | grep 'successfully formatted.'
   trap - EXIT
	
   for slave in $SLAVE_NAMES ; do
      clear_dfs_from_slave $slave &
   done

   wait
fi


# Function to clear log directories from a slave
function clear_logs_from_slave {
   local slave=$1
   echo "Clearing all log directories from $slave"
   ssh ${ssh_opts} $slave mkdir -p "/tmp/yarndata/$fsversion/logs"
   ssh ${ssh_opts} $slave mkdir -p "/tmp/yarndata/$fsversion/pastlogs"
   ssh ${ssh_opts} $slave mkdir -p "/tmp/yarndata/$fsversion/nm/userlogs"
   ssh ${ssh_opts} $slave mkdir -p "/tmp/yarndata/$fsversion/nm/pastuserlogs"
   ssh ${ssh_opts} $slave mv "/tmp/yarndata/$fsversion/logs" "/tmp/yarndata/$fsversion/pastlogs/logs_$datetime"
   ssh ${ssh_opts} $slave mv "/tmp/yarndata/$fsversion/nm/userlogs" "/tmp/yarndata/$fsversion/nm/pastuserlogs/userlogs_$datetime"
}

# Clear all logs directories (move them to a new folder)
if [ $optClearlogs == true ]; then
   echo "Clearing all log directories"
   datetime=`date +%y%m%d_%H%M%S`
   mkdir -p "/tmp/yarndata/$fsversion/logs"
   mkdir -p "/tmp/yarndata/$fsversion/pastlogs"
   mv "/tmp/yarndata/$fsversion/logs" "/tmp/yarndata/$fsversion/pastlogs/logs_$datetime"

   for slave in $SLAVE_NAMES ; do
      clear_logs_from_slave $slave &
   done

   wait
fi


# Function to clear all yarndata directories from a slave
function clear_all_logs_from_slave {
   local slave=$1
   echo "Clearing all yarndata directories of file system from $slave"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion/dfs"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion/dfs"
   ssh ${ssh_opts} $slave rm -rf "/tmp/yarndata/$fsversion/dfs"
}

#Clear all yarndata directories (e.g. temp, dfs, logs, yarn)
if [ $optClearall == true ] ; then
   echo "Clearing all yarndata directories of file system"
   rm -rf "/tmp/yarndata/$fsversion/dfs"
   rm -rf "/tmp/yarndata/$fsversion"

   trap "echo 'Failed to format the NameNode'; exit 1" EXIT
   $hadoopDeployDir/sbin/stop-dfs.sh
   $hadoopDeployDir/bin/hdfs namenode -format 2>&1 | grep 'successfully formatted.'
   trap - EXIT

   for slave in $SLAVE_NAMES ; do
      clear_all_logs_from_slave $slave &
   done

   wait
fi

