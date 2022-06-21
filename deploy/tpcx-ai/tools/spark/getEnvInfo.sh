#!/usr/bin/env bash

#
# Copyright (C) 2021 Transaction Processing Performance Council (TPC) and/or its contributors.
# This file is part of a software package distributed by the TPC
# The contents of this file have been developed by the TPC, and/or have been licensed to the TPC under one or more contributor
# license agreements.
# This file is subject to the terms and conditions outlined in the End-User
# License Agreement (EULA) which can be found in this distribution (EULA.txt) and is available at the following URL:
# http://www.tpc.org/TPC_Documents_Current_Versions/txt/EULA.txt
# Unless required by applicable law or agreed to in writing, this software is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, and the user bears the entire risk as to quality
# and performance as well as the entire cost of service or repair in case of defect. See the EULA for more details.
#


#
# Copyright 2021 Intel Corporation.
# This software and the related documents are Intel copyrighted materials, and your use of them 
# is governed by the express license under which they were provided to you ("License"). Unless the 
# License provides otherwise, you may not use, modify, copy, publish, distribute, disclose or 
# transmit this software or the related documents without Intel's prior written permission.
# 
# This software and the related documents are provided as is, with no express or implied warranties, 
# other than those that are expressly stated in the License.
# 
#


ENV_INFO_DIR_RELATIVE="envInfo-$HOSTNAME"
ENV_INFO_DIR="${TPCx_AI_HOME_DIR}/logs/$ENV_INFO_DIR_RELATIVE"
[ -d "$ENV_INFO_DIR" ] && rm -rf "$ENV_INFO_DIR"
mkdir "$ENV_INFO_DIR"
ENV_INFO_FILE="$ENV_INFO_DIR/envInfo.log"
echo "" > "$ENV_INFO_FILE"
if [ -w "$ENV_INFO_FILE" ]
then
  #echo "Nodes: $(yarn node -list -all | sed -e '1,2d' | wc -l)" >> "$ENV_INFO_FILE" 2>&1
  echo "Nodes: $(uniq /home/agalet/deploy/tpcx-ai/nodes | wc -l)" >> "$ENV_INFO_FILE" 2>&1

  # create ALL_NODES file containing all nodes WORKERS + DRIVER
  TPCx_AI_ALL_NODES_FILE="${TPCx_AI_HOME_DIR}/nodes_all"
  cp "${TPCx_AI_HOME_DIR}/nodes" "${TPCx_AI_ALL_NODES_FILE}"
  hostname >> "${TPCx_AI_ALL_NODES_FILE}"

  # gather env info on all nodes
  PSSH="${TPCxAI_PSSH} -h ${TPCx_AI_ALL_NODES_FILE} -o ${ENV_INFO_DIR}/nodes"
  ${PSSH} "${TPCx_AI_HOME_DIR}/tools/spark/getEnvInfoWorker.sh"
  rm "$TPCx_AI_ALL_NODES_FILE"

  # copy files
  for DIR in /etc/hadoop /etc/hive /etc/spark
  do
    [ -d "$DIR" ] && cp -a "$DIR" "$ENV_INFO_DIR/"
  done

  echo -e "\n##### Python environment #####\n" >> "$ENV_INFO_FILE" 2>&1
  "${TPCx_AI_HOME_DIR}"/lib/python-venv/bin/python --version >> "$ENV_INFO_FILE" 2>&1
  "${TPCx_AI_HOME_DIR}"/lib/python-venv/bin/pip list >> "$ENV_INFO_FILE" 2>&1

  echo -e "\n\n" >> "$ENV_INFO_FILE" 2>&1
  echo -e "\nPython clock Info - Perf_counter \n" >> "$ENV_INFO_FILE" 2>&1
  "${TPCx_AI_HOME_DIR}"/lib/python-venv/bin/python -c "import time; print(time.get_clock_info('perf_counter'))" >> "$ENV_INFO_FILE" 2>&1
  echo -e "\nPython clock Info - time \n" >> "$ENV_INFO_FILE" 2>&1
  "${TPCx_AI_HOME_DIR}"/lib/python-venv/bin/python -c "import time; print(time.get_clock_info('time'))" >> "$ENV_INFO_FILE" 2>&1

  echo -e "\n##### Python DL environment #####\n" >> "$ENV_INFO_FILE" 2>&1
  /usr/envs/adabench_dl/bin/pip list >> "$ENV_INFO_FILE" 2>&1


  cd "${TPCx_AI_HOME_DIR}"/logs || exit 1
  zip -r "$ENV_INFO_DIR_RELATIVE.zip" "$ENV_INFO_DIR_RELATIVE"
else
  echo "environment information could not be written to $ENV_INFO_FILE"
  exit 1
fi

