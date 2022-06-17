# TPCx-AI experiment over a Grid'5000 cluster with different storage mediums

## Nodes environment

The benchmark deployment relies on the common home directory of Grid'5000 which is accessible from all nodes.
All the files needed are located inside and organized in the following way :

- `deploy` folder contains a built version of Hadoop, Spark and the TPCx-AI benchmark with a generic and unsuitable configuration
- `confs` folder contains the true configuration of the previous software which is copied after the deployment
- `archives` folder contains the tar archives deployed on the nodes : Java 8, Python3.7, Spark, benchmark

The following scripts are located in the home directory :

- `exec-hadoop-deploy.sh` : Hadoop deployment and configuration
- `exec-spark-deploy.sh` : Spark deployment and configuration
- `cluster-control.sh` : Hadoop and Spark launch
- `setup.sh` : combined version of all the scripts I wrote in a unique non-interactive script

Running `setup.sh` in such an environment is supposed to install the experiment environment, run the benchmark and gather the results.
However it may very likely need adaptations to work on another environment.

---

## Configuration

### Placeholders

To namenode/datanode and master/worker repartition is automated and unpredictable. 
The files that could not use commands to resolve this parameters are configured with placeholders.
Those placeholders are replaced by the right values using _sed_ once deployed.

The following placeholders are used :
- _namenode-g5k_ : namenode/master
- _datanode-g5k_ : datanode/worker, can only be set when deployed
- _datadirs-g5k_ : directories where Hadoop/Spark can store their files, useful with multiple disks, can only be set when deployed

### Files

Here are some important configuration files modifications that I made.

- Hadoop : **hdfs-site.xml** and **core-site.xml** : _datanode-g5k_ and _namenode-g5k_ placeholders
- Spark :
    - **spark-defaults.conf** :
        - _namenode-g5k_ placeholder
        - `spark.pyspark.python` : path to benchmark virtual environment Python executable
        - hardware
    - **spark-env.sh** :
        - `$SPARK_DIST_CLASSPATH` : variable to have Spark 2.* working with Hadoop.3 (see [here](https://spark.apache.org/docs/latest/hadoop-provided.html))
        - _datadirs-g5k_ placeholder
- Benchmark :
    - **driver/config/spark.yml** :
        - in workload: engine_base : `--master yarn` removed to use spark manager
        - `pdgf_node_parallel` property set to True for parallel data generation
        - `temp_dir` property
    - **data-gen/config/tpcxai-generation.xml** : _namenode-g5k_ placeholders
    - **tools/spark/python.yaml** : virtual environment configuration file
    - **tools/spark/getEnvInfo** : changed a line using yarn to retrieve the nodes count to `uniq /home/agalet/deploy/tpcx-ai/nodes | wc -l`
    - **setenv.sh**

---

# Step by step installation

Here is a step by step explanation to install the experiment environment. It describes the tasks ran by the script.

The first part of the script is the installation of pssh, pscp and prsync. pscp is used by the benchmark, prsync by the installation script and pssh by both of them. A `pssh` command alias is created to avoid using `parallel-ssh`, as well as for `pscp` and `prsync`.

---

## Listing the nodes

The next objective is retrieving the list of the nodes. It relies on several files listing them.

- The `$nodefile` variable points to a file listing all the nodes, master and workers, available. It must be set before the execution.
- The `nodes` file located in the benchmark root folder should be a copy of the $nodefile.
- The `$workersfile` variable points to file listing all the nodes except the master. It does not have to be set before the execution.
- The `workers` file located in Hadoop configuration folder should be a copy of the $workersfile.
- The `workers` and/or `slaves` file located in Spark configuration folder should be copies of the $workersfile.

This step must be conducted before the deployment of Hadoop, Spark, the benchmark, and their configuration in order to have those files spread with the software. It can also be done after using ssh or pssh.

----

## Benchmark deployment

An archive of the benchmark installation is created with the name specified by the `$benchmark` variable.
The archive is recreated at each installation since it contains the list of the nodes.

The benchmark is then
- extracted locally for the master
- copied onto each node
- extracted on each node

Hadoop namenode address must be referenced in the benchmark `tpcx-ai/lib/pdgf/config/tpcxai-generation.xml` file. This is done using this command :

    sed -i s/namenode-g5k/$(uniq $nodefile | head -n 1)/g /tmp/tpcx-ai/lib/pdgf/config/tpcxai-generation.xml

Sed replace all _namenode-g5k_ (a placeholder) occurences by the namenode address, first line of `$nodefile`.
The file must be prepared in advance, my version is available.

---

## Dependencies installation

Java 8 and Python 3.7 must be installed on each node.
They are deployed using source code archives from ~/archives folder.

Python 3.7 is built locally and copied on the nodes.
Java 8 is deployed on the nodes, extracted there and installed.
Both of them must be set as default version.

---

## Benchmark virtual environments

Anaconda is required to install the virtual environments with the script provided with the benchmark.
Anaconda is installed locally and the virtual environment is created on the master.
Then it is deployed in parallel on all the nodes.

---

## Hadoop

The `exec-hadoop-deploy.sh` script is used to deploy Hadoop and its configuration on the nodes.
The original script was provided to me by Herodotos Herodotou.
I have been using only the `distr` and `hadoop3` parameters.

I made some small modifications to match with my installation :
- `$hadoopDeployDir` is set to /tmp/hadoop
- `$hadoopSrcDir` is not used, i am using a prebuilt version
- `$hadoopConfDir` is set to ~/confs/conf-${dmode}-mode-hadoop3, dmode being _distr_
- `$hadoopDistDir` is set to ~/deploy/hadoop/

The same principle of placeholders is used :
- `namenode-g5k` for the unique namenode address
- `datanode-g5k` for the local datanode address

The script is used in the following way :
- `~/exec-hadoop-deploy.sh distr hadoop3 -deploy` : install Hadoop on the nodes from $hadoopSrcDir to $hadoopDeployDir
- `~/exec-hadoop-deploy.sh distr hadoop3 -conf` : deploy the configuration from $hadoopConfDir to $hadoopDeployDir/etc/hadoop
- `~/exec-hadoop-deploy.sh distr hadoop3 -clearfs` : formats the namenode, done just before startup

---

## Spark

The `~/exec-spark-deploy.sh` is similar to the Hadoop script, it is designed to deploy Spark on the nodes.
I have been using only the `distr` and `spark24` parameters.

I made some small modifications to match with my installation :
- `$sparkDeployDir` is set to /tmp/spark
- `$sparkSrcDir` is set to ~/archives/, the location of Spark archive
- `$hadoopConfDir` is set to ~/confs/conf-${dmode}-mode-spark24, dmode being _distr_
- `$sparkPackageName` is set to spark-2.4.8, the name of the Spark archive

The `namenode-g5k` placeholder is used once.

The script is used in the following way :
- `~/exec-spark-deploy.sh distr spark24 -deploy` : install Spark on the nodes with the archive from $sparkSrcDir to $sparkDeployDir
- `~/exec-spark-deploy.sh distr spark24 -conf` : deploy the configuration from $hadoopConfDir to $sparkDeployDir/conf

---

## Disks setup

The disks setup consists in too aspects : making them available and determine their type.
Loops are use to execute this on all the disks of all the nodes.
A set of commands is dedicated to the clearing, formatting, partitioning and mounting of a disk

The `lsblk -dno ROTA /dev/${disk}` command returns 1 for a hard drives and 0 for SSDs.
In the case of a computer with two different storage mediums, this is useful to
- specify disk type for Hadoop directories with \[DISK\] and \[SSD\] prefixs
- define **One_SSD** storage policy for Hadoop

With either only SSDs or only hard drives, this is not useful.

