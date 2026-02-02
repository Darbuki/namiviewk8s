helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vso hashicorp/vault-secrets-operator \
    --namespace vault \
    --create-namespace