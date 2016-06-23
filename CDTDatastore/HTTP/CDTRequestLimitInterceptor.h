//
//  CDTRequestLimitInterceptor.h
//  CDTDatastore
//
//  Created by tomblench on 23/06/2016.
//  Copyright © 2016 IBM. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDTSessionCookieInterceptor.h"
#import "CDTLogging.h"



@interface CDTRequestLimitInterceptor : NSObject <CDTHTTPInterceptor>

- (nonnull instancetype)init;

@end
