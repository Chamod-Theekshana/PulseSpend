# ── ML Kit text recognition (google_mlkit_text_recognition) ──────────────────
# The plugin's TextRecognizer.initialize() references every language-specific
# recognizer (Chinese / Devanagari / Japanese / Korean), but we only depend on
# the Latin model (see core/ocr/receipt_parser.dart → TextRecognizer(latin)).
# Those optional classes aren't on the classpath, so R8 fails the release build
# with "Missing class ...TextRecognizerOptions". Suppressing the warnings is the
# correct fix — pulling in the other models would bloat the APK for scripts we
# never use. The Latin recognizer is unaffected.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
