import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  late SharedPreferences _prefs;

  static const _kExportDir = 'exportDir';
  static const _kCompanyDomain = 'companyDomain';
  static const _kAsrModel = 'asrModelId';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Toplantı kayıtlarının kopyalanacağı klasör. null ise yalnızca uygulama içinde tutulur.
  String? get exportDir => _prefs.getString(_kExportDir);

  Future<void> setExportDir(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_kExportDir);
    } else {
      await _prefs.setString(_kExportDir, value);
    }
    notifyListeners();
  }

  /// E-posta söylenirken alan adı atlanırsa eklenecek alan adı (ör. bicen.com.tr).
  String get companyDomain => _prefs.getString(_kCompanyDomain) ?? '';

  Future<void> setCompanyDomain(String value) async {
    await _prefs.setString(_kCompanyDomain, value.trim());
    notifyListeners();
  }

  /// Kullanılan konuşma tanıma modeli (bkz. asr/model_catalog.dart).
  String? get asrModelId => _prefs.getString(_kAsrModel);

  Future<void> setAsrModelId(String id) async {
    await _prefs.setString(_kAsrModel, id);
    notifyListeners();
  }
}
