#!/usr/bin/env bash

master_pod=$(kubectl get pod -n "${namespace}" | grep jmeter-master | awk '{print $1}')

kubectl exec "${master_pod}" -c jmmaster -ti  -- /bin/bash \
        "/opt/jmeter/apache-jmeter/bin/stoptest.sh"
