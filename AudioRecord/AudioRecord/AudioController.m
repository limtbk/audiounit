//
//  AudioController.m
//  AudioRecord
//
//  Created by lim on 6/29/14.
//  Copyright (c) 2014 lim. All rights reserved.
//

#import "AudioController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVAudioSession.h>
#import <Accelerate/Accelerate.h>

#define TRY(expr) {int s = (expr); if (s != noErr) { DLog(@"Error %d in " #expr, s); }}
#define TRYR(expr) {int s = (expr); if (s != noErr) { DLog(@"Error %d in " #expr " %@", s, OSStatusErrorDescription(s)); return s; }}
#define TRYE(expr) {NSError *error = nil; BOOL s = (expr); if (!s || error) { DLog(@"Error %@ in " #expr, error.localizedDescription); return 1; }}

typedef struct BufferStruct {
    uint32_t length;
    uint32_t minReturnLength;
    uint32_t currentLength;
    double firstSampleNumber;
    Float32 *data;
} BufferStruct;

typedef struct AudioDataStruct {
    double sampleRate;
    double bufferDuration;
    uint32_t maxFramesPerSlice;
    AudioUnit audioUnit;
    BufferStruct *buffer;
    double genDuration;
    Float32 *genPattern;
    uint32_t genPatternLength;
    double frequency;
    double timeoutTime;
    double gapTime;
    double histTimePeak;
    double lastTimePeak;
    double lastTimePeakAmp;
    double playTime;
    double lastPlayTime;
    double threshold;
} AudioDataStruct;

AudioDataStruct *adStruct;

@interface AudioController()

@end

@implementation AudioController

#pragma mark Lifecycle

-(id) init {
    self = [super init];
    if (self) {
        adStruct = calloc(1, sizeof(*adStruct));
    }
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    freeBuffer();
    free(adStruct);
    //TODO: stop audiounit, dealloc it
}

#pragma mark Public interface

-(void) startAudio {

    [self setupAudioSession];
    adStruct->genDuration = 0.01; //10ms
    setupBuffer();
    setupPattern();
    adStruct->gapTime = adStruct->genDuration * 2 * adStruct->sampleRate;
    [self setupIOUnit];

    [self startIOUnit];
}

#pragma mark Initialization

-(OSStatus) setupAudioSession {
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
    adStruct->bufferDuration = 0.005; //5 ms, 220.5 samples in 44100
    adStruct->sampleRate = 44100;
    adStruct->timeoutTime = 0.5 * adStruct->sampleRate;
    adStruct->threshold = 0.1;
    
    TRYE([sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:&error]);
    TRYE([sessionInstance setPreferredIOBufferDuration:adStruct->bufferDuration error:&error]);
    TRYE([sessionInstance setPreferredSampleRate:adStruct->sampleRate error:&error]);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:sessionInstance];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleRouteChange:) name:AVAudioSessionRouteChangeNotification object:sessionInstance];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMediaServerReset:) name:AVAudioSessionMediaServicesWereResetNotification object:sessionInstance];
    
    return [self activateAudioSession];
}

- (OSStatus)setupIOUnit
{
    AudioComponentDescription desc = [self audioComponentDescription];
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    AudioUnit audioUnit;
    TRYR(AudioComponentInstanceNew(comp, &audioUnit));
    adStruct->audioUnit = audioUnit;
    
    UInt32 one = 1;
    TRYR(AudioUnitSetProperty(adStruct->audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, sizeof(one)));
    TRYR(AudioUnitSetProperty(adStruct->audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, sizeof(one)));
    
    AudioStreamBasicDescription ioFormat = [self audioStreamBasicDescription];
    
    TRYR(AudioUnitSetProperty(adStruct->audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &ioFormat, sizeof(ioFormat)));
    TRYR(AudioUnitSetProperty(adStruct->audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &ioFormat, sizeof(ioFormat)));
    
    UInt32 maxFramesPerSlice = 4096;
    UInt32 maxFramesPerSliceSize = sizeof(maxFramesPerSlice);
    TRYR(AudioUnitSetProperty(adStruct->audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFramesPerSlice, maxFramesPerSliceSize));
    TRYR(AudioUnitGetProperty(adStruct->audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFramesPerSlice, &maxFramesPerSliceSize));
    adStruct->maxFramesPerSlice = maxFramesPerSlice;
    
    // Set the render callback on AURemoteIO
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = performRender;
    renderCallback.inputProcRefCon = NULL;
    TRYR(AudioUnitSetProperty(adStruct->audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, sizeof(renderCallback)));
    TRYR(AudioUnitInitialize(adStruct->audioUnit));
    return noErr;
}

- (AudioComponentDescription) audioComponentDescription {
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    return desc;
}

- (AudioStreamBasicDescription) audioStreamBasicDescription {
    AudioStreamBasicDescription ioFormat = {0};
    ioFormat.mSampleRate         = adStruct->sampleRate;
    ioFormat.mFormatID           = kAudioFormatLinearPCM;
    ioFormat.mFormatFlags        = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved; //Float32
    ioFormat.mBitsPerChannel     = sizeof(Float32)*8;
    ioFormat.mBytesPerPacket     = sizeof(Float32);
    ioFormat.mBytesPerFrame      = sizeof(Float32);
    //    ioFormat.mFormatFlags        = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked; //Int16
    //    ioFormat.mBitsPerChannel     = sizeof(SInt16)*8;
    //    ioFormat.mBytesPerPacket     = sizeof(SInt16);
    //    ioFormat.mBytesPerFrame      = sizeof(SInt16);
    ioFormat.mFramesPerPacket    = 1;
    ioFormat.mChannelsPerFrame   = 1; //mono
    return ioFormat;
}


-(OSStatus) activateAudioSession {
    TRYE([[AVAudioSession sharedInstance] setActive:YES error:&error]);
    return noErr;
}

- (OSStatus)startIOUnit
{
    TRYR(AudioOutputUnitStart(adStruct->audioUnit));
    return noErr;
}

- (OSStatus)stopIOUnit
{
    TRYR(AudioOutputUnitStop(adStruct->audioUnit));
    return noErr;
}

- (void)handleInterruption:(NSNotification *)notification
{
    UInt8 interruptionType = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
    DLog(@"Session interrupted %s\n", interruptionType == AVAudioSessionInterruptionTypeBegan ? "begin" : "end");
    
    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        [self stopIOUnit];
    }
    
    if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        if ([self activateAudioSession]) {
            [self startIOUnit];
        } else {
            DLog(@"Error activate session");
        }
    }
}

- (void)handleRouteChange:(NSNotification *)notification
{
    UInt8 reasonValue = [[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue];
    AVAudioSessionRouteDescription *routeDescription = [notification.userInfo valueForKey:AVAudioSessionRouteChangePreviousRouteKey];
    
    NSString *reason;
    switch (reasonValue) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable: reason = @"NewDeviceAvailable"; break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: reason = @"OldDeviceUnavailable"; break;
        case AVAudioSessionRouteChangeReasonCategoryChange: reason = [NSString stringWithFormat:@"CategoryChange to %@", [[AVAudioSession sharedInstance] category]]; break;
        case AVAudioSessionRouteChangeReasonOverride: reason = @"Override"; break;
        case AVAudioSessionRouteChangeReasonWakeFromSleep: reason = @"WakeFromSleep"; break;
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory: reason = @"NoSuitableRouteForCategory"; break;
        default: reason = @"ReasonUnknown";
    }
    DLog(@"Route change from %@, reason: %@", routeDescription, reason);
}

- (void)handleMediaServerReset:(NSNotification *)notification
{
    NSLog(@"Media server has reset, restart audio");
    [self startAudio];
}

#pragma mark Functions

static NSString *OSStatusErrorDescription(OSStatus error) {
    NSDictionary *statuses = @{@"-10830": @"kMIDIInvalidClient",
                               @"-10831": @"kMIDIInvalidPort",
                               @"-10832": @"kMIDIWrongEndpointType",
                               @"-10833": @"kMIDINoConnection",
                               @"-10834": @"kMIDIUnknownEndpoint",
                               @"-10835": @"kMIDIUnknownProperty",
                               @"-10836": @"kMIDIWrongPropertyType",
                               @"-10837": @"kMIDINoCurrentSetup",
                               @"-10838": @"kMIDIMessageSendErr",
                               @"-10839": @"kMIDIServerStartErr",
                               @"-10840": @"kMIDISetupFormatErr",
                               @"-10841": @"kMIDIWrongThread",
                               @"-10842": @"kMIDIObjectNotFound",
                               @"-10843": @"kMIDIIDNotUnique",
                               @"-10846": @"kAudioToolboxErr_InvalidSequenceType",
                               @"-10847": @"kAudioUnitErr_Unauthorized",
                               @"-10848": @"kAudioUnitErr_InvalidOfflineRender",
                               @"-10849": @"kAudioUnitErr_Initialized",
                               @"-10850": @"kAudioUnitErr_PropertyNotInUse",
                               @"-10851": @"kAudioUnitErr_InvalidPropertyValue",
                               @"-10852": @"kAudioToolboxErr_InvalidPlayerState",
                               @"-10853": @"kAudioToolboxErr_InvalidEventType",
                               @"-10854": @"kAudioToolboxErr_NoSequence",
                               @"-10855": @"kAudioToolboxErr_IllegalTrackDestination",
                               @"-10856": @"kAudioToolboxErr_StartOfTrack",
                               @"-10857": @"kAudioToolboxErr_EndOfTrack",
                               @"-10858": @"kAudioToolboxErr_TrackNotFound",
                               @"-10859": @"kAudioToolboxErr_TrackIndexError",
                               @"-10860": @"kAUGraphErr_NodeNotFound",
                               @"-10861": @"kAUGraphErr_InvalidConnection",
                               @"-10862": @"kAUGraphErr_OutputNodeErr",
                               @"-10863": @"kAUGraphErr_CannotDoInCurrentContext",
                               @"-10864": @"kAUGraphErr_InvalidAudioUnit",
                               @"-10865": @"kAudioUnitErr_PropertyNotWritable",
                               @"-10866": @"kAudioUnitErr_InvalidScope",
                               @"-10867": @"kAudioUnitErr_Uninitialized",
                               @"-10868": @"kAudioUnitErr_FormatNotSupported",
                               @"-10869": @"kAudioUnitErr_FileNotSpecified",
                               @"-10870": @"kAudioUnitErr_UnknownFileType",
                               @"-10871": @"kAudioUnitErr_InvalidFile",
                               @"-10872": @"kAudioUnitErr_InstrumentTypeNotFound",
                               @"-10873": @"kAudioUnitErr_IllegalInstrument",
                               @"-10874": @"kAudioUnitErr_TooManyFramesToProcess",
                               @"-10875": @"kAudioUnitErr_FailedInitialization",
                               @"-10876": @"kAudioUnitErr_NoConnection",
                               @"-10877": @"kAudioUnitErr_InvalidElement",
                               @"-10878": @"kAudioUnitErr_InvalidParameter",
                               @"-10879": @"kAudioUnitErr_InvalidProperty",
                               @"-66626": @"kAudioQueueErr_InvalidOfflineMode",
                               @"-66632": @"kAudioQueueErr_EnqueueDuringReset",
                               @"-66667": @"kAudioQueueErr_InvalidTapType",
                               @"-66668": @"kAudioQueueErr_RecordUnderrun",
                               @"-66669": @"kAudioQueueErr_InvalidTapContext",
                               @"-66670": @"kAudioQueueErr_TooManyTaps",
                               @"-66671": @"kAudioQueueErr_QueueInvalidated",
                               @"-66672": @"kAudioQueueErr_InvalidCodecAccess",
                               @"-66673": @"kAudioQueueErr_CodecNotFound",
                               @"-66674": @"kAudioQueueErr_PrimeTimedOut",
                               @"-66675": @"kAudioQueueErr_InvalidPropertyValue",
                               @"-66676": @"kAudioQueueErr_Permissions",
                               @"-66677": @"kAudioQueueErr_InvalidQueueType",
                               @"-66678": @"kAudioQueueErr_InvalidRunState",
                               @"-66679": @"kAudioQueueErr_BufferInQueue",
                               @"-66680": @"kAudioQueueErr_InvalidDevice",
                               @"-66681": @"kAudioQueueErr_CannotStart",
                               @"-66682": @"kAudioQueueErr_InvalidParameter",
                               @"-66683": @"kAudioQueueErr_InvalidPropertySize",
                               @"-66684": @"kAudioQueueErr_InvalidProperty",
                               @"-66685": @"kAudioQueueErr_DisposalPending",
                               @"-66686": @"kAudioQueueErr_BufferEmpty",
                               @"-66687": @"kAudioQueueErr_InvalidBuffer",
                               @"-66784": @"kAUVoiceIOErr_UnexpectedNumberOfInputChannels",
                               @"-38": @"kAudioFileNotOpenError",
                               @"-39": @"kAudioFileEndOfFileError",
                               @"-40": @"kAudioFilePositionError",
                               @"-43": @"kAudioFileFileNotFoundError",
                               @"1667787583": @"kAudioFileInvalidChunkError",
                               @"1685348671": @"kAudioFileInvalidFileError",
                               @"1718449215": @"kAudioFormatUnsupportedDataFormatError",
                               @"1868981823": @"kAudioFileDoesNotAllow64BitDataSizeError",
                               @"1869627199": @"kAudioFileOperationNotSupportedError",
                               @"1869640813": @"kAudioFileNotOptimizedError",
                               @"1885563711": @"kAudioFileInvalidPacketOffsetError",
                               @"1886547263": @"kAudioFilePermissionsError",
                               @"1886547824": @"kAudioFormatUnsupportedPropertyError",
                               @"1886681407": @"kAudioFileUnsupportedPropertyError",
                               @"1954115647": @"kAudioFileUnsupportedFileTypeError",
                               @"2003329396": @"kAudioFormatUnspecifiedError",
                               @"2003334207": @"kAudioFileUnspecifiedError",
                               @"560360820": @"kAudioFormatUnknownFormatError",
                               @"561211770": @"kAudioFormatBadPropertySizeError",
                               @"561213539": @"kAudioFormatBadSpecifierSizeError"};
    NSString *result = statuses[[NSString stringWithFormat:@"%d", (int)error]];
    if (!result) {
        result = @"Unknown";
    }
    return result;
}

static OSStatus	performRender (void                         *inRefCon,
                               AudioUnitRenderActionFlags 	*ioActionFlags,
                               const AudioTimeStamp 		*inTimeStamp,
                               UInt32 						inBusNumber,
                               UInt32 						inNumberFrames,
                               AudioBufferList              *ioData)
{
    static BOOL flGap = NO;
    static BOOL flPly = NO;
    TRYR(AudioUnitRender(adStruct->audioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData));
    addToBuffer(ioData->mBuffers[0].mData, inNumberFrames, inTimeStamp->mSampleTime); //assume that we have only one channel/buffer
    double peakAmplitude;
    double peakTime = getMaxPatternMatch(&peakAmplitude);
    if (peakAmplitude>adStruct->threshold) {
//        printf("l: %d t: %f Peak: %f Amp: %f\n", inNumberFrames, inTimeStamp->mSampleTime/adStruct->sampleRate, peakTime, peakAmplitude);
        
        if (peakTime - adStruct->lastTimePeak < adStruct->buffer->minReturnLength) {
            if (adStruct->lastTimePeakAmp<peakAmplitude) {
                adStruct->lastTimePeak = peakTime;
                adStruct->lastTimePeakAmp = peakAmplitude;
                flGap = YES;
            } else { //Amp go down, so max is found
                if (flGap) {
//                    printf("t: %f l: %d Peak: %f Amp: %f LP: %f\n", inTimeStamp->mSampleTime, (unsigned int)inNumberFrames, adStruct->lastTimePeak, adStruct->lastTimePeakAmp, adStruct->playTime);
                    printf("t: %f l: %d Peak: %f Amp: %f LP: %f Dt: %f\n", inTimeStamp->mSampleTime, (unsigned int)inNumberFrames, adStruct->lastTimePeak, adStruct->lastTimePeakAmp, adStruct->playTime, adStruct->lastTimePeak - adStruct->playTime);
                    if ((adStruct->playTime > inTimeStamp->mSampleTime) || (adStruct->playTime+adStruct->genPatternLength < inTimeStamp->mSampleTime)) { //if already played or not start play yet
                        adStruct->playTime = adStruct->lastTimePeak + adStruct->gapTime;
                        flPly = YES;
                    } else {
                        printf("Play already launched");
                    }
                }
                flGap = NO;
            }
        } else {
            adStruct->histTimePeak = adStruct->lastTimePeak;
            adStruct->lastTimePeak = peakTime;
            adStruct->lastTimePeakAmp = peakAmplitude;
            /*
            printf("t: %f l: %d Peak: %f Amp: %f LP: %f\n", inTimeStamp->mSampleTime, (unsigned int)inNumberFrames, peakTime, peakAmplitude, adStruct->playTime);
            if ((adStruct->playTime > inTimeStamp->mSampleTime) || (adStruct->playTime+adStruct->genPatternLength < inTimeStamp->mSampleTime)) { //if already played or not start play yet
                adStruct->playTime = adStruct->lastTimePeak + adStruct->gapTime;
            } else {
                printf("Play already launched");
            }
             */
        }
    }

    if (ABS(inTimeStamp->mSampleTime - adStruct->playTime) > adStruct->timeoutTime) {
        adStruct->playTime = inTimeStamp->mSampleTime + adStruct->timeoutTime/2;
    }
    
    if ((inTimeStamp->mSampleTime > adStruct->playTime) && (inTimeStamp->mSampleTime < adStruct->playTime + adStruct->genPatternLength)) {
        if (flPly) {
//            printf("t: %f Play: %f\n", inTimeStamp->mSampleTime, adStruct->playTime);
            adStruct->lastPlayTime = adStruct->playTime;
        }
        flPly = NO;
    }
    
    for (UInt32 i=0; i<ioData->mNumberBuffers; ++i) {
        Float32 *data = ioData->mBuffers[i].mData;
        for (NSUInteger frame = 0; frame < inNumberFrames; frame++) {
            double gframe = inTimeStamp->mSampleTime + frame;
//            double t = gframe/adStruct->sampleRate;
//            double dt = t - floor(t);
//            if (dt < adStruct->genDuration) {
//                data[frame] = sin(dt*M_PI*2*adStruct->frequency);
////                data[frame] = adStruct->genPattern[frame];
//            } else {
//                data[frame] = 0;
//            }

            if ((gframe > adStruct->playTime) && (gframe < adStruct->playTime + adStruct->genPatternLength)) {
                uint32_t patternIndex = gframe - adStruct->playTime;
                data[frame] = adStruct->genPattern[patternIndex];
//                data[frame] = 0;
            } else {
                data[frame] = 0;
            }
        
        }
        
    }
    
    return noErr;
}

void setupPattern() {
    adStruct->genPatternLength = adStruct->sampleRate * adStruct->genDuration;
    adStruct->frequency = adStruct->sampleRate/3;
    adStruct->genPattern = calloc(adStruct->genPatternLength, sizeof(Float32));
    for (NSUInteger frame = 0; frame < adStruct->genPatternLength; frame++) {
        double t = ((double)frame) / adStruct->sampleRate;
        adStruct->genPattern[frame] = sin(t*M_PI*2*adStruct->frequency);
    }
}

void setupBuffer() {
    adStruct->buffer = calloc(1, sizeof(*(adStruct->buffer)));
    BufferStruct *buf = adStruct->buffer;
    
    buf->minReturnLength = adStruct->genDuration * adStruct->sampleRate * 3;
    buf->length = buf->minReturnLength * 2;
    buf->data = calloc(buf->length, sizeof(Float32));
    buf->currentLength = buf->minReturnLength;
}

void freeBuffer() {
    free(adStruct->buffer->data);
    free(adStruct->buffer);
    adStruct->buffer = nil;
}

void addToBuffer(Float32 *data, uint32_t dataLength, double sampleTime) { //data length in samples, not in bytes; assume that data length < minreturnlength
    BufferStruct *buf = adStruct->buffer;
    if (buf->currentLength+dataLength>buf->length) {
        void *dst = buf->data;
        void *src = &(buf->data[buf->currentLength - buf->minReturnLength + dataLength]);
        memcpy(dst, src, sizeof(Float32) * (buf->minReturnLength - dataLength));
        buf->currentLength = buf->minReturnLength - dataLength;
    }
    void *dst = &(buf->data[buf->currentLength]);
    void *src = data;
    memcpy(dst, src, dataLength * sizeof(Float32));
    buf->firstSampleNumber = sampleTime - buf->currentLength;
    buf->currentLength += dataLength;
}

Float32 *getFromBuffer(uint32_t dataLength, double *sampleTime) {
    BufferStruct *buf = adStruct->buffer;
    Float32 *result = &(buf->data[buf->currentLength - dataLength]);

    *sampleTime = buf->firstSampleNumber + buf->currentLength - dataLength;
    return result;
}

double getMaxPatternMatch(double *amplitude) {
    double bufferTime;
    Float32 *bufferData = getFromBuffer(adStruct->genPatternLength*3, &bufferTime);
    Float32 *convResult = calloc(adStruct->genPatternLength*3, sizeof(Float32));
    vDSP_conv(bufferData, 1, adStruct->genPattern, 1, convResult, 1, adStruct->genPatternLength*2, adStruct->genPatternLength);
    Float32 max;
    vDSP_Length maxi;
    vDSP_maxmgvi(convResult, 1, &max, &maxi, adStruct->genPatternLength*2);
    free(convResult);
    *amplitude = max;
    return maxi+bufferTime;
}

@end
