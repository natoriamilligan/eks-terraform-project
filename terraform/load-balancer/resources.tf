# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "load-balancer/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-bootstrap"
    encrypt        = true
  }
}

# Create Load Balancer Controller IAM role
resource "aws_iam_role" "lb_controller_role" {
  name               = "lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume_policy.json
}

# Create policy for LB Controller
resource "aws_iam_policy" "lb_controller" {
  name   = "LBControllerIAMPolicy"
  policy = file("${path.module}/lb-iam-policy.json")
}

# Attach LB Controller policy to IAM role
resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.lb_controller_role.name
  policy_arn = aws_iam_policy.lb_controller.arn
}
