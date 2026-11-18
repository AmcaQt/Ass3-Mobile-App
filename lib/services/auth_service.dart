import 'package:firebase_auth/firebase_auth.dart';

/// Wraps FirebaseAuth so screens never touch the plugin directly.
///
/// Every database rule in this project checks `auth != null`, so nothing may
/// read or write /lab until one of the sign-in methods below has completed.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Null while signed out, a user once signed in. Emits the restored session
  /// on startup, so the gate does not ask for a password on every launch.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  /// Anonymous sign-in: a real token, so the rules pass, but no account.
  Future<void> signInAsGuest() => _auth.signInAnonymously();

  Future<void> signOut() => _auth.signOut();
}

/// Readable text for the failures this app can actually hit.
String authErrorMessage(Object error) {
  if (error is! FirebaseAuthException) {
    return 'Something went wrong. Please try again.';
  }
  return switch (error.code) {
    'invalid-email' => 'That email address is not valid.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Wrong email or password.',
    'user-disabled' => 'This account has been disabled.',
    'too-many-requests' => 'Too many attempts. Try again in a moment.',
    // the provider is off in Authentication -> Sign-in method
    'operation-not-allowed' ||
    'admin-restricted-operation' => 'This sign-in method is not enabled for '
        'the project.',
    'network-request-failed' => 'No connection. Check your network.',
    _ => error.message ?? 'Could not sign in (${error.code}).',
  };
}
