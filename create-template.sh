#!/bin/bash
set -e


# Use an associative array for default values
declare -A defaults=(
  [VM_ID]=1000
  [VM_CORES]=2
  [VM_MEM]=1024
  [VM_DISK]="5G"
  [STORAGE]="pool"
  [VM_NAME]="vm"
)

# Function to prompt for user input with a default value
prompt() {
  local message="$1"
  local default_value="$2"

  read -p "${message} (default is ${default_value}): "
  if [ -z "${REPLY}" ]; then
    echo "${default_value}"
  else
    echo "${REPLY}"
  fi
}

# Check for required dependencies
for cmd in wget jq qm; do
  if ! command -v $cmd >/dev/null; then
    echo "Error: $cmd command not found."
    echo "Please install $cmd and try again."
    exit 1
  fi
done

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


# Use a loop to handle multiple inputs
for key in "${!defaults[@]}"; do
  value=$(prompt "Enter $key" "${defaults[$key]}")
  eval "$key=\$value"
done

# Output VM configuration using a loop
echo "VM configuration is as follows:"
for key in "${!defaults[@]}"; do
  value=$(eval "echo \$$key")
  echo "$key: $value"
done

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

