//
//  MIDIReceiver.h
//  SH
//
//  Created by Flyvende Grise on 1/16/13.
//  Copyright (c) 2013 HalfdanJ. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <CoreMIDI/CoreMIDI.h>


@interface MIDIReceiver : NSObject{
    MIDIPortRef outputPort;
}

@property NSMutableArray * bindings;

-(void)addBindingTo:(id)object path:(NSString*)path channel:(int)channel number:(int)number rangeMin:(float)rangeMin rangeLength:(float)rangeLength;

-(void)addBindingPitchTo:(id)object path:(NSString*)path channel:(int)channel rangeMin:(float)rangeMin rangeLength:(float)rangeLength;


-(void)addBindingTo:(id)object selector:(NSString*)selector channel:(int)channel number:(int)number;

- (void) sendMidiChannel:(int)_midiChannel number:(int)midiNote value:(int)midiValue;
@end
