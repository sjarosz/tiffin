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

- (instancetype)initWithText:(NSString *)text
                    segments:(NSArray<WhisperCoreSegment *> *)segments
                    language:(nullable NSString *)language
                   modelUsed:(NSString *)modelUsed;
@end

// MARK: - Main Interface

@interface WhisperCore : NSObject

/// Initialize with model file path
/// @param modelPath Path to the .bin model file
/// @return WhisperCore instance or nil if initialization fails
- (nullable instancetype)initWithModelPath:(NSString *)modelPath;

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

@end

NS_ASSUME_NONNULL_END
