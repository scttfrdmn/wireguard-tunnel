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

variable "use_spot" {
  type        = bool
  default     = true
  description = <<-EOT
    Request Spot instances (KICKOFF prefers Spot to cut the ~hundreds-of-USD/hour cost).
    Set false for On-Demand if Spot capacity for 2x i8ge.48xlarge in a cluster placement
    group is unavailable, or if an interruption mid-matrix would be unacceptable. A Spot
    interruption terminates the node (one-time request); just re-apply to retry.
  EOT
}

variable "max_spot_price" {
  type        = string
  default     = ""
  description = <<-EOT
    Max Spot price per instance-hour (USD), e.g. "20.00". Empty = no cap, i.e. AWS bills the
    floating Spot rate but never above the On-Demand price (the recommended default — setting
    a low cap just causes launch failures / interruptions). Only used when use_spot = true.
  EOT
}

variable "root_volume_size" {
  type        = number
  default     = 100
  description = "Root gp3 EBS volume size in GiB per node (instance-store NVMe is the scratch target, not this)."
}
