//
//  SignalHandler.h
//  CrashExceptionHandler
//
//  Created by weiguang on 2020/2/27.
//  Copyright © 2020 weiguang. All rights reserved.
//

#import <Foundation/Foundation.h>



@interface SignalHandler : NSObject

+(void)saveCreash:(NSString *)exceptionInfo;

@end


// 捕获非异常情况，通过signal传递出来的崩溃
void InstallSignalHandler(void);
