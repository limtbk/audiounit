//
//  CMAudioController.m
//  recordPlaySound
//
//  Created by lim on 3/29/14.
//  Copyright (c) 2014 iMagicApps. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "CMAudioController.h"

@interface CMAudioController() {
    AUGraph au_graph;

    AUNode au_recNode;
    AudioUnit au_recUnit;
    
    AUNode au_playNode;
    AudioUnit au_playUnit;
    
    AUNode au_genNode;
    AudioUnit au_genUnit;
    
    AUNode au_anlsNode;
    AudioUnit au_anlsUnit;
}
@end

@implementation CMAudioController

- (id)init {
    self = [super init];
    if (self) {
    }
    return self;
}

AudioUnit *audioUnit = NULL;
float *convertedSampleBuffer = NULL;

int initAudioSession() {
    
    AVAudioSession* session = [AVAudioSession sharedInstance];
    BOOL success;
    NSError* error = nil;
    double preferredSampleRate = 48000;
    success  = [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    success  = [session setPreferredSampleRate:preferredSampleRate error:&error];

    
    [session setActive:YES error:&error];
    if (success) {
        NSLog (@"session.sampleRate = %f", session.sampleRate);
    } else {
        NSLog (@"error setting sample rate %@", error);
    }
//    [session setActive:NO error:&error];

    
    
    audioUnit = (AudioUnit*)malloc(sizeof(AudioUnit));
    
/*
    TRY(AudioSessionInitialize(NULL, NULL, NULL, NULL));
    TRY(AudioSessionSetActive(true));
    
    UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
    
    TRY(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(UInt32), &sessionCategory));
    
    Float32 bufferSizeInSec = 0.02f;
    TRY(AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration, sizeof(Float32), &bufferSizeInSec));
    
    UInt32 overrideCategory = 1;
    TRY(AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(UInt32), &overrideCategory));
    
    // There are many properties you might want to provide callback functions for:
    // kAudioSessionProperty_AudioRouteChange
    // kAudioSessionProperty_OverrideCategoryEnableBluetoothInput
    // etc.
 */
    
    return 0;
}

int initAudioStreams(AudioUnit *audioUnit) {
    UInt32 audioCategory = kAudioSessionCategory_PlayAndRecord;
    TRY(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                sizeof(UInt32), &audioCategory));
    
    UInt32 overrideCategory = 1;
    TRY(AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker,
                                sizeof(UInt32), &overrideCategory));
    // Less serious error, but you may want to handle it and bail here
    
    AudioComponentDescription componentDescription;
    componentDescription.componentType = kAudioUnitType_Output;
    //    componentDescription.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    componentDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    componentDescription.componentFlags = 0;
    componentDescription.componentFlagsMask = 0;
    AudioComponent component = AudioComponentFindNext(NULL, &componentDescription);
    TRY(AudioComponentInstanceNew(component, audioUnit));
    
    UInt32 enable = 1;
    TRY(AudioUnitSetProperty(*audioUnit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, 1, &enable, sizeof(UInt32)));
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = renderCallback; // Render function
    callbackStruct.inputProcRefCon = NULL;
    TRY(AudioUnitSetProperty(*audioUnit, kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0, &callbackStruct,
                             sizeof(AURenderCallbackStruct)));
    AudioStreamBasicDescription streamDescription;
    // You might want to replace this with a different value, but keep in mind that the
    // iPhone does not support all sample rates. 8kHz, 22kHz, and 44.1kHz should all work.
    //    streamDescription.mSampleRate = 96000;
    streamDescription.mSampleRate = 88200;
    // Yes, I know you probably want floating point samples, but the iPhone isn't going
    // to give you floating point data. You'll need to make the conversion by hand from
    // linear PCM <-> float.
    streamDescription.mFormatID = kAudioFormatLinearPCM;
    // This part is important!
    streamDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger |
    kAudioFormatFlagsNativeEndian |
    kAudioFormatFlagIsPacked;
    // Not sure if the iPhone supports recording >16-bit audio, but I doubt it.
    streamDescription.mBitsPerChannel = 16;
    // 1 sample per frame, will always be 2 as long as 16-bit samples are being used
    streamDescription.mBytesPerFrame = 2;
    // Record in mono. Use 2 for stereo, though I don't think the iPhone does true stereo recording
    streamDescription.mChannelsPerFrame = 1;
    streamDescription.mBytesPerPacket = streamDescription.mBytesPerFrame * streamDescription.mChannelsPerFrame;
    // Always should be set to 1
    streamDescription.mFramesPerPacket = 1;
    // Always set to 0, just to be sure
    streamDescription.mReserved = 0;
    
    // Set up input stream with above properties
    TRY(AudioUnitSetProperty(*audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDescription, sizeof(streamDescription)));
    
    // Ditto for the output stream, which we will be sending the processed audio to
    TRY(AudioUnitSetProperty(*audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamDescription, sizeof(streamDescription)));
    return 0;
}

int startAudioUnit(AudioUnit *audioUnit) {
    TRY(AudioUnitInitialize(*audioUnit));
    TRY(AudioOutputUnitStart(*audioUnit));
    return 0;
}

OSStatus renderCallback(void *userData, AudioUnitRenderActionFlags *actionFlags,
                        const AudioTimeStamp *audioTimeStamp, UInt32 busNumber,
                        UInt32 numFrames, AudioBufferList *buffers) {
    OSStatus status = AudioUnitRender(*audioUnit, actionFlags, audioTimeStamp,
                                      1, numFrames, buffers);
    if(status != noErr) {
        return status;
    }
    
    if(convertedSampleBuffer == NULL) {
        // Lazy initialization of this buffer is necessary because we don't
        // know the frame count until the first callback
        convertedSampleBuffer = (float*)malloc(sizeof(float) * numFrames);
    }
    
    SInt16 *inputFrames = (SInt16*)(buffers->mBuffers->mData);
    
    // If your DSP code can use integers, then don't bother converting to
    // floats here, as it just wastes CPU. However, most DSP algorithms rely
    // on floating point, and this is especially true if you are porting a
    // VST/AU to iOS.
    for(int i = 0; i < numFrames; i++) {
        convertedSampleBuffer[i] = (float)inputFrames[i] / 32768.0;
    }
    
    // Now we have floating point sample data from the render callback! We
    // can send it along for further processing, for example:
    // plugin->processReplacing(convertedSampleBuffer, NULL, sampleFrames);
    
    // Assuming that you have processed in place, we can now write the
    // floating point data back to the input buffer.
    for(int i = 0; i < numFrames; i++) {
        // Note that we multiply by 32767 here, NOT 32768. This is to avoid
        // overflow errors (and thus clipping).
        inputFrames[i] = (SInt16)(convertedSampleBuffer[i] * 32767.0);
    }
    
    return noErr;
}

int stopProcessingAudio(AudioUnit *audioUnit) {
    TRY(AudioOutputUnitStop(*audioUnit));
    TRY(AudioUnitUninitialize(*audioUnit));
    *audioUnit = NULL;
    return 0;
}


- (IBAction)record:(id)sender
{
//    if (!self.isRecording) {
        initAudioSession();
        initAudioStreams(audioUnit);
        startAudioUnit(audioUnit);
//    } else {
//        stopProcessingAudio(audioUnit);
//    }
}


@end
