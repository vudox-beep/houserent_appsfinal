/// Role helpers for the moving marketplace (tenant accounts may be `user` or `tenant`).
class MovingRoles {
  static bool isTenant(String? role) {
    final r = (role ?? '').toLowerCase();
    return r == 'user' || r == 'tenant';
  }

  static bool isDriver(String? role) => (role ?? '').toLowerCase() == 'driver';
}
