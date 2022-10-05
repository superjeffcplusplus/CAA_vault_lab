#!/bin/bash

stat conf/vault.hcl > /dev/null >&1
if [[ $? -ne 0 ]]; then
    echo "Required file does not exist..."
    echo "Exiting..."
    exit 1
fi

sudo -u vault vault server -config=conf/vault.hcl