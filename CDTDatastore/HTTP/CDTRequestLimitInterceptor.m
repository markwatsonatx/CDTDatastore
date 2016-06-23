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
 * Interceptor to retry after an exponential backoff if we receive a 429 error
 */
- (CDTHTTPInterceptorContext *)interceptResponseInContext:(CDTHTTPInterceptorContext *)context
{
    if (context.response.statusCode == 429) {
        
        CDTLogInfo(CDTTD_REMOTE_REQUEST_CONTEXT, @"429 error code received. Will retry in %f seconds.", self.sleep);
        
        // sleep for a short time before making next request
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow:self.sleep]];
        self.sleep *= 2; // exponential back-off
        context.shouldRetry = true;
    }
    return context;
}

@end
