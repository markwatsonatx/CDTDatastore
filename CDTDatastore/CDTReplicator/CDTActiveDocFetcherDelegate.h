//
//  CDTActiveDocFetcherDelegate.h
//  Pods
//
//  Created by Mark Watson on 6/30/16.
//
//

#import <Foundation/Foundation.h>

@protocol CDTActiveDocFetcherDelegate

- (NSMutableURLRequest *)getFetchAllActiveDocsRequest;
- (NSArray *)parseActiveDocsFromResponse:(NSData*)body errorMessage:(NSString**)errorMessage;

@end
