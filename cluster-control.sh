set -e            # Stop the script if some command fails
set -o nounset    # Check for unbound variables
set -o pipefail   # Fail if some part of a pipe fails


scriptName=`basename "$0"`
usage="Usage: $scriptName (start | stop | restart) [all] [dfs] [yarn] [mrhis] [spark] [sparkhis]"

# Show usage if no arguments
if [ $# -eq 0 ] ; then
  echo $usage
  echo "By default, it starts/stops dfs, yarn, and mrhis"
  exit 1
fi

hadoopDeployDir="/tmp/hadoop"
sparkDeployDir="/tmp/spark"

# Get start or stop command
cmdStart=false
cmdStop=false
if [ "$1" = "start" ] ; then
  cmdStart=true
elif [ "$1" = "stop" ] ; then
  cmdStop=true
elif [ "$1" = "restart" ] ; then
  cmdStop=true
  cmdStart=true
else
  echo "Invalid argument $1"
  echo $usage
  exit 1
fi

shift

# Get the input arguments
optdfs=false
optyarn=false
optmrhis=false
optspark=false
optsparkhis=false

for argument in "$@"
do
  case "$argument" in
    (all)
      optdfs=true
      optyarn=true
      optmrhis=true
      optspark=true
      optsparkhis=true
      ;;
    (dfs)
      optdfs=true
      ;;
    (yarn)
      optyarn=true
      ;;
    (mrhis)
      optmrhis=true
      ;;
    (spark)
      optspark=true
      optsparkhis=true
      ;;
    (sparkhis)
      optsparkhis=true
      ;;
    (*)
      echo "Invalid argument: $argument"
      echo $usage
      exit 1
      ;;
  esac
done

if [ $# -eq 0 ] ; then
  # By default, start/stop dfs, yarn, and mrhis
  optdfs=true
  optyarn=true
  optmrhis=true
fi

# Stop the requested services
if [ $cmdStop == true ] ; then
  if [ $optmrhis == true ] ; then
    $hadoopDeployDir/sbin/mr-jobhistory-daemon.sh stop historyserver
  fi
  if [ $optyarn == true ] ; then
    $hadoopDeployDir/sbin/stop-yarn.sh
  fi
  if [ $optsparkhis == true ] ; then
    $sparkDeployDir/sbin/stop-history-server.sh
  fi
  if [ $optspark == true ] ; then
    $sparkDeployDir/sbin/stop-all.sh
  fi
  if [ $optdfs == true ] ; then
    $hadoopDeployDir/sbin/stop-dfs.sh
  fi
fi

# Start the requested services
if [ $cmdStart == true ] ; then
  if [ $optdfs == true ] ; then
    $hadoopDeployDir/sbin/start-dfs.sh
  fi
  if [ $optyarn == true ] ; then
    $hadoopDeployDir/sbin/start-yarn.sh
  fi
  if [ $optmrhis == true ] ; then
    $hadoopDeployDir/sbin/mr-jobhistory-daemon.sh start historyserver
  fi
  if [ $optspark == true ] ; then
    $sparkDeployDir/sbin/start-all.sh
  fi
  if [ $optsparkhis == true ] ; then
    sparkLogsDir=`grep spark.history.fs.logDirectory $sparkDeployDir/conf/spark-defaults.conf | tr -s ' ' | cut -d' ' -f2`
    $hadoopDeployDir/bin/hdfs dfs -mkdir -p "$sparkLogsDir"
    $sparkDeployDir/sbin/start-history-server.sh
  fi
fi

