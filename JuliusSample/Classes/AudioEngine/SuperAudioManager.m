//
//  SuperAudioManager.m
//  JuliusSample
//
//  Created by Matthew Magee on 08/08/2013.
//
//

#import "SuperAudioManager.h"

#include "utils.h"

@implementation SuperAudioManager {
    float sampleRate;
    
    NSMutableDictionary *recordSettings;

}

// ########################################################################################################################################
// ########################################################################################################################################
// ########################################################################################################################################

#pragma mark - public methods

+(SuperAudioManager *)sharedInstance{
    static SuperAudioManager *_instance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!_instance) {
            _instance = [[SuperAudioManager alloc] init];
            [_instance firstTimeInitialisation];
        }
    });
    return _instance;
}

- (void)micRecordingStart:(AVAudioRecorder*)pAudioRecorder {
    if (pAudioRecorder) {
        [pAudioRecorder record];
    }
}

- (void)micRecordingEnd:(AVAudioRecorder*)pAudioRecorder {
    if (pAudioRecorder) {
        [pAudioRecorder stop];
    }
}

- (NSArray*)extractWordsFromFile:(NSURL*)pFilename {
    return nil;
}

// ########################################################################################################################################
// ########################################################################################################################################
// ########################################################################################################################################

#pragma mark - initialisation and configuration

/*
 *
 * Called only one time when this singleton is built.  It sets up common variables and all defaults.
 *
 */
- (void)firstTimeInitialisation {
    
    [self setSampleRate:16000.0f];
    
    // Settings to be used by the generic AVAAudioRecorder.
	recordSettings = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                   [NSNumber numberWithFloat:sampleRate], AVSampleRateKey,
                                   [NSNumber numberWithUnsignedInt:1], AVNumberOfChannelsKey,
                                   [NSNumber numberWithUnsignedInt:16], AVLinearPCMBitDepthKey,
                                   [NSNumber numberWithInt: AVAudioQualityMax], AVEncoderAudioQualityKey,
                                   [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                                   [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey, nil];
    
    // Init and prepare the recorder
    self.genericAudioRecorder = [[AVAudioRecorder alloc] initWithURL:[self getNewUniqueFileURL] settings:recordSettings error:NULL];
    self.genericAudioRecorder.meteringEnabled = YES;
    self.genericAudioRecorder.delegate = self;
    
}

/*
 *
 * Update the sample rate, updating other settings as appropriate.
 *
 */
- (void)setSampleRate:(float)pSampleRate {
    
    sampleRate = pSampleRate;

    if (recordSettings) {
        [recordSettings setObject:[NSNumber numberWithFloat:sampleRate] forKey:AVSampleRateKey];
    }
    
    //TODO: destroy and rebuild any objects or data structures that rely on the sample rate and/or recordSettings
    
    if (self.genericAudioRecorder) {
        
    }
    
}

// ########################################################################################################################################
// ########################################################################################################################################
// ########################################################################################################################################

#pragma mark - AVAudioRecorderDelegate methods

/* audioRecorderDidFinishRecording:successfully: is called when a recording has been finished or stopped. This method is NOT called if the recorder is stopped due to an interruption. */
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    
    if (flag) {
        
        NSLog(@"SuperAudioManager got audio (but isn't doing anything with it)!");
        
    }
    
}

/* if an error occurs while encoding it will be reported to the delegate. */
- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    
}

/* audioRecorderBeginInterruption: is called when the audio session has been interrupted while the recorder was recording. The recorded file will be closed. */
- (void)audioRecorderBeginInterruption:(AVAudioRecorder *)recorder {
    
}

/* audioRecorderEndInterruption:withOptions: is called when the audio session interruption has ended and this recorder had been interrupted while recording. */
/* Currently the only flag is AVAudioSessionInterruptionFlags_ShouldResume. */
- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder withOptions:(NSUInteger)flags NS_AVAILABLE_IOS(6_0) {
    
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder withFlags:(NSUInteger)flags NS_DEPRECATED_IOS(4_0, 6_0) {
    
}

/* audioRecorderEndInterruption: is called when the preferred method, audioRecorderEndInterruption:withFlags:, is not implemented. */
- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder NS_DEPRECATED_IOS(2_2, 6_0) {
    
}

// ########################################################################################################################################
// ########################################################################################################################################
// ########################################################################################################################################

#pragma mark - convenience methods

- (NSURL*)getNewUniqueFileURL {
    
    // Create file path.
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyyMMddHHmmss"];
	NSString *fileName = [NSString stringWithFormat:@"ef_temp_soundfile_%@.wav", [formatter stringFromDate:[NSDate date]]];
    
    // Set the audio file
    return [self fileUrlInDocFolderWithFileName:fileName];
    
}

-(NSURL *)fileUrlInDocFolderWithFileName:(NSString *)inputFileName{
    NSArray *pathComponents = [NSArray arrayWithObjects:
                               [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                               inputFileName,
                               nil];
    return [NSURL fileURLWithPathComponents:pathComponents];
}

// ########################################################################################################################################
// ########################################################################################################################################
// ########################################################################################################################################

#pragma mark - aubio methods for extracting pitch

unsigned int pos = 0; /*frames%dspblocksize*/
aubio_source_t *that_source = NULL;

/* pitch objects */
aubio_pitch_t *pitchObject;
fvec_t *pitch;

typedef struct {
    float *arrayData;
    size_t used;
    size_t size;
} GrowingFloatArrayPureC;

//------------------------------------------------------------------------------------------
// All the staff I need to store the C array for pitch value and pass it to Objectvive-C
float *pitchArray;
GrowingFloatArrayPureC pArray;

void initArray(GrowingFloatArrayPureC *a, size_t initialSize) {
    a->arrayData = (float *)malloc(initialSize * sizeof(float));
    a->used = 0;
    a->size = initialSize;
}

void insertArray(GrowingFloatArrayPureC *a, float element) {
    if (a->used == a->size) {
        a->size *= 2;// This is interesting
        a->arrayData = (float *)realloc(a->arrayData, a->size * sizeof(float));
    }
    a->arrayData[a->used++] = element;
}

void freeArray(GrowingFloatArrayPureC *a) {
    free(a->arrayData);
    a->arrayData = NULL;
    a->used = a->size = 0;
}


unsigned int posInFrame = 0; /*frames%dspblocksize*/
int framesRIO = 0;

#pragma mark -
#pragma mark Aubio Callback Methods

static int aubio_process(smpl_t **input, smpl_t **output, int nframes) {
    unsigned int j;       /*frames*/
    for (j=0;j<(unsigned)nframes;j++) {
        if(usejack) {
            /* write input to datanew */
            fvec_write_sample(ibuf, input[0][j], pos);
            /* put synthnew in output */
            output[0][j] = fvec_read_sample(obuf, pos);
        }
        /*time for fft*/
        if (pos == overlap_size-1) {
            /* block loop */
            aubio_pitch_do (pitchObject, ibuf, pitch);
            //            aubio_onset_do(onsetObject, ibuf, onset);
            
            if (fvec_read_sample(pitch, 0)) {
                for (pos = 0; pos < overlap_size; pos++){
                    // TODO, play sine at this freq
                }
            } else {
                fvec_zeros (obuf);
            }
            
            //            if (fvec_read_sample(onset, 0)) {
            //                fvec_copy(woodblock, obuf);
            //            } else {
            //                fvec_zeros(obuf);
            //            }
            /* end of block loop */
            
            pos = -1; /* so it will be zero next j loop */
        }
        pos++;
    }
    return 1;
}

static void process_print (void) {
    if (!verbose && usejack) return;
    smpl_t pitch_found = fvec_read_sample(pitch, 0);
    //outmsg("Time:%f Freq:%f\n",(frames)*overlap_size/(float)samplerate, pitch_found);
    
    pitchArray[frames] = pitch_found;//the array holding pitch values
    insertArray(&pArray, pitch_found);  // automatically resizes as necessary
    //    NSLog(@"pitchArray[%d]:%f",frames, pitchArray[frames]);
    
    //    smpl_t onset_found = fvec_read_sample (onset, 0);
    //    if (onset_found) {
    //        outmsg ("Onset:%f\n", aubio_onset_get_last_s (onsetObject) );
    //    }
}



-(NSArray*)extractPitchFloatArrayFromFile:(NSURL *)pFilename {
    NSString *path = [NSString stringWithFormat:@"%@",[pFilename relativePath]];
    char *temp = (char *)[path UTF8String];
    
    NSLog(@"filePath is %@",path);
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:pFilename options:nil];
    CMTime time = asset.duration;
    double durationInSeconds = CMTimeGetSeconds(time);
    
    NSLog(@"Got audio! Duration is %f",durationInSeconds);
    
    
    //we take the time, multiply it by the magic number, and then add one to avoid rounding issues.  This gives us our approximate number of frames in this file.
    int numberOfFramesInTheFile = (durationInSeconds * 62.0f)+1;

    
    //    examples_common_init(argc,&temp);
    debug ("Opening files ...\n");
    that_source = new_aubio_source ((char_t *)temp, 0, overlap_size);
    if (that_source == NULL) {
        outmsg ("Could not open input file %s.\n", temp);
        exit (1);
    }
    samplerate = aubio_source_get_samplerate(that_source);
    
    woodblock = new_fvec (overlap_size);
    ibuf = new_fvec (overlap_size);
    obuf = new_fvec (overlap_size);
    
    pitchObject = new_aubio_pitch ("yin", buffer_size, overlap_size, samplerate);
    //    if (threshold != 0.) {
    //        aubio_pitch_set_silence(pitchObject, -60);
    //        aubio_pitch_set_unit(pitchObject, "freq");
    //    }
    
    pitch = new_fvec (1);
    
    // ...
    pitchArray = (float *)malloc(sizeof(float)*numberOfFramesInTheFile);
    initArray(&pArray, 5);  // initially 5 elements
    
    //    examples_common_process(aubio_process,process_print);
    uint_t read = 0;
    debug ("Processing 1 ...\n");
    frames = 0;
    do {
        aubio_source_do (that_source, ibuf, &read);
        aubio_process (&ibuf->data, &obuf->data, overlap_size);
        process_print ();
        frames++;
    } while (read == overlap_size);
    del_aubio_pitch (pitchObject);
    del_fvec (pitch);
    
    debug ("Processed %d frames of %d samples.\n", frames, buffer_size);
    
    //    for (int idx = 0; idx < frames; idx++) {
    //        [self.pitchArray addObject:[NSNumber numberWithFloat:pitchAry[idx]]];
    //    }
    
    //    del_aubio_pitch (pitchObject);
    //    del_fvec (pitch);
    //    del_aubio_onset(onsetObject);
    //    del_fvec(onset);
    
#ifdef DEBUG
    //    DLog(@"pitchArray cnt: %d", [self.pitchArray count]);
#endif
    
    NSMutableArray *tempPitch = [NSMutableArray arrayWithCapacity:numberOfFramesInTheFile];
    for (int idx=0; idx<numberOfFramesInTheFile; idx++) {
        [tempPitch addObject:[NSNumber numberWithFloat:pitchArray[idx]]];
        //        NSLog(@"pitchArray[%d]:%f",idx, pitchArray[idx]);
    }
    
    NSMutableArray *tempPitch2 = [NSMutableArray array];
    for (int idx = 0; idx<pArray.size; idx++) {
        [tempPitch2 addObject:[NSNumber numberWithFloat:pArray.arrayData[idx]]];
    }
    freeArray(&pArray);
    
//    if (self.controllerDelegateAubio) {
//        [self.controllerDelegateAubio aubioCallBackResult:tempPitch];
//        //        [self.controllerDelegateAubio aubioCallBackResult:tempPitch2];// The GrowingFloatArrayPureC doesn't work?!
//    }
    
    examples_common_del();
    debug("End of program.\n");
    fflush(stderr);
    
    return tempPitch;
    
}



@end