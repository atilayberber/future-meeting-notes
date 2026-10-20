import '../utils/turkish.dart';

class Participant {
  Participant({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.voiceSamplePath,
    this.voiceSampleSeconds = 0,
  });

  final String id;
  String firstName;
  String lastName;
  String email;

  /// Kayıt sırasında okunan metnin ses dosyası (Faz 1c'de ses izi buradan çıkarılacak).
  String? voiceSamplePath;
  int voiceSampleSeconds;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.isNotEmpty ? firstName.substring(0, 1) : '';
    final l = lastName.isNotEmpty ? lastName.substring(0, 1) : '';
    return trUpper('$f$l');
  }

  bool get hasVoiceSample => voiceSamplePath != null && voiceSampleSeconds > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'voiceSamplePath': voiceSamplePath,
        'voiceSampleSeconds': voiceSampleSeconds,
      };

  factory Participant.fromJson(Map<String, dynamic> j) => Participant(
        id: j['id'] as String,
        firstName: j['firstName'] as String? ?? '',
        lastName: j['lastName'] as String? ?? '',
        email: j['email'] as String? ?? '',
        voiceSamplePath: j['voiceSamplePath'] as String?,
        voiceSampleSeconds: j['voiceSampleSeconds'] as int? ?? 0,
      );
}
