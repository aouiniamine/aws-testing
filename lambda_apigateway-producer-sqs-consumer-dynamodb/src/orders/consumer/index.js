const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");

// const endpoint = process.env.AWS_ENDPOINT_URL || "http://localhost:4566";
const endpoint = "http://host.docker.internal:4566";
const client = new DynamoDBClient({ endpoint, region: process.env.AWS_REGION || "us-east-1" });
const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log("Processing SQS message:", JSON.stringify(event));
    for (const record of event.Records) {
        const payload = JSON.parse(record.body);

        await docClient.send(new PutCommand({
            TableName: process.env.TABLE_NAME,
            Item: {
                orderId: payload.orderId,
                item: payload.item,
                amount: payload.amount,
                status: "PROCESSED",
                processedAt: new Date().toISOString(),
            },
        }));
    }
    return { status: "success" };
};