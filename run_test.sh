#!/usr/bin/env bash

#=== FUNCTION ================================================================
#        NAME: logit
# DESCRIPTION: Log into file and screen.
# PARAMETER - 1 : Level (ERROR, INFO)
#           - 2 : Message
#
#===============================================================================
logit()
{
    case "$1" in
        "INFO")
            echo -e " [\e[94m $1 \e[0m] [ $(date '+%d-%m-%y %H:%M:%S') ] $2 \e[0m" ;;
        "WARN")
            echo -e " [\e[93m $1 \e[0m] [ $(date '+%d-%m-%y %H:%M:%S') ]  \e[93m $2 \e[0m " && sleep 2 ;;
        "ERROR")
            echo -e " [\e[91m $1 \e[0m] [ $(date '+%d-%m-%y %H:%M:%S') ]  $2 \e[0m " ;;
    esac
}

#=== FUNCTION ================================================================
#        NAME: usage
# DESCRIPTION: Helper of the function
# PARAMETER - None
#
#===============================================================================
usage()
{
  logit "INFO" "-j <filename.jmx>"
  logit "INFO" "-n <namespace>"
  logit "INFO" "-c flag to split and copy csv if you use csv in your test"
  logit "INFO" "-m flag to copy fragmented jmx present in scenario/project/module if you use \
        include controller and external test fragment"
  logit "INFO" "-i <injectorNumber> to scale slaves pods to the desired number of JMeter injectors"
  logit "INFO" "-r flag to enable report generation at the end of the test"
  exit 1
}

### Parsing the arguments ###
while getopts 'i:mj:hcrn:' option;
    do
      case $option in
        n	)	namespace=${OPTARG}   ;;
        c   )   csv=1 ;;
        m   )   module=1 ;;
        r   )   enable_report=1 ;;
        j   )   jmx=${OPTARG} ;;
        i   )   nb_injectors=${OPTARG} ;;
        h   )   usage ;;
        ?   )   usage ;;
      esac
done

if [ "$#" -eq 0 ]
  then
    usage
fi

### CHECKING VARS ###
if [ -z "${namespace}" ]; then
    logit "ERROR" "Namespace not provided!"
    usage
    namespace=$(awk '{print $NF}' "${PWD}/namespace_export")
fi

if [ -z "${jmx}" ]; then
    #read -rp 'Enter the name of the jmx file ' jmx
    logit "ERROR" "jmx jmeter project not provided!"
    usage
fi

jmx_dir="${jmx%%.*}"

if [ ! -f "scenario/${jmx_dir}/${jmx}" ]; then
    logit "ERROR" "Test script file was not found in scenario/${jmx_dir}/${jmx}"
    usage
fi

# Recreating each pods
logit "INFO" "Recreating pod set"
kubectl -n "${namespace}" delete -f resources/jmeter/jmeter-master.yaml \
        -f resources/jmeter/jmeter-slave.yaml 2> /dev/null
# TODO write to author lacking -R
kubectl -n "${namespace}" apply -R -f resources/jmeter
kubectl -n "${namespace}" patch job jmeter-slaves -p '{"spec":{"parallelism":0}}'

logit "INFO" "Waiting for all slaves pods to be terminated before recreating the pod set"
while [[ $(kubectl -n ${namespace} get pods -l jmeter_mode=slave \
      -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "" ]];
do
  echo "$(kubectl -n ${namespace} get pods -l jmeter_mode=slave )" && sleep 1;
done

slaves_number=${nb_injectors}

# Starting jmeter slave pod
if [ -z "${nb_injectors}" ]; then
    logit "WARNING" "Keeping number of injector to 1"
    slaves_number=1
    kubectl -n "${namespace}" patch job jmeter-slaves -p '{"spec":{"parallelism":1}}'
else
    logit "INFO" "Scaling the number of pods to ${nb_injectors}. "
    kubectl -n "${namespace}" patch job jmeter-slaves -p \
            '{"spec":{"parallelism":'${nb_injectors}'}}'
    logit "INFO" "Waiting for pods to be ready"

    for ((i=1; i<=slaves_number; i++))
    do
        validation_string=${validation_string}"True"
    done

    while [[ $(kubectl -n ${namespace} get pods -l jmeter_mode=slave \
          -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' | sed 's/ //g') \
          != "${validation_string}" ]];
    do
      echo "$(kubectl -n ${namespace} get pods -l jmeter_mode=slave )" && sleep 1;
    done

    logit "INFO" "Finish scaling the number of pods."
fi

logit "INFO" "Waiting for master pod to be available"
while [[ $(kubectl -n ${namespace} get pods -l jmeter_mode=master \
      -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') \
      != "True" ]];
do
  echo "$(kubectl -n ${namespace} get pods -l jmeter_mode=master )" && sleep 1;
done

# Get Master pod details
master_pod=$(kubectl get pod -n "${namespace}" | grep jmeter-master | awk '{print $1}')

# Get Slave pod details
slave_pods=($(kubectl get pods -n "${namespace}" | grep jmeter-slave | grep Running | awk '{print $1}'))
slave_num=${#slave_pods[@]}
slave_digit="${#slave_num}"

# jmeter directory in pods
jmeter_directory="/opt/jmeter/apache-jmeter/bin"

# Copying module and config to pods
if [ -n "${module}" ]; then
    logit "INFO" "Using modules (test fragments), uploading them in the pods"
    module_dir="scenario/module"

    logit "INFO" "Number of slaves is ${slave_num}"
    logit "INFO" "Processing directory.. ${module_dir}"

    for modulePath in $(ls ${module_dir}/*.jmx)
    do
        module=$(basename "${modulePath}")

        for ((i=0; i<slaves_number; i++))
        do
            printf "Copy %s to %s on %s\n" "${module}" "${jmeter_directory}/${module}" \
                    "${slave_pods[$i]}"
            kubectl cp "${modulePath}" \
                    "${slave_pods[$i]}:${jmeter_directory}/${module}" -c jmslave
        done
        kubectl cp "${modulePath}" "${master_pod}:${jmeter_directory}/${module}" -c jmmaster 
    done

    logit "INFO" "Finish copying modules in slave pod"
fi

logit "INFO" "Copying ${jmx} to slaves pods"
logit "INFO" "Number of slaves is ${slave_num}"

for ((i=0; i<slaves_number; i++))
do
    currentPod=${slave_pods[$i]}
    destination="${currentPod}"
    logit "INFO" "${source}"
    logit "INFO" "Copying scenario/${jmx_dir}/${jmx} to ${currentPod}"
    kubectl cp "scenario/${jmx_dir}/${jmx}" "${destination}:/opt/jmeter/apache-jmeter/bin/" \
            -c jmslave
done
logit "INFO" "Finish copying scenario in slaves pod"

logit "INFO" "Copying scenario/${jmx_dir}/${jmx} into ${master_pod}"
kubectl cp "scenario/${jmx_dir}/${jmx}" "${master_pod}:/opt/jmeter/apache-jmeter/bin/" \
        -c jmmaster

logit "INFO" "Installing needed plugins on slave pods"

# Creating injector script
{
    echo "cd ${jmeter_directory}"
    echo "sh PluginsManagerCMD.sh install-for-jmx ${jmx} > plugins-install.out 2> plugins-install.err"
    echo "jmeter-server -Dserver.rmi.localport=50000 -Dserver_port=1099 -Jserver.rmi.ssl.disable=true >> jmeter-injector.out 2>> jmeter-injector.err &"
    echo "trap 'kill -10 1' EXIT INT TERM"
    echo "java -jar /opt/jmeter/apache-jmeter/lib/jolokia-java-agent.jar start JMeter >> jmeter-injector.out 2>> jmeter-injector.err"
    echo "wait"
} > "scenario/${jmx_dir}/jmeter_injector_start.sh"

# Copying dataset on slave pods
if [ -n "${csv}" ]; then
    logit "INFO" "Splitting and uploading csv to pods"
    dataset_dir="scenario/dataset"

    for csvfilefull in $(ls ${dataset_dir}/*.csv)
        do
            logit "INFO" "csvfilefull=${csvfilefull}"
            csvfile="${csvfilefull##*/}"

            logit "INFO" "Processing file.. $csvfile"
            lines_total=$(cat "${csvfilefull}" | wc -l)

            logit "INFO" "split --suffix-length=\"${slave_digit}\" -d -l \$((lines_total/slave_num)) \"${csvfilefull}\" \"${csvfilefull}/\""
            split --suffix-length="${slave_digit}" -d -l $((lines_total/slave_num)) \
                    "${csvfilefull}" "${csvfilefull}"

            for ((i=0; i<slaves_number; i++))
            do
                if [ ${slave_digit} -eq 2 ] && [ ${i} -lt 10 ]; then
                    j=0${i}
                elif [ ${slave_digit} -eq 2 ] && [ ${i} -ge 10 ]; then
                    j=${i}
                elif [ ${slave_digit} -eq 3 ] && [ ${i} -lt 10 ]; then
                    j=00${i}
                elif [ ${slave_digit} -eq 3 ] && [ ${i} -ge 10 ]; then
                    j=0${i}
                elif [ ${slave_digit} -eq 3 ] && [ ${i} -ge 100 ]; then
                    j=${i}
                else
                    j=${i}
                fi

                printf "Copy %s to %s on %s\n" "${csvfilefull}${j}" "${csvfile}" \
                        "${slave_pods[$i]}"
                kubectl cp "${csvfilefull}${j}" "${slave_pods[$i]}:${jmeter_directory}/${csvfile}" \
                        -c jmslave
            done
    done
fi

for ((i=0; i<slaves_number; i++))
do
        logit "INFO" "Starting jmeter server on ${slave_pods[$i]} in parallel"
        kubectl cp "scenario/${jmx_dir}/jmeter_injector_start.sh" \
                "${slave_pods[$i]}:/opt/jmeter/jmeter_injector_start" -c jmslave
        kubectl exec "${slave_pods[$i]}" -c jmslave -i -- /bin/bash "/opt/jmeter/jmeter_injector_start" &
done

slave_list=$(kubectl -n ${namespace} describe endpoints jmeter-slaves-svc \
            | grep ' Addresses' | awk -F" " '{print $2}')
slave_array=($(echo ${slave_list} | sed 's/,/ /g'))

logit "INFO" "JMeter slave array: ${slave_array}"

# Starting Jmeter load test
source "scenario/${jmx_dir}/.env"

param_host="-G HOST=${HOST} -G PORT=${PORT} -G PROTOCOL=${PROTOCOL}"
param_user="-G VU=${VU} -G DURATION=${DURATION} -G RAMP_UP=${RAMP_UP}"

if [ -n "${enable_report}" ]; then
    report_command_line="--reportatendofloadtests --reportoutputfolder /report/report-${jmx}-$(date +"%F_%H%M%S")"
fi

logit "INFO" "Report CMD: ${report_command_line}"

{
    echo "echo \"Installing needed plugins for master\""
    echo "cd /opt/jmeter/apache-jmeter/bin"
    echo "sh PluginsManagerCMD.sh install-for-jmx ${jmx}"
    echo "jmeter ${param_host} ${param_user} ${report_command_line} --logfile /report/${jmx}_$(date +"%F_%H%M%S").jtl --nongui --testfile ${jmx} -Dserver.rmi.ssl.disable=true --remoteexit --remotestart ${slave_list} >> jmeter-master.out 2>> jmeter-master.err &"
    echo "trap 'kill -10 1' EXIT INT TERM"
    echo "java -jar /opt/jmeter/apache-jmeter/lib/jolokia-java-agent.jar start JMeter >> jmeter-master.out 2>> jmeter-master.err"
    echo "wait"
} > "scenario/${jmx_dir}/load_test.sh"

logit "INFO" "Copying scenario/${jmx_dir}/load_test.sh into  ${master_pod}:/opt/jmeter/load_test"
kubectl cp "scenario/${jmx_dir}/load_test.sh" "${master_pod}:/opt/jmeter/load_test" -c jmmaster

logit "INFO" "Starting the performance test"
kubectl exec "${master_pod}" -c jmmaster -i -- /bin/bash "/opt/jmeter/load_test"
