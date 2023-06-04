

resource "aws_lambda_function" "translate_lambda" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename      = "../main.zip"
  function_name = "Translate-Files"
  role          = aws_iam_role.translate_files.arn
  handler       = "main.lambda_handler"
  timeout = 15
  description = "This lambda translates a source file to a target language and outputs file to s3"

  runtime = "python3.9"

  environment {
    variables = {
      source_language = "en"
      target_language = "de"
      upload_bucket = "translate-demo-us-east-1-bucket"
    }
  }
}

module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "translate-demo-us-east-1-bucket"
  block_public_policy = true
  block_public_acls = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "AWSLambdaTrustPolicy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "translate_files" {
  name               = "Translate-Files-Role"
  assume_role_policy = data.aws_iam_policy_document.AWSLambdaTrustPolicy.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_exec_policy" {
  role       = aws_iam_role.translate_files.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "policy" {
  name = "lambda-policy"
  role = aws_iam_role.translate_files.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation",
          "s3:ListBucket",
        ]
        Effect   = "Allow"
        Resource = [
            module.s3_bucket.s3_bucket_arn,
            format("%s/*",module.s3_bucket.s3_bucket_arn)
        ]
      },
      {
        Action = [
          "s3:PutObject",
        ]
        Effect   = "Allow"
        Resource = [
            module.s3_bucket.s3_bucket_arn,
            format("%s/translated/*",module.s3_bucket.s3_bucket_arn)
        ]
      },
      {
        Action = [
          "translate:TranslateText",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.translate_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_bucket.s3_bucket_arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.s3_bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.translate_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "source_files/"
  }
}

