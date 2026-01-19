import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart'; // Import
import 'package:javornik_timerush/screens/main_menu_screen.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoginMode = true;
  bool _isLoading = false;

  // Pomocná funkce pro Tag
  String _generateDiscriminator() {
    int randomNum = 1000 + Random().nextInt(9000);
    return "#$randomNum";
  }

  // --- GOOGLE SIGN IN ---
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // 1. Spustit Google flow
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return; // Uživatel to zrušil
      }

      // 2. Získat auth detaily
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 3. Vytvořit credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Přihlásit do Firebase
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // 5. Zkontrolovat, jestli už uživatel existuje v naší DB
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (!userDoc.exists) {
          // NOVÝ UŽIVATEL PŘES GOOGLE -> Musíme mu vygenerovat záznam a Tag
          String baseName = user.displayName ?? "Horal";
          String discriminator = _generateDiscriminator();

          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'username': baseName,
            'discriminator': discriminator, // Uložíme tag (#1234)
            'full_username': "$baseName$discriminator", // Pro snadné hledání
            'email': user.email,
            'profile_picture': user.photoURL, // Google fotka
            'created_at': DateTime.now(),
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

  // --- REGISTRACE E-MAILEM (S TAGEM) ---
  Future<void> _register() async {
    setState(() => _isLoading = true);
    try {
      // Zde už nekontrolujeme duplicitu jména, protože přidáme tag

      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      String baseName = _usernameController.text.trim();
      String discriminator = _generateDiscriminator();

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user?.uid).set({
        'username': baseName,
        'discriminator': discriminator,
        'full_username': "$baseName$discriminator",
        'email': _emailController.text.trim(),
        'created_at': DateTime.now(),
        'total_climbs': 0,
        'total_time_seconds': 0,
        'total_distance': 0.0,
      });

      if (!mounted) return;
      _navigateToMainScreen();
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Chyba registrace');
    } catch (e) {
      _showError('Chyba: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PŘIHLÁŠENÍ E-MAILEM ---
  // Poznámka: Přihlašujeme se E-mailem, ne jménem+tagem (to by bylo složité pro uživatele)
  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      // Uživatel může zadat buď E-mail, nebo "Jméno#1234".
      // Pro jednoduchost zde necháme přihlášení E-MAILEM (je to standard).
      // Pokud chcete login přes Username, museli bychom hledat v DB.

      // Zde předpokládám, že uživatel do pole "Email" zadá email.
      // Pokud do username inputu zadá email, použijeme ten.

      String input = _isLoginMode ? _emailController.text.trim() : _emailController.text.trim();

      // Pokud jsme v módu login a máme jen jedno pole pro "Jméno/Email", musíme to vyřešit.
      // Ale v designu níže mám pole pro Email odděleně.

      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      _navigateToMainScreen();
    } on FirebaseAuthException catch (e) {
      _showError('Chyba přihlášení. Zkontrolujte údaje.');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Hero(
                  tag: 'logo',
                  child: Image.asset('assets/images/logofinal.png', width: 150.0),
                ),
                SizedBox(height: 20),

                Container(
                  padding: EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isLoginMode ? 'Vítejte zpět' : 'Vytvořit účet',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 25),

                      // Username (Jen při registraci)
                      if (!_isLoginMode) ...[
                        _buildTextField(
                          controller: _usernameController,
                          label: 'Přezdívka (bez #)',
                          icon: Icons.person_outline,
                        ),
                        SizedBox(height: 15),
                      ],

                      // Email (Vždy)
                      _buildTextField(
                        controller: _emailController,
                        label: 'E-mail',
                        icon: Icons.email_outlined,
                        inputType: TextInputType.emailAddress,
                      ),
                      SizedBox(height: 15),

                      // Heslo (Vždy)
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Heslo',
                        icon: Icons.lock_outline,
                        isPassword: true,
                      ),

                      SizedBox(height: 25),

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
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text(_isLoginMode ? 'PŘIHLÁSIT SE' : 'ZAREGISTROVAT SE'),
                        ),
                      ),

                      SizedBox(height: 20),

                      // ODDĚLOVAČ
                      Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.all(8), child: Text("NEBO")), Expanded(child: Divider())]),
                      SizedBox(height: 20),

                      // TLAČÍTKO GOOGLE
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          icon: Image.network(
                            'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                            height: 24,
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.g_mobiledata), // Fallback
                          ),
                          label: Text("Pokračovat přes Google", style: TextStyle(color: Colors.black87)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 20),
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

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false, TextInputType inputType = TextInputType.text}) {
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