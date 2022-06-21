set -e            # Stop the script if some command fails
set -o nounset    # Check for unbound variables
set -o pipefail   # Fail if some part of a pipe fails

scriptName=`basename "$0"`
usage="Usage: $scriptName (local | distr) (spark16 | spark23 | spark24) (-all | [-package] [-deploy] [-conf])"

# Show usage if no arguments
if [ $# -eq 0 ] ; then
  echo $usage
  exit 1
fi

sparkDeployDir="/tmp/spark"
ssh_opts=""
scp_opts=""

# Get the distribution mode
if [ "$1" = "local" ] ; then
      echo "Using local Spark mode"
      dmode="local"
elif [ "$1" = "distr" ] ; then
      echo "Using distributed Spark mode"
      dmode="distr"
else
    echo "Invalid mode $1. Use local or distr"
    echo $usage
    exit 1
fi
shift

# Get the Spark version 
if [ "$1" = "spark16" ] ; then
      echo "Using Spark 1.6.2 (with octopus) version"
      sparkSrcDir="/home/agalet/spark-1.6.2"
      sparkConfDir="/home/agalet/confs/conf-${dmode}-mode-spark16"
      sparkPackageName="spark-1.6.2-bin-octapus"
      sparkVersion="spark-1.6.2"
elif [ "$1" = "spark23" ] ; then
      echo "Using Spark 2.3.2 original version"
      sparkSrcDir="/home/agalet/spark-2.3.2"
      sparkConfDir="/home/agalet/confs/conf-${dmode}-mode-spark23"
      sparkPackageName="spark-2.3.2"
      sparkVersion="spark-2.3.2"
elif [ "$1" = "spark24" ] ; then
      echo "Using Spark 2.4.8 original version"
      sparkSrcDir="/home/agalet/archives/"
      sparkConfDir="/home/agalet/confs/conf-${dmode}-mode-spark24"
      sparkPackageName="spark-2.4.8"
      sparkVersion="spark-2.4.6" #- no change, only used for build test
else
    echo "Invalid version $1. Use spark16 or spark23 or spark24"
    echo $usage
    exit 1
fi
shift

if [[ ! -d "$sparkConfDir" ]]
then
    echo "${sparkConfDir=} does not exist. Exiting"
    exit 1
fi

# Get slave names
if [ "$dmode" = "local" ] ; then
   SLAVE_NAMES=""
else
   SLAVE_FILE=${SPARK_SLAVES:-$sparkConfDir/slaves}
   SLAVE_NAMES=$(cat "$SLAVE_FILE" | sed  's/#.*$//;/^$/d')
fi

optAll=false
optPackage=false
optDeploy=false
optConf=false

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
    (*)
      echo "Invalid argument: $argument"
      echo $usage
      exit 1
      ;;
  esac
done

# Generate the Spark  package
if [ $optAll == true ] || [ $optPackage == true ]; then
   echo "Generating the Spark package"

   if [ "$sparkVersion" = "spark-1.6.2" ]; then

      # Update the mvn repo with octapus' latest jars
      cp /home/agalet/deploy/hadoop/share/hadoop/common/hadoop-common-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-common/2.7.0/hadoop-common-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/common/lib/hadoop-annotations-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-annotations/2.7.0/hadoop-annotations-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/common/lib/hadoop-auth-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-auth/2.7.0/hadoop-auth-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/hdfs/hadoop-hdfs-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-hdfs/2.7.0/hadoop-hdfs-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-client-app-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-mapreduce-client-app/2.7.0/hadoop-mapreduce-client-app-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-client-common-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-mapreduce-client-common/2.7.0/hadoop-mapreduce-client-common-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-common-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-common/2.7.0/hadoop-yarn-common-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-api-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-api/2.7.0/hadoop-yarn-api-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-client-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-client/2.7.0/hadoop-yarn-client-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-client-core-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-mapreduce-client-core/2.7.0/hadoop-mapreduce-client-core-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-server-common-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-server-common/2.7.0/hadoop-yarn-server-common-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-client-shuffle-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-mapreduce-client-shuffle/2.7.0/hadoop-mapreduce-client-shuffle-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-client-jobclient-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-mapreduce-client-jobclient/2.7.0/hadoop-mapreduce-client-jobclient-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-server-nodemanager-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-server-nodemanager/2.7.0/hadoop-yarn-server-nodemanager-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-server-web-proxy-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-server-web-proxy/2.7.0/hadoop-yarn-server-web-proxy-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-server-resourcemanager-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-server-resourcemanager/2.7.0/hadoop-yarn-server-resourcemanager-2.7.0.jar
      cp /home/agalet/deploy/hadoop/share/hadoop/yarn/hadoop-yarn-server-applicationhistoryservice-2.7.0.jar /home/agalet/.m2/repository/org/apache/hadoop/hadoop-yarn-server-applicationhistoryservice/2.7.0/hadoop-yarn-server-applicationhistoryservice-2.7.0.jar

      # build spark
      currDir=`pwd`
      cd $sparkSrcDir
      trap "echo 'Compilation Error: Check $currDir/build_output.txt'; exit 1" EXIT
      ./make-distribution.sh --name octapus --tgz -Pyarn -Phadoop-provided -Phive -Phive-thriftserver -Dhadoop.version=2.7.0 -Dscala-2.10  2>&1 | tee "$currDir/build_output.txt" # | grep 'Building Spark Project'
      trap - EXIT
      cd $currDir

   elif [ "$sparkVersion" = "spark-2.3.2" ]; then
      echo "Option package is not supported for spark23. Skipping."

   elif [ "$sparkVersion" = "spark-2.4.6" ]; then
      # build spark
      currDir=`pwd`
      cd $sparkSrcDir
      trap "echo 'Compilation Error: Check $currDir/build_output.txt'; exit 1" ERR
       ./build/mvn initialize -DskipTests -Dhadoop.version=2.7.0 2>&1 | tee "$currDir/build_output.txt" | grep 'Building Spark Project'
       ./dev/make-distribution.sh --name octapus --clean --tgz -Pyarn -Dhadoop.version=2.7.0 -Phive -Phive-thriftserver 2>&1 | tee "$currDir/build_output.txt" | grep 'Building Spark Project'
      ./build/mvn initialize -DskipTests -Dhadoop.version=3.3.2 2>&1 | tee "$currDir/build_output.txt" | grep 'Building Spark Project'
      ./dev/make-distribution.sh --name octapus --clean --tgz -Pyarn -Dhadoop.version=3.3.2 -Phive -Phive-thriftserver 2>&1 | tee "$currDir/build_output.txt" | grep 'Building Spark Project'
      trap - ERR
      cd $currDir
   fi
fi

# Deploy the Spark package
if [ $optAll == true ] || [ $optDeploy == true ]; then
   echo "Deploying the Spark package to $sparkDeployDir"
   rm -rf "$sparkDeployDir"
   deployDir=`dirname "$sparkDeployDir"`
   cp "$sparkSrcDir/${sparkPackageName}.tgz" "$deployDir"/.
   tar -C $deployDir -xzf "$deployDir/${sparkPackageName}.tgz"  
   mv "$deployDir/$sparkPackageName" "$sparkDeployDir" 
   rm "$deployDir/${sparkPackageName}.tgz"

   for slave in $SLAVE_NAMES ; do
      echo "Deploying the Spark package to $slave:$sparkDeployDir"
      ssh ${ssh_opts} $slave rm -rf "$sparkDeployDir"
      scp ${scp_opts} $sparkSrcDir/${sparkPackageName}.tgz $slave:$deployDir > /dev/null
      ssh ${ssh_opts} $slave tar -C $deployDir -xzf "$deployDir/${sparkPackageName}.tgz" 2>&1 | awk '!/future/'
      ssh ${ssh_opts} $slave mv "$deployDir/$sparkPackageName" "$sparkDeployDir"   
      ssh ${ssh_opts} $slave rm "$deployDir/${sparkPackageName}.tgz"
   done
fi

# Deploy the Spark configuration
if [ $optAll == true ] || [ $optConf == true ]; then
   echo "Deploying the Spark configuration to $sparkDeployDir/conf"
   cp $sparkConfDir/* $sparkDeployDir/conf/.
   sed -i s/namenode-g5k/$(uniq $OAR_NODEFILE | head -n 1)/g $sparkDeployDir/conf/spark-defaults.conf

   for slave in $SLAVE_NAMES ; do
      echo "Deploying the configuration to $slave"
      ssh ${ssh_opts} $slave rm -rf "$sparkDeployDir/conf/*"
      scp ${scp_opts} $sparkConfDir/* $slave:$sparkDeployDir/conf/. > /dev/null
      ssh ${ssh_opts} $slave sed -i s/namenode-g5k/$(uniq $OAR_NODEFILE | head -n 1)/g $sparkDeployDir/conf/spark-defaults.conf
   done
fi

echo "DONE"

