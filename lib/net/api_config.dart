/// Adresse de l'API. Modifiable dans Compte › Serveur (enregistrée sur l'appareil).
/// Valeur par défaut à la compilation :  flutter build apk --dart-define=API_URL=https://api.exemple.com
class ApiConfig {
  ApiConfig([String? url]) : url = (url == null || url.isEmpty) ? defaultUrl : url;

  static const String defaultUrl = String.fromEnvironment('API_URL');

  String url;

  /// Nettoie une saisie : espaces, « / » final, schéma ajouté si absent (https par défaut).
  static String normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (s.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) s = 'https://$s';
    return s;
  }
}
