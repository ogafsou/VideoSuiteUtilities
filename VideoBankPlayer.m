//
//  VideoBankPlayer.m
//  SH
//
//  Created by Jonas Jongejan on 07/01/13.
//  Copyright (c) 2013 HalfdanJ. All rights reserved.
//

#import "VideoBankPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "NSString+Timecode.h"

@interface VideoBankPlayer ()

//@property AVQueuePlayer * avPlayer;
//@property AVPlayerLayer * avPlayerLayer;


@property BOOL pingPong;

//@property NSMutableArray * outTimes;
//@property NSMutableArray * bankRefs;
@property NSMutableDictionary * playerData;

@end


@implementation VideoBankPlayer
static void *AVSPPlayerLayerReadyForDisplay = &AVSPPlayerLayerReadyForDisplay;
static void *AVPlayerRateContext = &AVPlayerRateContext;
static void *AvPlayerCurrentItemContext = &AvPlayerCurrentItemContext;


- (id)init
{
    self = [super init];
    if (self) {
        self.layer = [CALayer layer];
        [self.layer setAutoresizingMask: kCALayerWidthSizable | kCALayerHeightSizable];
        self.layer.hidden = YES;
        
        self.playing = NO;
        self.bankSelection = 0;
        self.numberOfBanksToPlay = 2;
        //self.simultaneousPlayback = NO;
        
    }
    return self;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    if (context == AVSPPlayerLayerReadyForDisplay)
	{
		if ([[change objectForKey:NSKeyValueChangeNewKey] boolValue] == YES)
		{

			// The AVPlayerLayer is ready for display.
            [CATransaction begin];
            [CATransaction setValue:(id)kCFBooleanTrue
                             forKey:kCATransactionDisableActions];
            self.layer.hidden = !self.playing;
            [CATransaction commit];
            
//            [avPlayer[self.pingPong] play];
		}
	}
    if(context== AvPlayerCurrentItemContext){
        [self newItemPlaying];
        /*
         NSLog(@"CurrentItemContext");
        NSLog(@"Out times %@",self.outTimes);
        if(self.outTimes.count > 0){
            if(avPlayer[self.pingPong].rate){
                NSLog(@"Rate");
            NSArray * times = @[self.outTimes[0]];
            [self.outTimes removeObjectAtIndex:0];
            [self.bankRefs removeObjectAtIndex:0];

            self.timeOutTimeObserverToken = [avPlayer[self.pingPong] addBoundaryTimeObserverForTimes:times queue:dispatch_get_current_queue() usingBlock:^{
                
                [avPlayer[self.pingPong] removeTimeObserver:self.timeOutTimeObserverToken];
                self.timeOutTimeObserverToken = nil;
                
                [avPlayer[self.pingPong] advanceToNextItem];
                
            }];
            }
        } else {
            NSLog(@"Stop playing");
            self.playing = NO;
        }*/
    }
}


-(NSDictionary*)getDataForCurrentItem{
    return  [self getDataForItem:avPlayer[self.pingPong].currentItem];
}
-(NSDictionary*)getDataForItem:(AVPlayerItem*)item{
    return [self.playerData objectForKey:item.asset];
}

-(void) newItemPlaying{
    NSLog(@"\n\nNew item playing");
    
    NSDictionary * data = [self getDataForCurrentItem];
    if(data){
        VideoBankItem * bankItem = [data valueForKey:@"bankRef"];
        
        double outTime = CMTimeGetSeconds( [[data valueForKey:@"outTime"] CMTimeValue] );
        double inTime = [[data valueForKey:@"inTime"] doubleValue];
        NSArray * times = @[[data valueForKey:@"outTime"]];
        
        __weak AVQueuePlayer * thisPlayer = avPlayer[self.pingPong];
        __weak AVPlayerLayer * thisLayer = avPlayerLayer[self.pingPong];
        int pingPong = self.pingPong;
        
        //Out time advance observer
        timeOutTimeObserverToken[pingPong] = [thisPlayer addBoundaryTimeObserverForTimes:times queue:dispatch_get_current_queue() usingBlock:^{
            
            [thisPlayer removeTimeObserver:timeOutTimeObserverToken[pingPong]];
            timeOutTimeObserverToken[pingPong] = nil;
            [thisPlayer advanceToNextItem];
        }];
        
        
        //Crossfade IN 
        double crossfadeTimeIn = [[data valueForKey:@"crossfadeTimeIn"] doubleValue];
        if(crossfadeTimeIn == 0){
            thisLayer.opacity = 1.0;
        } else {
            thisLayer.opacity = 0.0;
            
            fadeInObserverToken[pingPong] = [thisPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 25) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
                
                double p = (CMTimeGetSeconds(time)-inTime) / crossfadeTimeIn;
                thisLayer.opacity = p;
                avPlayer[pingPong].volume = p;
                
                if(p >= 1){
                    [thisPlayer removeTimeObserver:fadeInObserverToken[pingPong]];
                }

              //  NSLog(@"Fade up %f",p);
            }];
   
        }
        
        //Crossfade OUT
        double crossfadeTimeOut = [[data valueForKey:@"crossfadeTimeOut"] doubleValue];
        if(crossfadeTimeOut > 0){
            double eventTime =  outTime - crossfadeTimeOut;
            eventTime = MAX(inTime, eventTime);
            
            CMTime eventCMTime = CMTimeMakeWithSeconds(eventTime, 100);
            NSValue * value = [NSValue valueWithCMTime:eventCMTime];
            
            fadeOutEventObserverToken[pingPong] = [thisPlayer addBoundaryTimeObserverForTimes:@[value] queue:dispatch_get_current_queue() usingBlock:^{

                
                //Remove observers
                [thisPlayer removeTimeObserver: fadeOutEventObserverToken[pingPong]];
                fadeOutEventObserverToken[pingPong] = nil;
                
                if(fadeInObserverToken[!pingPong]){
                    [avPlayer[!pingPong] removeTimeObserver:fadeInObserverToken[!pingPong]];
                    fadeInObserverToken[!pingPong] = nil;
                }
                
                //Switch ping pong
                self.pingPong = !self.pingPong;
                

                fadeOutObserverToken[pingPong] = [thisPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 25) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
                    
                    double p = MAX(0,(CMTimeGetSeconds(time)-eventTime) / crossfadeTimeOut);
                    thisLayer.opacity = 1-p;
                    avPlayer[pingPong].volume = 1-p;
                    
                    //NSLog(@"Fade down %f",1-p);
                    
                    if(p == 0){
                        [thisPlayer removeTimeObserver:fadeOutObserverToken[pingPong]];
                        fadeOutObserverToken[pingPong] = nil;
                    }
                }];
                
                //Start new player
                if([data objectForKey:@"playerItems"] != nil){
               //     NSLog(@"Start new player. Current player %@ ",avPlayer[self.pingPong].currentItem);
                    if(avPlayer[self.pingPong].currentItem){
                        [avPlayer[self.pingPong] pause];
                    }

                    avPlayer[self.pingPong] = [AVQueuePlayer queuePlayerWithItems:[data objectForKey:@"playerItems"]];
                    
                    //Clear observers
                    timeObserverToken[self.pingPong] = nil;
                    timeOutTimeObserverToken[self.pingPong] = nil;
                    fadeInObserverToken[self.pingPong] = nil;
                    fadeOutObserverToken[self.pingPong] = nil;
                    fadeOutEventObserverToken[self.pingPong] = nil;
                    [avPlayer[!self.pingPong] removeObserver:self forKeyPath:@"currentItem"];

                    //Start player
                    [avPlayer[self.pingPong] play];
                    
                    [avPlayer[self.pingPong] addObserver:self forKeyPath:@"currentItem" options:0 context:AvPlayerCurrentItemContext];
                    
                    avPlayerLayer[self.pingPong].player = avPlayer[self.pingPong];
                    
                    
//                    if(timeObserverToken[self.pingPong] ){
//                        [avPlayer[self.pingPong] removeTimeObserver:timeObserverToken[self.pingPong]];
//                        avPlayer[self.pingPong] = nil;
//                    }

                    
                    int pingPongNewplayer = self.pingPong;
                    timeObserverToken[self.pingPong] = [avPlayer[self.pingPong] addPeriodicTimeObserverForInterval:CMTimeMake(1, 50) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
                        self.currentTimeString = [NSString stringWithTimecode:CMTimeGetSeconds(time)];
                        
                        if(avPlayer[self.pingPong].rate){
                            VideoBankItem * item = [[self getDataForItem:avPlayer[pingPongNewplayer].currentItem] valueForKey:@"bankRef"];
                            item.queued = NO;
                            item.playing = YES;
                            item.playHeadPosition = CMTimeGetSeconds(time);
                        }
                    }];
                    
                    [self newItemPlaying];
                }
                //                [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
                //avPlayerLayer[self.pingPong].opacity = 0.1;
                //              [CATransaction commit];

            }];
            
        }

        
    } else {
        self.playing = NO;
    }
}

-(void) preparePlayback{

    //Cleanup
    [avPlayer[self.pingPong] removeTimeObserver:timeOutTimeObserverToken[self.pingPong]];
    timeOutTimeObserverToken[self.pingPong] = nil;
    
    [avPlayer[self.pingPong] removeTimeObserver:timeObserverToken[self.pingPong]];
    timeObserverToken[self.pingPong] = nil;
    
    if(avPlayerLayer[self.pingPong]){
        [avPlayerLayer[self.pingPong] removeFromSuperlayer];
    }
    
    if(avPlayer[self.pingPong]){
        [avPlayer[self.pingPong] removeObserver:self forKeyPath:@"currentItem"];
        avPlayer[self.pingPong] = nil;

    }
    
    self.pingPong = 0;
    
    //Prepare items
    NSMutableArray * playerItems = [NSMutableArray array];
    NSArray * initialPlayerItems;
    
    self.playerData = [NSMutableDictionary dictionary];
    
    id lastKey = nil;
    id newPlayerKey = nil;
    
    for(int i=self.bankSelection;i<self.bankSelection + self.numberOfBanksToPlay;i++){
        if([self.videoBank.content count] > i){
            BOOL isLast = (i == self.bankSelection + self.numberOfBanksToPlay -1 )?YES : NO;
            VideoBankItem * bankItem = [self.videoBank content][i];
            double duration = bankItem.duration;
            
            AVAsset * asset = bankItem.avPlayerItem.asset;
            
            if([asset isPlayable]){
                AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
                
                
                //In time
                CMTime inTime = CMTimeMakeWithSeconds([bankItem.inTime doubleValue], 100);
                [playerItem seekToTime:inTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
                
                
                //UI
                bankItem.queued = YES;
                
                
                
                //Out time calculation
                double outTime;
                if(bankItem.outTime != nil){
                    outTime = [bankItem.outTime doubleValue];
                } else {
                    outTime = bankItem.duration;
                }
                outTime = MIN(duration, outTime);
                
                NSValue * outTimeValue = [NSValue valueWithCMTime:CMTimeMakeWithSeconds(outTime, 100)];
                
                
                //Crossfade times
                double crossfadeTimeIn = [bankItem.crossfadeTime doubleValue];
                double crossfadeTimeOut = 0;
                
                if(crossfadeTimeIn >  bankItem.duration){
                    crossfadeTimeIn = bankItem.duration-0.01;
                }
                
                if(crossfadeTimeIn > 0 && lastKey){
                    NSMutableDictionary * lastDict = [NSMutableDictionary dictionaryWithDictionary:[self.playerData objectForKey:lastKey] ];

                    [lastDict setValue:@(crossfadeTimeIn) forKey:@"crossfadeTimeOut"];
                    
                    [self.playerData setObject:[NSDictionary dictionaryWithDictionary:lastDict] forKey:lastKey];
                }
                
                
                if((crossfadeTimeIn > 0 && lastKey)){
                    NSLog(@"----Make new player magic at index %i",i);
                    
                    if(newPlayerKey == nil){
                        NSLog(@"No newPlayerKey. Store in initialPlayerItems");
                        initialPlayerItems = playerItems;
                    } else {
                        NSLog(@"Store in newPlayerKey dictionary");
                        NSMutableDictionary * lastDict = [NSMutableDictionary dictionaryWithDictionary:[self.playerData objectForKey:newPlayerKey] ];
                        
                        [lastDict setValue:playerItems forKey:@"playerItems"];
                        
                        [self.playerData setObject:[NSDictionary dictionaryWithDictionary:lastDict] forKey:newPlayerKey];

                        
                    }

                    playerItems = [NSMutableArray array];
                    newPlayerKey = lastKey;

                }
                
                [playerItems addObject:playerItem];
                
                if(isLast){
                    if(newPlayerKey == nil){
                        initialPlayerItems = playerItems;
                    } else {
                        
                        NSMutableDictionary * lastDict = [NSMutableDictionary dictionaryWithDictionary:[self.playerData objectForKey:lastKey] ];
                        
                        [lastDict setValue:playerItems forKey:@"playerItems"];
                        
                        [self.playerData setObject:[NSDictionary dictionaryWithDictionary:lastDict] forKey:lastKey];
                        
                        
                    }
                    
   
                }

                
                NSDictionary * dict = @{
                @"bankRef" : bankItem,
                @"outTime" : outTimeValue,
                @"inTime" : @([bankItem.inTime doubleValue]),
                @"crossfadeTimeIn" : @(crossfadeTimeIn),
                @"crossfadeTimeOut" : @(crossfadeTimeOut),
                @"playerItems" : @[]
                };
                

                [self.playerData setObject:dict forKey:playerItem.asset];
                
                lastKey = playerItem.asset;
                
            }
        }
    }
    
    //Create AVPlayer
    avPlayer[self.pingPong] = [AVQueuePlayer queuePlayerWithItems:initialPlayerItems];
    [avPlayer[self.pingPong] play];
    
    //Layer
    for(int i=0;i<2;i++){
        AVPlayerLayer *newPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:avPlayer[i]];
        [newPlayerLayer setFrame:self.layer.frame];
        newPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [newPlayerLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
        [newPlayerLayer setHidden:NO];
        newPlayerLayer.opacity = 0.0;
        
        avPlayerLayer[i] = newPlayerLayer;
        [self.layer addSublayer:avPlayerLayer[i]];
    }
    
    
    [self newItemPlaying];
    
    //Timecode updater
    timeObserverToken[self.pingPong] = [avPlayer[self.pingPong] addPeriodicTimeObserverForInterval:CMTimeMake(1, 50) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        self.currentTimeString = [NSString stringWithTimecode:CMTimeGetSeconds(time)];
        
        if(avPlayer[0].rate){
            VideoBankItem * item = [[self getDataForItem:avPlayer[0].currentItem] valueForKey:@"bankRef"];
            item.queued = NO;
            item.playing = YES;
            item.playHeadPosition = CMTimeGetSeconds(time);
        }
    }];
    
    
    //Observers
    [avPlayerLayer[self.pingPong] addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:AVSPPlayerLayerReadyForDisplay];
    
    [avPlayer[self.pingPong] addObserver:self forKeyPath:@"currentItem" options:0 context:AvPlayerCurrentItemContext];
    
    
}

-(void) clearBankStatus{
    for(VideoBankItem * item in self.videoBank.content){
        item.queued = NO;
        item.playHeadPosition = 0;
        item.playing = NO;

    }
}

-(void)setPlaying:(BOOL)playing{
    if(_playing != playing){
        _playing = playing;


        
        if(playing){
            [self preparePlayback];
        } else {
            [self clearBankStatus];

            [avPlayer[self.pingPong] pause];
            [CATransaction begin];
            [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
            self.layer.hidden = YES;
            [CATransaction commit];
            

            
        }
        

    }
}

-(BOOL)playing{
    return _playing;
}

@end