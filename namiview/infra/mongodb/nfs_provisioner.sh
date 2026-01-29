#!/bin/bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update
helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=<server_ip> \
    --set nfs.path=<storage_path> \
    --set storageClass.name=<storage_class_name> \
    --set storageClass.onDelete=delete
