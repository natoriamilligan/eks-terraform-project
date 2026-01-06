module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = ">= 21.10.1"  

  cluster_name    = "eks-cluster"
  cluster_version = "1.35.0"
  subnets         = local.private_subnet_ids
  vpc_id          = aws_vpc.main.id

  node_groups = {
    default = {
      desired_capacity = 1
      max_capacity     = 1
      min_capacity     = 1
      instance_type    = "t3.small"
    }
  }

  manage_aws_auth = true
  enable_irsa     = true
}
