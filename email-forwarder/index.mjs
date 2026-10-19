// SNS -> SES forwarder.
// Subscribed to the fraud-detection-alerts SNS topic. For each published message,
// sends it as an email via Amazon SES. SES email has NO unsubscribe link and no
// subscription lifecycle, so it can't be auto-deactivated by link scanners.
// The agent is unchanged — it still calls sns.publish.

import { SESClient, SendEmailCommand } from '@aws-sdk/client-ses'

const REGION = process.env.AWS_REGION
const SENDER = process.env.SENDER_EMAIL
const RECIPIENT = process.env.RECIPIENT_EMAIL

const ses = new SESClient({ region: REGION })

export const handler = async (event) => {
  const records = event.Records || []
  for (const rec of records) {
    const sns = rec.Sns || {}
    const subject = (sns.Subject || 'Fraud Detection Alert').slice(0, 200)
    const body = sns.Message || ''
    await ses.send(new SendEmailCommand({
      Source: SENDER,
      Destination: { ToAddresses: [RECIPIENT] },
      Message: {
        Subject: { Data: subject, Charset: 'UTF-8' },
        Body: { Text: { Data: body, Charset: 'UTF-8' } },
      },
    }))
    console.log(`Forwarded SNS message to SES: subject="${subject}"`)
  }
  return { statusCode: 200 }
}
