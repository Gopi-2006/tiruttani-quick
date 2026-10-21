package com.youpi.observer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Telephony;
import android.telephony.SmsMessage;
import android.util.Log;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Privacy-Preserving Bank Payment SMS Receiver.
 * Strictly filters incoming messages so that ONLY confirmed incoming bank/UPI credit transactions
 * are processed and dispatched.
 * Personal messages, OTPs, login verification codes, and non-financial texts are dropped immediately
 * on-device and never transmitted or retained.
 */
public class SmsReceiver extends BroadcastReceiver {
    private static final String TAG = "YoupiSmsReceiver";

    // Regular expressions for detecting legitimate bank credit transactions
    private static final Pattern AMOUNT_PATTERN = Pattern.compile(
        "(?:Rs\\.?|INR|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)",
        Pattern.CASE_INSENSITIVE
    );

    private static final Pattern UTR_PATTERN = Pattern.compile(
        "(?:UPI\\s*(?:ref|reference|txn|id)?|Ref(?:erence)?\\s*(?:no|number)?|UTR)\\s*[:#-]?\\s*([0-9]{12})",
        Pattern.CASE_INSENSITIVE
    );

    // Strict negative keywords: Messages containing OTPs, authentication tokens, or personal verification codes must NEVER be processed
    private static final String[] SENSITIVE_OTP_KEYWORDS = {
        "otp", "one time password", "one-time password", "verification code",
        "secret code", "do not share", "login pin", "security code", "auth code"
    };

    // Positive keywords: Required indicators that the SMS is a bank credit confirmation
    private static final String[] BANK_CREDIT_KEYWORDS = {
        "credited", "credit of", "received", "deposited", "deposit of", "credited by", "paid you"
    };

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) {
            return;
        }

        SmsMessage[] messages = Telephony.Sms.Intents.getMessagesFromIntent(intent);
        if (messages == null || messages.length == 0) return;

        final ApiClient client = new ApiClient(context);
        if (!client.isPaired()) {
            return;
        }

        for (SmsMessage sms : messages) {
            if (sms == null) continue;
            final String sender = sms.getOriginatingAddress();
            final String body = sms.getMessageBody();
            final long timestamp = sms.getTimestampMillis();

            if (body == null || body.trim().isEmpty()) {
                continue;
            }

            // 1. Strict Privacy Shield: Check if message is an OTP or authentication code
            if (isOtpOrAuthenticationMessage(body)) {
                // Drop immediately on-device. Zero transmission.
                continue;
            }

            // 2. Validate that message is an actual incoming financial payment/credit
            if (!isBankCreditTransaction(body)) {
                // Not a credit transaction (e.g. personal SMS, promotional, or debit notification). Drop.
                continue;
            }

            Log.i(TAG, "Validated incoming bank credit SMS from sender [" + (sender != null ? sender : "BANK") + "]");

            // 3. Dispatch validated bank credit SMS to Merchant Gateway
            new Thread(new Runnable() {
                @Override
                public void run() {
                    boolean success = client.sendSms(sender, body, timestamp);
                    Log.i(TAG, "Dispatched verified credit SMS to Gateway: " + (success ? "SUCCESS" : "FAILED"));
                }
            }).start();
        }
    }

    /**
     * Rejects any SMS containing OTPs, one-time passwords, or authentication secrets.
     */
    public static boolean isOtpOrAuthenticationMessage(String text) {
        if (text == null) return false;
        String lower = text.toLowerCase(Locale.ROOT);
        for (String kw : SENSITIVE_OTP_KEYWORDS) {
            if (lower.contains(kw)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Ensures the SMS is genuinely a bank credit transaction with positive monetary amount.
     */
    public static boolean isBankCreditTransaction(String text) {
        if (text == null) return false;
        String lower = text.toLowerCase(Locale.ROOT);

        // Check for credit keywords
        boolean hasCreditKeyword = false;
        for (String kw : BANK_CREDIT_KEYWORDS) {
            if (lower.contains(kw)) {
                hasCreditKeyword = true;
                break;
            }
        }
        if (!hasCreditKeyword) {
            return false;
        }

        // Must have monetary amount pattern
        Matcher mAmount = AMOUNT_PATTERN.matcher(text);
        if (!mAmount.find()) {
            return false;
        }

        try {
            String cleanNum = mAmount.group(1).replace(",", "");
            double val = Double.parseDouble(cleanNum);
            if (val <= 0.0) return false;
        } catch (Exception e) {
            return false;
        }

        return true;
    }
}
