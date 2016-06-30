//
//  TDAllDocsURLConnectionChangeTracker.m
//
//
//  Created by Adam Cox on 1/5/15.
//  Copyright (c) 2015 IBM.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
// <http://wiki.apache.org/couchdb/HTTP_database_API#Changes>
//

#import "CDTActiveDoc.h"
#import "CDTActiveDocFetcherDelegate.h"
#import "TDActiveDocURLConnectionChangeTracker.h"
#import "TDRemoteRequest.h"
#import "TDAuthorizer.h"
#import "TDStatus.h"
#import "TDBase64.h"
#import "MYURLUtils.h"
#import <string.h>
#import "TDJSON.h"
#import "CDTLogging.h"
#import "TDMisc.h"
#import "CDTURLSession.h"
#import "Test.h"

#define kMaxRetries 6
#define kInitialRetryDelay 0.2

@interface TDActiveDocURLConnectionChangeTracker()
@property (strong, nonatomic) NSMutableData* inputBuffer;
@property (strong, nonatomic) NSMutableURLRequest *request;
@property (strong, nonatomic) NSDate* startTime;
@property (nonatomic, readwrite) NSUInteger totalRetries;
@property (nonatomic, strong) CDTURLSession * session;
@property (nonatomic, strong) CDTURLSessionTask * task;
@property (nonatomic, strong) id<CDTActiveDocFetcherDelegate> activeDocFetcherDelegate;
@end

@implementation TDActiveDocURLConnectionChangeTracker

- (instancetype)initWithDatabaseURL:(NSURL *)databaseURL
                               mode:(TDChangeTrackerMode)mode
                          conflicts:(BOOL)includeConflicts
                       lastSequence:(id)lastSequenceID
                             client:(id<TDChangeTrackerClient>)client
                            session:(CDTURLSession *)session
                   activeDocFetcher:(id<CDTActiveDocFetcherDelegate>)activeDocFetcher
{
    NSParameterAssert(session);
    self = [super initWithDatabaseURL:databaseURL
                                 mode:mode
                            conflicts:includeConflicts
                         lastSequence:lastSequenceID
                               client:client
                              session:session
                     activeDocFetcher:activeDocFetcher];
    
    if(self){
        _session = session;
        self.activeDocFetcherDelegate = activeDocFetcher;
        if (! self.activeDocFetcherDelegate) {
            self.activeDocFetcherDelegate = self;
        }
    }
    return self;
}

- (NSMutableURLRequest *)getFetchAllActiveDocsRequest {
    NSURL* url = self.allDocsURL;
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.HTTPMethod = @"GET";
    
    // Add headers from my .requestHeaders property:
    for(NSString *key in self.requestHeaders) {
        [request setValue:self.requestHeaders[key] forHTTPHeaderField:key];
    }
    
    NSArray *requestHeadersKeys = [self.requestHeaders allKeys];
    
    if (self.authorizer) {
        NSString* authHeader = [self.authorizer authorizeURLRequest:self.request forRealm:nil];
        if (authHeader) {
            if ([requestHeadersKeys containsObject:@"Authorization"]) {
                CDTLogWarn(CDTREPLICATION_LOG_CONTEXT, @"%@ Overwriting 'Authorization' header with "
                           @"value %@", self, authHeader);
            }
            [request setValue: authHeader forHTTPHeaderField:@"Authorization"];
        }
    }
    return request;
}

- (NSArray *)parseActiveDocsFromResponse:(NSData*)body errorMessage:(NSString**)errorMessage {
    if (!body) {
        *errorMessage = @"No body in response";
        return nil;
    }
    NSError* error;
    id changeObj = [TDJSON JSONObjectWithData:body options:0 error:&error];
    if (!changeObj) {
        *errorMessage = $sprintf(@"JSON parse error: %@", error.localizedDescription);
        return nil;
    }
    NSDictionary* changeDict = $castIf(NSDictionary, changeObj);
    NSArray* rows = $castIf(NSArray, changeDict[@"rows"]);
    if (!rows) {
        *errorMessage = @"No 'rows' array in response";
        return nil;
    }
    NSMutableArray *activeDocs = [[NSMutableArray alloc] init];
    for(NSDictionary *row in rows) {
        NSDictionary *rowValue = (NSDictionary *)[row objectForKey:@"value"];
        [activeDocs addObject:[[CDTActiveDoc alloc] initWithId:[row objectForKey:@"id"] revision:[rowValue objectForKey:@"rev"]]];
    }
    return activeDocs;
}

- (BOOL)start
{
    if (self.task) return NO;
    
    CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"%@: Starting...", [self class]);
    [super start];
    
    self.request = [self.activeDocFetcherDelegate getFetchAllActiveDocsRequest];
    
    self.task = [self.session dataTaskWithRequest:self.request taskDelegate:self];
    
    [self.task resume];
    
    self.inputBuffer = [NSMutableData dataWithCapacity:0];
    
    self.startTime = [NSDate date];
    //CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"%@: Started... <%@>", self, TDCleanURLtoString(url));
    
    return YES;
}

- (void)clearConnection
{
    if(self.task.state != NSURLSessionTaskStateCompleted){
        [self.task cancel];
    }
    self.task = nil;
    self.inputBuffer = nil;
}

- (void)stop
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(start)
                                               object:nil];  // cancel pending retries
    if (self.task) {
        CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"%@: stop", [self class]);
        [self clearConnection];
    }
    [super stop];
}

- (void)retryOrError:(NSError*)error
{
    CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"%@: retryOrError: %@", [self class], error);
    if (++_retryCount <= kMaxRetries && TDMayBeTransientError(error)) {
        self.totalRetries++;
        [self clearConnection];
        NSTimeInterval retryDelay = kInitialRetryDelay * (1 << (_retryCount - 1));
        [self performSelector:@selector(start) withObject:nil afterDelay:retryDelay];
    } else {
        CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@: Can't connect, giving up: %@", self, error);
        
        self.error = error;
        [self stop];
    }
}

-(void)  URLSession:(NSURLSession *)session
               task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
  completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler{
    NSURLProtectionSpace *space = challenge.protectionSpace;
    NSString *authMethod = space.authenticationMethod;
    CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"Got challenge for %@: method=%@, proposed=%@, err=%@",
                  [self class], authMethod, challenge.proposedCredential, challenge.error);
    
    if ($equal(authMethod, NSURLAuthenticationMethodHTTPBasic)) {
        // On basic auth challenge, use proposed credential on first attempt. On second attempt,
        // or if there's no proposed credential, look one up. After that, continue without
        // credential and see what happens (probably a 401)
        
        if (challenge.previousFailureCount <= 1) {
            
            NSURLCredential *cred = challenge.proposedCredential;
            if (cred == nil || challenge.previousFailureCount > 0) {
                cred = [self.request.URL my_credentialForRealm:space.realm
                                          authenticationMethod:authMethod];
            }
            if (cred) {
                CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@ challenge: useCredential: %@",
                              [self class], cred);
                completionHandler(NSURLSessionAuthChallengeUseCredential,cred);
                // Update my authorizer so my owner (the replicator) can pick it up when I'm done
                _authorizer = [[TDBasicAuthorizer alloc] initWithCredential:cred];
                return;
            }
        }
        
        CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@ challenge: continueWithoutCredential",
                      [self class]);
        completionHandler(NSURLSessionAuthChallengeUseCredential,nil);
    }
    else if ($equal(authMethod, NSURLAuthenticationMethodServerTrust)) {
        
        SecTrustRef trust = space.serverTrust;
        if ([TDRemoteRequest checkTrust:trust forHost:space.host]) {
            
            CDTLogVerbose(CDTTD_REMOTE_REQUEST_CONTEXT, @"%@ useCredential for trust: %@",
                          self, trust);
            NSURLCredential *cred = [NSURLCredential credentialForTrust:trust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
            
        }
        else {
            CDTLogWarn(CDTTD_REMOTE_REQUEST_CONTEXT, @"%@ challenge: cancel", self);
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);
        }
    }
    else {
        CDTLogWarn(CDTREPLICATION_LOG_CONTEXT, @"%@ challenge: performDefaultHandling", self);
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
    
}

-(void)receivedResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpresponse = (NSHTTPURLResponse *)response;
    TDStatus status = (TDStatus)httpresponse.statusCode;
    CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@: didReceiveResponse, status %ld", [self class], (long)status);
    
    [self.inputBuffer setLength:0];
    
    if (TDStatusIsError(status)) {
        
        NSDictionary* errorInfo = nil;
        if (status == 401 || status == 407) {
            
            NSString* authorization = [self.requestHeaders objectForKey:@"Authorization"];
            NSString* authResponse = [httpresponse allHeaderFields][@"WWW-Authenticate"];
            
            CDTLogError(CDTREPLICATION_LOG_CONTEXT,
                        @"%@: HTTP auth failed; sent Authorization: %@  ;  got WWW-Authenticate: %@", [self class],
                        authorization, authResponse);
            errorInfo = $dict({ @"HTTPAuthorization", authorization },
                              { @"HTTPAuthenticateHeader", authResponse });
        }
        
        //retryOrError will only retry if the error seems to be a transient error.
        //otherwise, retryOrError will set the error and stop.
        [self retryOrError:TDStatusToNSErrorWithInfo(status, self.allDocsURL, errorInfo)];
    }
    
    if (TDStatusIsError(((NSHTTPURLResponse *)response).statusCode)) {
        [self finishedLoading];
    }
}

-(void)receivedData:(NSData *)data
{
    CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@: didReceiveData: %ld bytes",
                  [self class], (unsigned long)[data length]);
    
    [self.inputBuffer appendData:data];
    [self finishedLoading];
}

-(void) finishedLoading
{
    //parse the input buffer into JSON (or NSArray of changes?)
    CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@: didFinishLoading, %u bytes", self,
                  (unsigned)self.inputBuffer.length);
    
    BOOL restart = NO;
    NSString* errorMessage = nil;
    NSInteger numChanges;
    NSArray *activeDocs = [self.activeDocFetcherDelegate parseActiveDocsFromResponse:self.inputBuffer errorMessage:&errorMessage];
    if (! activeDocs) {
        numChanges = -1;
    }
    else {
        // Convert activeDocs to changes
        NSMutableArray *changes = [[NSMutableArray alloc] init];
        for(CDTActiveDoc *activeDoc in activeDocs) {
            NSDictionary *change = @{
                                            @"id":activeDoc._id,
                                            @"seq":activeDoc.revision,
                                            @"changes": @[@{@"rev": activeDoc.revision}]
                                            };
            [changes addObject:change];
        }
        if (![self receivedChanges:changes errorMessage:&errorMessage]) {
            numChanges = -1;
        }
        else {
            numChanges = changes.count;
        }
    }
    
    if (numChanges < 0) {
        // unparseable response. See if it gets special handling:
        if ([self receivedDataBeginsCorrectly]) {
            
            // The response at least starts out as what we'd expect, so it looks like the connection
            // was closed unexpectedly before the full response was sent.
            NSTimeInterval elapsed = [self.startTime timeIntervalSinceNow] * -1.0;
            CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@: connection closed unexpectedly after "
                        @"%.1f sec. will retry", self, elapsed);
            
            [self retryOrError:[NSError errorWithDomain:NSURLErrorDomain
                                                   code:NSURLErrorNetworkConnectionLost
                                               userInfo:nil]];
            
            return;
        }
        
        // Otherwise report an upstream unparseable-response error
        [self setUpstreamError:errorMessage];
    }
    else {
        // Poll again if there was no error, and it looks like we
        // ran out of changes due to a _limit rather than because we hit the end.
        restart = numChanges == (NSInteger)_limit;
    }
    
    [self clearConnection];
    
    if (restart){
        [self start];  // Next poll...
    } else {
        [self stopped];
    }
    
}

-(void) requestDidError:(NSError *)error
{
    [self retryOrError:error];
}

- (BOOL)receivedDataBeginsCorrectly
{
    NSString *prefixString = @"{\"results\":";
    NSData *prefixData = [prefixString dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger prefixLength = [prefixData length];
    NSUInteger inputLength = [self.inputBuffer length];
    BOOL match = NO;
    
    for (NSUInteger index = 0; index < inputLength; index++)
    {
        char currentChar;
        NSRange currentCharRange = NSMakeRange(index, 1);
        [self.inputBuffer getBytes:&currentChar range:currentCharRange];
        
        // If it's the opening {, check for valid start JSON
        if (currentChar == '{') {
            NSRange r = NSMakeRange(index, prefixLength);
            char buf[prefixLength];
            
            if (inputLength >= (index + prefixLength)) {  // enough data left
                [self.inputBuffer getBytes:buf range:r];
                match = (memcmp(buf, prefixData.bytes, prefixLength) == 0);
            }
            break;  // once we've seen a {, break always as can't succeed if we've not already.
        }
    }
    
    if (!match) {
        CDTLogError(CDTREPLICATION_LOG_CONTEXT, @"%@: Unparseable response from %@. Did not find "
                    @"start of the expected response: %@", self,
                    TDCleanURLtoString(self.request.URL), prefixString);
    }
    
    return match;
}

@end
