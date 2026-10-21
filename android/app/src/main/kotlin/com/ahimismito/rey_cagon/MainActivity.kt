package com.ahimismito.rey_cagon

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // De extremo a extremo en todas las versiones, no solo en Android 15+ (lo que pide Play).
        // Flutter reparte los bordes del sistema con SafeArea y Scaffold.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}
