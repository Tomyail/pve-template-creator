#!/bin/bash
set -e

# 检查 jq 命令是否已安装，如果没有则安装
if ! command -v jq >/dev/null; then
  echo "jq command not found, installing..."
  apt-get update && apt-get install -y jq
fi

# 获取远程 JSON 文件的 URL
JSON_URL="https://raw.githubusercontent.com/Tomyail/pve-template-creator/main/image-list.json"

# 下载远程 JSON 文件
wget -q "$JSON_URL" -O image-list.json --show-progress

# 读取 JSON 文件并提示用户选择
echo "Please select an image:"
jq -r '.[] | "\(.name) (\(.path))"' image-list.json | nl
read -p "Enter the index of the image: " INDEX

# 根据用户选择获取对应的 name 和 image_path
NAME=$(jq -r ".[$INDEX-1].name" image-list.json)
IMAGE_PATH=$(jq -r ".[$INDEX-1].path" image-list.json)
SHA256SUMS_URL=$(jq -r ".[$INDEX-1].checksum" image-list.json)
CHECKSUM_TYPE=$(jq -r ".[$INDEX-1].checksum_type" image-list.json)

# 创建目标文件夹
mkdir -p "/tmp/$NAME"

local_checksum_file="/tmp/$NAME/$(basename $SHA256SUMS_URL)"
wget -N -q $SHA256SUMS_URL -O $local_checksum_file --show-progress

# 下载目标文件
LOCAL_PATH="/tmp/$NAME/$(basename $IMAGE_PATH)"
if [ -f "$LOCAL_PATH" ]; then
  # 如果本地文件已存在，检查 checksum 是否一致，不一致重新下载

  #echo "grep '$(basename $IMAGE_PATH)' $local_checksum_file"
  CHECKSUM=$(grep "$(basename $IMAGE_PATH)" $local_checksum_file | awk '{ print $1}')
  #echo "$CHECKSUM"
  img_checksum=$($CHECKSUM_TYPE "$LOCAL_PATH" | awk '{ print $1 }')
  #echo "$img_checksum"
  if [[ "$img_checksum" != "$CHECKSUM" ]]; then
    echo "Checksum mismatch, redownloading $IMAGE_PATH"

    echo "wget -q '$IMAGE_PATH' -O '$LOCAL_PATH'"
    wget -q "$IMAGE_PATH" -O "$LOCAL_PATH"  --show-progress
  fi
else
  # 如果本地文件不存在，直接下载
  wget -q "$IMAGE_PATH" -O "$LOCAL_PATH" --show-progress
fi

echo "Download complete: $LOCAL_PATH"


# 如果用户未输入任何值，则将VM ID设置为默认值1000
read -p "请输入VM ID（默认为1000）：" VM_ID_INPUT
if [ -z "$VM_ID_INPUT" ]; then
    VM_ID=1000
else
    VM_ID=$VM_ID_INPUT
fi

# 请求VM的核心数量
read -p "请输入VM核心数量（默认为2）：" VM_CORES_INPUT
if [ -z "$VM_CORES_INPUT" ]; then
    VM_CORES=2
else
    VM_CORES=$VM_CORES_INPUT
fi

# 请求VM的内存大小
read -p "请输入VM内存大小（单位MB，默认为1024）：" VM_MEM_INPUT
if [ -z "$VM_MEM_INPUT" ]; then
    VM_MEM=1024
else
    VM_MEM=$VM_MEM_INPUT
fi

# 请求VM的磁盘大小
read -p "请输入VM磁盘大小（默认为5G）：" VM_DISK_INPUT
if [ -z "$VM_DISK_INPUT" ]; then
    VM_DISK=5G
else
    VM_DISK=$VM_DISK_INPUT
fi

# 请求VM的存储位置
read -p "请输入VM存储位置（默认为pool）：" STORAGE_INPUT
if [ -z "$STORAGE_INPUT" ]; then
    STORAGE=pool
else
    STORAGE=$STORAGE_INPUT
fi


read -p "请输入VM存储位置（默认为vm）：" VM_NAME_INPUT
if [ -z "$VM_NAME_INPUT" ]; then
    VM_NAME=vm
else
    VM_NAME=$VM_NAME_INPUT
fi

# 输出VM的配置
echo "VM配置信息如下："
echo "ID: $VM_ID"
echo "核心数量：$VM_CORES"
echo "内存大小：$VM_MEM"
echo "磁盘大小：$VM_DISK"
echo "存储位置：$STORAGE"

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
# package_upgrade: true
package_reboot_if_required: true
locale: en_GB.UTF-8
packages:
  - qemu-guest-agent
EOF
qm set $VM_ID --cicustom "user=local:snippets/user.yaml"

# 提示用户是否将虚拟机转换为模板
read -p "Do you want to convert this VM to template? [y/n] " CONVERT_TO_TEMPLATE

if [ "$CONVERT_TO_TEMPLATE" == "y" ] || [ "$CONVERT_TO_TEMPLATE" == "Y" ]; then
  # 将虚拟机转换为模板
  qm template "$VM_ID"
  echo "VM $NAME has been converted to template."
fi
