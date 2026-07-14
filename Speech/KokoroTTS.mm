//
//  KokoroTTS.mm
//  Steelman — on-device text-to-speech for the Discover feed
//
//  Objective-C++ implementation of `KokoroTTSBridge` over sherpa-onnx's
//  offline-TTS C API, running Kokoro-82M on-device. All C++ is confined to this
//  translation unit so no Swift file ever sees a sherpa-onnx header.
//
//  Guarded behind `__has_include` of the sherpa-onnx C API header so the target
//  still compiles (to a stub) if the xcframework isn't linked. In that case
//  `isBackendAvailable` returns NO and `SpeechRenderer` falls back to
//  AVSpeechSynthesizer rather than failing — the app always speaks.
//

#import "KokoroTTS.h"

#if __has_include(<sherpa-onnx/c-api/c-api.h>)
  #define KOKORO_HAVE_BACKEND 1
  #import <sherpa-onnx/c-api/c-api.h>
#elif __has_include("sherpa-onnx/c-api/c-api.h")
  #define KOKORO_HAVE_BACKEND 1
  #import "sherpa-onnx/c-api/c-api.h"
#elif __has_include(<c-api.h>) || __has_include("c-api.h")
  #define KOKORO_HAVE_BACKEND 1
  #if __has_include(<c-api.h>)
    #import <c-api.h>
  #else
    #import "c-api.h"
  #endif
#else
  #define KOKORO_HAVE_BACKEND 0
#endif

#import <Foundation/Foundation.h>

NSErrorDomain const KokoroTTSErrorDomain = @"KokoroTTSErrorDomain";

static NSError *KokoroTTSMakeError(KokoroTTSErrorCode code, NSString *message) {
    return [NSError errorWithDomain:KokoroTTSErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@implementation KokoroTTSBridge {
#if KOKORO_HAVE_BACKEND
    const SherpaOnnxOfflineTts *_tts;
#endif
    BOOL _isLoaded;
}

+ (BOOL)isBackendAvailable {
    return KOKORO_HAVE_BACKEND ? YES : NO;
}

- (BOOL)isLoaded {
    return _isLoaded;
}

- (BOOL)loadWithModelPath:(NSString *)modelPath
               voicesPath:(NSString *)voicesPath
               tokensPath:(NSString *)tokensPath
                  dataDir:(NSString *)dataDir
                    error:(NSError **)error {
#if KOKORO_HAVE_BACKEND
    if (_isLoaded) { [self unload]; }

    SherpaOnnxOfflineTtsConfig config;
    memset(&config, 0, sizeof(config));

    config.model.kokoro.model    = modelPath.fileSystemRepresentation;
    config.model.kokoro.voices   = voicesPath.fileSystemRepresentation;
    config.model.kokoro.tokens   = tokensPath.fileSystemRepresentation;
    config.model.kokoro.data_dir = dataDir.fileSystemRepresentation;
    config.model.num_threads     = (int) MAX(1, [[NSProcessInfo processInfo] activeProcessorCount] - 1);
    config.model.provider        = "cpu";
    config.model.debug           = 0;
    config.max_num_sentences     = 1;

    _tts = SherpaOnnxCreateOfflineTts(&config);
    if (_tts == NULL) {
        if (error) *error = KokoroTTSMakeError(KokoroTTSErrorModelLoadFailed,
                                               @"sherpa-onnx could not build the Kokoro TTS engine from the supplied files.");
        return NO;
    }
    _isLoaded = YES;
    return YES;
#else
    if (error) *error = KokoroTTSMakeError(KokoroTTSErrorBackendUnavailable,
                                           @"KokoroTTSBridge was built without the sherpa-onnx backend linked.");
    return NO;
#endif
}

- (nullable NSData *)generateForText:(NSString *)text
                           speakerId:(int)speakerId
                               speed:(float)speed
                          sampleRate:(int *)sampleRate
                               error:(NSError **)error {
#if KOKORO_HAVE_BACKEND
    if (!_isLoaded || _tts == NULL) {
        if (error) *error = KokoroTTSMakeError(KokoroTTSErrorNotLoaded,
                                               @"generate called before the Kokoro engine was loaded.");
        return nil;
    }

    const SherpaOnnxGeneratedAudio *audio =
        SherpaOnnxOfflineTtsGenerate(_tts, text.UTF8String, speakerId, speed > 0 ? speed : 1.0f);
    if (audio == NULL || audio->samples == NULL || audio->n <= 0) {
        if (audio) SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
        if (error) *error = KokoroTTSMakeError(KokoroTTSErrorGenerateFailed,
                                               @"Kokoro produced no audio for the supplied text.");
        return nil;
    }

    if (sampleRate) *sampleRate = audio->sample_rate;
    // Copy the samples out before sherpa frees them.
    NSData *pcm = [NSData dataWithBytes:audio->samples length:(NSUInteger) audio->n * sizeof(float)];
    SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
    return pcm;
#else
    if (error) *error = KokoroTTSMakeError(KokoroTTSErrorBackendUnavailable,
                                           @"KokoroTTSBridge was built without the sherpa-onnx backend linked.");
    return nil;
#endif
}

- (void)unload {
#if KOKORO_HAVE_BACKEND
    if (_tts) { SherpaOnnxDestroyOfflineTts(_tts); _tts = NULL; }
#endif
    _isLoaded = NO;
}

- (void)dealloc {
    [self unload];
}

@end
