//
//  CDTRequestLimitInterceptor.m
//  CDTDatastore
//
//  Created by tomblench on 23/06/2016.
//  Copyright © 2016 IBM. All rights reserved.
//

#import "CDTRequestLimitInterceptor.h"

@interface CDTRequestLimitInterceptor ()

@property NSTimeInterval sleep;


@end

@implementation CDTRequestLimitInterceptor


- (instancetype)init
{
    if (self = [super init]) {
        self.sleep = 0.25; // 250ms
    }
    return self;
}

/**

 */
- (CDTHTTPInterceptorContext *)interceptResponseInContext:(CDTHTTPInterceptorContext *)context
{
    if (context.response.statusCode == 429) {
        // sleep for a short time before making next request
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow:self.sleep]];
        self.sleep *= 2; // exponential back-off
        context.shouldRetry = true;
    }
    return context;
}





@end
