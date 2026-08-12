data "archive_file" "janitor_engine" {
  type        = "zip"
  source_file = "${path.module}/../python/scripts/janitor_engine.py"
  output_path = "${path.module}/janitor_engine.zip"
}

resource "aws_iam_role" "lambda_janitor" {
  name = "janitor-engine-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_janitor_policy" {
  name = "janitor-engine-lambda-policy"
  role = aws_iam_role.lambda_janitor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DeleteVolume",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DetachNetworkInterface",
          "ec2:DescribeSecurityGroups",
          "ec2:DeleteNetworkInterface",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/*",
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/*:log-stream:*",
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "janitor_engine" {
  function_name    = "janitor-engine"
  filename         = data.archive_file.janitor_engine.output_path
  source_code_hash = data.archive_file.janitor_engine.output_base64sha256
  handler          = "janitor_engine.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_janitor.arn
  timeout          = 30
  memory_size      = 128
}
