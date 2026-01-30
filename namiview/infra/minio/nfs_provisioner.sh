helm install nfs-minio nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.1.127 \
    --set nfs.path=/srv/nfs/minio \
    --set storageClass.name=minio-nfs-storage \
    --set storageClass.onDelete=retain