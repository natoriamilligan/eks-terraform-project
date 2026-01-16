# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "bootstrap/terraform.tfstate"
    region         = var.region
    dynamodb_table = "terraform-lock-bootstrap"
    encrypt        = true
  }
}

# Create locals
locals {
  root_domain = "banksie.app"
  subdomain   = "www.banksie.app" 
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

# Create lambda function
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

# Policy for Schedular IAM role
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

# Schedular group
resource "aws_scheduler_schedule_group" "lamdba_group" {
  name = "lambda-group"
}

# Create schedule for lambda function
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
