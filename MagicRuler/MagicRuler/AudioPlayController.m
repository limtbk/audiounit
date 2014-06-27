//
//  AudioPlayController.m
//  MagicRuler
//
//  Created by lim on 6/24/14.
//  Copyright (c) 2014 lim. All rights reserved.
//

#import "AudioPlayController.h"
#import <AVFoundation/AVFoundation.h>

#define TRY(expr) {int s = (expr); if (s != noErr) { DLog(@"Error %d in " #expr, s); }}
#define TRYR(expr) {int s = (expr); if (s != noErr) { DLog(@"Error %d in " #expr " %@", s, OSStatusErrorDescription(s)); return s; }}
#define TRYE(expr) {NSError *error = nil; BOOL s = (expr); if (!s || error) { DLog(@"Error %@ in " #expr, error.localizedDescription); return 1; }}

double g_theta;

OSStatus RenderTone(
                    void *inRefCon,
                    AudioUnitRenderActionFlags 	*ioActionFlags,
                    const AudioTimeStamp 		*inTimeStamp,
                    UInt32 						inBusNumber,
                    UInt32 						inNumberFrames,
                    AudioBufferList 			*ioData)

{
	const double amplitude = 0.25;
    
    DLog(@"%f", inTimeStamp->mSampleTime);
	double theta = g_theta;
	double theta_increment = 2.0 * M_PI * 11025.0 / 44100.0;
    
	// This is a mono tone generator so we only need the first buffer
	const int channel = 0;
	Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
	
	// Generate the samples
	for (UInt32 frame = 0; frame < inNumberFrames; frame++)
	{
		buffer[frame] = sin(theta) * amplitude;
		
		theta += theta_increment;
		if (theta > 2.0 * M_PI)
		{
			theta -= 2.0 * M_PI;
		}
	}
	g_theta = theta;
	return noErr;
}


@interface AudioPlayController() {
    AUGraph au_graph;

//    AUNode au_recNode;
//    AudioUnit au_recUnit;

    AUNode au_iONode;
//    AudioUnit au_iOUnit;

    AUNode au_genNode;
//    AudioUnit au_genUnit;
}

@end

@implementation AudioPlayController

-(id) init {
    self = [super init];
    if (self) {
        [self setupAudioPlayback];
    }
    
    return self;
}

-(void) dealloc {
    if (au_graph) {
        TRY(DisposeAUGraph(au_graph));
        au_graph = nil;
    }
}

-(OSStatus) setupAudioPlayback {
    
#pragma mark AVAudioSession init
    AVAudioSession *mySession = [AVAudioSession sharedInstance];
    TRYE([mySession setActive:YES error:&error]);
    TRYE([mySession setCategory: AVAudioSessionCategoryPlayAndRecord error: &error]);
    if (![mySession isInputAvailable]) {
        DLog(@"Input is disabled, nothing to do here");
        return 1;
    }
    Float64 graphSampleRate = 44100.0;    // Hertz
    TRYE([mySession setPreferredSampleRate: graphSampleRate error: &error]);
    graphSampleRate = mySession.preferredSampleRate;
    
    Float32 currentBufferDuration =  (Float32) (1024.0 / graphSampleRate);
    TRYE([mySession setPreferredIOBufferDuration:currentBufferDuration error:&error]);
    currentBufferDuration = mySession.preferredIOBufferDuration;

    NSInteger numberOfInputChannels = 1;
    TRYE([mySession setPreferredInputNumberOfChannels:numberOfInputChannels error:&error]);
    numberOfInputChannels = mySession.inputNumberOfChannels;

    NSInteger numberOfOutputChannels = 1;
    TRYE([mySession setPreferredOutputNumberOfChannels:numberOfOutputChannels error:&error]);
    numberOfOutputChannels = mySession.outputNumberOfChannels;

    TRYE([mySession setActive:YES error: &error]);
    DLog(@"\nInit complete.\nIChannels = %d\nOChannels = %d\nIOBuffer = %f\nSampleRate = %f\n", numberOfInputChannels, numberOfOutputChannels, currentBufferDuration, graphSampleRate);
    
    size_t bytesPerSample = sizeof (AudioUnitSampleType);
    AudioStreamBasicDescription streamFormat;
    streamFormat.mFormatID          = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags       = kAudioFormatFlagsAudioUnitCanonical;
    streamFormat.mBytesPerPacket    = bytesPerSample;
    streamFormat.mFramesPerPacket   = 1;
    streamFormat.mBytesPerFrame     = bytesPerSample;
    streamFormat.mChannelsPerFrame  = numberOfOutputChannels;
    streamFormat.mBitsPerChannel    = 8 * bytesPerSample;
    streamFormat.mSampleRate        = graphSampleRate;
    
#pragma mark AudioGraph init
    TRYR(NewAUGraph(&au_graph));
    
    AudioComponentDescription iOUnitDescription;
    iOUnitDescription.componentType          = kAudioUnitType_Output;
    iOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    iOUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    iOUnitDescription.componentFlags         = 0;
    iOUnitDescription.componentFlagsMask     = 0;
    
//    AudioComponentDescription auScheduledSoundPlayerUnitDescription;
//    auScheduledSoundPlayerUnitDescription.componentType         = kAudioUnitType_Generator;
//    auScheduledSoundPlayerUnitDescription.componentSubType      = kAudioUnitSubType_ScheduledSoundPlayer;
//    auScheduledSoundPlayerUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    TRYR(AUGraphAddNode(au_graph, &iOUnitDescription, &au_iONode));
//    TRYR(AUGraphAddNode(au_graph, &auScheduledSoundPlayerUnitDescription, &au_genNode));
//    TRYR(AUGraphConnectNodeInput(au_graph, au_genNode, 0, au_iONode, 0));
    
	AURenderCallbackStruct input;
	input.inputProc = RenderTone;
	input.inputProcRefCon = (__bridge void *)(self);
    
    TRYR(AUGraphOpen(au_graph));
    AudioUnit iOUnit;
    TRYR(AUGraphNodeInfo(au_graph, au_iONode, NULL, &iOUnit));
//    AudioUnit genUnit;
//    TRYR(AUGraphNodeInfo(au_graph, au_genNode, NULL, &genUnit));
    AudioUnitElement ioUnitInputBus = 1;

//	TRYR(AudioUnitSetProperty(genUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &input, sizeof(input)));
	TRYR(AudioUnitSetProperty(iOUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &input, sizeof(input)));
    
//    UInt32 enableInput = 1;
//    TRYR(AudioUnitSetProperty (iOUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, ioUnitInputBus, &enableInput, sizeof(enableInput)));
    TRYR(AudioUnitSetProperty(iOUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, ioUnitInputBus, &streamFormat, sizeof(streamFormat)));
//    TRYR(AudioUnitSetProperty(genUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, ioUnitInputBus, &streamFormat, sizeof(streamFormat)));
    
    CAShow(au_graph);
    
    
    Boolean outIsInitialized;
    TRYR(AUGraphIsInitialized(au_graph, &outIsInitialized));
    if(!outIsInitialized) {
        TRYR(AUGraphInitialize(au_graph));
    }
    
    Boolean isRunning;
    TRYR(AUGraphIsRunning(au_graph, &isRunning));
    if(!isRunning) {
        TRYR(AUGraphStart(au_graph));
    }

    return noErr;
}

NSString *OSStatusErrorDescription(OSStatus error) {
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
                               @"-66784": @"kAUVoiceIOErr_UnexpectedNumberOfInputChannels"};
    NSString *result = statuses[[NSString stringWithFormat:@"%ld", error]];
    if (!result) {
        result = @"Unknown";
    }
    return result;
}

@end
