class AuthFlowGuard {
  int _revision = 0;

  int get revision => _revision;

  int begin() {
    _revision += 1;
    return _revision;
  }

  int invalidate() {
    _revision += 1;
    return _revision;
  }

  bool isCurrent(int revision) => _revision == revision;
}
