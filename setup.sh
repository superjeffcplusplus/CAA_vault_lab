#!/bin/bash

# Function to test if passed by args exists
check_install() {
    if [ -z "$1" ]; then
        echo "Error: bad function call." >&2
        echo "Exiting..."
        exit 1
    fi
    if ! [ -x "$(command -v $1)" ]; then
        echo "Error: $1 is not installed." >&2
        if ! [ -z "$2" ]; then
            echo $2
        fi
        echo "Exiting..."
        exit 1
    fi
}

check_ret_status() {
    if [ $? -ne 0 ]; then
        echo "ERROR ---> exiting"
        exit 1
    fi
}

# Checks for required files
check_if_exist() {
    stat $1 > /dev/null >&1
    if [[ $? -ne 0 ]]; then
        echo "Required file does not exist..."
        echo "Exiting..."
        exit 1
    fi
}
check_if_exist policies/admin.hcl
check_if_exist policies/intra-heigvd-cert.hcl

# Check if vault and jq are installed
install_msg=$(cat <<EOF
To install vault, follow this guide :
https://learn.hashicorp.com/tutorials/vault/getting-started-install?in=vault/getting-started
EOF
)
check_install vault "$install_msg"

install_msg=$(cat <<EOF
To install jq, type "sudo apt install jq".
EOF
)
check_install jq "$install_msg"

# Vault server address
export VAULT_ADDR=http://127.0.0.1:8200

vault_status=$(vault status)
retval=$?
# Check if vault is running
if [[ $retval -ne 0 && $retval -ne 2 ]]; then 
    echo "vault seams to not be running."
    echo "Before running this script, please start the vault server in deploy mode."
    echo "Exiting..."
    exit 1
fi

# Check if vault is already initialized
vault_initialized=$(vault status -format=json | jq -r ".initialized")
if [[ $vault_initialized == "true" ]]; then
    echo "Error: vault already initialized." >&2
    echo "Exiting..."
    exit 1
fi

keys_folder=key_files

if [ -d $keys_folder ]; then
    rm -rf $keys_folder
fi
mkdir $keys_folder

init_output=$(vault operator init -key-shares=6 -key-threshold=2)

check_ret_status

# Retrive unseal keys
unseal_keys=$(echo -e "$init_output" | grep "Unseal Key" | cut -d: -f2)

check_ret_status

# Retrive root token
root_token=$(echo -e "$init_output" | grep "Root Token" | cut -d: -f2)

check_ret_status

# Save unseal keys in a file
echo $unseal_keys > $keys_folder/unseal_keys.txt

#save root token in a file
echo $unseal_keys > $keys_folder/root_token.txt

# Unseal the vault
vault operator unseal $(echo $unseal_keys | cut -d\  -f1)
check_ret_status
vault operator unseal $(echo $unseal_keys | cut -d\  -f2)
check_ret_status

# Login with root
echo $root_token | vault login - 


### Users setup ###

admin_policy=admin
intra_policy=intra-heigvd-cert

# Add policies
vault policy write $admin_policy policies/admin.hcl
vault policy write $intra_policy policies/intra-heigvd-cert.hcl

# Create admin token and login with it
echo $(vault token create -format=json -policy="admin" | jq -r ".auth.client_token") | vault login -

# Enable password authentication a create 2 users
vault auth enable userpass
vault write auth/userpass/users/admin \
    password=admin \
    policies=$admin_policy
vault write auth/userpass/users/toto \
    password=titi \
    policies=$intra_policy


### PKI SETUP ###

root_folder=root_cert
root_cert_CN="heig-vd.ch Root"
root_cert_issuer_name=heig-vd-root-2022

inter_folder=intermadiate_cert
inter_cert_CN="heig-vd.ch Intermediate Authority"
inter_cert_issuer_name=heigvd-dot-ch-intermediate

if [ -d $root_folder ]; then
    rm -rf $root_folder
fi
mkdir $root_folder

if [ -d $inter_folder ]; then
    rm -rf $inter_folder
fi
mkdir $inter_folder

# Enable pki engine
vault secrets enable pki

# Define certificate max lifetime
vault secrets tune -max-lease-ttl=87600h pki

# First we create root certificate (self signed)
vault write -field=certificate pki/root/generate/internal \
     common_name="$root_cert_CN" \
     issuer_name=$root_cert_issuer_name \
     ttl=87600h > $root_folder/$root_cert_issuer_name.crt

# Create a role for root CA
vault write pki/roles/2022-servers allow_any_name=true

# Add intermediate CA
vault secrets enable -path=pki_int pki
# Define certificates max lifetime
vault secrets tune -max-lease-ttl=43800h pki_int

# Then we create an intermadiate certificate
vault write -format=json pki_int/intermediate/generate/internal \
     common_name="$inter_cert_CN" \
     issuer_name=$inter_cert_issuer_name \
     | jq -r '.data.csr' > $inter_folder/$inter_cert_issuer_name.csr

# Sign the new certificate with root CA
vault write -format=json pki/root/sign-intermediate \
     issuer_ref=$root_cert_issuer_name \
     csr=@$inter_folder/$inter_cert_issuer_name.csr \
     format=pem_bundle ttl="43800h" \
     | jq -r '.data.certificate' > $inter_folder/$inter_cert_issuer_name.cert.pem

# We can now import the certificate in the vault
vault write pki_int/intermediate/set-signed certificate=@$inter_folder/$inter_cert_issuer_name.cert.pem

# Finally, add a role to permit creation and update of intra.heig-vd.ch certificate
vault write pki_int/roles/intra-dot-heigvd-dot-ch \
     issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
     allowed_domains="intra.heig-vd.ch" \
     allow_subdomains=false \
     allow_bare_domains=true \
     max_ttl="720h"


### Create certificate with user toto ###

# Login
vault login -method=userpass username=toto password=titi

# Operations that should fail ...
echo "These operation should fail >>"

echo "1. -->"
vault policy list
echo "2. -->"
vault write auth/userpass/users/admin2 \
    password=admin2 \
    policies=$admin_policy
echo "2. -->"
vault write pki_int/issue/intra-dot-heigvd-dot-ch \
             common_name="intra2.heig-vd.ch" \
             ttl="24h"
echo "<< These operation should fail"

# Issuing new certificate for intra.heig-vd.ch

intra_cert_folder=intra_heigvd_cert
if [ -d $intra_cert_folder ]; then
    rm -rf $intra_cert_folder
fi
mkdir $intra_cert_folder

echo "This operation should succeed >>"
intra_heigvd_json=$(vault write -format=json pki_int/issue/intra-dot-heigvd-dot-ch \
             common_name=intra.heig-vd.ch \
             ttl="24h")
if [ $? -eq 0 ]; then
    # Saving in seperate files
    ca_chain=$(echo $intra_heigvd_json | jq -r ".data.ca_chain[] | @base64")
    for row in $ca_chain; do
        echo ${row} | base64 --decode >> $intra_cert_folder/ca_chain.pem
    done
    echo $intra_heigvd_json | jq -r ".data.private_key" > $intra_cert_folder/private_key.pem
    echo $intra_heigvd_json | jq -r ".data.issuing_ca" > $intra_cert_folder/issuing_ca.pem
    echo $intra_heigvd_json | jq -r ".data.certificate" > $intra_cert_folder/certificate.pem
    echo 'Success !'
else
    echo "Failure :("
fi
echo "<< This operation should succeed"