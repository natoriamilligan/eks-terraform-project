# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-bootstrap"
    encrypt        = true
  }
}

# Create locals
locals {
  root_domain = "banksie.app"
  subdomain  = "www.banksie.app
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create public subnets
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
}

# Create public route table and connect internet gateway
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
  }
}

# Connect public subnet to route table for internet access
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.route_table.id
}

# Create elastic IP for NAT Gateway
resource "aws_eip" "ngw" {}

# Create NAT Gateway
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.ngw.id
  subnet_id     = aws_subnet.public_a.id

  depends_on    = [aws_internet_gateway.igw]
}

# Create private route table and connect NAT gateway
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_nat_gateway.ngw.id
  }
}

# Create private subnets
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Attach private subnets to private route tables
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create hosted zone
resource "aws_route53_zone" "hosted_zone" {
  name = locals.root_domain
}

# Create Lambda IAM role
resource "aws_iam_role" "lambda_role" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach role allows Lambda to write to CW logs
resource "aws_iam_role_policy_attachment" "lambda_execution_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy to allow Lamdba to access Secrets Manager
resource "aws_iam_role_policy" "lambda_policy" {
  name = "accessSecretsManager"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
          Action = ["secretsmanager:GetSecretValue"]
          Effect   = "Allow"
          Resource = "arn:aws:secretsmanager:${data.aws_caller_identity.current.account_id}:secret:slack-webhook-url*"
      },
      {
          Effect   = "Allow"
          Action = [
            "scheduler:UpdateSchedule",
            "scheduler:DescribeSchedule"
          ]
          Resource = aws_scheduler_schedule.lambda_schedule.arn
      },
    ]
  })
}

# Creat lambda function
resource "aws_lambda_function" "lambda_function" {
  filename         = "ns-propagation.zip"
  function_name    = "ns-propagation"
  role             = aws_iam_role.lamda_role.arn
  handler          = "ns-propagation.lambda_handler"
  source_code_hash = filebase64sha256("ns-propagation.zip")
  runtime          = "python3.11"

  environment {
    variables = {
      NAMESERVERS           = jsonencode(aws_route53_zone.hosted_zone.nameservers)
      DOMAIN                = locals.root_domain
      SLACK_URL_SECRET_NAME = "slack-webhook-url"
      TOKEN_NAME            = "aws-github-token"
      GITHUB_REPO           = "natoriamilligan/eks-terraform-project"
      GITHUB_WORKFLOW       = "infra.yml"
      GITHUB_REF            = "master"
    }
  }
}

# Create Scheduler IAM role
resource "aws_iam_role" "scheduler_role" {
  name               = "scheduler_execution_role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

# policy for Schedular IAM role
resource "aws_iam_role_policy" "scheduler_lambda_policy" {
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.lambda_function.arn
      }
    ]
  })
}

resource "aws_scheduler_schedule_group" "lamdba_group" {
  name = "lambda-group"
}

resource "aws_scheduler_schedule" "lambda_scheduler" {
  name       = "lambda-schedule"
  group_name = aws_scheduler_schedule_group.lambda_group.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(30 minutes)"

  target {
    arn      = aws_lambda_function.lambda_function.arn
    role_arn = aws_iam_role.scheduler_role.arn
  }
}
