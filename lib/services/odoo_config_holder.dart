import 'connection_service.dart';

// ✅ Singleton holder สำหรับ dynamic configuration
class OdooConfigHolder {
  static OdooConfigHolder? _instance;
  ConnectionConfig? config;

  OdooConfigHolder._();

  static OdooConfigHolder getInstance() {
    _instance ??= OdooConfigHolder._();
    return _instance!;  // ✅ เพิ่ม ! เพื่อ assert non-null
  }

  void setConfig(ConnectionConfig newConfig) {
    config = newConfig;
  }

  ConnectionConfig? getConfig() => config;
}
