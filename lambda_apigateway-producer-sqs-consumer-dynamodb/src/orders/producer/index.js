const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");
const { randomUUID } = require('crypto');

// const endpoint = process.env.AWS_ENDPOINT_URL || "http://localhost:4566";
const endpoint = "http://host.docker.internal:4566";
const sqs = new SQSClient({ endpoint, region: process.env.AWS_REGION || "us-east-1" });

exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body || "{}");
        const orderId = body.orderId || `ord_${randomUUID()}`;

        const command = new SendMessageCommand({
            QueueUrl: process.env.QUEUE_URL,
            MessageBody: JSON.stringify({
                orderId,
                item: body.item || "Default Item",
                amount: body.amount || 1,
                timestamp: new Date().toISOString(),
            }),
        });

        await sqs.send(command);

        return {
            statusCode: 202,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message: "Order accepted for processing", orderId }),
        };
    } catch (err) {
        return {
            statusCode: 500,
            body: JSON.stringify({ error: err.message }),
        };
    }
};