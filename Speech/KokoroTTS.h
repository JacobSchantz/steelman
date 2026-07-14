//
//  KokoroTTS.h
//  Steelman — on-device text-to-speech for the Discover feed
//
//  Pure Obj-C surface of a thin bridge over sherpa-onnx's offline-TTS C API,
//  used to run Kokoro-82M (Hexgrad, Apache-2.0) fully on-device — a non-Apple
//  replacement for the AVSpeechSynthesizer voice that reads arguments aloud.
//
//  All C++ / sherpa-onnx usage lives in KokoroTTS.mm; this header stays
//  Swift-safe so it can be imported through the app's bridging header. When the
//  sherpa-onnx xcframework is absent the bridge still compiles;
//  `isBackendAvailable` returns NO and load/generate fail with
//  `KokoroTTSErrorBackendUnavailable` instead of synthesizing.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const KokoroTTSErrorDomain;

typedef NS_ERROR_ENUM(KokoroTTSErrorDomain, KokoroTTSErrorCode) {
    /// Built without the sherpa-onnx xcframework linked in.
    KokoroTTSErrorBackendUnavailable = 1,
    /// The Kokoro model / voices / tokens / espeak data could not be loaded.
    KokoroTTSErrorModelLoadFailed = 2,
    /// `generate` was called before a successful `load`.
    KokoroTTSErrorNotLoaded = 3,
    /// sherpa-onnx returned no audio for the supplied text.
    KokoroTTSErrorGenerateFailed = 4,
};

/// Thin, synchronous Objective-C++ wrapper around one loaded Kokoro TTS engine.
/// Not thread-safe by itself; the Swift `SpeechRenderer` actor serializes calls.
@interface KokoroTTSBridge : NSObject

/// YES once `load…` has succeeded and the engine is resident.
@property (atomic, readonly) BOOL isLoaded;

/// YES when the binary was linked against the sherpa-onnx backend.
+ (BOOL)isBackendAvailable;

/// Builds the offline-TTS engine from the Kokoro model files. `modelPath` and
/// `voicesPath` are the downloaded weights; `tokensPath` and `dataDir` (the
/// espeak-ng-data directory) ship in the app bundle.
- (BOOL)loadWithModelPath:(NSString *)modelPath
               voicesPath:(NSString *)voicesPath
               tokensPath:(NSString *)tokensPath
                  dataDir:(NSString *)dataDir
                    error:(NSError **)error;

/// Synthesizes `text` and returns the raw mono Float32 PCM samples (host-endian)
/// as `NSData`. The output sample rate is written to `sampleRate` (Kokoro is
/// 24 kHz). Blocks the calling thread for the duration of synthesis.
- (nullable NSData *)generateForText:(NSString *)text
                           speakerId:(int)speakerId
                               speed:(float)speed
                          sampleRate:(int *)sampleRate
                               error:(NSError **)error;

/// Frees the resident engine. Idempotent.
- (void)unload;

@end

NS_ASSUME_NONNULL_END
