package com.shipeast.customerapp

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

// Flutter regenerates GeneratedPluginRegistrant.java with `catch (Exception e)` only,
// which does not catch UnsatisfiedLinkError (a java.lang.Error) from JNI native library
// loading failures. We register each plugin individually with catch (Throwable) so a
// failure in one plugin cannot prevent the rest from loading.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Firebase Core must be registered first — other Firebase plugins depend on it.
        registerPlugin(flutterEngine, "firebase_core") {
            flutterEngine.plugins.add(io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin())
        }
        registerPlugin(flutterEngine, "firebase_auth") {
            flutterEngine.plugins.add(io.flutter.plugins.firebase.auth.FlutterFirebaseAuthPlugin())
        }
        registerPlugin(flutterEngine, "cloud_firestore") {
            flutterEngine.plugins.add(io.flutter.plugins.firebase.firestore.FlutterFirebaseFirestorePlugin())
        }
        // P3-03: promo redemption is a callable function.
        registerPlugin(flutterEngine, "cloud_functions") {
            flutterEngine.plugins.add(io.flutter.plugins.firebase.functions.FlutterFirebaseFunctionsPlugin())
        }
        registerPlugin(flutterEngine, "firebase_storage") {
            flutterEngine.plugins.add(io.flutter.plugins.firebase.storage.FlutterFirebaseStoragePlugin())
        }
        registerPlugin(flutterEngine, "firebase_messaging") {
            flutterEngine.plugins.add(io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingPlugin())
        }
        registerPlugin(flutterEngine, "flutter_plugin_android_lifecycle") {
            flutterEngine.plugins.add(io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin())
        }
        registerPlugin(flutterEngine, "image_picker_android") {
            flutterEngine.plugins.add(io.flutter.plugins.imagepicker.ImagePickerPlugin())
        }
        registerPlugin(flutterEngine, "jni") {
            flutterEngine.plugins.add(com.github.dart_lang.jni.JniPlugin())
        }
        registerPlugin(flutterEngine, "jni_flutter") {
            flutterEngine.plugins.add(com.github.dart_lang.jni_flutter.JniFlutterPlugin())
        }
        registerPlugin(flutterEngine, "shared_preferences_android") {
            flutterEngine.plugins.add(io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin())
        }
        registerPlugin(flutterEngine, "url_launcher_android") {
            flutterEngine.plugins.add(io.flutter.plugins.urllauncher.UrlLauncherPlugin())
        }
        // Live delivery tracking reads the customer's own device location to show
        // how far the driver's GPS is. Missing this registration silently disables it.
        registerPlugin(flutterEngine, "geolocator_android") {
            flutterEngine.plugins.add(com.baseflow.geolocator.GeolocatorPlugin())
        }
        // Transitive dependency (local key/value cache). Present in Flutter's
        // generated registrant, so it must be registered here too.
        registerPlugin(flutterEngine, "sqflite_android") {
            flutterEngine.plugins.add(com.tekartik.sqflite.SqflitePlugin())
        }
    }

    private fun registerPlugin(flutterEngine: FlutterEngine, name: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.e("ShipEast", "Plugin $name failed to register: ${t.javaClass.simpleName}: ${t.message}", t)
        }
    }
}
