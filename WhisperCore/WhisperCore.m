//
//  WhisperCore.m
//  WhisperCore
//
//

#import "WhisperCore.h"
#import <AVFoundation/AVFoundation.h>

// Include whisper.cpp header
#ifdef __cplusplus
extern "C" {
#endif
#include "whisper.h"
#ifdef __cplusplus
}
#endif

// MARK: - Error Domain

NSString *const WhisperCoreErrorDomain = @"com.lunarclass.whispercore";

// MARK: - WhisperCoreConfiguration Implementation

@implementation WhisperCoreConfiguration

+ (instancetype)defaultConfiguration {
    WhisperCoreConfiguration *config = [[WhisperCoreConfiguration alloc] init];
    config.gpuMode = 1;  // WhisperCoreGPUModePreferred - Try GPU first, fallback to CPU
    config.gpuDevice = 0;
    config.flashAttention = YES;
    config.threads = 4;
    return config;
}

- (instancetype)initWithGPUMode:(WhisperCoreGPUMode)gpuMode {
    self = [super init];
    if (self) {
        _gpuMode = gpuMode;
        _gpuDevice = 0;
        _flashAttention = YES;
        _threads = 4;
    }
    return self;
}

- (instancetype)init {
    return [self initWithGPUMode:1];  // WhisperCoreGPUModePreferred
}

@end

// MARK: - WhisperCoreSegment Implementation

@implementation WhisperCoreSegment

- (instancetype)initWithStartTime:(NSTimeInterval)startTime
                          endTime:(NSTimeInterval)endTime
                             text:(NSString *)text
                       confidence:(float)confidence {
    self = [super init];
    if (self) {
        _startTime = startTime;
        _endTime = endTime;
        _text = text;
        _confidence = confidence;
    }
    return self;
}

@end

// MARK: - WhisperCoreResult Implementation

@implementation WhisperCoreResult

- (instancetype)initWithText:(NSString *)text
                    segments:(NSArray<WhisperCoreSegment *> *)segments
                    language:(NSString *)language
                   modelUsed:(NSString *)modelUsed
                     usedGPU:(BOOL)usedGPU {
    self = [super init];
    if (self) {
        _text = text;
        _segments = segments;
        _language = language;
        _modelUsed = modelUsed;
        _usedGPU = usedGPU;
    }
    return self;
}

@end

// MARK: - WhisperCore Implementation

@interface WhisperCore ()
@property (nonatomic, assign) struct whisper_context *whisperContext;
@property (nonatomic, strong) NSString *modelPath;
@property (nonatomic, strong) WhisperCoreConfiguration *configuration;
@property (nonatomic, assign) BOOL actuallyUsingGPU;
@end

@implementation WhisperCore

- (void)dealloc {
    if (_whisperContext) {
        whisper_free(_whisperContext);
        _whisperContext = NULL;
    }
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath {
    // Use default configuration which is already set to GPU-preferred mode
    WhisperCoreConfiguration *config = [WhisperCoreConfiguration defaultConfiguration];
    config.threads = MAX(4, (int)(NSProcessInfo.processInfo.processorCount / 2));  // Use half of available cores
    
    return [self initWithModelPath:modelPath configuration:config];
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath 
                             configuration:(WhisperCoreConfiguration *)configuration {
    self = [super init];
    if (self) {
        _modelPath = modelPath;
        _configuration = configuration;
        _actuallyUsingGPU = NO;
        
        // Check if model file exists
        if (![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
            NSLog(@"[WhisperCore] Model file not found: %@", modelPath);
            return nil;
        }
        
        // Try to initialize whisper context with the specified configuration
        _whisperContext = [self initializeWhisperContextWithConfiguration:configuration];
        
        if (!_whisperContext) {
            NSLog(@"[WhisperCore] Failed to initialize whisper context");
            return nil;
        }
    }
    return self;
}

- (struct whisper_context *)initializeWhisperContextWithConfiguration:(WhisperCoreConfiguration *)config {
    struct whisper_context_params cparams = whisper_context_default_params();
    
    // Set basic parameters
    cparams.flash_attn = config.flashAttention;
    cparams.gpu_device = config.gpuDevice;
    
    // Handle GPU configuration
    switch (config.gpuMode) {
        case 0:  // WhisperCoreGPUModeDisabled
            // CPU only
            cparams.use_gpu = false;
            NSLog(@"[WhisperCore] Using CPU only (as requested)");
            return [self tryInitializeWithParams:cparams];
            
        case 2:  // WhisperCoreGPUModeRequired
            // GPU required - fail if not available
            cparams.use_gpu = true;
            NSLog(@"[WhisperCore] Attempting GPU initialization (required)");
            return [self tryInitializeWithParams:cparams];
            
        case 1:  // WhisperCoreGPUModePreferred
        default:
            // Try GPU first, fallback to CPU
            NSLog(@"[WhisperCore] Attempting GPU initialization (with CPU fallback)");
            
            // First try with GPU
            cparams.use_gpu = true;
            struct whisper_context *ctx = [self tryInitializeWithParams:cparams];
            
            if (ctx) {
                self.actuallyUsingGPU = YES;
                NSLog(@"[WhisperCore] Successfully initialized with GPU acceleration");
                return ctx;
            }
            
            // GPU failed, try CPU
            NSLog(@"[WhisperCore] GPU initialization failed, falling back to CPU");
            cparams.use_gpu = false;
            ctx = [self tryInitializeWithParams:cparams];
            
            if (ctx) {
                self.actuallyUsingGPU = NO;
                NSLog(@"[WhisperCore] Successfully initialized with CPU");
                return ctx;
            }
            
            NSLog(@"[WhisperCore] Both GPU and CPU initialization failed");
            return NULL;
    }
}

- (struct whisper_context *)tryInitializeWithParams:(struct whisper_context_params)cparams {
    struct whisper_context *ctx = whisper_init_from_file_with_params([self.modelPath UTF8String], cparams);
    
    if (ctx && cparams.use_gpu) {
        // For GPU mode, verify that GPU is actually being used
        // This is a basic check - whisper.cpp should handle GPU initialization internally
        self.actuallyUsingGPU = YES;
    }
    
    return ctx;
}

- (BOOL)isInitialized {
    return _whisperContext != NULL;
}

- (BOOL)isUsingGPU {
    return _actuallyUsingGPU;
}

- (NSString *)modelInfo {
    if (!_whisperContext) {
        return @"Not initialized";
    }
    
    // Get model information from whisper context
    int n_vocab = whisper_n_vocab(_whisperContext);
    int n_audio_ctx = whisper_n_audio_ctx(_whisperContext);
    int n_text_ctx = whisper_n_text_ctx(_whisperContext);
    
    NSString *deviceInfo = _actuallyUsingGPU ? @"GPU" : @"CPU";
    
    return [NSString stringWithFormat:@"Device: %@, Vocab: %d, Audio ctx: %d, Text ctx: %d", 
            deviceInfo, n_vocab, n_audio_ctx, n_text_ctx];
}

- (nullable WhisperCoreResult *)transcribeAudioData:(const float *)audioData
                                        sampleCount:(NSUInteger)sampleCount {
    if (!_whisperContext) {
        return nil;
    }
    
    if (!audioData || sampleCount == 0) {
        return nil;
    }
    
    // Configure whisper parameters
    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_realtime = false;
    wparams.print_progress = false;
    wparams.print_timestamps = true;
    wparams.print_special = false;
    wparams.translate = false;
    wparams.language = "auto"; // Auto-detect language
    wparams.n_threads = _configuration.threads;
    wparams.n_max_text_ctx = 16384;
    wparams.offset_ms = 0;
    wparams.duration_ms = 0;
    
    // Run the transcription
    int result = whisper_full(_whisperContext, wparams, audioData, (int)sampleCount);
    
    if (result != 0) {
        NSLog(@"[WhisperCore] Transcription failed with code: %d", result);
        return nil;
    }
    
    // Extract results
    const int n_segments = whisper_full_n_segments(_whisperContext);
    NSMutableArray<WhisperCoreSegment *> *segments = [NSMutableArray arrayWithCapacity:n_segments];
    NSMutableString *fullText = [NSMutableString string];
    
    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(_whisperContext, i);
        const int64_t t0 = whisper_full_get_segment_t0(_whisperContext, i);
        const int64_t t1 = whisper_full_get_segment_t1(_whisperContext, i);
        
        // Convert whisper timestamps (in 10ms units) to seconds
        NSTimeInterval startTime = t0 * 0.01;
        NSTimeInterval endTime = t1 * 0.01;
        
        NSString *segmentText = [NSString stringWithUTF8String:text];
        
        WhisperCoreSegment *segment = [[WhisperCoreSegment alloc] 
            initWithStartTime:startTime
                      endTime:endTime
                         text:segmentText
                   confidence:0.0]; // Whisper.cpp doesn't provide confidence per segment
        
        [segments addObject:segment];
        [fullText appendString:segmentText];
    }
    
    // Detect language if possible
    NSString *detectedLanguage = nil;
    if (n_segments > 0) {
        const char* lang = whisper_lang_str(whisper_full_lang_id(_whisperContext));
        if (lang) {
            detectedLanguage = [NSString stringWithUTF8String:lang];
        }
    }
    
    NSString *modelUsed = [NSString stringWithFormat:@"whisper.cpp (%@)", _actuallyUsingGPU ? @"GPU" : @"CPU"];
    
    return [[WhisperCoreResult alloc] initWithText:[fullText copy]
                                          segments:[segments copy]
                                          language:detectedLanguage
                                         modelUsed:modelUsed
                                           usedGPU:_actuallyUsingGPU];
}

- (nullable WhisperCoreResult *)transcribeAudioFile:(NSURL *)audioFileURL {
    // Convert audio file to the format whisper.cpp expects
    NSArray<NSNumber *> *audioData = [self convertAudioFileToFloatArray:audioFileURL];
    if (!audioData) {
        return nil;
    }
    
    // Convert NSArray to C float array
    NSUInteger sampleCount = audioData.count;
    float *floatArray = malloc(sampleCount * sizeof(float));
    if (!floatArray) {
        return nil;
    }
    
    for (NSUInteger i = 0; i < sampleCount; i++) {
        floatArray[i] = audioData[i].floatValue;
    }
    
    // Transcribe the audio data
    WhisperCoreResult *result = [self transcribeAudioData:floatArray
                                              sampleCount:sampleCount];
    
    // Clean up
    free(floatArray);
    
    return result;
}

#pragma mark - Private Methods

- (nullable NSArray<NSNumber *> *)convertAudioFileToFloatArray:(NSURL *)audioFileURL {
    NSError *audioError = nil;
    
    // Open the audio file
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:audioFileURL error:&audioError];
    if (!audioFile) {
        NSLog(@"[WhisperCore] Failed to open audio file: %@", audioError.localizedDescription);
        return nil;
    }
    
    // Define the target format (16kHz, mono, float32)
    AVAudioFormat *targetFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                    sampleRate:16000.0
                                                                      channels:1
                                                                   interleaved:NO];
    
    if (!targetFormat) {
        NSLog(@"[WhisperCore] Failed to create target audio format");
        return nil;
    }
    
    // Create a converter
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:audioFile.processingFormat
                                                                  toFormat:targetFormat];
    if (!converter) {
        NSLog(@"[WhisperCore] Failed to create audio converter");
        return nil;
    }
    
    // Calculate the output frame count
    AVAudioFrameCount inputFrameCount = (AVAudioFrameCount)audioFile.length;
    AVAudioFrameCount outputFrameCount = (AVAudioFrameCount)(inputFrameCount * targetFormat.sampleRate / audioFile.processingFormat.sampleRate);
    
    // Create output buffer
    AVAudioPCMBuffer *outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:targetFormat
                                                                   frameCapacity:outputFrameCount];
    if (!outputBuffer) {
        NSLog(@"[WhisperCore] Failed to create output buffer");
        return nil;
    }
    
    // Convert the audio
    AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
        AVAudioPCMBuffer *inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFile.processingFormat
                                                                       frameCapacity:inputFrameCount];
        NSError *readError = nil;
        [audioFile readIntoBuffer:inputBuffer error:&readError];
        
        if (readError) {
            *outStatus = AVAudioConverterInputStatus_EndOfStream;
            return nil;
        }
        
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return inputBuffer;
    };
    
    NSError *conversionError = nil;
    AVAudioConverterOutputStatus status = [converter convertToBuffer:outputBuffer
                                                               error:&conversionError
                                                   withInputFromBlock:inputBlock];
    
    if (status != AVAudioConverterOutputStatus_HaveData) {
        NSLog(@"[WhisperCore] Audio conversion failed: %@", conversionError.localizedDescription);
        return nil;
    }
    
    // Extract float data
    const float *floatChannelData = outputBuffer.floatChannelData[0];
    NSMutableArray<NSNumber *> *floatArray = [NSMutableArray arrayWithCapacity:outputBuffer.frameLength];
    
    for (AVAudioFrameCount i = 0; i < outputBuffer.frameLength; i++) {
        [floatArray addObject:@(floatChannelData[i])];
    }
    
    return [floatArray copy];
}

@end
