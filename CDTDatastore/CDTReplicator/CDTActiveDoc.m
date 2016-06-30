//
//  TDActiveDoc.m
//  Pods
//
//  Created by Mark Watson on 6/30/16.
//
//

#import "CDTActiveDoc.h"

@implementation CDTActiveDoc

- (id)initWithId:(NSString *)docId
        revision:(NSString *)docRevision
{
    self = [super init];
    if (self) {
        self._id = docId;
        self.revision = docRevision;
    }
    return self;
}


@end
