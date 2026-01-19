import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("O aplikaci", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // LOGO
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))],
              ),
              child: Image.asset("assets/images/logo.png", width: 100),
            ),

            SizedBox(height: 30),

            // NÁZEV
            Text(
              "Javorník TimeRush",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            Text(
              "Verze 1.0.0",
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),

            SizedBox(height: 40),

            // POPIS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Aplikace pro všechny milovníky Javorníku a horských výšlapů. Měřte své časy, sledujte statistiky a soutěžte s přáteli.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
              ),
            ),

            SizedBox(height: 50),

            // KREDITY
            Text("Vytvořili", style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 5),
            Text("Dominik S. a Max P.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[900])),

            SizedBox(height: 60),

            // COPYRIGHT
            Text(
              "© 2026 Javorník TimeRush",
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}