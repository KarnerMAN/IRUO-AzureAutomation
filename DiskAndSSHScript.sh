#!/bin/bash

STORAGE_ACCOUNT_NAME="$1"
CONTAINER_NAME="$2"
STORAGE_ACCOUNT_KEY="$3"
ADMIN_USERNAME="$4"

LOGFILE="/home/${ADMIN_USERNAME}/DiskSSHScript.log"

echo "Starting disk setup" | tee -a $LOGFILE

# /dev/sdc
sudo parted /dev/sdc --script mklabel gpt mkpart xfspart xfs 0% 100% 2>&1 | tee -a $LOGFILE
sudo partprobe /dev/sdc 2>&1 | tee -a $LOGFILE
sleep 2
sudo mkfs.xfs /dev/sdc1 2>&1 | tee -a $LOGFILE
sudo mkdir -p /mnt/sdc 2>&1 | tee -a $LOGFILE
sudo mount /dev/sdc1 /mnt/sdc 2>&1 | tee -a $LOGFILE
echo "/dev/sdc1 /mnt/sdc xfs defaults,nofail 1 2" | sudo tee -a /etc/fstab 2>&1 | tee -a $LOGFILE

# /dev/sdd
sudo parted /dev/sdd --script mklabel gpt mkpart xfspart xfs 0% 100% 2>&1 | tee -a $LOGFILE
sudo partprobe /dev/sdd 2>&1 | tee -a $LOGFILE
sleep 2
sudo mkfs.xfs /dev/sdd1 2>&1 | tee -a $LOGFILE
sudo mkdir -p /mnt/sdd 2>&1 | tee -a $LOGFILE
sudo mount /dev/sdd1 /mnt/sdd 2>&1 | tee -a $LOGFILE
echo "/dev/sdd1 /mnt/sdd xfs defaults,nofail 1 2" | sudo tee -a /etc/fstab 2>&1 | tee -a $LOGFILE

echo "Disk setup done" | tee -a $LOGFILE

# Install BlobFuse2 and dependencies
echo "Installing BlobFuse2" | tee -a $LOGFILE
sudo wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb 2>&1 | tee -a $LOGFILE
sudo dpkg -i packages-microsoft-prod.deb 2>&1 | tee -a $LOGFILE
sudo apt-get update 2>&1 | tee -a $LOGFILE
sudo apt-get install -y libfuse3-dev fuse3 blobfuse2 2>&1 | tee -a $LOGFILE

# Config BlobFuse2
echo "Configuring BlobFuse2" | tee -a $LOGFILE
cat <<EOF > /home/${ADMIN_USERNAME}/fuse_connection.yaml
version: 2
accounts:
  - accountName: $STORAGE_ACCOUNT_NAME
    accountKey: $STORAGE_ACCOUNT_KEY
    containerName: $CONTAINER_NAME
    file_cache:
      tmp_path: /mnt/blobfusetmp
EOF

sudo mkdir -p /mnt/blobcontainer 2>&1 | tee -a $LOGFILE
sudo mkdir -p /mnt/blobfusetmp 2>&1 | tee -a $LOGFILE

# Mount the blob container
echo "Mounting blob container" | tee -a $LOGFILE
sudo blobfuse2 mount /mnt/blobcontainer --config-file=/home/${ADMIN_USERNAME}/fuse_connection.yaml 2>&1 | tee -a $LOGFILE

echo "Disks and blob storage mounted." | tee -a $LOGFILE

# Generate SSH key pair for the admin user if not present
echo "Checking/generating SSH key" | tee -a $LOGFILE
if [ ! -f /home/${ADMIN_USERNAME}/.ssh/id_rsa ]; then
  sudo -u ${ADMIN_USERNAME} ssh-keygen -t rsa -b 4096 -f /home/${ADMIN_USERNAME}/.ssh/id_rsa -N "" 2>&1 | tee -a $LOGFILE
fi

ls -l /home/${ADMIN_USERNAME}/.ssh/ 2>&1 | tee -a $LOGFILE
cat /home/${ADMIN_USERNAME}/.ssh/id_rsa.pub 2>&1 | tee -a $LOGFILE

echo "Script completed" | tee -a $LOGFILE
