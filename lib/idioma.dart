import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Idioma de la app: 'es' o 'en'. Sale del teléfono (español si el teléfono está en español,
/// inglés para todo lo demás) o de lo que la persona elija en Perfil.
final idioma = ValueNotifier<String>('es');

/// Lo que eligió en Perfil: 'auto', 'es' o 'en'.
var idiomaElegido = 'auto';

bool get enIngles => idioma.value == 'en';

/// El texto en el idioma de la app. Los chistes se adaptan, no se traducen palabra por palabra.
String tr(String es, String en) => enIngles ? en : es;

String _delTelefono() => PlatformDispatcher.instance.locale.languageCode == 'es' ? 'es' : 'en';

Future<void> iniciarIdioma() async {
  try {
    idiomaElegido = (await SharedPreferences.getInstance()).getString('idioma') ?? 'auto';
  } catch (_) {}
  idioma.value = idiomaElegido == 'auto' ? _delTelefono() : idiomaElegido;
}

Future<void> elegirIdioma(String valor) async {
  idiomaElegido = valor;
  try {
    await (await SharedPreferences.getInstance()).setString('idioma', valor);
  } catch (_) {}
  idioma.value = valor == 'auto' ? _delTelefono() : valor;
}

/// Los errores que manda la base de datos vienen en español: aquí su versión en inglés.
const _errores = {
  'Accesorio desconocido': 'Unknown accessory',
  'Esa cagada no es racha': "That poop isn't a streak",
  'Esa racha ya salió en el chat': 'That streak is already in the chat',
  'Esa cagada no existe o no dijiste qué salió': "That poop doesn't exist or you didn't say what came out",
  'Ese reto era de otro día': 'That challenge was for another day',
  'Ese reto no es tuyo': "That challenge isn't yours",
  'Ese reto ya no está pendiente': 'That challenge is no longer pending',
  'Mensaje vacío': 'Empty message',
  'No puedes quitar el género, solo cambiarlo': "You can't remove your gender, only change it",
  'No compartas teléfonos ni correos en el chat': "Don't share phone numbers or emails in the chat",
  'No puedes hacer eso': "You can't do that",
  'No puedes retar a esa persona': "You can't challenge that person",
  'Solo puedes retar a gente que sigues': 'You can only challenge people you follow',
  'Tarjeta desconocida': 'Unknown card',
  'Todavía no': 'Not yet',
  'Todavía no has desbloqueado eso': "You haven't unlocked that yet",
  'Todavía no llegas a ese número': "You haven't reached that number yet",
  'Ya tienen un Cagadón hoy': 'You already have a Poop-Off today',
};

/// Un mensaje de error del servidor en el idioma de la app.
String trServidor(String mensaje) {
  if (!enIngles) return mensaje;
  final fijo = _errores[mensaje];
  if (fijo != null) return fijo;
  final espera = RegExp(r'^Calma, (?:rey|reina): solo una por hora\. Espera (\d+) min más\.$').firstMatch(mensaje);
  if (espera != null) return 'Easy, your majesty: one per hour. Wait ${espera[1]} more min.';
  final genero = RegExp(r'^Solo puedes cambiar el género una vez al año\. Próximo cambio: (.+)$').firstMatch(mensaje);
  if (genero != null) return 'You can only change your gender once a year. Next change: ${genero[1]}';
  final link = RegExp(r'^Link bloqueado: no se permiten (.+)$').firstMatch(mensaje);
  if (link != null) return 'Link blocked: ${_bloqueados[link[1]] ?? link[1]} not allowed';
  return mensaje;
}

// Lo que devuelve public.link_peligroso().
const _bloqueados = {
  'ese tipo de link': 'that kind of link is',
  'links con usuario@': 'links with user@ are',
  'links a una IP': 'links to an IP address are',
  'dominios con letras raras': 'domains with weird letters are',
  'acortadores de links': 'link shorteners are',
  'ese dominio': 'that domain is',
  'links a archivos que se instalan': 'links to installable files are',
};
