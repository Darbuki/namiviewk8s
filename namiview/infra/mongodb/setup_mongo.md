to set up this mongo you need helm installed on your system
1. make sure you created a namespace: namiview-infra
2. run nfs_provisioner.sh
3. apply mongo_hl_svc.yaml
4. apply mongo_sts.yaml
5. run setup_mongo_rs.sh