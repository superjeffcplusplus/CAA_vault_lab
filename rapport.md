Jean-François Pasche
# CAA 22-23 : Lab #1
Ce rapport contient les réponses aux questions posées dans la consigne du laboratoire.  
Des explications sur les scripts fournis sont disponibles dans le readme.

## 4.1. What is the goal of the unseal process. Why are they more than one unsealing key?
Ce processus permet de reconstituer la clef *root* qui permet de déchiffrer les clefs qui chiffrent les données du *vault*.    
La clef *root* est générée lors de l'initialisation du vault ou lors d'une opération de *rekey*. Elle est divisée en plusieurs fragments grâce à l'algorithme `shamir`. Le nombre de fragments nécessaires à la reconstitution de la clef *root*.
Dans notre cas, on génère 6 fragments et 2 sont nécessaires pour le débloquage. Ces fragments ne sont pas sensés se trouver au même endroits. Il doivent être stockés complètement séparément. Ainsi, si un malandrin venait à récupérer l'un d'eux, il serait incapable d'exécuter le *unseal process*.

## 4.2. What is a security officer. What do you do if one leaves the company?
Un *security officer* est le possesseur d'un fragment de clef. S'il quitte la compagnie, il faudra alors effectuer une opération de *rekey*, qui consiste à regénérer une clef root et sa fragmentation avec `shamir`.

## 6.1. Why is it recommended to store the root certificate private key outside of Vault (we did not do this here)?
Car ce certificat est auto-signé et non révoquable. De ce fait, il doit être particulièrement bien protégé. Toute la sécurité de la PKI repose sur lui. Si un malandrin se la procure, il peut signer tous les certificats qu'il veut. Le seul moyen d'arrêter son action serait alors de retirer manuellement le certificat root partout où il est utilisé.

## 6.2. Where would you typically store the root certificate private key?
La clef privée du certificat peut typiquement être gérée par un HSM, voire plusieurs HSM, ou alors être séparée en plusieurs morceaux stockés séparément dans différents emplacements sûrs, tels des coffres forts.

## 6.3. How would you implement this?
Je me servirait d'un HSM pour gérer la clef. Cette dernière est générée par le device et n'en sort jamais. Ce HSM serait stocké dans un coffre fort. Il n'en serait sorti que dans la nécessité de signer le certificat d'une autorité intermédiaire.

La commande suivante permet de générer une CSR:
```bash
vault write -field=certificate pki/root/generate/exported \
     common_name="heig-vd.ch Root" \
     issuer_name="heig-vd-root-2022" \
     ttl=87600h > heig-vd_root_ca.crt
```
> Par rapport à la commande utilisée dans le lab, `internal` est remplacé par `exported` à la fin du chemin.

Il faudrait ensuite demander au HSM de signer la CSR et importer le résultat dans `vault`.

## 6.4. How are the CRLs managed? How do you revoke a certificate (give the command)?
Il y a la possibilité d'activer une route qui permet de récupérer la liste de révovation. Les utilisateurs de la PKI pourront alors facilement vérifier quels certificats s'y trouvent.  
Pour activer cett route, exécuter la commande :
```bash
vault write pki/config/urls \
     crl_distribution_points="$VAULT_ADDR/v1/pki/crl"
```
Pour révoquer un certificat, exécuter la commande :
```bash
vault write pki_int/revoke serial_number=<serial_number>
```
