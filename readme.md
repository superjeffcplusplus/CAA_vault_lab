# PKI setup with Hashicorp Vault
This repo is a lab in which we had to configure a PKI with Hashicorp Vault.

## Prerequities
To install Vault, follow this [guide](https://learn.hashicorp.com/tutorials/vault/getting-started-install).
The PKI install also requires `jq` to parse JSON files. Install with `sudo apt install jq`. 

## Starting the server
To start the server, make sure that the current directory is ~/vault.
Then run the script `server_start.sh`

## Setuping PKI
All the setup is made with the script `setup.sh`. Just run it. At the beginning it will check if configurations file (i.e policies) exits.  
Be aware that it will succeed only once. As soon as the vault is initialised, it will throw errors.  
After running the script, you find the root token and the unseal keys in `key_files` folder. Note that it is a bad practice to store this files together and non encrypted. We've done so only for demo purpose.
### Cert files
The cert files generated for intra.heig-vd.ch are in the folder `intra_higvd_cert`. It may include the CA chain, the certificate itself, the certificate of the isuing authority and the private key for intra_higvd_cert. `root_cert` contains the root certificate and `intermadiate_cert` the intermadiate authority certificate signed by root and the coresponding CSR.