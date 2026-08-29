import os
import io
import time
import urllib.parse
import boto3
from PIL import Image

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

SIZES = {
    'thumb': (150, 150),
    'medium': (500, 500),
    'large': (1024, 1024)
}

DEST_BUCKET = os.environ['DEST_BUCKET']
TABLE_NAME = os.environ['DYNAMODB_TABLE']

def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    for record in event['Records']:
        source_bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')

        # Download original image
        response = s3.get_object(Bucket=source_bucket, Key=key)
        image_bytes = response['Body'].read()

        file_name, file_ext = os.path.splitext(os.path.basename(key))
        format_type = 'JPEG' if file_ext.lower() in ['.jpg', '.jpeg'] else 'PNG'

        metadata_variants = {}

        # Resize and upload each variant
        for size_name, (max_w, max_h) in SIZES.items():
            img = Image.open(io.BytesIO(image_bytes))
            img.thumbnail((max_w, max_h))

            buffer = io.BytesIO()
            img.save(buffer, format=format_type)
            buffer.seek(0)

            dest_key = f"images/{size_name}/{file_name}{file_ext}"

            # Put object in destination S3 bucket
            s3.put_object(
                Bucket=DEST_BUCKET,
                Key=dest_key,
                Body=buffer,
                ContentType=response.get('ContentType', 'image/jpeg')
            )

            # Record variant metadata
            metadata_variants[size_name] = {
                's3_key': dest_key,
                's3_url': f"https://{DEST_BUCKET}.s3.amazonaws.com/{dest_key}",
                'floci_s3_url': f"http://localhost:4566/{DEST_BUCKET}/{dest_key}", # for local testing
                'width': img.width,
                'height': img.height,
                'file_size_bytes': buffer.getbuffer().nbytes
            }

        # Put metadata record in DynamoDB
        table.put_item(
            Item={
                'ImageId': key,  # Partition Key
                'SourceBucket': source_bucket,
                'ProcessedAt': int(time.time()),
                'Variants': metadata_variants
            }
        )
        print(f"Processed image and saved metadata for key: {key}")