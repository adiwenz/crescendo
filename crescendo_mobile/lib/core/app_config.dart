enum AppMode {
  v0,
  full,
}

class AppConfig {
  static AppMode appMode = AppMode.v0;

  static bool get isV0 => appMode == AppMode.v0;
}
