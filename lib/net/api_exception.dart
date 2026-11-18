/// Famille d'erreur réseau, pour décider quoi faire (réessayer, abandonner, avertir).
enum ApiErrorKind {
  /// Pas de réseau / serveur injoignable.
  offline,
  timeout,
  unauthorized,
  forbidden,
  notFound,

  /// Refus métier (déjà remis, trop-perçu, identifiant déjà pris…).
  conflict,
  validation,
  rateLimited,
  server,
  unknown,
}

class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.status, this.code});

  final ApiErrorKind kind;

  /// Message lisible, en français (celui du serveur si disponible).
  final String message;
  final int? status;

  /// Code machine du serveur (« already_collected », « overpayment »…).
  final String? code;

  /// Problème de connexion : l'opération peut être rejouée plus tard sans risque.
  bool get isNetwork => kind == ApiErrorKind.offline || kind == ApiErrorKind.timeout;

  /// Vaut la peine de réessayer plus tard (réseau, serveur en panne, trop de requêtes).
  bool get isRetryable =>
      isNetwork || kind == ApiErrorKind.server || kind == ApiErrorKind.rateLimited;

  @override
  String toString() => 'ApiException($kind, $status, $code): $message';
}
