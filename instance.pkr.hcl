# Build a base image (weekly or so) to get latest patches

variable "region" {  type = string }

data "amazon-ami" "jammy" {
  filters = {
    virtualization-type = "hvm"
    name                = "ubuntu/images/*ubuntu-jammy-22.04-arm64-server-*"
    root-device-type    = "ebs"
  }

  # Canonical
  owners      = ["099720109477"]

  most_recent = true

  region = "${var.region}"
}

source "amazon-ebs" "jammy" {
  ami_name      = "mattermost {{timestamp}}"
  instance_type = "t4g.nano"
  region        = "${var.region}"
  source_ami    = data.amazon-ami.jammy.id
  ssh_username  = "ubuntu"
  communicator  = "ssh"
  temporary_key_pair_type = "ed25519"
}

build {
  sources = ["source.amazon-ebs.jammy"]

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "setup-instance.sh"
    ]
  }

  post-processor "manifest" {
    output = "packer-manifest.json"
  }
}
