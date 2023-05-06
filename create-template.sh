#!/bin/bash
set -e

# Default values
DEFAULT_VM_ID=1000
DEFAULT_VM_CORES=2
DEFAULT_VM_MEM=1024
DEFAULT_VM_DISK="5G"
DEFAULT_STORAGE="pool"
DEFAULT_VM_NAME="vm"

# Check if jq command is installed, install if not
if ! command -v jq >/dev/null; then
  echo "jq command not found, installing..."
  apt-get update && apt-get install -y jq
fi

# Remote JSON file URL
JSON_URL="https://raw.githubusercontent.com/Tomyail/pve-template-creator/main/image-list.json"

# Download remote JSON file
wget -q "$JSON_URL" -O image-list.json --show-progress

# Read JSON file and prompt user to choose
echo "Please select an image:"
jq -r '.[] | "\(.name) (\(.path))"' image-list.json | nl
read -p "Enter the index of the image: " INDEX

# Get corresponding name and image_path based on user's choice
NAME=$(jq -r ".[$INDEX-1].name" image-list.json)
IMAGE_PATH=$(jq -r ".[$INDEX-1].path" image-list.json)
SHA256SUMS_URL=$(jq -r ".[$INDEX-1].checksum" image-list.json)
CHECKSUM_TYPE=$(jq -r ".[$INDEX-1].checksum_type" image-list.json)

# Create destination folder
mkdir -p "/tmp/$NAME"

local_checksum_file="/tmp/$NAME/$(basename $SHA256SUMS_URL)"
wget -N -q $SHA256SUMS_URL -O $local_checksum_file --show-progress

# Download target file
LOCAL_PATH="/tmp/$NAME/$(basename $IMAGE_PATH)"
if [ -f "$LOCAL_PATH" ]; then
  # If local file exists, check checksum, redownload if not matching
  CHECKSUM=$(grep "$(basename $IMAGE_PATH)" $local_checksum_file | awk '{ print $1}')
  img_checksum=$($CHECKSUM_TYPE "$LOCAL_PATH" | awk '{ print $1 }')
  if [[ "$img_checksum" != "$CHECKSUM" ]]; then
    echo "Checksum mismatch, redownloading $IMAGE_PATH"
    wget -q "$IMAGE_PATH" -O "$LOCAL_PATH"  --show-progress
  fi
else
  # If local file doesn't exist, download
  wget -q "$IMAGE_PATH" -O "$LOCAL_PATH" --show-progress
fi

echo "Download complete: $LOCAL_PATH"

# Prompt for VM ID, use default value if no input
read -p "Enter VM ID (default is ${DEFAULT_VM_ID}): " VM_ID_INPUT
if [ -z "$VM_ID_INPUT" ]; then
    VM_ID=$DEFAULT_VM_ID
else
    VM_ID=$VM_ID_INPUT
fi

# Prompt for VM core count, use default value if no input
read -p "Enter VM core count (default is ${DEFAULT_VM_CORES}): " VM_CORES_INPUT
if [ -z "$VM_CORES_INPUT" ]; then
    VM_CORES=$DEFAULT_VM_CORES
else
    VM_CORES=$VM_CORES_INPUT
fi

# Prompt for VM memory size, use default value if no input
read -p "Enter VM memory size in MB (default is ${DEFAULT_VM_MEM}): " VM_MEM_INPUT
if [ -z "$VM_MEM_INPUT" ]; then
    VM_MEM=$DEFAULT_VM_MEM
else
    VM_MEM=$VM_MEM_INPUT
fi


# Prompt for VM disk size, use default value if no input
read -p "Enter VM disk size (default is ${DEFAULT_VM_DISK}): " VM_DISK_INPUT
if [ -z "$VM_DISK_INPUT" ]; then
    VM_DISK=$DEFAULT_VM_DISK
else
    VM_DISK=$VM_DISK_INPUT
fi

# Prompt for VM storage location, use default value if no input
read -p "Enter VM storage location (default is ${DEFAULT_STORAGE}): " STORAGE_INPUT
if [ -z "$STORAGE_INPUT" ]; then
    STORAGE=$DEFAULT_STORAGE
else
    STORAGE=$STORAGE_INPUT
fi

# Prompt for VM name, use default value if no input
read -p "Enter VM name (default is ${DEFAULT_VM_NAME}): " VM_NAME_INPUT
if [ -z "$VM_NAME_INPUT" ]; then
    VM_NAME=$DEFAULT_VM_NAME
else
    VM_NAME=$VM_NAME_INPUT
fi

# Output VM configuration
echo "VM configuration is as follows:"
echo "ID: $VM_ID"
echo "Core count: $VM_CORES"
echo "Memory size: $VM_MEM"
echo "Disk size: $VM_DISK"
echo "Storage location: $STORAGE"

qm create $VM_ID --cores $VM_CORES --memory $VM_MEM --name $VM_NAME --net0 virtio,bridge=vmbr0
qm importdisk $VM_ID $LOCAL_PATH $STORAGE
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:$VM_ID/vm-$VM_ID-disk-0.raw
qm set $VM_ID --ide2 $STORAGE:cloudinit
qm resize $VM_ID scsi0 $VM_DISK
qm set $VM_ID --boot c --bootdisk scsi0
qm set $VM_ID --serial0 socket --vga serial0
qm set $VM_ID --ipconfig0 ip=dhcp
qm set $VM_ID -agent 1

CLOUD_INIT_CONFIG="/var/lib/vz/snippets/user.yaml"

# Ask the user for their desired username and password
read -p "Enter your desired username: " USER_NAME
read -sp "Enter your desired password: " USER_PASSWORD
echo

# Generate the hashed password using mkpasswd
HASHED_PASSWORD=$(mkpasswd -m sha-512 $USER_PASSWORD)

# Create the cloud-init config file if it doesn't exist
cat << EOF > $CLOUD_INIT_CONFIG
#cloud-config
users:
  - name: $USER_NAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    lock_passwd: false
    passwd: $HASHED_PASSWORD
ssh_pwauth: true
package_upgrade: true
package_reboot_if_required: true
locale: en_GB.UTF-8
packages:
  - qemu-guest-agent
EOF
qm set $VM_ID --cicustom "user=local:snippets/user.yaml"

# Prompt user whether to convert the VM to a template
read -p "Do you want to convert this VM to a template? [y/n] " CONVERT_TO_TEMPLATE

if [ "$CONVERT_TO_TEMPLATE" == "y" ] || [ "$CONVERT_TO_TEMPLATE" == "Y" ]; then
  # Convert the VM to a template
  qm template "$VM_ID"
  echo "VM $NAME has been converted to a template."
fi

