//
//  WhisperCore.h
//  WhisperCore
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Error Definitions

extern NSString *const WhisperCoreErrorDomain;

typedef NS_ENUM(NSInteger, WhisperCoreErrorCode) {
    WhisperCoreErrorCodeModelLoadFailed = 1001,
    WhisperCoreErrorCodeTranscriptionFailed = 1002,
    WhisperCoreErrorCodeInvalidAudioData = 1003,
    WhisperCoreErrorCodeInvalidModelPath = 1004,
    WhisperCoreErrorCodeContextNotInitialized = 1005
};

// MARK: - GPU Configuration

typedef NS_ENUM(NSInteger, WhisperCoreGPUMode) {
    WhisperCoreGPUModeDisabled = 0,    // CPU only
    WhisperCoreGPUModePreferred = 1,   // Try GPU first, fallback to CPU
    WhisperCoreGPUModeRequired = 2     // GPU only (fail if not available)
};

@interface WhisperCoreConfiguration : NSObject
@property (nonatomic, assign) WhisperCoreGPUMode gpuMode;
@property (nonatomic, assign) int gpuDevice;  // GPU device ID (0 for first GPU)
@property (nonatomic, assign) BOOL flashAttention;  // Enable flash attention
@property (nonatomic, assign) int threads;  // Number of CPU threads

+ (instancetype)defaultConfiguration;
- (instancetype)initWithGPUMode:(WhisperCoreGPUMode)gpuMode;
@end

// MARK: - Result Classes

@interface WhisperCoreSegment : NSObject
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval endTime;
@property (nonatomic, strong) NSString *text;
@property (nonatomic, assign) float confidence;

- (instancetype)initWithStartTime:(NSTimeInterval)startTime
                          endTime:(NSTimeInterval)endTime
                             text:(NSString *)text
                       confidence:(float)confidence;
@end

@interface WhisperCoreResult : NSObject
@property (nonatomic, strong) NSString *text;
@property (nonatomic, strong) NSArray<WhisperCoreSegment *> *segments;
@property (nonatomic, strong, nullable) NSString *language;
@property (nonatomic, strong) NSString *modelUsed;
@property (nonatomic, assign) BOOL usedGPU;  // Whether GPU was actually used

- (instancetype)initWithText:(NSString *)text
                    segments:(NSArray<WhisperCoreSegment *> *)segments
                    language:(nullable NSString *)language
                   modelUsed:(NSString *)modelUsed
                     usedGPU:(BOOL)usedGPU;
@end

// MARK: - Main Interface

@interface WhisperCore : NSObject

/// Initialize with model file path and default configuration (GPU preferred)
/// @param modelPath Path to the .bin model file
/// @return WhisperCore instance or nil if initialization fails
- (nullable instancetype)initWithModelPath:(NSString *)modelPath;

/// Initialize with model file path and custom configuration
/// @param modelPath Path to the .bin model file
/// @param configuration GPU and performance configuration
/// @return WhisperCore instance or nil if initialization fails
- (nullable instancetype)initWithModelPath:(NSString *)modelPath 
                             configuration:(WhisperCoreConfiguration *)configuration;

/// Transcribe audio data
/// @param audioData Float array of audio samples (16kHz, mono)
/// @param sampleCount Number of samples in the audio data
/// @return WhisperCoreResult object containing transcription, or nil if failed
- (nullable WhisperCoreResult *)transcribeAudioData:(const float *)audioData
                                        sampleCount:(NSUInteger)sampleCount;

/// Transcribe audio file
/// @param audioFileURL URL to the audio file
/// @return WhisperCoreResult object containing transcription, or nil if failed
- (nullable WhisperCoreResult *)transcribeAudioFile:(NSURL *)audioFileURL;

/// Check if whisper context is properly initialized
@property (nonatomic, readonly) BOOL isInitialized;

/// Get model information
@property (nonatomic, readonly) NSString *modelInfo;

/// Get whether GPU is currently being used
@property (nonatomic, readonly) BOOL isUsingGPU;

/// Get current configuration
@property (nonatomic, readonly) WhisperCoreConfiguration *configuration;

@end

NS_ASSUME_NONNULL_END
