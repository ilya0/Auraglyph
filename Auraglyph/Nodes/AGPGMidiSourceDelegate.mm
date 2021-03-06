//
//  AGPGMidiSourceDelegate.mm
//  Auragraph
//
//  Created by Andrew Piepenbrink on 7/21/17.
//  Copyright © 2017 Spencer Salazar. All rights reserved.
//
//  Parts of this code are based on ofxMidi by Dan Wilcox.
//  See https://github.com/danomatika/ofxMidi for documentation

#include "AGPGMidiSourceDelegate.h"
#include "AGControlMidiInput.h"

#include <mach/mach_time.h>

#include <sstream>

// -----------------------------------------------------------------------------
// there is no conversion fucntion on iOS, so we make one here
// from https://developer.apple.com/library/mac/#qa/qa1398/_index.html
uint64_t AbsoluteToNanos(uint64_t time) {
    static struct mach_timebase_info timebaseInfo;
    
    // only init once
    if(timebaseInfo.denom == 0) {
        mach_timebase_info(&timebaseInfo);
    }
    
    return time * timebaseInfo.numer / timebaseInfo.denom;
}

// PG MIDI IN DELEGATE
// -----------------------------------------------------------------------------
@implementation AGPGMidiSourceDelegate

@synthesize bIgnoreSysex, bIgnoreTiming, bIgnoreSense;

// -----------------------------------------------------------------------------
- (id) init {
    self = [super init];
    
    inputPtr = NULL;
    
    lastTime = 0;
    bFirstPacket = true;
    bContinueSysex = false;
    
    maxMessageLen = 100; // default RtMidiIn length
    
    return self;
}

// -----------------------------------------------------------------------------
// adapted from RTMidi CoreMidi message parsing
- (void) midiSource:(PGMidiSource *)input midiReceived:(const MIDIPacketList *)packetList {
    
    const MIDIPacket *packet = &packetList->packet[0];
    std::stringstream msg;
    unsigned char statusByte;
    unsigned short nBytes, curByte, msgSize;
    unsigned long long time;
    double delta = 0.0;
    
    for(int i = 0; i < packetList->numPackets; ++i) {
        
        nBytes = packet->length;
        if(nBytes == 0)
            continue;
        
        // calc time stamp
        time = 0;
        if(bFirstPacket) {
            bFirstPacket = false;
        }
        else {
            time = packet->timeStamp;
            if(time == 0) { // this happens when receiving asynchronous sysex messages
                time = mach_absolute_time();
            }
            time -= lastTime;
            
            // set the delta time between individual messages
            if(!bContinueSysex) {
                delta = AbsoluteToNanos(time) * 0.000001; // convert to ms
            }
        }
        lastTime = packet->timeStamp;
        if(lastTime == 0 ) { // this happens when receiving asynchronous sysex messages
            lastTime = mach_absolute_time();
        }
        
        // handle segmented sysex messages
        curByte = 0;
        if(bContinueSysex) {
            
            // copy the packet if not ignoring
            if(!bIgnoreSysex) {
                for(int i = 0; i < nBytes; ++i) {
                    message.push_back(packet->data[i]);
                }
            }
            bContinueSysex = packet->data[nBytes-1] != 0xF7; // look for stop
            
            if(!bContinueSysex) {
                // send message if sysex message complete
                if(!message.empty()) {
                    inputPtr->messageReceived(delta, &message);
                }
                message.clear();
            }
        }
        else { // not sysex, parse bytes
            
            while(curByte < nBytes) {
                msgSize = 0;
                
                // next byte in the packet should be a status byte
                statusByte = packet->data[curByte];
                if(!statusByte & 0x80)
                    break;
                
                // determine number of bytes in midi message
                if(statusByte < 0xC0) // Note off, note on, polyphonic aftertouch, or CC
                    msgSize = 3;
                else if(statusByte < 0xE0) // Program change or channel aftertouch
                    msgSize = 2;
                else if(statusByte < 0xF0) // 14-bit pitch bend
                    msgSize = 3;
                else if(statusByte == 0xF0) { // sysex message
                    
                    if(bIgnoreSysex) {
                        msgSize = 0;
                        curByte = nBytes;
                    }
                    else {
                        msgSize = nBytes - curByte;
                    }
                    bContinueSysex = packet->data[nBytes-1] != 0xF7;
                }
                else if(statusByte == 0xF1) { // time code message
                    
                    if(bIgnoreTiming) {
                        msgSize = 0;
                        curByte += 2;
                    }
                    else {
                        msgSize = 2;
                    }
                }
                else if(statusByte == 0xF2)
                    msgSize = 3;
                else if(statusByte == 0xF3)
                    msgSize = 2;
                else if(statusByte == 0xF8 && bIgnoreTiming) { // timing tick message
                    // ignoring ...
                    msgSize = 0;
                    curByte += 1;
                }
                else if(statusByte == 0xFE && bIgnoreSense) { // active sense message
                    // ignoring ...
                    msgSize = 0;
                    curByte += 1;
                }
                else {
                    msgSize = 1;
                }
                
                // copy packet
                if(msgSize) {
                    
                    message.assign(&packet->data[curByte], &packet->data[curByte+msgSize]);
                    
                    if(!bContinueSysex) {
                        // send message if sysex message complete
                        if(!message.empty()) {
                            inputPtr->messageReceived(delta, &message);
                        }
                        message.clear();
                    }
                    curByte += msgSize;
                }
            }
        }
        
        packet = MIDIPacketNext(packet);
    }
}

// -----------------------------------------------------------------------------
- (void) setInputPtr:(AGControlMidiInput *)p {
    inputPtr = p;
}

@end
