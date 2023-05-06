# Proxmox VM Template Creator

This shell script automates the process of creating a new Proxmox VM from a JSON file containing a list of available images. It downloads the selected image, configures the VM, and optionally converts the VM to a template.

## Features

- Downloads a list of available images from a JSON file
- Allows user to select an image
- Downloads the selected image and verifies its checksum
- Configures the VM with user-defined settings, such as VM ID, core count, memory size, disk size, and storage location
- Generates a cloud-init config file with the user-defined username and password
- Automatically installs `qemu-guest-agent` for better guest/host integration
- Optionally converts the VM to a template

## Prerequisites

- Proxmox VE installed and configured
- The `jq`, `wget`, and `qm` commands must be available on the system

## Usage

1. Download the `create-template.sh` script using either `curl` or `wget`.

With `curl`:

```bash
curl -O https://raw.githubusercontent.com/Tomyail/pve-template-creator/main/create-template.sh
```

With `wget`:

```bash
wget https://raw.githubusercontent.com/Tomyail/pve-template-creator/main/create-template.sh
```

2. Make the script executable.

```bash
chmod +x create-template.sh
```

3. Run the script.

```bash
./create-template.sh
```

4. Follow the prompts to enter the required information, such as VM ID, core count, memory size, disk size, storage location, username, and password.

5. The script will download the selected image, configure the VM, and create a cloud-init config file with the user-defined username and password.

6. If desired, you can choose to convert the VM to a template.

## Contributing

If you'd like to contribute to this project, please feel free to submit a pull request or open an issue with your suggestions or bug reports.

## License

This project is licensed under the [MIT License](LICENSE).

