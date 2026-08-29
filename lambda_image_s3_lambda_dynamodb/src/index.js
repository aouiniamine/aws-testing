const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');
const sharp = require('sharp');
const path = require('path');

// Floci endpoint handling
// const endpoint = process.env.AWS_ENDPOINT_URL || 'http://localhost:4566';
const endpoint = 'http://host.docker.internal:4566';
const region = process.env.AWS_REGION || 'us-east-1';

const s3 = new S3Client({ endpoint, region, forcePathStyle: true });
const ddbClient = new DynamoDBClient({ endpoint, region });
const docClient = DynamoDBDocumentClient.from(ddbClient);

const SIZES = {
    thumb: { width: 150, height: 150 },
    medium: { width: 500, height: 500 },
    large: { width: 1024, height: 1024 },
};

const DEST_BUCKET = process.env.DEST_BUCKET;
const TABLE_NAME = process.env.DYNAMODB_TABLE;

// Helper to convert ReadableStream to Buffer
const streamToBuffer = async (stream) => {
    const chunks = [];
    for await (const chunk of stream) {
        chunks.push(chunk);
    }
    return Buffer.concat(chunks);
};

exports.handler = async (event) => {
    for (const record of event.Records) {
        const sourceBucket = record.s3.bucket.name;
        const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));

        // Download original image from S3
        const getObjResponse = await s3.send(new GetObjectCommand({ Bucket: sourceBucket, Key: key }));
        const imageBuffer = await streamToBuffer(getObjResponse.Body);

        const ext = path.extname(key);
        const fileName = path.basename(key, ext);
        const contentType = getObjResponse.ContentType || 'image/jpeg';

        const metadataVariants = {};

        // Resize and upload each variant
        for (const [sizeName, dimensions] of Object.entries(SIZES)) {
            // sharp fit: 'inside' replicates Pillow's thumbnail() aspect-ratio behavior
            const resizedBuffer = await sharp(imageBuffer)
                .resize({
                    width: dimensions.width,
                    height: dimensions.height,
                    fit: 'inside',
                    withoutEnlargement: true,
                })
                .toBuffer();

            // Read output width/height/metadata via sharp
            const resizedMetadata = await sharp(resizedBuffer).metadata();

            const destKey = `images/${sizeName}/${fileName}${ext}`;

            // Upload resized variant to destination S3 bucket
            await s3.send(new PutObjectCommand({
                Bucket: DEST_BUCKET,
                Key: destKey,
                Body: resizedBuffer,
                ContentType: contentType,
            }));

            // Record variant metadata
            metadataVariants[sizeName] = {
                s3_key: destKey,
                s3_url: `https://${DEST_BUCKET}.s3.amazonaws.com/${destKey}`,
                floci_s3_url: `http://localhost:4566/${DEST_BUCKET}/${destKey}`,
                width: resizedMetadata.width,
                height: resizedMetadata.height,
                file_size_bytes: resizedBuffer.length,
            };
        }

        // Write item to DynamoDB
        await docClient.send(new PutCommand({
            TableName: TABLE_NAME,
            Item: {
                ImageId: key, // Partition Key
                SourceBucket: sourceBucket,
                ProcessedAt: Math.floor(Date.now() / 1000),
                Variants: metadataVariants,
            },
        }));

        console.log(`Successfully processed image and stored metadata for key: ${key}`);
    }
};