variable "aws_profile" {
  type        = string
  description = "AWS CLI profile to use"
  default     = "TemporalSelfHostingAdmin"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-2"
}

variable "name_prefix" {
  type        = string
  description = "Name prefix for all resources"
  default     = "payton-temporal"
}

variable "vpc_cidr" {
  type    = string
  default = "10.50.0.0/16"
}

variable "az_count" {
  type    = number
  default = 3
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "node_instance_type" {
  type        = string
  default     = "c6i.large"
  description = "EKS managed node group instance type"
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "db_name" {
  type    = string
  default = "temporal"
}

variable "visibility_db_name" {
  type        = string
  default     = "temporal_visibility"
  description = "Temporal visibility SQL database name"
}

variable "db_username" {
  type    = string
  default = "temporal_admin"
}

variable "db_instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "db_allocated_storage" {
  type    = number
  default = 100
}

variable "temporal_namespace" {
  type    = string
  default = "temporal"
}

variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace to install Argo CD into"
}

variable "argocd_chart_version" {
  type        = string
  default     = "7.7.16"
  description = "Argo CD Helm chart version"
}
