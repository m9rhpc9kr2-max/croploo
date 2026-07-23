import 'dart:convert';

import 'package:http/http.dart' as http;

class BillingException implements Exception {
  BillingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to the Node/Express backend's `/v1/billing` endpoints.
class BillingApi {
  BillingApi({
    this.baseUrl = 'https://croploo-backend-78230737866.europe-west1.run.app/v1',
  });

  final String baseUrl;

  /// Creates a Stripe Checkout session for [tier] ('basic' | 'pro' | 'desk')
  /// and returns the hosted checkout URL to open in the browser.
  Future<String> createCheckoutSession({
    required String tier,
    required String accessToken,
  }) async {
    final http.Response res;
    try {
      res = await http.post(
        Uri.parse('$baseUrl/billing/checkout'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'tier': tier}),
      );
    } catch (_) {
      throw BillingException('Cannot reach Croploo backend at $baseUrl');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw BillingException(json['detail'] as String? ?? 'Checkout failed');
    }
    return json['url'] as String;
  }
}
