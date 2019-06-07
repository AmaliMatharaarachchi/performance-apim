#!/bin/bash -e
# Copyright (c) 2018, WSO2 Inc. (http://wso2.org) All Rights Reserved.
#
# WSO2 Inc. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# ----------------------------------------------------------------------------
# Run API Manager Performance Tests
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")
# Execute common script
. $script_dir/perf-test-common.sh



function initialize() {
    export jmeter_hosts=(34.83.163.132 35.233.136.188)
    export jmeter_ssh_hosts=(jmeter-server-1.us-west1-a.apim-in-kubernates-environment  jmeter-server-2.us-west1-a.apim-in-kubernates-environment)
    # export backend_ssh_host=netty-backend.us-west1-a.apim-in-kubernates-environment
    export apim_host=apim-gateway
    export apim_port=443

    export numofgw=2
    export numofkm=2

    export gateway=wso2apim-pattern-2-gateway
    export iskm=wso2apim-pattern-2-is-as-km
    # login to gcloud cluster
    gcloud container clusters get-credentials cluster-v5 --zone us-west1-a --project apim-in-kubernates-environment

    echo "moving tokens to $HOME."
    cp apim/target/tokens.csv $HOME/
    if [[ $jmeter_servers -gt 1 ]]; then
        for jmeter_ssh_host in ${jmeter_ssh_hosts[@]}; do
            echo "Copying tokens to $jmeter_ssh_host"
            scp $HOME/tokens.csv $jmeter_ssh_host:
        done
    fi
}
export -f initialize

declare -A test_scenario0=(
    [name]="passthrough"
    [display_name]="Passthrough"
    [description]="A secured API, which directly invokes the back-end service."
    [jmx]="jmeter/apim-test.jmx"
    [protocol]="https"
    [path]="/echo/1.0.0"
    [use_backend]=true
    [skip]=false
)
declare -A test_scenario1=(
    [name]="transformation"
    [display_name]="Transformation"
    [description]="A secured API, which has a mediation extension to modify the message."
    [jmx]="jmeter/apim-test.jmx"
    [protocol]="https"
    [path]="/mediation/1.0.0"
    [use_backend]=true
    [skip]=false
)

function restartApim()
{
    gateway_deployment=${gateway}-deployment
    iskm_deployment=${iskm}-deployment
    echo "restarting deployments"
    kubectl scale deployment $iskm_deployment --replicas=0 -n wso2
    kubectl scale deployment $iskm_deployment --replicas=$numofkm -n wso2
    kubectl rollout status -n wso2 deploy/$iskm_deployment

    kubectl scale deployment $gateway_deployment --replicas=0 -n wso2
    kubectl scale deployment $gateway_deployment --replicas=$numofgw -n wso2
    kubectl rollout status -n wso2 deploy/$gateway_deployment
}

function before_execute_test_scenario() {
    local service_path=${scenario[path]}
    local protocol=${scenario[protocol]}
    jmeter_params+=("host=$apim_host" "port=$apim_port" "path=$service_path")
    jmeter_params+=("payload=$HOME/${msize}B.json" "response_size=${msize}B" "protocol=$protocol"
        tokens="$HOME/tokens.csv")
    echo "Starting APIM service"
    restartApim || {
    echo "error thrown while restarting apim"
    sleep 1m
    kubectl get pods -n wso2
    }
}

function after_execute_test_scenario() {
    kubetransfer $gateway /home/wso2carbon/wso2am-2.6.0/gc.log apim_gc $numofgw || {
    echo "[ERROR] kubetransfer apim_gc log failed"
    }
    kubetransferFolder $gateway /home/wso2carbon/wso2am-2.6.0/repository/logs/ gw $numofgw || {
    echo "[ERROR] kubetransfer gw logs failed"
    }
    kubetransfer $iskm /home/wso2carbon/wso2is-km-5.7.0/gc.log km_gc $numofkm || {
    echo "[ERROR] kubetransfer km_gc log failed"
    }
    kubetransferFolder $iskm /home/wso2carbon/wso2is-km-5.7.0/repository/logs/ km $numofkm || {
    echo "[ERROR] kubetransfer km logs failed"
    }
    kubeLogs $gateway gw wso2carbon $numofgw || {
    echo "[ERROR] kubeLog gw logs failed"
    }
    kubeLogs $iskm km wso2carbon $numofkm || {
    echo "[ERROR] kubeLog km logs failed"
    }
}

test_scenarios
