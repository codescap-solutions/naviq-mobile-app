/// A non-2xx answer from the backend, with the parts a caller needs to decide
/// whether retrying can ever help (HTTP status, the additive `error_code`, and
/// the response `data`). Its text is identical to a plain `Exception(message)`,
/// so every existing `catch` / message-extraction keeps working unchanged.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;
  final Map<String, dynamic>? data;

  const ApiException(this.message, {this.statusCode, this.errorCode, this.data});

  @override
  String toString() => 'Exception: $message';
}
