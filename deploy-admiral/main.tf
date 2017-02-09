###############################################################################
# Copyright 2016 Aurora Solutions
#
#    http://www.aurorasolutions.io
#
# Aurora Solutions is an innovative services and product company at
# the forefront of the software industry, with processes and practices
# involving Domain Driven Design(DDD), Agile methodologies to build
# scalable, secure, reliable and high performance products.
#
# Stakater is an Infrastructure-as-a-Code DevOps solution to automate the
# creation of web infrastructure stack on Amazon. Stakater is a collection
# of Blueprints; where each blueprint is an opinionated, reusable, tested,
# supported, documented, configurable, best-practices definition of a piece
# of infrastructure. Stakater is based on Docker, CoreOS, Terraform, Packer,
# Docker Compose, GoCD, Fleet, ETCD, and much more.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################
## Configures providers
provider "aws" {
  region = "${var.aws_region}"
}

# Remote states
data "terraform_remote_state" "env_state" {
    backend = "s3"
    config {
        bucket = "${var.tf_state_bucket_name}"
        key = "${var.env_state_key}"
        region = "${var.aws_region}"
    }
}

data "terraform_remote_state" "global-admiral" {
    backend = "s3"
    config {
        bucket = "${var.tf_state_bucket_name}"
        key = "${var.global_admiral_state_key}"
        region = "${var.aws_region}"
    }
}

module "solo-instance" {
  source = "git::https://github.com/stakater/blueprint-solo-instance-aws.git//modules"
  name                        = "${var.stack_name}-${var.environment}-admiral"
  vpc_id                      = "${data.terraform_remote_state.env_state.vpc_id}"
  subnet_id                   = "${element(split(",", data.terraform_remote_state.env_state.private_app_subnet_ids), 0)}" # First subnet
  iam_assume_role_policy      = "${file("../policy/assume-role-policy.json")}"
  iam_role_policy             = "${data.template_file.deployer-policy.rendered}"
  ami                         = "${var.ami_id}"
  instance_type               = "${var.instance_type}"
  key_name                    = "${var.stack_name}-${var.environment}-admiral-key"
  associate_public_ip_address = false
  enable_eip                  = false
  user_data                   = "" # No user data as custom AMI will be launched
  root_vol_size               = 30
  root_vol_del_on_term        = true
}

# Create keypair if not exists and upload to s3
# make sure this resource is created before the module the solo-instance module
resource "null_resource" "create-key-pair" {
  provisioner "local-exec" {
      command = "../scripts/create-keypair.sh -k ${var.stack_name}-${var.environment}-admiral-key -r ${var.aws_region} -b ${data.terraform_remote_state.env_state.config-bucket-name}"
  }
}

## Template files
data "template_file" "deployer-policy" {
  template = "${file("../policy/role-policy.json")}"

  vars {
    config_bucket_arn = "${data.terraform_remote_state.env_state.config-bucket-arn}"
    cloudinit_bucket_arn = "${data.terraform_remote_state.env_state.cloudinit-bucket-arn}"
    global_admiral_config_bucket_arn = "${data.terraform_remote_state.global-admiral.config-bucket-arn}"
  }
}

# Security Group rules for applications in admiral
# Allow Outgoing traffic
resource "aws_security_group_rule" "rule-outgoing" {
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  cidr_blocks              = ["0.0.0.0/0"]
  security_group_id        = "${module.solo-instance.security_group_id}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rule-22" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  cidr_blocks              = ["${data.terraform_remote_state.env_state.vpc_cidr}"]
  security_group_id        = "${module.solo-instance.security_group_id}"

  lifecycle {
    create_before_destroy = true
  }
}

# Kibana
resource "aws_security_group_rule" "rule-5601" {
  type                     = "ingress"
  from_port                = 5601
  to_port                  = 5601
  protocol                 = "tcp"
  cidr_blocks              = ["0.0.0.0/0"]
  security_group_id        = "${module.solo-instance.security_group_id}"

  lifecycle {
    create_before_destroy = true
  }
}