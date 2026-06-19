variable "region" {
  type    = string
  default = "us-east-1" # i8ge currently in us-east-1 / us-west-2
}

variable "az" {
  type    = string
  default = "us-east-1a"
}

variable "instance_type" {
  type    = string
  default = "i8ge.48xlarge" # 192 vCPU Graviton4, 180 Gbps VPC, ENA Express + EFA
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name for SSH"
}

variable "operator_cidr" {
  type        = string
  description = "Your IP in CIDR form, e.g. 1.2.3.4/32, for SSH access"
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "Override AMI (otherwise latest Ubuntu 24.04 arm64)"
}
