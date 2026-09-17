import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:javornik_timerush/screens/main_menu_screen.dart';
import 'package:javornik_timerush/utils/constants.dart';
import 'package:javornik_timerush/utils/helpers.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  AuthScreenState createState() => AuthScreenState();
}

class AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  bool _isLoginMode = true;
  bool _isLoading = false;

  // --- GOOGLE SIGN IN ---
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw 'Google Sign In nevrátil ID Token.';
      }

      final AuthResponse res = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final user = res.user;
      if (user != null) {
        final existingProfile = await supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (existingProfile == null) {
          String baseName = user.userMetadata?['full_name'] ??
              user.userMetadata?['name'] ??
              "Horal";
          String discriminator = generateDiscriminator();

          await supabase.from('profiles').insert({
            'id': user.id,
            'username': baseName,
            'discriminator': discriminator,
            'full_username': "$baseName$discriminator",
            'email': user.email,
            'profile_picture': user.userMetadata?['avatar_url'] ??
                user.userMetadata?['picture'],
            'created_at': DateTime.now().toIso8601String(),
            'total_climbs': 0,
            'total_time_seconds': 0,
            'total_distance': 0.0,
          });
        }

        if (!mounted) return;
        _navigateToMainScreen();
      }
    } catch (e) {
      _showError('Chyba Google přihlášení: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- REGISTRACE E-MAILEM ---
  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final baseName = _usernameController.text.trim();

    if (email.isEmpty || password.isEmpty || baseName.isEmpty) {
      _showError('Vyplňte prosím všechna pole.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final AuthResponse res = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final user = res.user;
      if (user != null) {
        String discriminator = generateDiscriminator();

        await supabase.from('profiles').insert({
          'id': user.id,
          'username': baseName,
          'discriminator': discriminator,
          'full_username': "$baseName$discriminator",
          'email': email,
          'created_at': DateTime.now().toIso8601String(),
          'total_climbs': 0,
          'total_time_seconds': 0,
          'total_distance': 0.0,
        });

        if (!mounted) return;
        _navigateToMainScreen();
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Chyba: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PŘIHLÁŠENÍ E-MAILEM ---
  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Zadejte prosím e-mail a heslo.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;
      _navigateToMainScreen();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Chyba přihlášení: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToMainScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MainMenuScreen()),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Hero(
                  tag: 'logo',
                  child: Image.asset('assets/images/logofinal.png', width: 150.0),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isLoginMode ? 'Vítejte zpět' : 'Vytvořit účet',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 25),

                      // Username (jen při registraci)
                      if (!_isLoginMode) ...[
                        _buildTextField(
                          controller: _usernameController,
                          label: 'Přezdívka (bez #)',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 15),
                      ],

                      // Email
                      _buildTextField(
                        controller: _emailController,
                        label: 'E-mail',
                        icon: Icons.email_outlined,
                        inputType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 15),

                      // Heslo
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Heslo',
                        icon: Icons.lock_outline,
                        isPassword: true,
                      ),

                      const SizedBox(height: 25),

                      // TLAČÍTKO E-MAIL AKCE
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : (_isLoginMode ? _login : _register),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(_isLoginMode ? 'PŘIHLÁSIT SE' : 'ZAREGISTROVAT SE'),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ODDĚLOVAČ
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(padding: EdgeInsets.all(8), child: Text("NEBO")),
                          Expanded(child: Divider())
                        ],
                      ),
                      const SizedBox(height: 20),

                      // TLAČÍTKO GOOGLE
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          icon: const Icon(Icons.g_mobiledata, size: 30, color: Colors.redAccent),
                          label: const Text("Pokračovat přes Google", style: TextStyle(color: Colors.black87)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => setState(() => _isLoginMode = !_isLoginMode),
                  child: Text(
                    _isLoginMode ? "Ještě nemáš účet? Zaregistruj se" : "Už máš účet? Přihlas se",
                    style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType inputType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: inputType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue[300]),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}