import boto3
import os
import logging
import urllib

log = logging.getLogger()
log.setLevel(logging.INFO)

translate_client = boto3.client("translate")
s3 = boto3.client("s3")

#Code for language of source file
SOURCE_LANGUAGE = os.getenv("source_language")
TARGET_LANGUAGE = os.getenv("target_language")

UPLOAD_BUCKET = os.getenv("upload_bucket")

def open_file(source_file):
    """
    This function opens the source file.
    """
    localFile = source_file
    file = open(localFile, "rb")
    data = file.read()
    file.close()
    return data


def write_document(source_file, translate_result):
    """
    This function pulls the translated result from
    aws response.
    """
    if "TranslatedText" in translate_result:
        file_name = source_file.split("/")[-1]
        tmp_file = f"/tmp/translated.{file_name}"
        with open(tmp_file, "w", encoding="utf-8") as f:
            f.write(str(translate_result["TranslatedText"]))
        return tmp_file
    log.error("No Translated Document found in response")

def translate(source_language_code, target_language_code, source_file):
    """
    This function translates the source file to from the
    source language to the target language.
    """
    data = open_file(source_file).decode('UTF-8')
    log.info("File %s opened", source_file)
    try:
        result = translate_client.translate_text(
            Text=data,
            SourceLanguageCode=source_language_code,
            TargetLanguageCode=target_language_code,
        )
    except Exception as e:
        log.error(e)
        raise e
    translated_file = write_document(source_file, result)
    log.info("Translated document: %s", translated_file)
    return translated_file

def get_file(event):
    # Get the object from the event and show its content type
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')
    filename = event['Records'][0]['s3']['object']['key'].split("/")[-1]
    try:
        response = s3.download_file(Bucket=bucket, Key=key,Filename=f"/tmp/{filename}")
    except Exception as e:
        log.error(e)
        print('Error getting object {} from bucket {}. Make sure they exist and your bucket is in the same region as this function.'.format(key, bucket))
        raise e
    return f"/tmp/{filename}"

def upload_file(file_name, bucket, object_name):
    """Upload a file to an S3 bucket

    :param file_name: File to upload
    :param bucket: Bucket to upload to
    :param object_name: S3 object name. If not specified then file_name is used
    """
    try:
        response = s3.upload_file(file_name, bucket, object_name)
    except Exception as e:
        log.error(e)
        raise e

def lambda_handler(event, context):
    file_key=get_file(event)
    target_file = translate(SOURCE_LANGUAGE,TARGET_LANGUAGE,file_key)
    target_file_name = target_file.split("/")[-1]
    upload_file(target_file,UPLOAD_BUCKET,f"translated/{target_file_name}")
