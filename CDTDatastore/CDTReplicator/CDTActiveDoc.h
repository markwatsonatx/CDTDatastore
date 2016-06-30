//
//  TDActiveDoc.h
//  Pods
//
//  Created by Mark Watson on 6/30/16.
//
//

#import <Foundation/Foundation.h>

@interface CDTActiveDoc : NSObject

@property (nonatomic, strong) NSString *_id;
@property (nonatomic, strong) NSString *revision;

- (id)initWithId:(NSString *)docId
        revision:(NSString *)docRevision;

@end
