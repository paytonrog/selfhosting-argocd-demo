provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnet_cidrs = [
    for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)
  ]

  public_subnet_cidrs = [
    for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)
  ]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnet_cidrs
  public_subnets  = local.public_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Project = var.name_prefix
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.20.0"

  cluster_name    = "${var.name_prefix}-eks"
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    primary = {
      name           = "${var.name_prefix}-ng"
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      ami_type      = "AL2_x86_64"
      capacity_type = "ON_DEMAND"
    }
  }

  tags = {
    Project = var.name_prefix
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "RDS security group"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.name_prefix}-rds-sg"
    Project = var.name_prefix
  }
}

resource "aws_security_group" "rds_proxy" {
  name        = "${var.name_prefix}-rds-proxy-sg"
  description = "RDS Proxy security group"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.name_prefix}-rds-proxy-sg"
    Project = var.name_prefix
  }
}

resource "aws_security_group_rule" "rds_from_proxy" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.rds_proxy.id
}

resource "aws_security_group_rule" "proxy_from_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_proxy.id
  source_security_group_id = module.eks.node_security_group_id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name    = "${var.name_prefix}-db-subnets"
    Project = var.name_prefix
  }
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name = "${var.name_prefix}/rds/master"

  tags = {
    Project = var.name_prefix
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}

resource "aws_db_instance" "temporal" {
  identifier                 = "${replace(var.name_prefix, "_", "-")}-pg"
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.db_name
  username                   = var.db_username
  password                   = random_password.db.result
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  multi_az                   = true
  backup_retention_period    = 7
  auto_minor_version_upgrade = true
  publicly_accessible        = false
  skip_final_snapshot        = true
  deletion_protection        = false

  tags = {
    Name    = "${var.name_prefix}-pg"
    Project = var.name_prefix
  }
}

resource "aws_iam_role" "rds_proxy" {
  name = "${var.name_prefix}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "rds.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.name_prefix
  }
}

resource "aws_iam_role_policy" "rds_proxy" {
  name = "${var.name_prefix}-rds-proxy-policy"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db.arn
      }
    ]
  })
}

resource "aws_db_proxy" "temporal" {
  name                   = "${replace(var.name_prefix, "_", "-")}-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db.arn
    iam_auth    = "DISABLED"
  }

  tags = {
    Project = var.name_prefix
  }

}

resource "aws_db_proxy_default_target_group" "temporal" {
  db_proxy_name = aws_db_proxy.temporal.name

  connection_pool_config {
    max_connections_percent      = 90
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
  }
}

resource "aws_db_proxy_target" "temporal" {
  db_proxy_name          = aws_db_proxy.temporal.name
  target_group_name      = aws_db_proxy_default_target_group.temporal.name
  db_instance_identifier = aws_db_instance.temporal.identifier
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.region,
      "--profile",
      var.aws_profile
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.region,
        "--profile",
        var.aws_profile
      ]
    }
  }
}

resource "kubernetes_namespace" "temporal" {
  metadata {
    name = var.temporal_namespace
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  timeout = 1200

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

resource "helm_release" "temporal" {
  name       = "temporal"
  namespace  = kubernetes_namespace.temporal.metadata[0].name
  repository = "https://go.temporal.io/helm-charts"
  chart      = "temporal"
  version    = "0.57.0"

  timeout = 1200

  values = [
    yamlencode({
      server = {
        replicaCount = 1
        config = {
          persistence = {
            default = {
              driver = "sql"
              sql = {
                driver   = "postgres12"
                host     = aws_db_proxy.temporal.endpoint
                port     = 5432
                database = var.db_name
                user     = var.db_username
                password = random_password.db.result
                tls = {
                  enabled                = true
                  serverName             = aws_db_proxy.temporal.endpoint
                  enableHostVerification = true
                }
                maxConns     = 30
                maxIdleConns = 15
              }
            }
            visibility = {
              driver = "sql"
              sql = {
                driver   = "postgres12"
                host     = aws_db_proxy.temporal.endpoint
                port     = 5432
                database = var.visibility_db_name
                user     = var.db_username
                password = random_password.db.result
                tls = {
                  enabled                = true
                  serverName             = aws_db_proxy.temporal.endpoint
                  enableHostVerification = true
                }
                maxConns     = 30
                maxIdleConns = 15
              }
            }
          }
        }
      }
      cassandra = {
        enabled = false
      }
      elasticsearch = {
        enabled = false
      }
      prometheus = {
        enabled = false
      }
      grafana = {
        enabled = false
      }
      web = {
        service = {
          type = "ClusterIP"
        }
      }
      schema = {
        setup = {
          enabled = true
        }
        update = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [aws_db_proxy_target.temporal]
}