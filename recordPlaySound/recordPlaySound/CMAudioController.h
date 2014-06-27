//
//  CMAudioController.h
//  recordPlaySound
//
//  Created by lim on 3/29/14.
//  Copyright (c) 2014 iMagicApps. All rights reserved.
//

#import <Foundation/Foundation.h>

#define TRY(expr) if (expr != noErr) { DLog(@"Error in " #expr); return 1; }

@interface CMAudioController : NSObject



@end
