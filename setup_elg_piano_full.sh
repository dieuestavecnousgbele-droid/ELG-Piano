#!/usr/bin/env bash
# =============================================================================
#  ELG Piano - setup_elg_piano_full.sh
#  Étape 1 : clavier 88 touches + moteur audio Oboe/TinySoundFont + 2 SF2
#  Compilation prévue sur GitHub Actions (workflow généré).
#
#  Usage : placer ce script, Yamaha_C5_Pianoteq.sf2 et Bright_Synth.sf2 dans le
#          même dossier (racine du dépôt Git), puis :  bash setup_elg_piano_full.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${ELG_PIANO_DIR:-$SCRIPT_DIR}"
ASSETS_DIR="$PROJECT_DIR/app/src/main/assets/soundfonts"
CPP_DIR="$PROJECT_DIR/app/src/main/cpp"
PKG_DIR="$PROJECT_DIR/app/src/main/java/com/elg/piano"
UI_DIR="$PKG_DIR/ui"
RES_DIR="$PROJECT_DIR/app/src/main/res"
WORKFLOW_DIR="$PROJECT_DIR/.github/workflows"
SF2_FILES=("Yamaha_C5_Pianoteq.sf2" "Bright_Synth.sf2")
TSF_URL="https://raw.githubusercontent.com/schellingb/TinySoundFont/master/tsf.h"

log()  { printf '\033[1;34m[ELG Piano]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ATTENTION]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERREUR]\033[0m %s\n' "$*" >&2; exit 1; }

# Vérifie l'en-tête RIFF....sfbk d'un fichier SoundFont 2
is_sf2() {
  [ -f "$1" ] || return 1
  [ "$(head -c 4 "$1")" = "RIFF" ] || return 1
  [ "$(dd if="$1" bs=1 skip=8 count=4 2>/dev/null)" = "sfbk" ] || return 1
  return 0
}

# -----------------------------------------------------------------------------
# 1. SoundFonts : recherche, validation, copie dans assets
# -----------------------------------------------------------------------------
log "Étape 1/7 : SoundFonts"
mkdir -p "$ASSETS_DIR"
for f in "${SF2_FILES[@]}"; do
  target="$ASSETS_DIR/$f"
  if ! is_sf2 "$target"; then
    found=""
    for dir in "$SCRIPT_DIR" "$SCRIPT_DIR/soundfonts" "$PWD" "$PWD/soundfonts"; do
      if is_sf2 "$dir/$f"; then found="$dir/$f"; break; fi
    done
    [ -n "$found" ] || die "SoundFont introuvable ou invalide : $f (placez-le à côté du script)."
    cp "$found" "$target"
  fi
  log "  OK : $f ($(wc -c < "$target") octets)"
done

# -----------------------------------------------------------------------------
# 2. Racine Gradle
# -----------------------------------------------------------------------------
log "Étape 2/7 : fichiers Gradle"
mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/settings.gradle.kts" <<'EOF_SETTINGS'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ELG Piano"
include(":app")
EOF_SETTINGS

mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/build.gradle.kts" <<'EOF_ROOTGRADLE'
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
EOF_ROOTGRADLE

mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/gradle.properties" <<'EOF_GRADLEPROPS'
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
org.gradle.parallel=true
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
EOF_GRADLEPROPS

mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/.gitignore" <<'EOF_GITIGNORE'
*.iml
.gradle/
.idea/
build/
app/build/
local.properties
captures/
.externalNativeBuild/
.cxx/
*.apk
*.aab
EOF_GITIGNORE

mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" <<'EOF_APPGRADLE'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.elg.piano"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.elg.piano"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
                )
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        prefab = true
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Les SoundFonts ne sont pas recompressés : lecture/copie plus rapide.
    androidResources {
        noCompress += listOf("sf2")
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")

    implementation("com.google.oboe:oboe:1.9.3")
}
EOF_APPGRADLE

# -----------------------------------------------------------------------------
# 3. Code natif : Oboe + TinySoundFont
# -----------------------------------------------------------------------------
log "Étape 3/7 : moteur audio natif (C++)"
mkdir -p "$CPP_DIR"
cat > "$CPP_DIR/CMakeLists.txt" <<'EOF_CMAKE'
cmake_minimum_required(VERSION 3.22.1)
project(elgpiano LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tsf.h")
    message(FATAL_ERROR "tsf.h est introuvable dans app/src/main/cpp. Telechargez-le depuis https://github.com/schellingb/TinySoundFont (fichier tsf.h) ou relancez setup_elg_piano_full.sh avec acces Internet.")
endif()

find_package(oboe REQUIRED CONFIG)

add_library(elgpiano SHARED
    engine.cpp
    tsf_impl.cpp)

target_include_directories(elgpiano PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(elgpiano PRIVATE -O2 -Wall -Wno-unused-function)
target_link_options(elgpiano PRIVATE -Wl,-z,max-page-size=16384)
target_link_libraries(elgpiano oboe::oboe log)
EOF_CMAKE

mkdir -p "$CPP_DIR"
cat > "$CPP_DIR/tsf_impl.cpp" <<'EOF_TSFIMPL'
// Implémentation unique de TinySoundFont (en-tête tsf.h, licence MIT).
#define TSF_IMPLEMENTATION
#include "tsf.h"
EOF_TSFIMPL

mkdir -p "$CPP_DIR"
cat > "$CPP_DIR/engine.cpp" <<'EOF_ENGINE'
// ELG Piano - moteur audio : Oboe (sortie faible latence) + TinySoundFont (SF2).
//
// Règles de conception :
//  - Le thread audio ne fait ni allocation de SoundFont, ni verrou bloquant.
//  - Les notes arrivent par une file de commandes sans verrou côté lecteur.
//  - Les deux SoundFonts sont chargés une fois, puis seul un index change.

#include <jni.h>
#include <oboe/Oboe.h>
#include <android/log.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>

#include "tsf.h"

#define LOG_TAG "ELGPiano"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

constexpr int kMaxInstruments = 4;
constexpr uint32_t kQueueSize = 1024;  // puissance de 2
constexpr float kGainDb = -6.0f;       // marge pour la polyphonie

enum CommandType : int {
    CMD_NOTE_ON = 1,
    CMD_NOTE_OFF = 2,
    CMD_ALL_OFF = 3,
    CMD_SET_INSTRUMENT = 4
};

struct Command {
    int type;
    int a;    // note MIDI ou index d'instrument
    float b;  // vélocité 0..1
};

// File de commandes : plusieurs producteurs (protégés par un mutex que le
// thread audio ne prend jamais), un seul consommateur (thread audio).
class CommandQueue {
public:
    CommandQueue() : mHead(0), mTail(0) {}

    bool push(const Command& c) {
        std::lock_guard<std::mutex> lock(mProducerMutex);
        const uint32_t head = mHead.load(std::memory_order_relaxed);
        const uint32_t next = (head + 1) & (kQueueSize - 1);
        if (next == mTail.load(std::memory_order_acquire)) return false;  // pleine
        mBuffer[head] = c;
        mHead.store(next, std::memory_order_release);
        return true;
    }

    bool pop(Command& c) {
        const uint32_t tail = mTail.load(std::memory_order_relaxed);
        if (tail == mHead.load(std::memory_order_acquire)) return false;  // vide
        c = mBuffer[tail];
        mTail.store((tail + 1) & (kQueueSize - 1), std::memory_order_release);
        return true;
    }

private:
    Command mBuffer[kQueueSize];
    std::atomic<uint32_t> mHead;
    std::atomic<uint32_t> mTail;
    std::mutex mProducerMutex;
};

class Engine;

class DataCallback : public oboe::AudioStreamDataCallback {
public:
    explicit DataCallback(Engine* engine) : mEngine(engine) {}
    oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream,
                                          void* audioData,
                                          int32_t numFrames) override;

private:
    Engine* mEngine;
};

class ErrorCallback : public oboe::AudioStreamErrorCallback {
public:
    explicit ErrorCallback(Engine* engine) : mEngine(engine) {}
    void onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) override;

private:
    Engine* mEngine;
};

class Engine {
public:
    Engine()
        : mDataCb(std::make_shared<DataCallback>(this)),
          mErrCb(std::make_shared<ErrorCallback>(this)),
          mSampleRate(0),
          mStopped(false),
          mPaused(false),
          mActive(0) {
        for (int i = 0; i < kMaxInstruments; ++i) mFonts[i].store(nullptr);
    }

    ~Engine() { stop(); }

    // Ouvre le flux audio. Retourne la fréquence d'échantillonnage, ou 0 si échec.
    int start() {
        std::lock_guard<std::mutex> lock(mStreamMutex);
        mStopped = false;
        if (mStream) return mSampleRate.load();
        return openStreamLocked() ? mSampleRate.load() : 0;
    }

    void stop() {
        std::lock_guard<std::mutex> lock(mStreamMutex);
        mStopped = true;
        if (mStream) {
            mStream->requestStop();
            mStream->close();
            mStream.reset();
        }
        for (int i = 0; i < kMaxInstruments; ++i) {
            tsf* f = mFonts[i].exchange(nullptr);
            if (f) tsf_close(f);
        }
    }

    void pause() {
        std::lock_guard<std::mutex> lock(mStreamMutex);
        mPaused = true;
        if (mStream) mStream->requestPause();
    }

    void resume() {
        std::lock_guard<std::mutex> lock(mStreamMutex);
        mPaused = false;
        if (mStream) mStream->requestStart();
    }

    // Charge un SoundFont depuis un fichier (appelé hors thread audio).
    bool loadFont(int index, const char* path) {
        if (index < 0 || index >= kMaxInstruments || path == nullptr) return false;
        if (mFonts[index].load(std::memory_order_acquire) != nullptr) return true;
        const int rate = mSampleRate.load();
        if (rate <= 0) {
            LOGE("loadFont: flux audio non démarré");
            return false;
        }
        tsf* f = tsf_load_filename(path);
        if (f == nullptr) {
            LOGE("loadFont: échec de lecture de %s", path);
            return false;
        }
        tsf_set_output(f, TSF_STEREO_INTERLEAVED, rate, kGainDb);
        mFonts[index].store(f, std::memory_order_release);
        LOGI("SoundFont %d chargé (%d Hz)", index, rate);
        return true;
    }

    void send(int type, int a, float b) {
        Command c;
        c.type = type;
        c.a = a;
        c.b = b;
        mQueue.push(c);
    }

    // Appelé uniquement par le thread audio.
    void render(float* out, int32_t frames) {
        Command c;
        while (mQueue.pop(c)) {
            tsf* cur = mFonts[mActive].load(std::memory_order_acquire);
            switch (c.type) {
                case CMD_NOTE_ON:
                    if (cur) tsf_note_on(cur, 0, c.a, c.b);
                    break;
                case CMD_NOTE_OFF:
                    if (cur) tsf_note_off(cur, 0, c.a);
                    break;
                case CMD_ALL_OFF:
                    if (cur) tsf_note_off_all(cur);
                    break;
                case CMD_SET_INSTRUMENT:
                    if (c.a >= 0 && c.a < kMaxInstruments && c.a != mActive) {
                        if (cur) tsf_reset(cur);  // coupe net l'ancien instrument
                        mActive = c.a;
                    }
                    break;
                default:
                    break;
            }
        }

        tsf* font = mFonts[mActive].load(std::memory_order_acquire);
        const int32_t samples = frames * 2;
        if (font == nullptr) {
            std::memset(out, 0, sizeof(float) * static_cast<size_t>(samples));
            return;
        }
        tsf_render_float(font, out, frames, 0);
        for (int32_t i = 0; i < samples; ++i) {
            if (out[i] > 1.0f) out[i] = 1.0f;
            else if (out[i] < -1.0f) out[i] = -1.0f;
        }
    }

    // Réouverture après déconnexion (casque débranché, changement de sortie...).
    void reopen() {
        std::unique_lock<std::mutex> lock(mStreamMutex, std::try_to_lock);
        if (!lock.owns_lock() || mStopped) return;
        mStream.reset();
        if (!openStreamLocked()) LOGE("reopen: échec");
    }

private:
    bool openStreamLocked() {
        oboe::AudioStreamBuilder builder;
        builder.setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setSharingMode(oboe::SharingMode::Exclusive)
            ->setFormat(oboe::AudioFormat::Float)
            ->setChannelCount(oboe::ChannelCount::Stereo)
            ->setUsage(oboe::Usage::Media)
            ->setContentType(oboe::ContentType::Music)
            ->setDataCallback(mDataCb)
            ->setErrorCallback(mErrCb);

        const oboe::Result result = builder.openStream(mStream);
        if (result != oboe::Result::OK) {
            LOGE("openStream: %s", oboe::convertToText(result));
            mStream.reset();
            return false;
        }

        mSampleRate.store(mStream->getSampleRate());
        mStream->setBufferSizeInFrames(mStream->getFramesPerBurst() * 2);

        // Le flux n'est pas encore démarré : on peut ajuster les SoundFonts sans risque.
        for (int i = 0; i < kMaxInstruments; ++i) {
            tsf* f = mFonts[i].load(std::memory_order_acquire);
            if (f) tsf_set_output(f, TSF_STEREO_INTERLEAVED, mSampleRate.load(), kGainDb);
        }

        if (!mPaused) {
            const oboe::Result startResult = mStream->requestStart();
            if (startResult != oboe::Result::OK) {
                LOGE("requestStart: %s", oboe::convertToText(startResult));
                mStream->close();
                mStream.reset();
                return false;
            }
        }
        LOGI("Flux audio ouvert : %d Hz, burst %d trames",
             mSampleRate.load(), mStream->getFramesPerBurst());
        return true;
    }

    std::shared_ptr<DataCallback> mDataCb;
    std::shared_ptr<ErrorCallback> mErrCb;
    std::shared_ptr<oboe::AudioStream> mStream;
    std::mutex mStreamMutex;
    std::atomic<int> mSampleRate;
    std::atomic<bool> mStopped;
    std::atomic<bool> mPaused;
    std::atomic<tsf*> mFonts[kMaxInstruments];
    CommandQueue mQueue;
    int mActive;  // lu/écrit uniquement par le thread audio
};

oboe::DataCallbackResult DataCallback::onAudioReady(oboe::AudioStream*,
                                                    void* audioData,
                                                    int32_t numFrames) {
    mEngine->render(static_cast<float*>(audioData), numFrames);
    return oboe::DataCallbackResult::Continue;
}

void ErrorCallback::onErrorAfterClose(oboe::AudioStream*, oboe::Result error) {
    LOGE("Flux fermé sur erreur : %s", oboe::convertToText(error));
    mEngine->reopen();
}

std::mutex gEngineMutex;
std::shared_ptr<Engine> gEngine;

std::shared_ptr<Engine> getEngine() {
    std::lock_guard<std::mutex> lock(gEngineMutex);
    return gEngine;
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_com_elg_piano_NativeEngine_nativeStart(JNIEnv*, jobject) {
    std::shared_ptr<Engine> engine;
    {
        std::lock_guard<std::mutex> lock(gEngineMutex);
        if (!gEngine) gEngine = std::make_shared<Engine>();
        engine = gEngine;
    }
    return static_cast<jint>(engine->start());
}

JNIEXPORT void JNICALL
Java_com_elg_piano_NativeEngine_nativeStop(JNIEnv*, jobject) {
    std::shared_ptr<Engine> engine;
    {
        std::lock_guard<std::mutex> lock(gEngineMutex);
        engine = std::move(gEngine);
        gEngine.reset();
    }
    if (engine) engine->stop();
}

JNIEXPORT void JNICALL
Java_com_elg_piano_NativeEngine_nativePause(JNIEnv*, jobject) {
    std::shared_ptr<Engine> engine = getEngine();
    if (engine) engine->pause();
}

JNIEXPORT void JNICALL
Java_com_elg_piano_NativeEngine_nativeResume(JNIEnv*, jobject) {
    std::shared_ptr<Engine> engine = getEngine();
    if (engine) engine->resume();
}

JNIEXPORT jboolean JNICALL
Java_com_elg_piano_NativeEngine_nativeLoad(JNIEnv* env, jobject, jint index, jstring path) {
    std::shared_ptr<Engine> engine = getEngine();
    if (!engine || path == nullptr) return JNI_FALSE;
    const char* cpath = env->GetStringUTFChars(path, nullptr);
    if (cpath == nullptr) return JNI_FALSE;
    const bool ok = engine->loadFont(static_cast<int>(index), cpath);
    env->ReleaseStringUTFChars(path, cpath);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_elg_piano_NativeEngine_nativeNoteOn(JNIEnv*, jobject, jint note, jfloat velocity) {
    std::shared_ptr<Engine> engine = getEngine();
    if (!engine || note < 0 || note > 127) return;
    float v = velocity;
    if (v < 0.05f) v = 0.05f;
    if (v > 1.0f) v = 1.0f;
    engine->send(CMD_NOTE_ON, static_cast<int>(note), v);
}

JNIEXPORT void JNICALL
Java_com_elg_piano_NativeEngine_nativeNoteOff(JNIEnv*, jobject, jint note) {
    std::shared_ptr<Engine> engine = getEngine();
    if (!engine || note < 0 || note > 127) return;
    engine->send(CMD_NOTE_OFF, static_cast<int>(note), 0.0f);
}

JNIEXPORT void JNICALL
Java_com_elg_piano_NativeEngine_nativeAllNotesOff(JNIEnv*, jobject) {
    std::shared_ptr<Engine> engine = getEngine();
    if (engine) engine->send(CMD_ALL_OFF, 0, 0.0f);
}

JNIEXPORT void JNICALL
Java_com_elg_piano_NativeEngine_nativeSetInstrument(JNIEnv*, jobject, jint index) {
    std::shared_ptr<Engine> engine = getEngine();
    if (engine) engine->send(CMD_SET_INSTRUMENT, static_cast<int>(index), 0.0f);
}

}  // extern "C"
EOF_ENGINE

# TinySoundFont : en-tête unique téléchargé (le workflow GitHub le re-télécharge s'il manque)
mkdir -p "$CPP_DIR"
if [ -s "$CPP_DIR/tsf.h" ] && grep -q "TSF_IMPLEMENTATION" "$CPP_DIR/tsf.h"; then
  log "  tsf.h déjà présent"
elif command -v curl >/dev/null 2>&1 && curl -fsSL --max-time 60 -o "$CPP_DIR/tsf.h" "$TSF_URL" && grep -q "TSF_IMPLEMENTATION" "$CPP_DIR/tsf.h"; then
  log "  tsf.h téléchargé"
else
  rm -f "$CPP_DIR/tsf.h"
  warn "tsf.h non téléchargé (pas d'accès réseau). Le workflow GitHub Actions le téléchargera automatiquement."
fi

# -----------------------------------------------------------------------------
# 4. Code Kotlin
# -----------------------------------------------------------------------------
log "Étape 4/7 : code Kotlin"
mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/Instrument.kt" <<'EOF_INSTRUMENT'
package com.elg.piano

/**
 * Les deux instruments embarqués. L'ordinal sert d'index côté moteur natif.
 */
enum class Instrument(val label: String, val assetName: String) {
    GRAND_PIANO("Piano à queue", "Yamaha_C5_Pianoteq.sf2"),
    BRIGHT_SYNTH("Synthé brillant", "Bright_Synth.sf2")
}
EOF_INSTRUMENT

mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/NativeEngine.kt" <<'EOF_NATIVEENGINE'
package com.elg.piano

/**
 * Pont JNI vers le moteur Oboe + TinySoundFont (libelgpiano.so).
 */
object NativeEngine {
    init {
        System.loadLibrary("elgpiano")
    }

    /** Ouvre le flux audio. Retourne la fréquence d'échantillonnage, ou 0 en cas d'échec. */
    external fun nativeStart(): Int
    external fun nativeStop()
    external fun nativePause()
    external fun nativeResume()
    external fun nativeLoad(index: Int, path: String): Boolean
    external fun nativeNoteOn(note: Int, velocity: Float)
    external fun nativeNoteOff(note: Int)
    external fun nativeAllNotesOff()
    external fun nativeSetInstrument(index: Int)
}
EOF_NATIVEENGINE

mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/SoundFontInstaller.kt" <<'EOF_INSTALLER'
package com.elg.piano

import android.content.Context
import java.io.File
import java.io.IOException

/**
 * Copie les SoundFonts embarqués (assets) vers le stockage interne de l'application.
 * La copie est refaite à chaque nouvelle version de l'application.
 * Aucun fichier fourni par l'utilisateur n'est accepté.
 */
object SoundFontInstaller {
    private const val ASSET_DIR = "soundfonts"
    private const val MARKER = ".installed_version"

    fun install(context: Context): Map<Instrument, File> {
        val dir = File(context.filesDir, ASSET_DIR)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IOException("Impossible de créer le dossier ${dir.absolutePath}")
        }

        val version = currentVersionCode(context).toString()
        val marker = File(dir, MARKER)
        val upToDate = marker.exists() && marker.readText().trim() == version

        val result = LinkedHashMap<Instrument, File>()
        for (instrument in Instrument.entries) {
            val target = File(dir, instrument.assetName)
            if (!upToDate || !target.exists() || target.length() == 0L) {
                val temp = File(dir, instrument.assetName + ".tmp")
                context.assets.open("$ASSET_DIR/${instrument.assetName}").use { input ->
                    temp.outputStream().use { output -> input.copyTo(output, 256 * 1024) }
                }
                if (target.exists() && !target.delete()) {
                    throw IOException("Impossible de remplacer ${target.name}")
                }
                if (!temp.renameTo(target)) {
                    throw IOException("Impossible de finaliser ${target.name}")
                }
            }
            checkSoundFontHeader(target)
            result[instrument] = target
        }
        marker.writeText(version)
        return result
    }

    private fun checkSoundFontHeader(file: File) {
        val header = ByteArray(12)
        file.inputStream().use { stream ->
            var read = 0
            while (read < header.size) {
                val n = stream.read(header, read, header.size - read)
                if (n < 0) break
                read += n
            }
            if (read < header.size) throw IOException("${file.name} est tronqué")
        }
        val riff = String(header, 0, 4, Charsets.ISO_8859_1)
        val form = String(header, 8, 4, Charsets.ISO_8859_1)
        if (riff != "RIFF" || form != "sfbk") {
            throw IOException("${file.name} n'est pas un SoundFont 2 valide")
        }
    }

    @Suppress("DEPRECATION")
    private fun currentVersionCode(context: Context): Long =
        context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode
}
EOF_INSTALLER

mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/PianoViewModel.kt" <<'EOF_VIEWMODEL'
package com.elg.piano

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PianoUiState(
    val instrument: Instrument = Instrument.GRAND_PIANO,
    val loaded: Set<Instrument> = emptySet(),
    val pressed: Set<Int> = emptySet(),
    val error: String? = null
)

class PianoViewModel(application: Application) : AndroidViewModel(application) {

    private val _state = MutableStateFlow(PianoUiState())
    val state: StateFlow<PianoUiState> = _state.asStateFlow()

    // Nombre de doigts posés par note (appelé uniquement depuis le thread principal).
    private val pressCount = IntArray(128)

    init {
        viewModelScope.launch(Dispatchers.IO) { boot() }
    }

    private fun boot() {
        try {
            val files = SoundFontInstaller.install(getApplication())
            val sampleRate = NativeEngine.nativeStart()
            if (sampleRate <= 0) throw IllegalStateException("Moteur audio indisponible")

            for (instrument in Instrument.entries) {
                val path = files.getValue(instrument).absolutePath
                if (!NativeEngine.nativeLoad(instrument.ordinal, path)) {
                    throw IllegalStateException("Échec du chargement : ${instrument.label}")
                }
                if (instrument == _state.value.instrument) {
                    NativeEngine.nativeSetInstrument(instrument.ordinal)
                }
                _state.update { it.copy(loaded = it.loaded + instrument) }
            }
        } catch (e: Exception) {
            _state.update { it.copy(error = e.message ?: "Erreur inconnue") }
        }
    }

    fun noteOn(note: Int, velocity: Float) {
        if (note !in 0..127) return
        pressCount[note]++
        NativeEngine.nativeNoteOn(note, velocity)
        _state.update { it.copy(pressed = it.pressed + note) }
    }

    fun noteOff(note: Int) {
        if (note !in 0..127 || pressCount[note] == 0) return
        pressCount[note]--
        if (pressCount[note] == 0) {
            NativeEngine.nativeNoteOff(note)
            _state.update { it.copy(pressed = it.pressed - note) }
        }
    }

    fun selectInstrument(instrument: Instrument) {
        val current = _state.value
        if (instrument == current.instrument || instrument !in current.loaded) return
        releaseAll()
        NativeEngine.nativeSetInstrument(instrument.ordinal)
        _state.update { it.copy(instrument = instrument) }
    }

    fun onAppBackground() {
        releaseAll()
        NativeEngine.nativePause()
    }

    fun onAppForeground() {
        NativeEngine.nativeResume()
    }

    private fun releaseAll() {
        pressCount.fill(0)
        NativeEngine.nativeAllNotesOff()
        _state.update { it.copy(pressed = emptySet()) }
    }

    override fun onCleared() {
        NativeEngine.nativeStop()
        super.onCleared()
    }
}
EOF_VIEWMODEL

mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/MainActivity.kt" <<'EOF_MAINACTIVITY'
package com.elg.piano

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.elg.piano.ui.ElgPianoTheme
import com.elg.piano.ui.PianoScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent {
            ElgPianoTheme {
                PianoScreen()
            }
        }
    }
}
EOF_MAINACTIVITY

mkdir -p "$UI_DIR"
cat > "$UI_DIR/Theme.kt" <<'EOF_THEME'
package com.elg.piano.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

@Composable
fun ElgPianoTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Color(0xFF7FB2FF),
            background = Color(0xFF121214),
            surface = Color(0xFF1C1C1E)
        ),
        content = content
    )
}
EOF_THEME

mkdir -p "$UI_DIR"
cat > "$UI_DIR/PianoKeyboard.kt" <<'EOF_KEYBOARD'
package com.elg.piano.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp

const val FIRST_NOTE = 21        // A0
const val LAST_NOTE = 108        // C8
const val WHITE_KEY_COUNT = 52   // touches blanches d'un clavier de 88 touches
private const val INITIAL_LEFT_NOTE = 48  // C3 affiché à gauche au démarrage

private val BLACK_PITCH_CLASSES = setOf(1, 3, 6, 8, 10)

class KeyRect(val midi: Int, val x: Float, val width: Float)

/** Géométrie du clavier 88 touches, en pixels. */
class KeyboardLayout(val whiteWidth: Float, val height: Float) {
    val blackWidth: Float = whiteWidth * 0.62f
    val blackHeight: Float = height * 0.62f
    val totalWidth: Float = whiteWidth * WHITE_KEY_COUNT
    val whites: List<KeyRect>
    val blacks: List<KeyRect>

    init {
        val whiteList = ArrayList<KeyRect>(WHITE_KEY_COUNT)
        val blackList = ArrayList<KeyRect>(36)
        var whiteIndex = 0
        for (midi in FIRST_NOTE..LAST_NOTE) {
            if (midi % 12 in BLACK_PITCH_CLASSES) {
                blackList.add(KeyRect(midi, whiteIndex * whiteWidth - blackWidth / 2f, blackWidth))
            } else {
                whiteList.add(KeyRect(midi, whiteIndex * whiteWidth, whiteWidth))
                whiteIndex++
            }
        }
        whites = whiteList
        blacks = blackList
    }

    /** Note MIDI sous le point (x, y), ou null en dehors du clavier. */
    fun hit(x: Float, y: Float): Int? {
        if (x < 0f || x >= totalWidth || y < 0f || y > height) return null
        if (y <= blackHeight) {
            for (key in blacks) {
                if (x >= key.x && x < key.x + key.width) return key.midi
            }
        }
        val index = (x / whiteWidth).toInt().coerceIn(0, whites.size - 1)
        return whites[index].midi
    }
}

private fun velocityFor(y: Float, height: Float): Float =
    (0.45f + 0.55f * (y / height)).coerceIn(0.3f, 1f)

/**
 * Clavier 88 touches multi-touch. Le défilement horizontal est piloté par le
 * [scrollState] (curseur et boutons d'octave), jamais par le doigt, afin que
 * le jeu ne soit pas perturbé par un geste de défilement.
 */
@Composable
fun PianoKeyboard(
    pressed: Set<Int>,
    visibleWhiteKeys: Int,
    scrollState: ScrollState,
    onNoteOn: (Int, Float) -> Unit,
    onNoteOff: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(modifier = modifier) {
        val density = LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val layout = remember(widthPx, heightPx, visibleWhiteKeys) {
            KeyboardLayout(widthPx / visibleWhiteKeys, heightPx)
        }
        val totalWidthDp = with(density) { layout.totalWidth.toDp() }
        val textMeasurer = rememberTextMeasurer()
        val noteOnState by rememberUpdatedState(onNoteOn)
        val noteOffState by rememberUpdatedState(onNoteOff)

        var initialScrollDone by remember { mutableStateOf(false) }
        LaunchedEffect(scrollState.maxValue, layout) {
            if (!initialScrollDone && scrollState.maxValue > 0) {
                val key = layout.whites.firstOrNull { it.midi == INITIAL_LEFT_NOTE }
                if (key != null) {
                    scrollState.scrollTo(key.x.toInt().coerceIn(0, scrollState.maxValue))
                }
                initialScrollDone = true
            }
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .horizontalScroll(scrollState, enabled = false)
        ) {
            Canvas(
                modifier = Modifier
                    .width(totalWidthDp)
                    .fillMaxHeight()
                    .pointerInput(layout) {
                        val active = HashMap<PointerId, Int>()
                        try {
                            awaitPointerEventScope {
                                while (true) {
                                    val event = awaitPointerEvent()
                                    for (change in event.changes) {
                                        val current = active[change.id]
                                        if (change.pressed) {
                                            val note = layout.hit(change.position.x, change.position.y)
                                            val velocity = velocityFor(change.position.y, layout.height)
                                            if (current == null) {
                                                if (note != null) {
                                                    active[change.id] = note
                                                    noteOnState(note, velocity)
                                                }
                                            } else if (note != current) {
                                                noteOffState(current)
                                                if (note != null) {
                                                    active[change.id] = note
                                                    noteOnState(note, velocity)
                                                } else {
                                                    active.remove(change.id)
                                                }
                                            }
                                            change.consume()
                                        } else if (current != null) {
                                            noteOffState(current)
                                            active.remove(change.id)
                                            change.consume()
                                        }
                                    }
                                }
                            }
                        } finally {
                            for (note in active.values) noteOffState(note)
                            active.clear()
                        }
                    }
            ) {
                val labelStyle = TextStyle(color = Color(0xFF7A7A7A), fontSize = 11.sp)

                for (key in layout.whites) {
                    val isPressed = key.midi in pressed
                    drawRect(
                        color = if (isPressed) Color(0xFF9CC4FF) else Color(0xFFF8F8F4),
                        topLeft = Offset(key.x, 0f),
                        size = Size(key.width, size.height)
                    )
                    drawRect(
                        color = Color(0xFF3A3A3A),
                        topLeft = Offset(key.x, 0f),
                        size = Size(key.width, size.height),
                        style = Stroke(width = 1.5f)
                    )
                    if (key.midi % 12 == 0) {
                        drawText(
                            textMeasurer = textMeasurer,
                            text = "C${key.midi / 12 - 1}",
                            topLeft = Offset(key.x + 6f, size.height - 34f),
                            style = labelStyle
                        )
                    }
                }

                for (key in layout.blacks) {
                    val isPressed = key.midi in pressed
                    drawRoundRect(
                        color = if (isPressed) Color(0xFF4F83CC) else Color(0xFF1A1A1C),
                        topLeft = Offset(key.x, 0f),
                        size = Size(key.width, layout.blackHeight),
                        cornerRadius = CornerRadius(6f, 6f)
                    )
                }
            }
        }
    }
}
EOF_KEYBOARD

mkdir -p "$UI_DIR"
cat > "$UI_DIR/PianoScreen.kt" <<'EOF_SCREEN'
package com.elg.piano.ui

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.elg.piano.Instrument
import com.elg.piano.PianoViewModel
import kotlinx.coroutines.launch

@Composable
fun PianoScreen(viewModel: PianoViewModel = viewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val visibleWhiteKeys = if (landscape) 14 else 8

    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { viewModel.onAppBackground() }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { viewModel.onAppForeground() }

    fun shiftOctave(direction: Int) {
        scope.launch {
            val whiteWidth = scrollState.maxValue.toFloat() / (WHITE_KEY_COUNT - visibleWhiteKeys)
            val target = (scrollState.value + direction * 7 * whiteWidth).toInt()
            scrollState.animateScrollTo(target.coerceIn(0, scrollState.maxValue))
        }
    }

    val error = state.error
    val currentReady = state.instrument in state.loaded

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF121214))
            .safeDrawingPadding()
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "ELG Piano",
                color = Color.White,
                style = MaterialTheme.typography.titleLarge
            )
            Spacer(modifier = Modifier.weight(1f))
            for (instrument in Instrument.entries) {
                FilterChip(
                    selected = state.instrument == instrument,
                    enabled = instrument in state.loaded,
                    onClick = { viewModel.selectInstrument(instrument) },
                    label = { Text(instrument.label) }
                )
            }
        }

        if (error != null) {
            Text(
                text = error,
                color = Color(0xFFFF8A80),
                modifier = Modifier.padding(vertical = 8.dp)
            )
        } else if (!currentReady) {
            Row(
                modifier = Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Text(text = "Chargement des sons…", color = Color.LightGray)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(onClick = { shiftOctave(-1) }) { Text("◀ Octave") }
            val fraction =
                if (scrollState.maxValue > 0) scrollState.value.toFloat() / scrollState.maxValue else 0f
            Slider(
                value = fraction,
                onValueChange = { value ->
                    scope.launch { scrollState.scrollTo((value * scrollState.maxValue).toInt()) }
                },
                modifier = Modifier.weight(1f)
            )
            OutlinedButton(onClick = { shiftOctave(1) }) { Text("Octave ▶") }
        }

        PianoKeyboard(
            pressed = state.pressed,
            visibleWhiteKeys = visibleWhiteKeys,
            scrollState = scrollState,
            onNoteOn = viewModel::noteOn,
            onNoteOff = viewModel::noteOff,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(top = 4.dp)
        )
    }
}
EOF_SCREEN

# -----------------------------------------------------------------------------
# 5. Manifeste et ressources
# -----------------------------------------------------------------------------
log "Étape 5/7 : manifeste et ressources"
mkdir -p "$PROJECT_DIR/app/src/main"
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<'EOF_MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.ELGPiano">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|smallestScreenSize"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF_MANIFEST

mkdir -p "$RES_DIR/values"
cat > "$RES_DIR/values/strings.xml" <<'EOF_STRINGS'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">ELG Piano</string>
</resources>
EOF_STRINGS

mkdir -p "$RES_DIR/values"
cat > "$RES_DIR/values/colors.xml" <<'EOF_COLORS'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1F3A5F</color>
    <color name="window_background">#121214</color>
</resources>
EOF_COLORS

mkdir -p "$RES_DIR/values"
cat > "$RES_DIR/values/themes.xml" <<'EOF_THEMES'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.ELGPiano" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">@color/window_background</item>
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/transparent</item>
    </style>
</resources>
EOF_THEMES

mkdir -p "$RES_DIR/drawable"
cat > "$RES_DIR/drawable/ic_launcher_foreground.xml" <<'EOF_ICONFG'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#F5F5F0"
        android:pathData="M30,34h48v40h-48z" />
    <path
        android:fillColor="#1C1C1E"
        android:pathData="M38,34h6v24h-6z M51,34h6v24h-6z M64,34h6v24h-6z" />
</vector>
EOF_ICONFG

mkdir -p "$RES_DIR/mipmap-anydpi-v26"
cat > "$RES_DIR/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF_ICON'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
EOF_ICON

# -----------------------------------------------------------------------------
# 6. Workflow GitHub Actions
# -----------------------------------------------------------------------------
log "Étape 6/7 : workflow GitHub Actions"
mkdir -p "$WORKFLOW_DIR"
cat > "$WORKFLOW_DIR/build-apk.yml" <<'EOF_WORKFLOW'
name: Build ELG Piano APK

on:
  push:
    branches: [ main, master ]
  pull_request:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 45

    steps:
      - name: Récupérer le dépôt
        uses: actions/checkout@v4
        with:
          lfs: true

      - name: Installer Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Vérifier les SoundFonts
        run: |
          for f in Yamaha_C5_Pianoteq.sf2 Bright_Synth.sf2; do
            p="app/src/main/assets/soundfonts/$f"
            test -s "$p" || { echo "SoundFont manquant : $p"; exit 1; }
            test "$(head -c 4 "$p")" = "RIFF" || { echo "Fichier invalide (pointeur LFS ?) : $p"; exit 1; }
          done

      - name: Télécharger TinySoundFont si absent
        run: |
          if [ ! -s app/src/main/cpp/tsf.h ]; then
            curl -fsSL -o app/src/main/cpp/tsf.h \
              https://raw.githubusercontent.com/schellingb/TinySoundFont/master/tsf.h
          fi
          grep -q TSF_IMPLEMENTATION app/src/main/cpp/tsf.h

      - name: Installer SDK, NDK et CMake
        run: |
          SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
          yes | "$SDKMANAGER" --licenses > /dev/null || true
          "$SDKMANAGER" "platforms;android-35" "build-tools;35.0.0" "ndk;27.0.12077973" "cmake;3.22.1"

      - name: Installer Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.9'

      - name: Compiler l'APK de debug
        run: gradle --no-daemon assembleDebug

      - name: Publier l'APK
        uses: actions/upload-artifact@v4
        with:
          name: ELG-Piano-debug-apk
          path: app/build/outputs/apk/debug/*.apk
          if-no-files-found: error
EOF_WORKFLOW

# -----------------------------------------------------------------------------
# 7. Contrôles finaux
# -----------------------------------------------------------------------------
log "Étape 7/7 : contrôles"
for required in \
  "$PROJECT_DIR/settings.gradle.kts" \
  "$PROJECT_DIR/build.gradle.kts" \
  "$PROJECT_DIR/app/build.gradle.kts" \
  "$CPP_DIR/CMakeLists.txt" \
  "$CPP_DIR/engine.cpp" \
  "$CPP_DIR/tsf_impl.cpp" \
  "$PKG_DIR/MainActivity.kt" \
  "$PKG_DIR/PianoViewModel.kt" \
  "$UI_DIR/PianoKeyboard.kt" \
  "$UI_DIR/PianoScreen.kt" \
  "$PROJECT_DIR/app/src/main/AndroidManifest.xml" \
  "$WORKFLOW_DIR/build-apk.yml"; do
  [ -s "$required" ] || die "Fichier non généré : $required"
done

if command -v xmllint >/dev/null 2>&1; then
  while IFS= read -r xml; do
    xmllint --noout "$xml" || die "XML invalide : $xml"
  done < <(find "$PROJECT_DIR/app/src/main" -name '*.xml' -type f)
  log "  XML valides (xmllint)"
else
  warn "xmllint absent : validation XML ignorée."
fi

total_size=$(du -sk "$ASSETS_DIR" | cut -f1)
log "Projet ELG Piano généré dans : $PROJECT_DIR"
log "  SoundFonts embarqués : ${total_size} Ko"
log "Suite : git add -A && git commit -m \"ELG Piano - étape 1\" && git push"
log "Puis récupérez l'APK dans l'onglet Actions > ELG-Piano-debug-apk."
